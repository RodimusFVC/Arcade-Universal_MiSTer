//============================================================================
//
//  Universal 8201 board (Mr. Do!)
//  Copyright (C) 2026 Rodimus
//
//  From MAME mrdo.cpp / mrdo_v.cpp (Nicola Salmoria), with the U001 PAL
//  behaviour from Darren Olafson's Mr. Do! core (secret_pal.v).
//
//  Main Z80 8.2 MHz / 2, video 19.6 MHz / 4 (here 19.656 / 4: +0.29 %),
//  312 x 262, visible x 8-247, y 32-223.
//    0000-7FFF ROM            8000-87FF bg RAM (attr 000-3FF, code 400-7FF)
//    8800-8FFF fg RAM         9000-90FF sprite RAM (write only)
//    9800 flip (bit 0)        9801 / 9802 SN76489         9803 U001 PAL read
//    A000-A003 P1, P2, DSW1, DSW2                         E000-EFFF RAM
//    F000-F7FF bg scroll x    F800-FFFF bg scroll y
//  IRQ at vblank, held until acknowledged (MAME irq0_line_hold).
//
//  prot_mode: 0 mrdo (PAL with feedback: Darren Olafson's state model, clocked by
//  fg RAM writes), 1 Taito PAL (MAME mrdot_state jedutil equations), 2 none (mrlo).
//
//============================================================================

module mrdo_board
(
    output logic        [13:0] z80_o,          // shared T80 (rtl/z80_socket.sv)
    input  logic        [29:0] z80_i,
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic               pause,
    input  logic         [1:0] prot_mode,
    input  logic               cpu_4m0,        // 1: 4.000 MHz CPU (mrdobl), 0: 4.1 MHz
    input  logic               crt_flip,       // mirror the whole picture (OSD CRT Flip)

    input  logic         [7:0] p1,
    input  logic         [7:0] p2,
    input  logic         [7:0] dsw1,
    input  logic         [7:0] dsw2,

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
    output logic        [11:0] rom_fg_a,       // gfx1: [7:0] plane 0x0000 (MSB), [15:8] plane 0x1000
    input  logic        [15:0] rom_fg_d,
    output logic        [11:0] rom_bg_a,       // gfx2
    input  logic        [15:0] rom_bg_d,
    output logic        [10:0] rom_spr_a,      // gfx3: 4 byte lanes of one sprite row
    input  logic        [31:0] rom_spr_d,

    input  logic               prom_wr,        // MAME proms region 0x00-0x7F
    input  logic         [6:0] prom_a,
    input  logic         [7:0] prom_d,

    input  logic        [11:0] hs_address,
    output logic         [7:0] hs_data_out,
    input  logic         [7:0] hs_data_in,
    input  logic               hs_write
);

// ------------------------------------------------------------------ clocks
logic [1:0] ph = 2'd0;
always_ff @(posedge clk) ph <= ph + 2'd1;
assign ce_pix = (ph == 2'd3);

// CPU: 2x CPU clock edge stream (8.2 or 8.0 MHz) from 19.656 MHz, alternating rising / falling
wire  [11:0] frac_n = cpu_4m0 ? 12'd1000 : 12'd1025;
logic [11:0] frac_q = 12'd0;
logic        frac_ph = 1'b0, cen_p = 1'b0, cen_n = 1'b0;
wire  [12:0] frac_sum = {1'b0, frac_q} + {1'b0, frac_n};
wire         frac_edge = frac_sum >= 13'd2457;
wire  [12:0] frac_sub = frac_sum - 13'd2457;
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
logic        int_n = 1'b1, vbl_d = 1'b0;

z80_socket cpu
(
    .RESET_n   (~reset),
    .CLK       (clk),
    .CEN_p     (cen_p & ~pause),
    .CEN_n     (cen_n & ~pause),
    .WAIT_n    (1'b1),
    .INT_n     (int_n),
    .NMI_n     (1'b1),
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

always_ff @(posedge clk) begin
    vbl_d <= vbl_s0;
    if (reset)                   int_n <= 1'b1;
    else if (!m1_n && !iorq_n)   int_n <= 1'b1;
    else if (vbl_s0 && !vbl_d && vcnt == 9'd224) int_n <= 1'b0;
end

wire mem      = !mreq_n && rfsh_n;
wire rom_cs   = mem && !a[15];
wire bg_cs    = mem && a[15:11] == 5'b10000;
wire fg_cs    = mem && a[15:11] == 5'b10001;
wire spr_cs   = mem && a[15:8]  == 8'h90;
wire io98_cs  = mem && a[15:11] == 5'b10011;
wire in_cs    = mem && a[15:12] == 4'hA;
wire ram_cs   = mem && a[15:12] == 4'hE;
wire scx_cs   = mem && a[15:11] == 5'b11110;
wire scy_cs   = mem && a[15:11] == 5'b11111;
wire wr       = !wr_n;

assign rom_cpu_a = a[14:0];

logic [7:0] bga_q, bgc_q, fga_q, fgc_q, ram_q;
logic [7:0] vbga_q, vbgc_q, vfga_q, vfgc_q;
logic [9:0] vbg_a, vfg_a;

dpram_dc #(.widthad_a(10)) bg_attr
(
    .clock_a(clk), .address_a(a[9:0]), .data_a(dout), .wren_a(bg_cs && wr && !a[10]), .q_a(bga_q),
    .clock_b(clk), .address_b(vbg_a), .q_b(vbga_q)
);
dpram_dc #(.widthad_a(10)) bg_code
(
    .clock_a(clk), .address_a(a[9:0]), .data_a(dout), .wren_a(bg_cs && wr && a[10]), .q_a(bgc_q),
    .clock_b(clk), .address_b(vbg_a), .q_b(vbgc_q)
);
dpram_dc #(.widthad_a(10)) fg_attr
(
    .clock_a(clk), .address_a(a[9:0]), .data_a(dout), .wren_a(fg_cs && wr && !a[10]), .q_a(fga_q),
    .clock_b(clk), .address_b(vfg_a), .q_b(vfga_q)
);
dpram_dc #(.widthad_a(10)) fg_code
(
    .clock_a(clk), .address_a(a[9:0]), .data_a(dout), .wren_a(fg_cs && wr && a[10]), .q_a(fgc_q),
    .clock_b(clk), .address_b(vfg_a), .q_b(vfgc_q)
);
dpram_dc #(.widthad_a(12)) work_ram
(
    .clock_a(clk), .address_a(a[11:0]), .data_a(dout), .wren_a(ram_cs && wr), .q_a(ram_q),
    .clock_b(clk), .address_b(hs_address), .data_b(hs_data_in), .wren_b(hs_write), .q_b(hs_data_out)
);

// Sprite RAM: 64 entries x 4 byte lanes (code, y, attr, x)
logic [5:0] spr_rd_e;
logic [7:0] spr_q[4];
genvar l;
generate
    for (l = 0; l < 4; l++) begin : spr_lane
        dpram_dc #(.widthad_a(6)) ram
        (
            .clock_a(clk), .address_a(a[7:2]), .data_a(dout), .wren_a(spr_cs && wr && a[1:0] == l),
            .clock_b(clk), .address_b(spr_rd_e), .q_b(spr_q[l])
        );
    end
endgenerate

logic       flip = 1'b0;
logic [7:0] scroll_x = 8'd0, scroll_y = 8'd0;
always_ff @(posedge clk) begin
    if (reset) begin
        flip <= 1'b0; scroll_x <= 8'd0; scroll_y <= 8'd0;
    end
    else if (wr) begin
        if (io98_cs && a[1:0] == 2'd0) flip     <= dout[0];   // bits 1-3: playfield priority (unused by Mr. Do!, as MAME)
        if (scx_cs)                    scroll_x <= dout;
        if (scy_cs)                    scroll_y <= dout;
    end
end

// ------------------------------------------------------------------ U001 PAL16R6
logic [7:0] pal_q = 8'hFF;
logic [7:0] pal_r = 8'h00;     // Darren's state model output
logic       pal_method = 1'b0;
logic       fg_wr_d = 1'b0;
wire        fg_wr = fg_cs && wr;
wire  [7:0] i_d = dout;

// MAME mrdot_state::protection_w (jedutil equations): i9 = D0 ... i2 = D7
wire i9 = i_d[0], i8 = i_d[1], i6 = i_d[3], i5 = i_d[4], i4 = i_d[5], i3 = i_d[6], i2 = i_d[7];
wire t1 =  i2 & ~i3 &  i4 & ~i5 & ~i6 & ~i8 &  i9;
wire t2 = ~i2 & ~i3 &  i4 &  i5 & ~i6 &  i8 & ~i9;
wire t3 =  i2 &  i3 & ~i4 & ~i5 &  i6 & ~i8 &  i9;
wire t4 = ~i2 &  i3 &  i4 & ~i5 &  i6 &  i8 &  i9;
wire [7:0] taito_pal = ~{1'b0, t3 | t4, t1 | t3, t1, t1 | t3, t1 | t2, t1, 1'b0};

always_ff @(posedge clk) begin
    fg_wr_d <= fg_wr;
    if (reset) pal_q <= 8'hFF;                                      // MAME machine_reset: outputs high
    else if (fg_wr && !fg_wr_d) begin
        pal_q <= taito_pal;
        // Darren Olafson's model of the real (feedback) PAL: partial-match chain, then exact values win
        if      (i_d[7:4] == 4'b1010)                    pal_r <= 8'h40;
        else if (i_d[6:3] == 4'b1001) begin              pal_r <= 8'h16; pal_method <= 1'b0; end
        else if (i_d[6:3] == 4'b1000) begin              pal_r <= 8'h4C; pal_method <= 1'b1; end
        else if (i_d[7:4] == 4'b0011 && !pal_method)     pal_r <= 8'h7A;
        else if (i_d[7:4] == 4'b0011 &&  pal_method)     pal_r <= 8'h2A;
        else if (i_d[7:4] == 4'b0110 && !pal_method)     pal_r <= 8'h3E;
        else if (i_d[7:4] == 4'b0110 &&  pal_method)     pal_r <= 8'h66;
        if      (i_d == 8'hA5)                           pal_r <= 8'h40;
        else if (i_d == 8'hCD) begin                     pal_r <= 8'h16; pal_method <= 1'b0; end
        else if (i_d == 8'hC2) begin                     pal_r <= 8'h4C; pal_method <= 1'b1; end
        else if (i_d == 8'h36 && !pal_method)            pal_r <= 8'h7A;
        else if (i_d == 8'h36 &&  pal_method)            pal_r <= 8'h2A;
        else if (i_d == 8'h6F && !pal_method)            pal_r <= 8'h3E;
        else if (i_d == 8'h6F &&  pal_method)            pal_r <= 8'h66;
    end
end

wire [7:0] pal_out = (prot_mode == 2'd0) ? {1'b0, pal_r[6:1], 1'b0} :
                     (prot_mode == 2'd1) ? pal_q : 8'h00;

always_comb begin
    din = 8'hFF;
    if (rom_cs)                                din = rom_cpu_d;
    else if (bg_cs)                            din = a[10] ? bgc_q : bga_q;
    else if (fg_cs)                            din = a[10] ? fgc_q : fga_q;
    else if (ram_cs)                           din = ram_q;
    else if (io98_cs && a[1:0] == 2'd3)        din = pal_out;
    else if (in_cs)
        case (a[1:0])
            2'd0: din = p1;
            2'd1: din = p2;
            2'd2: din = dsw1;
            2'd3: din = dsw2;
        endcase
end

// ------------------------------------------------------------------ sound
logic signed [10:0] sn1_out, sn2_out;
wire sn_cen = cen_p & ~pause;

jt89 sn1
(
    .rst(reset), .clk(clk), .clk_en(sn_cen),
    .wr_n(~(io98_cs && wr && a[1:0] == 2'd1)), .cs_n(1'b0), .din(dout), .sound(sn1_out), .ready()
);
jt89 sn2
(
    .rst(reset), .clk(clk), .clk_en(sn_cen),
    .wr_n(~(io98_cs && wr && a[1:0] == 2'd2)), .cs_n(1'b0), .din(dout), .sound(sn2_out), .ready()
);

wire signed [11:0] snd_sum = {sn1_out[10], sn1_out} + {sn2_out[10], sn2_out};
assign audio = {snd_sum, 4'd0};

// ------------------------------------------------------------------ PROMs (U2, T2 palette; F10 sprite lookup)
logic [7:0] prom_u2[32], prom_t2[32], prom_f10[32];
always_ff @(posedge clk) begin
    if (prom_wr) begin
        case (prom_a[6:5])
            2'd0: prom_u2[prom_a[4:0]]  <= prom_d;
            2'd1: prom_t2[prom_a[4:0]]  <= prom_d;
            2'd2: prom_f10[prom_a[4:0]] <= prom_d;
            default: ;                                   // J10 timing PROM: video timing is built in logic
        endcase
    end
end

// ------------------------------------------------------------------ sprites: line buffer built a line ahead
logic [7:0] lb_q[2];
logic [7:0] lb_wa;
logic [7:0] lb_wd;
logic       lb_we;
logic [7:0] lb_ra;
logic       lb_clr;

// buffer for line y is buffer y[0]; the builder fills buffer (y+1)[0] during line y
logic       build_buf;
logic       disp_buf;

generate
    for (l = 0; l < 2; l++) begin : lbuf
        dpram_dc #(.widthad_a(8)) ram
        (
            .clock_a(clk), .address_a(lb_wa), .data_a(lb_wd), .wren_a(lb_we && build_buf == l),
            .clock_b(clk), .address_b(lb_ra), .data_b(8'd0), .wren_b(lb_clr && disp_buf == l), .q_b(lb_q[l])
        );
    end
endgenerate

// target line for the builder (CRT Flip: build the mirrored logical line; visible y 32-223 is symmetric)
wire  [8:0] sp_tgt = (vcnt >= 9'd260) ? vcnt - 9'd260 : vcnt + 9'd2;

typedef enum logic [1:0] {SP_IDLE, SP_ADDR, SP_CHK, SP_PIX} sp_state_t;
sp_state_t   sp_st = SP_IDLE;
logic  [5:0] sp_e;
logic  [8:0] sp_line;
logic  [3:0] sp_px;
logic  [7:0] sp_x;
logic  [3:0] sp_col;
logic        sp_fx;
logic  [3:0] sp_color;
logic        sp_rom_ok;

assign spr_rd_e = sp_e;

wire  [8:0] sp_ytop = 9'd256 - {1'b0, spr_q[1]};
wire  [8:0] sp_r    = sp_line - sp_ytop;
wire        sp_vis  = (spr_q[1] != 8'd0) && (sp_line >= sp_ytop) && (sp_r < 9'd16);
logic [10:0] sp_rom_a;
assign rom_spr_a = sp_rom_a;

wire  [3:0] sp_c    = sp_fx ? ~sp_px : sp_px;
wire  [7:0] sp_byte = rom_spr_d[{sp_c[3:2], 3'b000} +: 8];
wire  [1:0] sp_pen  = {sp_byte[sp_c[1:0]], sp_byte[{1'b1, sp_c[1:0]}]};
wire  [5:0] sp_ci   = {sp_color, sp_pen};
wire  [7:0] sp_ct   = prom_f10[sp_ci[4:0]];
wire  [3:0] sp_ent  = sp_ci[5] ? sp_ct[7:4] : sp_ct[3:0];
wire  [8:0] sp_xp   = {1'b0, sp_x} + {5'd0, sp_px};

always_ff @(posedge clk) begin
    lb_we <= 1'b0;
    case (sp_st)
        // At the end of line v, build line v+2 during line v+1 into buffer v[0] (displayed for line v,
        // already cleared behind the read); finishes before line v+2 reaches the line-buffer stage.
        SP_IDLE: if (ce_pix && hcnt == 9'd311) begin
                     sp_line   <= crt_flip ? {1'b0, ~sp_tgt[7:0]} : sp_tgt;
                     build_buf <= vcnt[0];
                     sp_e  <= 6'd63;
                     sp_st <= SP_ADDR;
                 end
        SP_ADDR: sp_st <= SP_CHK;                                // sprite RAM read
        SP_CHK:  begin
                     if (sp_vis) begin
                         sp_rom_a <= {spr_q[0][6:0], spr_q[2][5] ? ~sp_r[3:0] : sp_r[3:0]};
                         sp_x     <= spr_q[3];
                         sp_fx    <= spr_q[2][4];
                         sp_color <= spr_q[2][3:0];
                         sp_px    <= 4'd0;
                         sp_rom_ok <= 1'b0;
                         sp_st    <= SP_PIX;
                     end
                     else if (sp_e == 6'd0) sp_st <= SP_IDLE;
                     else begin sp_e <= sp_e - 6'd1; sp_st <= SP_ADDR; end
                 end
        SP_PIX:  begin
                     if (!sp_rom_ok) sp_rom_ok <= 1'b1;            // ROM read cycle
                     else begin
                         if (sp_pen != 2'd0 && !sp_xp[8]) begin
                             lb_we <= 1'b1;
                             lb_wa <= sp_xp[7:0];
                             lb_wd <= {1'b1, sp_ent[3:2], 1'b0, sp_ent};
                         end
                         sp_px <= sp_px + 4'd1;
                         if (sp_px == 4'd15) begin
                             if (sp_e == 6'd0) sp_st <= SP_IDLE;
                             else begin sp_e <= sp_e - 6'd1; sp_st <= SP_ADDR; end
                         end
                     end
                 end
    endcase
end

// ------------------------------------------------------------------ tile pipeline (4 pixel stages)
// CRT Flip mirrors the logical raster (visible x 8-247 / y 32-223 are symmetric), so it XORs with the game's flip
wire       tflip = flip ^ crt_flip;
wire [7:0] xs = tflip ? ~hcnt[7:0] : hcnt[7:0];
wire [7:0] ys = tflip ? ~vcnt[7:0] : vcnt[7:0];
wire [7:0] bx = xs + scroll_x;
wire [7:0] by = ys + scroll_y;

assign vfg_a = {ys[7:3], xs[7:3]};
assign vbg_a = {by[7:3], bx[7:3]};

// stage 1: tile RAM data
logic [7:0] s1_fga, s1_fgc, s1_bga, s1_bgc;
logic [2:0] s1_fx, s1_fy, s1_bx, s1_by;
logic [7:0] s1_x;
logic       s1_ln;
// stage 2: gfx ROM data
logic [7:0] s2_fga, s2_bga;
logic [15:0] s2_fgd, s2_bgd;
logic [2:0] s2_fx, s2_bx;
logic [7:0] s2_x;
logic       s2_ln;
// stage 3: palette index
logic [7:0] s3_idx;
logic [3:0] blk_d[4];                                         // {hbl, vbl, hs, vs} per stage

assign rom_fg_a = {s1_fga[7], s1_fgc, s1_fy};
assign rom_bg_a = {s1_bga[7], s1_bgc, s1_by};

wire [1:0] fg_pen = {s2_fgd[s2_fx], s2_fgd[{1'b1, s2_fx}]};
wire [1:0] bg_pen = {s2_bgd[s2_bx], s2_bgd[{1'b1, s2_bx}]};
wire       fg_op  = (fg_pen != 2'd0) || s2_fga[6];             // attr bit 6: TILE_FORCE_LAYER0 (pen 0 opaque)
wire       bg_op  = (bg_pen != 2'd0) || s2_bga[6];
wire [7:0] lbq    = lb_q[disp_buf];

assign lb_ra  = crt_flip ? ~s2_x : s2_x;
assign lb_clr = ce_pix;                                       // clear on the edge that samples the read

always_ff @(posedge clk) begin
    if (ce_pix) begin
        s1_fga <= vfga_q; s1_fgc <= vfgc_q; s1_bga <= vbga_q; s1_bgc <= vbgc_q;
        s1_fx  <= xs[2:0]; s1_fy <= ys[2:0]; s1_bx <= bx[2:0]; s1_by <= by[2:0];
        s1_x   <= hcnt[7:0]; s1_ln <= vcnt[0];

        s2_fga <= s1_fga; s2_bga <= s1_bga; s2_fx <= s1_fx; s2_bx <= s1_bx;
        s2_fgd <= rom_fg_d; s2_bgd <= rom_bg_d;
        s2_x   <= s1_x;   s2_ln  <= s1_ln;
        disp_buf <= s1_ln;

        if (lbq[7])     s3_idx <= {1'b0, lbq[6:0]};
        else if (fg_op) s3_idx <= {s2_fga[5:0], fg_pen};
        else if (bg_op) s3_idx <= {s2_bga[5:0], bg_pen};
        else            s3_idx <= 8'd0;

        blk_d[0] <= {hbl_s0, vbl_s0, hs_s0, vs_s0};
        blk_d[1] <= blk_d[0];
        blk_d[2] <= blk_d[1];
        blk_d[3] <= blk_d[2];
    end
end

// ------------------------------------------------------------------ palette (MAME palette_init)
function automatic [7:0] w16(input [3:0] i);
    case (i)
        4'd0: w16 = 8'd0;    4'd1: w16 = 8'd0;    4'd2: w16 = 8'd0;    4'd3: w16 = 8'd88;
        4'd4: w16 = 8'd0;    4'd5: w16 = 8'd112;  4'd6: w16 = 8'd133;  4'd7: w16 = 8'd192;
        4'd8: w16 = 8'd60;   4'd9: w16 = 8'd150;  4'd10: w16 = 8'd166; 4'd11: w16 = 8'd212;
        4'd12: w16 = 8'd180; 4'd13: w16 = 8'd221; 4'd14: w16 = 8'd229; 4'd15: w16 = 8'd255;
    endcase
endfunction

wire [7:0] pt = prom_t2[{s3_idx[7:5], s3_idx[1:0]}];
wire [7:0] pu = prom_u2[{s3_idx[4:2], s3_idx[1:0]}];

always_ff @(posedge clk) begin
    if (ce_pix) begin
        video_r <= w16({pu[1:0], pt[1:0]});
        video_g <= w16({pu[3:2], pt[3:2]});
        video_b <= w16({pu[5:4], pt[5:4]});
        {video_hblank, video_vblank, video_hs, video_vs} <= blk_d[2];
    end
end

endmodule
