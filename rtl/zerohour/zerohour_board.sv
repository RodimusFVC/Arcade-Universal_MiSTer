//============================================================================
//
//  Universal Zero Hour / Red Clash board
//  Copyright (C) 2026 Rodimus
//
//  From MAME zerohour.cpp (David Haywood, inkling) and zerohour_stars.cpp (Frank Palazzolo).
//
//  Z80 4 MHz, video 9.828 MHz / 2 (= 19.656 / 4), 312 x 262, visible x 8-247, y 32-223.
//  No periodic interrupt (the game polls vblank on IN1): coin 1 holds IRQ until 7800 is written,
//  coin 2 pulses NMI.
//    zerohour_state                            redclash_state
//    0000-2FFF ROM                             0000-2FFF ROM
//    3000-37FF RAM                             3000 background, 3800 beeper frequency
//    3800-3BFF sprite RAM                      6000-67FF RAM, 6800-6BFF sprite RAM
//    4000-43FF video RAM (00-3F also the bullet registers), 4800-4803 IN0 IN1 DSW1 DSW2,
//    5000-5007 / 5800-5807 LS259 latches (sound board, stars, flip), 7000 star enable, 7800 IRQ ack
//  Latch 2: Q0 / Q5 / Q6 star speed, Q1 thrust (Zero Hour) / sprite bank (Red Clash), Q2 sound enable,
//  Q3 1-bit DAC (Zero Hour), Q4 coin sound, Q7 flip.
//
//  Video in MAME screen coordinates; CRT Flip mirrors the logical raster (visible area is symmetric):
//  stars (bottom) < Red Clash white background < bullets < sprites < chars.
//  Bullets and sprites are drawn into a line buffer one line ahead, in MAME drawing order (overwrite).
//
//============================================================================

module zerohour_board
(
    output logic        [13:0] z80_o,          // shared T80 (rtl/z80_socket.sv)
    input  logic        [29:0] z80_i,
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic               pause,
    input  logic               redclash,       // 0: zerohour_state, 1: redclash_state
    input  logic               crt_flip,       // mirror the whole picture (OSD CRT Flip)

    input  logic         [7:0] in0,
    input  logic         [7:0] in1,
    input  logic         [7:0] dsw1,
    input  logic         [7:0] dsw2,
    input  logic         [7:0] coin,           // MAME FAKE port: [0] coin 1 (IRQ), [1] coin 2 (NMI), active high

    input  logic         [3:0] h_adj,
    input  logic         [3:0] v_adj,

    output logic               ce_pix,
    output logic         [7:0] video_r,
    output logic         [7:0] video_g,
    output logic         [7:0] video_b,
    output logic               video_hs,
    output logic               video_vs,
    output logic               video_hblank,
    output logic               video_vblank,
    output logic signed [15:0] audio,

    output logic        [14:0] rom_cpu_a,
    input  logic         [7:0] rom_cpu_d,
    output logic        [11:0] rom_chr_a,      // gfx1
    input  logic         [7:0] rom_chr_d,
    output logic        [11:0] rom_spr_a,      // gfx2 as 64-bit rows (8 byte lanes)
    input  logic        [63:0] rom_spr_d,

    input  logic               prom_wr,        // MAME proms region 0x00-0x7F
    input  logic         [6:0] prom_a,
    input  logic         [7:0] prom_d,

    input  logic        [10:0] hs_address,
    output logic         [7:0] hs_data_out,
    input  logic         [7:0] hs_data_in,
    input  logic               hs_write
);

// ------------------------------------------------------------------ clocks
logic [1:0] ph = 2'd0;
always_ff @(posedge clk) ph <= ph + 2'd1;
assign ce_pix = (ph == 2'd3);

// CPU: 8.000 MHz edge stream from 19.656 MHz, alternating rising / falling = 4.000 MHz
logic [11:0] frac_q = 12'd0;
logic        frac_ph = 1'b0, cen_p = 1'b0, cen_n = 1'b0;
wire  [12:0] frac_sum  = {1'b0, frac_q} + 13'd1000;
wire         frac_edge = frac_sum >= 13'd2457;
wire  [12:0] frac_sub  = frac_sum - 13'd2457;
always_ff @(posedge clk) begin
    frac_q <= frac_edge ? frac_sub[11:0] : frac_sum[11:0];
    cen_p  <= frac_edge & ~frac_ph;
    cen_n  <= frac_edge &  frac_ph;
    if (frac_edge) frac_ph <= ~frac_ph;
end

// ------------------------------------------------------------------ video timing
logic [8:0] hcnt = 9'd0, vcnt = 9'd0;
always_ff @(posedge clk) begin
    if (ce_pix) begin
        if (hcnt == 9'd311) begin
            hcnt <= 9'd0;
            vcnt <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
        end
        else hcnt <= hcnt + 9'd1;
    end
end

wire [8:0] hs_start = 9'd264 + {{5{h_adj[3]}}, h_adj};
wire [8:0] vs_start = 9'd240 + {{5{v_adj[3]}}, v_adj};
wire hbl_s0 = (hcnt < 9'd8) || (hcnt >= 9'd248);
wire vbl_s0 = (vcnt < 9'd32) || (vcnt >= 9'd224);
wire hs_s0  = (hcnt >= hs_start) && (hcnt < hs_start + 9'd24);
wire vs_s0  = (vcnt >= vs_start) && (vcnt < vs_start + 9'd3);

// ------------------------------------------------------------------ CPU
logic        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n;
logic [15:0] a;
logic  [7:0] din, dout;
logic        int_n = 1'b1;
logic  [1:0] coin_d = 2'b00;

z80_socket cpu
(
    .RESET_n   (~reset),
    .CLK       (clk),
    .CEN_p     (cen_p & ~pause),
    .CEN_n     (cen_n & ~pause),
    .WAIT_n    (1'b1),
    .INT_n     (int_n),
    .NMI_n     (~coin[1]),                     // edge-triggered in the Z80
    .BUSRQ_n   (1'b1),
    .M1_n      (m1_n),
    .MREQ_n    (mreq_n),
    .IORQ_n    (iorq_n),
    .RD_n      (rd_n),
    .WR_n      (wr_n),
    .RFSH_n    (rfsh_n),
    .HALT_n    (),
    .BUSAK_n   (),
    .OUT0      (1'b0),
    .A         (a),
    .DI        (din),
    .DO        (dout),
    .R800_mode (1'b0),
    .REG       (),
    .DIRSet    (1'b0),
    .DIR       (212'd0),
    .to_cpu    (z80_o),
    .from_cpu  (z80_i)
);

wire mem     = !mreq_n && rfsh_n;
wire wr      = !wr_n;
wire rom_cs  = mem && a < 16'h3000;
wire ram_cs  = mem && (redclash ? a[15:11] == 5'b01100 : a[15:11] == 5'b00110);
wire spr_cs  = mem && (redclash ? a[15:10] == 6'b011010 : a[15:10] == 6'b001110);
wire bgr_cs  = mem && redclash && a[15:11] == 5'b00110;   // 3000 background
wire vram_cs = mem && a[15:10] == 6'b010000;
wire in_cs   = mem && a[15:11] == 5'b01001;
wire l1_cs   = mem && a[15:11] == 5'b01010;
wire l2_cs   = mem && a[15:11] == 5'b01011;
wire star_cs = mem && a[15:11] == 5'b01110;
wire ack_cs  = mem && a[15:11] == 5'b01111;

assign rom_cpu_a = a[14:0];

always_ff @(posedge clk) begin
    coin_d <= coin[1:0];
    if (reset)                     int_n <= 1'b1;
    else if (coin[0] && !coin_d[0]) int_n <= 1'b0;   // MAME left_coin_inserted: ASSERT_LINE
    else if (ack_cs && wr)         int_n <= 1'b1;
end

logic [7:0] latch1 = 8'd0, latch2 = 8'd0, background = 8'd0;
always_ff @(posedge clk) begin
    if (reset) begin
        latch1 <= 8'd0; latch2 <= 8'd0; background <= 8'd0;
    end
    else if (wr) begin
        if (l1_cs)  latch1[a[2:0]] <= dout[0];
        if (l2_cs)  latch2[a[2:0]] <= dout[0];
        if (bgr_cs) background <= dout;
    end
end

wire gflip   = latch2[7];
wire gfxbank = redclash & latch2[1];

logic [7:0] ram_q, vram_q, vram_vq;
logic [7:0] spr_q[4], spr_vq[4];
logic [9:0] vram_va;
logic [7:0] spr_ve;

dpram_dc #(.widthad_a(11)) work_ram
(
    .clock_a(clk), .address_a(a[10:0]), .data_a(dout), .wren_a(ram_cs && wr), .q_a(ram_q),
    .clock_b(clk), .address_b(hs_address), .data_b(hs_data_in), .wren_b(hs_write), .q_b(hs_data_out)
);
dpram_dc #(.widthad_a(10)) video_ram
(
    .clock_a(clk), .address_a(a[9:0]), .data_a(dout), .wren_a(vram_cs && wr), .q_a(vram_q),
    .clock_b(clk), .address_b(vram_va), .q_b(vram_vq)
);
genvar l;
generate
    for (l = 0; l < 4; l++) begin : spr_lane
        dpram_dc #(.widthad_a(8)) ram
        (
            .clock_a(clk), .address_a(a[9:2]), .data_a(dout), .wren_a(spr_cs && wr && a[1:0] == l), .q_a(spr_q[l]),
            .clock_b(clk), .address_b(spr_ve), .q_b(spr_vq[l])
        );
    end
endgenerate

// bullet registers = video RAM 00-1F (fine x, width, colour) and 20-3F (y), shadowed for the line builder
logic [7:0] bl_attr[32], bl_y[32];
always_ff @(posedge clk) begin
    if (vram_cs && wr && a[9:6] == 4'd0) begin
        if (a[5]) bl_y[a[4:0]]    <= dout;
        else      bl_attr[a[4:0]] <= dout;
    end
end

always_comb begin
    din = 8'hFF;
    if (rom_cs)       din = rom_cpu_d;
    else if (ram_cs)  din = ram_q;
    else if (spr_cs)  din = spr_q[a[1:0]];
    else if (vram_cs) din = vram_q;
    else if (in_cs)
        case (a[1:0])
            2'd0: din = in0;
            2'd1: din = {vbl_s0, ~vbl_s0, in1[5:0]};      // two vblank inputs, active high / active low
            2'd2: din = dsw1;
            2'd3: din = dsw2;
        endcase
end

// ------------------------------------------------------------------ sound
// Zero Hour 8011 sound board (discrete, rtl/zerohour/zerohour_sound.sv); Red Clash's sound board is not modelled
logic signed [15:0] zh_snd;

zerohour_sound sound
(
    .clk    (clk),
    .reset  (reset | redclash),
    .latch1 (latch1),
    .latch2 (latch2),
    .audio  (zh_snd)
);

assign audio = redclash ? 16'sd0 : zh_snd;

// ------------------------------------------------------------------ PROMs (palette; sprite lookup)
logic [7:0] prom_pal[32], prom_spr[32];
always_ff @(posedge clk) begin
    if (prom_wr) begin
        case (prom_a[6:5])
            2'd0: prom_pal[prom_a[4:0]] <= prom_d;
            2'd1: prom_spr[prom_a[4:0]] <= prom_d;
            default: ;                                   // third PROM: purpose unknown (MAME)
        endcase
    end
end

// ------------------------------------------------------------------ stars (zerohour_stars.cpp)
// The 17-bit LFSR state for logical pixel (x, y) is the field start state stepped (y * 256 + x - offset)
// mod 65536 times. A stepper chases that index for the pixel on the counters, forwards or backwards
// (CRT Flip scans the field in reverse), across the field wrap via the precomputed end states.
logic        st_en = 1'b0, st_cnt = 1'b0;
logic  [2:0] st_speed;
logic [15:0] st_off = 16'd0;
logic [16:0] st = 17'd0;
logic [15:0] st_idx = 16'd0;

assign st_speed = {latch2[6], latch2[5], latch2[0]};

function automatic logic st_fb(input logic [16:0] s);
    st_fb = ~(s[16] ^ s[5]);
endfunction

// next pixel the star stage will evaluate, in physical raster coordinates
logic [7:0] nx, ny;
always_comb begin
    if (vcnt < 9'd32 || vcnt > 9'd223 || (vcnt == 9'd223 && hcnt > 9'd247)) begin nx = 8'd8; ny = 8'd32; end
    else if (hcnt < 9'd8)                                                    begin nx = 8'd8; ny = vcnt[7:0]; end
    else if (hcnt > 9'd247)                                                  begin nx = 8'd8; ny = vcnt[7:0] + 8'd1; end
    else                                                                     begin nx = hcnt[7:0]; ny = vcnt[7:0]; end
end
wire [7:0]  nlx    = crt_flip ? ~nx : nx;
wire [7:0]  nly    = crt_flip ? ~ny : ny;
wire [15:0] want   = {nly, nlx} - st_off;
wire [15:0] st_dif = want - st_idx;
wire [16:0] st_start = st_cnt ? 17'h1FC71 : 17'h00000;
wire [16:0] st_end   = st_cnt ? 17'h00001 : 17'h1FF1C;     // start state stepped 65535 times
wire        fld_new  = ce_pix && hcnt == 9'd0 && vcnt == 9'd224;
wire [15:0] off_next = st_off + {12'd0, st_speed, 1'b0} - 16'd9;

always_ff @(posedge clk) begin
    if (reset) begin
        st_en <= 1'b0; st_cnt <= 1'b0; st_off <= 16'd0;
    end
    else begin
        if (star_cs && wr) begin                          // MAME set_enable(true): offset reset on enabling
            st_en <= 1'b1;
            if (!st_en) st_off <= 16'd0;
        end
        if (fld_new && st_en) begin                       // MAME update_state, one frame earlier in the raster
            st_cnt <= ~st_cnt;
            if (st_cnt) begin st_off <= off_next; st <= 17'h00000; end
            else        st <= 17'h1FC71;
            st_idx <= 16'd0;
        end
        else if (st_dif != 16'd0) begin
            if (!st_dif[15]) begin                        // forward
                if (st_idx == 16'hFFFF) st <= st_start;
                else                    st <= {st[15:0], st_fb(st)};
                st_idx <= st_idx + 16'd1;
            end
            else begin                                    // backward
                if (st_idx == 16'h0000) st <= st_end;
                else                    st <= {st[6] ? st[0] : ~st[0], st[16:1]};
                st_idx <= st_idx - 16'd1;
            end
        end
    end
end

// ------------------------------------------------------------------ bullets + sprites: line buffer built a line ahead
logic [7:0] lb_q[2];
logic [7:0] lb_wa, lb_wd, lb_ra;
logic       lb_we = 1'b0;
logic       lb_clr;
logic       build_buf = 1'b0;
wire        disp_buf;

generate
    for (l = 0; l < 2; l++) begin : lbuf
        dpram_dc #(.widthad_a(8)) ram
        (
            .clock_a(clk), .address_a(lb_wa), .data_a(lb_wd), .wren_a(lb_we && build_buf == l),
            .clock_b(clk), .address_b(lb_ra), .data_b(8'd0), .wren_b(lb_clr && disp_buf == l), .q_b(lb_q[l])
        );
    end
endgenerate

typedef enum logic [3:0] {B_IDLE, B_BUL, B_BPX, B_BNEXT, B_SCAN, B_SCAN_W, B_SCAN_R, B_ENT, B_ENT_W, B_ENT_R,
                          B_ROWA_W, B_ROWA_R, B_ROWB_W, B_ROWB_R, B_PIX} bstate_t;
bstate_t     bs = B_IDLE;

wire  [8:0] tgt = (vcnt >= 9'd260) ? vcnt - 9'd260 : vcnt + 9'd2;
logic [7:0] bl_line;                                     // logical line being built
logic [4:0] b_col;
logic [8:0] b_x;
logic [2:0] b_n;                                         // pixels left - 1
logic [6:0] b_pen;
logic [4:0] b_blk, b_lo;
logic [3:0] b_e;                                         // entry (scan: 0-8)
logic [7:0] s0, s1, s2, s3;                              // sprite entry bytes
logic [4:0] s_row;                                       // row inside the sprite
logic [4:0] s_px, s_w;
logic [63:0] row_a, row_b;
logic [5:0] s_base;                                      // bit offset of pixel 0 in the row
logic       s_two;                                       // 16x16 (bank 2): pixels 8-15 come from row b

// bullet column under test (MAME draw_bullets)
wire  [7:0] ba     = bl_attr[b_col];
wire  [8:0] b_sy   = 9'd255 - {1'b0, bl_y[b_col]};
wire        b_hit  = ({1'b0, bl_line} == b_sy) || ({1'b0, bl_line} + 9'd1 == b_sy);
wire  [8:0] b_sx0  = {1'b0, b_col, 3'b000} + 9'd8;
wire  [8:0] b_sx   = (gflip ? 9'd264 - b_sx0 : b_sx0) - {6'd0, ba[5:3]};
wire  [2:0] b_wm1  = 3'd7 - {ba[7:6], 1'b0};             // width 8 - (attr >> 5 & 6), minus 1
wire  [6:0] b_col7 = {2'b00, ba[7], 4'h5};               // pen (attr >> 3 & 0x10) | 5

// sprite entry decode (MAME draw_sprites): e-sssyyy iiiiiiii --c--ccc xxxxxxxx
wire [8:0]  l16    = {1'b0, bl_line} + 9'd16;
wire [4:0]  e_rr   = e_r[4:0];
wire [9:0]  e_sy   = {2'b00, b_blk, 3'b000} + {7'd0, spr_vq[0][2:0]} - 10'd16;
wire [9:0]  e_r    = {2'b00, bl_line} - e_sy;
wire [1:0]  e_sz   = spr_vq[0][4:3];
wire [4:0]  e_h    = (e_sz == 2'd1) ? 5'd8 : (e_sz == 2'd2) ? 5'd16 : 5'd24;
wire        e_vis  = spr_vq[0][7] && e_sz != 2'd0 && !e_r[9] && e_r < {5'd0, e_h};

// row address for the decoded entry (gfx2 viewed as 64-bit rows; 8x8 = MAME gfx3 rearrangement)
logic [9:0] e_rowa;
logic [5:0] e_base;
always_comb begin
    e_rowa = 10'd0; e_base = 6'd0;
    case (e_sz)
        2'd1: begin                                                    // 8x8: code {bank, i}
                  e_rowa = {gfxbank, spr_vq[1][7:2], ~e_rr[2:0]};
                  e_base = {spr_vq[1][1:0], 4'b0000};
              end
        2'd2: if (spr_vq[0][5]) begin                                  // 16x16 spaceships (banks 4 / 5)
                  e_rowa = {gfxbank, spr_vq[1][7:3], ~e_rr[3:0]};
                  e_base = spr_vq[1][1] ? 6'd32 : 6'd0;
              end
              else begin                                               // 16x16 (bank 2)
                  e_rowa = {gfxbank, spr_vq[1][7:4], ~e_rr[3], 1'b0, ~e_rr[2:0]};
                  e_base = 6'd48;
              end
        default: begin                                                 // 24x24
                  e_rowa = {gfxbank, spr_vq[1][7:4], 5'd23 - e_rr};
                  e_base = 6'd0;
              end
    endcase
end

// pixel s_px of the current sprite line
wire [4:0]  s_pxl  = s_two ? {2'b00, s_px[2:0]} : s_px;
wire [63:0] s_rowd = (s_two && s_px[3]) ? row_b : row_a;
wire [5:0]  s_bit  = s_base + {s_pxl, 1'b0};
wire [7:0]  s_byte = s_rowd[{s_bit[5:3], 3'b000} +: 8];
wire [1:0]  s_pen  = {s_byte[3'd6 - s_bit[2:0]], s_byte[3'd7 - s_bit[2:0]]};

assign spr_ve = {b_blk, b_e[2:0]};

always_ff @(posedge clk) begin
    lb_we <= 1'b0;
    if (ce_pix && hcnt == 9'd311) begin                   // build line vcnt + 2 during line vcnt + 1
        bl_line   <= crt_flip ? ~tgt[7:0] : tgt[7:0];
        build_buf <= vcnt[0];
        b_col     <= 5'd0;
        bs        <= B_BUL;
    end
    else case (bs)
        B_IDLE: ;
        B_BUL:  begin
                    if (b_hit && !b_sx[8]) begin
                        b_x <= b_sx; b_n <= b_wm1; b_pen <= b_col7;
                        bs  <= B_BPX;
                    end
                    else bs <= B_BNEXT;
                end
        B_BNEXT: begin
                    if (b_col == 5'd31) begin                 // sprite blocks that can reach this line
                        b_blk <= l16[8] ? 5'd31 : l16[7:3];
                        b_lo  <= (bl_line < 8'd24) ? 5'd0 : l16[7:3] - 5'd4;
                        b_e   <= 4'd0;
                        bs    <= B_SCAN;
                    end
                    else begin b_col <= b_col + 5'd1; bs <= B_BUL; end
                end
        B_BPX:  begin
                    if (!b_x[8]) begin lb_we <= 1'b1; lb_wa <= b_x[7:0]; lb_wd <= {1'b1, b_pen}; end
                    b_x <= b_x + 9'd1;
                    b_n <= b_n - 3'd1;
                    if (b_n == 3'd0) bs <= B_BNEXT;
                end
        // count the block's chain: entries until the first with byte 0 == 0
        B_SCAN:   bs <= B_SCAN_W;
        B_SCAN_W: bs <= B_SCAN_R;
        B_SCAN_R: begin
                      if (spr_vq[0] == 8'd0 || b_e == 4'd7) begin
                          // draw entries (count - 1) down to 0
                          if (spr_vq[0] == 8'd0 && b_e == 4'd0) begin
                              if (b_blk == b_lo) bs <= B_IDLE;
                              else begin b_blk <= b_blk - 5'd1; b_e <= 4'd0; bs <= B_SCAN; end
                          end
                          else begin
                              if (spr_vq[0] == 8'd0) b_e <= b_e - 4'd1;
                              bs <= B_ENT;
                          end
                      end
                      else begin b_e <= b_e + 4'd1; bs <= B_SCAN; end
                  end
        B_ENT:    bs <= B_ENT_W;
        B_ENT_W:  bs <= B_ENT_R;
        B_ENT_R:  begin
                      if (e_vis) begin
                          s0 <= spr_vq[0]; s1 <= spr_vq[1]; s2 <= spr_vq[2]; s3 <= spr_vq[3];
                          s_row  <= e_r[4:0];
                          s_base <= e_base;
                          s_two  <= e_sz == 2'd2 && !spr_vq[0][5];
                          s_w    <= (e_sz == 2'd1) ? 5'd7 : (e_sz == 2'd2) ? 5'd15 : 5'd23;
                          rom_spr_a <= {2'b00, e_rowa};
                          bs <= B_ROWA_W;
                      end
                      else begin                              // nothing to draw: B_PIX steps to the next entry
                          s0  <= 8'd0;
                          s_w <= 5'd0;
                          bs  <= B_PIX;
                      end
                      s_px <= 5'd0;
                  end
        B_ROWA_W: bs <= B_ROWA_R;
        B_ROWA_R: begin
                      row_a <= rom_spr_d;
                      if (s_two) begin rom_spr_a <= rom_spr_a | 12'd8; bs <= B_ROWB_W; end
                      else bs <= B_PIX;
                  end
        B_ROWB_W: bs <= B_ROWB_R;
        B_ROWB_R: begin row_b <= rom_spr_d; bs <= B_PIX; end
        B_PIX:    begin
                      if (s0 != 8'd0 && s_pen != 2'd0) begin  // s0 cleared for a skipped entry
                          lb_we <= 1'b1;
                          lb_wa <= s3 + {3'd0, s_px};          // MAME draws at x and x - 256: 8-bit wrap
                          lb_wd <= {1'b1, 1'b1, s2[5], s2[2:0], s_pen};
                      end
                      s_px <= s_px + 5'd1;
                      if (s_px == s_w) begin
                          s0 <= 8'd0;
                          if (b_e == 4'd0) begin
                              if (b_blk == b_lo) bs <= B_IDLE;
                              else begin b_blk <= b_blk - 5'd1; b_e <= 4'd0; bs <= B_SCAN; end
                          end
                          else begin b_e <= b_e - 4'd1; bs <= B_ENT; end
                      end
                  end
        default:  bs <= B_IDLE;
    endcase
end

// ------------------------------------------------------------------ display pipeline
// S0: counters -> logical coordinates, video RAM address, star test
wire [7:0] lx = crt_flip ? ~hcnt[7:0] : hcnt[7:0];
wire [7:0] ly = crt_flip ? ~vcnt[7:0] : vcnt[7:0];
wire [7:0] tx = gflip ? ~lx : lx;
wire [7:0] ty = gflip ? ~ly : ly;
assign vram_va = {ty[7:3], tx[7:3]};

wire [7:0] lxp8   = lx + 8'd8;
wire       st_on  = st_en && st_idx == want && !hbl_s0 && !vbl_s0 &&
                    lxp8[4] == (redclash ? ly[0] : 1'b1) && st[7:0] == 8'hFF && !st_fb(st);

// S1
logic [7:0] s1_code, s1_lx;
logic [2:0] s1_tx, s1_ty;
logic [4:0] s1_tcol, s1_trow;
logic       s1_star;
logic [4:0] s1_scol;
logic       s1_ln, s1_clr;
// S2
logic [7:0] chr_lo, s2_lo, s2_hi, s2_lb;
logic [2:0] s2_tx, s2_color;
logic       s2_star;
logic [4:0] s2_scol;
// S3
logic [2:0] s3_kind;                                       // 0 black, 1 char pen, 2 sprite pen, 3 star, 4 white
logic [5:0] s3_val;
logic [3:0] blk_d[3];                                      // {hbl, vbl, hs, vs} per stage

assign rom_chr_a = {1'b0, s1_code[6:0], ph[1], s1_ty};     // plane 1 (pen bit 0) then plane 0 (+8)
assign lb_ra     = s1_lx;
assign lb_clr    = ce_pix && s1_clr;                       // clear on the edge that samples the read, hcnt 0-255 only
assign disp_buf  = s1_ln;

wire [4:0] trow12 = s1_trow + 5'd12;
wire [2:0] tcolor = (s1_tcol > 5'd27) ? {1'b1, ~trow12[4:3]} : s1_code[6:4];   // score panel: (((row + 12) & 31) >> 3) ^ 7
wire [1:0] tpen   = {s2_hi[s2_tx], s2_lo[s2_tx]};
wire [7:0] lbq    = lb_q[disp_buf];

always_ff @(posedge clk) begin
    if (ph == 2'd2) chr_lo <= rom_chr_d;
    if (ce_pix) begin
        s1_code <= vram_vq;   s1_lx <= lx;
        s1_tx   <= tx[2:0];   s1_ty <= ty[2:0];
        s1_tcol <= tx[7:3];   s1_trow <= ty[7:3];
        s1_star <= st_on;     s1_scol <= st[13:9];
        s1_ln   <= vcnt[0];   s1_clr <= !hcnt[8];

        s2_lo <= chr_lo;      s2_hi <= rom_chr_d;
        s2_tx <= s1_tx;       s2_color <= tcolor;
        s2_lb <= lbq;         s2_star <= s1_star;   s2_scol <= s1_scol;

        if (tpen != 2'd0)                           begin s3_kind <= 3'd1; s3_val <= {1'b0, s2_color, tpen}; end
        else if (s2_lb[7] && !s2_lb[6])             begin s3_kind <= 3'd1; s3_val <= {1'b0, s2_lb[4:0]}; end
        else if (s2_lb[7])                          begin s3_kind <= 3'd2; s3_val <= s2_lb[5:0]; end
        else if (redclash && background[3:0] != 0)  begin s3_kind <= 3'd4; s3_val <= 6'd0; end
        else if (s2_star)                           begin s3_kind <= 3'd3; s3_val <= {1'b0, s2_scol}; end
        else                                        begin s3_kind <= 3'd0; s3_val <= 6'd0; end

        blk_d[0] <= {hbl_s0, vbl_s0, hs_s0, vs_s0};
        blk_d[1] <= blk_d[0];
        blk_d[2] <= blk_d[1];
    end
end

// ------------------------------------------------------------------ palette (MAME zerohour_state::palette)
wire [7:0] spr_lut = prom_spr[s3_val[4:0]];
wire [3:0] spr_nib = s3_val[5] ? spr_lut[7:4] : spr_lut[3:0];
wire [4:0] ctab    = (s3_kind == 3'd2) ? {1'b0, spr_nib[0], spr_nib[1], spr_nib[2], spr_nib[3]}
                                       : {s3_val[1:0], s3_val[4:2]};
wire [7:0] pe      = prom_pal[ctab];

function automatic [7:0] w2(input b0, input b1);
    w2 = (b0 ? 8'h47 : 8'h00) + (b1 ? 8'h97 : 8'h00);
endfunction

always_ff @(posedge clk) begin
    if (ce_pix) begin
        case (s3_kind)
            3'd1, 3'd2: begin video_r <= w2(pe[0], pe[5]); video_g <= w2(pe[2], pe[6]); video_b <= w2(pe[4], pe[7]); end
            3'd3:       begin video_r <= w2(1'b0, s3_val[0]); video_g <= w2(s3_val[2], s3_val[1]); video_b <= w2(s3_val[4], s3_val[3]); end
            3'd4:       begin video_r <= 8'hFF; video_g <= 8'hFF; video_b <= 8'hFF; end
            default:    begin video_r <= 8'h00; video_g <= 8'h00; video_b <= 8'h00; end
        endcase
        {video_hblank, video_vblank, video_hs, video_vs} <= blk_d[2];
    end
end

endmodule
