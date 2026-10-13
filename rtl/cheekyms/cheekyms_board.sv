//============================================================================
//
//  Universal Cheeky Mouse board (8004)
//  Copyright (C) 2026 Rodimus
//
//  From MAME cheekyms.cpp (Lee Taylor, Chris Moore).
//
//  Z80 5 MHz / 2, video 10.816 MHz / 2 = 5.408 MHz (fractional pixel enable from 19.656 MHz), 352 x 262,
//  visible x 0-255, y 32-223.
//    0000-1FFF ROM, 3000-33FF RAM, 3800-3BFF video RAM
//    I/O 00 DSW, 01 INPUTS, 20-3F sprite RAM (8 x 4, write only), 40 sound, 80 sound / scroll / palette / IRQ / flip
//  Port 80: D0 mute, D1 coin / extra sound, D2 IRQ enable (0 clears the IRQ), D3-D5 man scroll, D6 palette
//  bank (PROM M8), D7 flip. Coin: NMI. Vblank (both edges, as MAME's screen_vblank callback) asserts IRQ.
//  Sprites under the playfield; the playfield's "man area" (columns 8-11, rows 6-26) is read scrolly lines lower.
//  CRT Flip mirrors the logical raster (visible area symmetric).
//
//============================================================================

module cheekyms_board
(
    output logic        [13:0] z80_o,          // shared T80 (rtl/z80_socket.sv)
    input  logic        [29:0] z80_i,
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic               pause,
    input  logic               crt_flip,

    input  logic         [7:0] inputs,
    input  logic         [7:0] dsw,
    input  logic         [7:0] coin,           // MAME COIN port: [0] coin 1, active high

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
    output logic         [7:0] port40,         // to the sound board
    output logic         [1:0] port80_snd,     // [1] coin / extra, [0] mute

    output logic        [14:0] rom_cpu_a,
    input  logic         [7:0] rom_cpu_d,
    output logic        [11:0] rom_chr_a,      // chars: [7:0] cm02 (pen bit 0), [15:8] cm01 (pen bit 1)
    input  logic        [15:0] rom_chr_d,
    output logic        [11:0] rom_spr_a,      // sprites: [7:0] cm07 (pen bit 0), [15:8] cm08 (pen bit 1)
    input  logic        [15:0] rom_spr_d,

    input  logic               prom_wr,        // MAME proms region 0x00-0x7F (M9, M8, P3)
    input  logic         [6:0] prom_a,
    input  logic         [7:0] prom_d,

    input  logic         [9:0] hs_address,
    output logic         [7:0] hs_data_out,
    input  logic         [7:0] hs_data_in,
    input  logic               hs_write
);

// ------------------------------------------------------------------ clocks
// pixel: 19.656 MHz * 5408 / 19656 = 5.408 MHz; CPU edges: 19.656 MHz * 625 / 2457 = 5 MHz (2.5 MHz CPU)
logic [14:0] pix_acc = 15'd0;
wire  [15:0] pix_sum = {1'b0, pix_acc} + 16'd5408;
wire  [15:0] pix_sub = pix_sum - 16'd19656;
always_ff @(posedge clk) begin
    ce_pix  <= pix_sum >= 16'd19656;
    pix_acc <= (pix_sum >= 16'd19656) ? pix_sub[14:0] : pix_sum[14:0];
end

logic [11:0] frac_q = 12'd0;
logic        frac_ph = 1'b0, cen_p = 1'b0, cen_n = 1'b0;
wire  [12:0] frac_sum  = {1'b0, frac_q} + 13'd625;
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
        if (hcnt == 9'd351) begin
            hcnt <= 9'd0;
            vcnt <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
        end
        else hcnt <= hcnt + 9'd1;
    end
end

wire [8:0] hs_start = 9'd288 + {{5{h_adj[3]}}, h_adj};
wire [8:0] vs_start = 9'd240 + {{5{v_adj[3]}}, v_adj};
wire hbl_s0 = hcnt[8];
wire vbl_s0 = (vcnt < 9'd32) || (vcnt >= 9'd224);
wire hs_s0  = (hcnt >= hs_start) && (hcnt < hs_start + 9'd32);
wire vs_s0  = (vcnt >= vs_start) && (vcnt < vs_start + 9'd3);

// ------------------------------------------------------------------ CPU
logic        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n;
logic [15:0] a;
logic  [7:0] din, dout;
logic        int_n = 1'b1;
logic        vbl_d = 1'b0;
logic  [7:0] p80 = 8'd0;

z80_socket cpu
(
    .RESET_n   (~reset),
    .CLK       (clk),
    .CEN_p     (cen_p & ~pause),
    .CEN_n     (cen_n & ~pause),
    .WAIT_n    (1'b1),
    .INT_n     (int_n),
    .NMI_n     (~coin[0]),                     // MAME coin_inserted: NMI on the coin edge
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

wire mem    = !mreq_n && rfsh_n;
wire io     = !iorq_n && m1_n;
wire wr     = !wr_n;
wire rom_cs = mem && a[15:13] == 3'b000;
wire ram_cs = mem && a[15:10] == 6'b001100;           // 3000-33FF
wire vid_cs = mem && a[15:10] == 6'b001110;           // 3800-3BFF
wire dsw_cs = io && a[7:0] == 8'h00;
wire in_cs  = io && a[7:0] == 8'h01;
wire spr_cs = io && a[7:5] == 3'b001;                 // 20-3F
wire p40_cs = io && a[7:0] == 8'h40;
wire p80_cs = io && a[7:0] == 8'h80;

assign rom_cpu_a = {2'b00, a[12:0]};

always_ff @(posedge clk) begin
    vbl_d <= vbl_s0;
    if (reset) begin
        p80 <= 8'd0; port40 <= 8'd0; int_n <= 1'b1;
    end
    else begin
        if (p80_cs && wr) p80 <= dout;
        if (p40_cs && wr) port40 <= dout;
        if (p80_cs && wr && !dout[2])                int_n <= 1'b1;
        else if (p80[2] && (vbl_s0 != vbl_d))        int_n <= 1'b0;   // vblank_int_w on both edges
    end
end

assign port80_snd = p80[1:0];
wire       gflip   = p80[7];
wire [2:0] scrolly = p80[5:3];
wire       palbank = p80[6];

logic [7:0] ram_q, vram_q, vram_vq;
logic [9:0] vram_va;
dpram_dc #(.widthad_a(10)) work_ram
(
    .clock_a(clk), .address_a(a[9:0]), .data_a(dout), .wren_a(ram_cs && wr), .q_a(ram_q),
    .clock_b(clk), .address_b(hs_address), .data_b(hs_data_in), .wren_b(hs_write), .q_b(hs_data_out)
);
dpram_dc #(.widthad_a(10)) video_ram
(
    .clock_a(clk), .address_a(a[9:0]), .data_a(dout), .wren_a(vid_cs && wr), .q_a(vram_q),
    .clock_b(clk), .address_b(vram_va), .q_b(vram_vq)
);

logic [7:0] spram[32];
always_ff @(posedge clk) if (spr_cs && wr) spram[a[4:0]] <= dout;

always_comb begin
    din = 8'hFF;
    if (rom_cs)      din = rom_cpu_d;
    else if (ram_cs) din = ram_q;
    else if (vid_cs) din = vram_q;
    else if (dsw_cs) din = dsw;
    else if (in_cs)  din = inputs;
end

// ------------------------------------------------------------------ PROMs: M9, M8 (chars), P3 (sprites)
logic [7:0] prom[96];
always_ff @(posedge clk) if (prom_wr && prom_a < 7'd96) prom[prom_a] <= prom_d;

// ------------------------------------------------------------------ sprites: line buffer built a line ahead
logic [7:0] lb_q[2];
logic [7:0] lb_wa, lb_wd, lb_ra;
logic       lb_we = 1'b0;
logic       lb_clr;
logic       build_buf = 1'b0;
wire        disp_buf;

genvar l;
generate
    for (l = 0; l < 2; l++) begin : lbuf
        dpram_dc #(.widthad_a(8)) ram
        (
            .clock_a(clk), .address_a(lb_wa), .data_a(lb_wd), .wren_a(lb_we && build_buf == l),
            .clock_b(clk), .address_b(lb_ra), .data_b(8'd0), .wren_b(lb_clr && disp_buf == l), .q_b(lb_q[l])
        );
    end
endgenerate

typedef enum logic [2:0] {S_IDLE, S_SPR, S_PIECE, S_ROW_W, S_ROW_R, S_PIX} sstate_t;
sstate_t    ss = S_IDLE;
wire  [8:0] tgt = (vcnt >= 9'd260) ? vcnt - 9'd260 : vcnt + 9'd2;
logic [7:0] sl_line;
logic [2:0] s_n;                       // sprite 0-7 (MAME draw order: later overwrites)
logic       s_pc;                      // piece 0 / 1 of a double sprite
logic [5:0] s_code;
logic [8:0] s_x;
logic [3:0] s_px;
logic [2:0] s_color;

wire  [7:0] sb0 = spram[{s_n, 2'd0}], sb1 = spram[{s_n, 2'd1}], sb2 = spram[{s_n, 2'd2}], sb3 = spram[{s_n, 2'd3}];
wire  [5:0] base_code = {1'b0, ~sb0[3:0], 1'b0};
wire        single    = sb0[7];
wire        side      = sb0[1];
// piece geometry (MAME draw_sprites)
wire  [5:0] pc_code = single ? base_code + (gflip ? 6'd0 : 6'd1) : (base_code | (s_pc ? 6'h21 : 6'h20));
wire  [8:0] pc_x    = (9'd256 - {1'b0, sb2}) + ((!single && side && s_pc) ? 9'd16 : 9'd0);
wire  [8:0] pc_y    = {1'b0, sb1} + ((!single && !side && s_pc) ? 9'd16 : 9'd0);
wire  [8:0] pc_r    = {1'b0, sl_line} - pc_y;
wire        pc_vis  = sb3[3] && !pc_r[8] && pc_r[7:4] == 4'd0;
wire        pc_last = single || s_pc;

logic [15:0] row_l, row_h;             // 16 pixels: bytes {left, right} per plane
wire  [3:0]  bx = s_px;
wire         px_l = row_l[15 - bx];
wire         px_h = row_h[15 - bx];
wire  [8:0]  wx   = s_x + {5'd0, s_px};
logic        s_half;

always_ff @(posedge clk) begin
    lb_we <= 1'b0;
    if (ce_pix && hcnt == 9'd351) begin                   // build line vcnt + 2 during line vcnt + 1
        sl_line   <= crt_flip ? ~tgt[7:0] : tgt[7:0];
        build_buf <= vcnt[0];
        s_n <= 3'd0; s_pc <= 1'b0;
        ss  <= S_SPR;
    end
    else case (ss)
        S_IDLE:  ;
        S_SPR,
        S_PIECE: begin
                     if (pc_vis) begin
                         s_code    <= pc_code;
                         s_x       <= pc_x;
                         s_color   <= ~sb3[2:0];
                         s_half    <= 1'b0;
                         rom_spr_a <= {1'b0, pc_code, pc_r[3:0], 1'b0};
                         ss        <= S_ROW_W;
                     end
                     else if (!pc_last) s_pc <= 1'b1;
                     else if (s_n == 3'd7) ss <= S_IDLE;
                     else begin s_n <= s_n + 3'd1; s_pc <= 1'b0; ss <= S_SPR; end
                 end
        S_ROW_W: ss <= S_ROW_R;
        S_ROW_R: begin
                     if (!s_half) begin
                         row_l[15:8] <= rom_spr_d[7:0]; row_h[15:8] <= rom_spr_d[15:8];
                         rom_spr_a[0] <= 1'b1; s_half <= 1'b1; ss <= S_ROW_W;
                     end
                     else begin
                         row_l[7:0] <= rom_spr_d[7:0]; row_h[7:0] <= rom_spr_d[15:8];
                         s_px <= 4'd0; ss <= S_PIX;
                     end
                 end
        S_PIX:   begin
                     if ({px_h, px_l} != 2'd0 && !wx[8]) begin
                         lb_we <= 1'b1; lb_wa <= wx[7:0]; lb_wd <= {1'b1, 2'b00, s_color, px_h, px_l};
                     end
                     s_px <= s_px + 4'd1;
                     if (s_px == 4'd15) begin
                         if (!pc_last) begin s_pc <= 1'b1; ss <= S_PIECE; end
                         else if (s_n == 3'd7) ss <= S_IDLE;
                         else begin s_n <= s_n + 3'd1; s_pc <= 1'b0; ss <= S_SPR; end
                     end
                 end
        default: ss <= S_IDLE;
    endcase
end

// ------------------------------------------------------------------ playfield pipeline
// S0: logical (MAME screen) coordinates; the man area reads the tilemap scrolly lines lower
wire [7:0] lx = crt_flip ? ~hcnt[7:0] : hcnt[7:0];
wire [7:0] ly = crt_flip ? ~vcnt[7:0] : vcnt[7:0];
wire       man = (gflip ? (lx >= 8'd152 && lx < 8'd192) : (lx >= 8'd64 && lx < 8'd96)) && ly > 8'd40 && ly < 8'd216;
wire [8:0] sy  = {1'b0, ly} + (man ? {6'd0, scrolly} : 9'd0);
wire       t_ok = !(man && sy >= 9'd216);
wire [7:0] tx  = gflip ? ~lx : lx;
wire [7:0] ty  = gflip ? ~sy[7:0] : sy[7:0];
assign vram_va = {ty[7:3], tx[7:3]};

logic [2:0] s1_tx, s1_ty;
logic [4:0] s1_col, s1_row;
logic [7:0] s1_lx;
logic       s1_ok, s1_ln, s1_clr;
logic [7:0] s1_code;
logic [2:0] s2_tx;
logic [4:0] s2_color;
logic       s2_ok;
logic [15:0] s2_chr;
logic [7:0] s2_lb;
logic [7:0] s3_pen;                    // palette pen 0x00-0xBF
logic [3:0] blk_d[3];

assign rom_chr_a = {1'b0, s1_code, s1_ty};
assign lb_ra     = s1_lx;
assign lb_clr    = ce_pix && s1_clr;
assign disp_buf  = s1_ln;

// MAME get_tile_info colour
wire [4:0] tcolor = (s1_col >= 5'h1e) ? ((s1_row < 5'h0c) ? 5'h15 : (s1_row < 5'h14) ? 5'h16 : 5'h14) :
                    (s1_row == 5'h04 || s1_row == 5'h1b) ? {palbank, 4'hc} : {palbank, s1_col[4:1]};
wire [1:0] tpen   = {s2_chr[15 - s2_tx], s2_chr[7 - s2_tx]};
wire [7:0] lbq    = lb_q[disp_buf];

always_ff @(posedge clk) begin
    if (ce_pix) begin
        s1_code <= vram_vq;   s1_lx <= lx;     s1_ok <= t_ok;
        s1_tx   <= tx[2:0];   s1_ty <= ty[2:0];
        s1_col  <= tx[7:3];   s1_row <= ty[7:3];
        s1_ln   <= vcnt[0];   s1_clr <= !hcnt[8];

        s2_chr  <= rom_chr_d; s2_tx <= s1_tx;  s2_color <= tcolor; s2_ok <= s1_ok;
        s2_lb   <= lbq;

        if (s2_ok && tpen != 2'd0) s3_pen <= {1'b0, s2_color, tpen};
        else if (s2_lb[7])         s3_pen <= {3'b100, s2_lb[4:0]};
        else                       s3_pen <= 8'd0;

        blk_d[0] <= {hbl_s0, vbl_s0, hs_s0, vs_s0};
        blk_d[1] <= blk_d[0];
        blk_d[2] <= blk_d[1];
    end
end

// ------------------------------------------------------------------ palette (MAME cheekyms_state::palette): 1-bit RGB
wire [7:0] pb  = prom[{s3_pen[7:6], 5'd0} + {2'b00, s3_pen[4:0]}];      // 0x20 * (i / 2) + j, i = pen >> 5
wire [2:0] rgb = s3_pen[5] ? pb[6:4] : pb[2:0];

always_ff @(posedge clk) begin
    if (ce_pix) begin
        video_r <= {8{rgb[0]}};
        video_g <= {8{rgb[1]}};
        video_b <= {8{rgb[2]}};
        {video_hblank, video_vblank, video_hs, video_vs} <= blk_d[2];
    end
end

endmodule
