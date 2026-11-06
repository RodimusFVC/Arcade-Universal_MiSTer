//  Copyright (C) 2026 Rodimus
// Based on MAME cosmicg.cpp, getaway.cpp (Nicola Salmoria, Lee Taylor, AJR, hap, Angelo Salese, BSD-3-Clause)

module tms_board
(
    input  logic               clk,
    input  logic               reset,
    input  logic               pause,
    input  logic               getaway,
    input  logic               crt_flip,

    input  logic         [7:0] in0,
    input  logic         [7:0] in1,            // cosmicg IN1 / getaway controls: [0] accelerate, [1] left, [2] right (low)
    input  logic         [7:0] in2,            // cosmicg IN2: [0] coin (high), [1] cocktail
    input  logic         [7:0] dsw0,
    input  logic         [7:0] dsw1,

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
    output logic        [15:0] snd_out,

    output logic        [14:0] rom_cpu_a,
    input  logic         [7:0] rom_cpu_d,
    output logic        [11:0] rom_chr_a,      // cosmicg colour map / getaway gfx (bit 12 of the gfx address = [15:8])
    input  logic        [15:0] rom_chr_d,

    output ram_pool_pkg::pram_i_t [12:0] pr_i,
    input  ram_pool_pkg::pram_o_t [12:0] pr_o,

    output chip_pool_pkg::tms9900_i_t   tms9900_0_i,
    input  chip_pool_pkg::tms9900_o_t   tms9900_0_o,
    output chip_pool_pkg::mc6845_i_t    mc6845_0_i,
    input  chip_pool_pkg::mc6845_o_t    mc6845_0_o,

    input  logic        [15:0] hs_address,
    output logic         [7:0] hs_data_out,
    input  logic         [7:0] hs_data_in,
    input  logic               hs_write
);

logic [1:0] ph = 2'd0;
always_ff @(posedge clk) ph <= ph + 2'd1;
wire ce_cg = (ph == 2'd3);

logic [14:0] pix_acc = 15'd0;
wire  [15:0] pix_sum = {1'b0, pix_acc} + 16'd5408;
wire  [15:0] pix_sub = pix_sum - 16'd19656;
logic        ce_ga = 1'b0;
always_ff @(posedge clk) begin
    ce_ga   <= pix_sum >= 16'd19656;
    pix_acc <= (pix_sum >= 16'd19656) ? pix_sub[14:0] : pix_sum[14:0];
end
assign ce_pix = getaway ? ce_ga : ce_cg;

logic [14:0] st_acc = 15'd0;
logic        step2 = 1'b0;
wire  [15:0] st_sum = {1'b0, st_acc} + 16'd4344;
always_ff @(posedge clk) begin
    step2  <= getaway && st_sum >= 16'd19656;
    st_acc <= (st_sum >= 16'd19656) ? st_sum[14:0] - 15'd19656 : st_sum[14:0];
end

logic [15:0] cpu_a, cpu_do;
logic        cpu_rd, cpu_wr, cpu_as, cpu_cruin, cpu_cruout, cpu_cruclk, cpu_int_ack;
logic        cpu_ready = 1'b1;
logic        cpu_holda;
logic        int_req;
logic  [7:0] bhi, blo;
logic        blit_busy;

assign tms9900_0_i.reset    = reset;
assign tms9900_0_i.data_in  = {bhi, blo};
assign tms9900_0_i.ready    = cpu_ready;
assign tms9900_0_i.int_req  = int_req;
assign tms9900_0_i.ic03     = getaway ? 4'd2 : 4'd4;
assign tms9900_0_i.cruin    = cpu_cruin;
assign tms9900_0_i.hold     = pause | blit_busy;
assign tms9900_0_i.byte_bus = ~getaway;
assign tms9900_0_i.ir_step2 = step2;
assign cpu_a       = tms9900_0_o.addr_out;
assign cpu_do      = tms9900_0_o.data_out;
assign cpu_rd      = tms9900_0_o.rd;
assign cpu_wr      = tms9900_0_o.wr;
assign cpu_as      = tms9900_0_o.as;
assign cpu_int_ack = tms9900_0_o.int_ack;
assign cpu_cruout  = tms9900_0_o.cruout;
assign cpu_cruclk  = tms9900_0_o.cruclk;
assign cpu_holda   = tms9900_0_o.holda;

logic [1:0]  bs = 2'd0;
wire         bph = (bs == 2'd2);
wire  [15:0] ba  = {cpu_a[15:1], bph};
logic [15:0] ba_q;
logic  [7:0] byte_q;
wire         b_wr = cpu_wr && (bs == 2'd1 || bs == 2'd2);

logic hs_own = 1'b0;
always_ff @(posedge clk) hs_own <= pause && !getaway && cpu_holda && bs == 2'd0;
assign hs_data_out = pr_o[0].a_q;
wire  [7:0]  b_do = bph ? cpu_do[7:0] : cpu_do[15:8];

always_ff @(posedge clk) begin
    ba_q <= ba;
    if (reset) begin bs <= 2'd0; cpu_ready <= 1'b1; end
    else case (bs)
        2'd0: if (cpu_as) begin bs <= 2'd1; cpu_ready <= 1'b0; end
        2'd1: bs <= 2'd2;
        2'd2: begin bhi <= byte_q; bs <= 2'd3; end
        2'd3: begin blo <= byte_q; bs <= 2'd0; cpu_ready <= 1'b1; end
    endcase
end

wire cg_rom  = !ba[13];
wire cg_hole = ba[13:3] == 11'h7FE;
wire cg_vram = ba[13] && !cg_hole;
wire crtc_en = !getaway && cg_hole && (bs == 2'd2) && ((cpu_wr && (ba[2:0] == 3'd1 || ba[2:0] == 3'd5)) ||
                                                      (cpu_rd && ba[2:0] == 3'd7));
wire ga_rom = ba < 16'h3000;
wire ga_ram = ba[15:11] == 5'b00111;

assign rom_cpu_a = getaway ? {1'b0, ba[0], ba[13:1]} : {2'b00, ba[12:0]};

wire [7:0] cg_s = rom_cpu_d ^ ((ba_q[13:0] == 14'h1E9B || ba_q[13:0] == 14'h1E9F) ? 8'h20 : 8'h00);
wire [7:0] cg_rom_d = {cg_s[4], cg_s[5], cg_s[6], cg_s[7], cg_s[0], cg_s[1], cg_s[2], cg_s[3]};

logic [7:0] pl_qa[3], ram_q, crtc_do;
always_comb begin
    byte_q = 8'h00;
    if (!getaway) begin
        if (!ba_q[13])                          byte_q = cg_rom_d;
        else if (ba_q[13:3] == 11'h7FE)         byte_q = (ba_q[2:0] == 3'd7) ? crtc_do : 8'h00;
        else                                    byte_q = pl_qa[0];
    end
    else begin
        if (ba_q < 16'h3000)                    byte_q = rom_cpu_d;
        else if (ba_q[15:11] == 5'b00111)       byte_q = ram_q;
    end
end

assign pr_i[3].a_addr = {5'd0, ba[10:0]};  assign pr_i[3].a_d = b_do;  assign pr_i[3].a_we = getaway && ga_ram && b_wr;
assign pr_i[3].b_addr = 16'd0;             assign pr_i[3].b_d = 8'd0;  assign pr_i[3].b_we = 1'b0;
assign ram_q = pr_o[3].a_q;

wire [10:0] cb = getaway ? {4'd0, cpu_a[7:1]} : cpu_a[11:1];
logic [4:0] pedal = 5'd0;
logic [7:0] wheel = 8'd0;
wire [10:0] dsw   = {dsw1[2:0], dsw0};
logic [13:0] crtc_ma;
logic  [4:0] crtc_ra;
wire  [4:0] cb_w = cb[4:0] - 5'd5;
wire  [4:0] cb_d = cb[4:0] - 5'd13;

always_comb begin
    cpu_cruin = 1'b0;
    if (!getaway) begin
        if (cb[10:2] == 9'd0)                   cpu_cruin = crtc_ma[{2'b10, cb[1:0]}];
        else if (cb[10:2] == 9'd1)              cpu_cruin = in0[cb[2:0]];
        else if (cb[10:3] == 8'd1)              cpu_cruin = in1[cb[2:0]];
    end
    else begin
        if (cb < 11'h005)                       cpu_cruin = pedal[cb[2:0]];
        else if (cb < 11'h00D)                  cpu_cruin = wheel[cb_w[2:0]];
        else if (cb < 11'h018)                  cpu_cruin = dsw[cb_d[3:0]];
        else if (cb == 11'h019)                 cpu_cruin = in0[0];
        else if (cb == 11'h01A)                 cpu_cruin = in0[1];
    end
end

logic       cruclk_d = 1'b0;
wire        cru_wr = cpu_cruclk && !cruclk_d && cpu_a[15:13] == 3'd0;
logic [1:0] creg = 2'd0;
logic [7:0] regs[16];
logic       blit_go;

always_ff @(posedge clk) begin
    cruclk_d <= cpu_cruclk;
    blit_go  <= 1'b0;
    if (reset) begin
        snd_out <= 16'd0; creg <= 2'd0;
        for (int i = 0; i < 16; i++) regs[i] <= 8'd0;
    end
    else if (cru_wr) begin
        if (!getaway) begin
            if (cb < 11'd16)                    snd_out[cb[3:0]] <= cpu_cruout;
            if (cb == 11'h016 || cb == 11'h017) creg[cb[0]] <= cpu_cruout;
        end
        else if (!cb[7]) begin
            regs[cb[6:3]][cb[2:0]] <= cpu_cruout;
            if (cb == 11'h00F && cpu_cruout && !regs[1][7]) blit_go <= 1'b1;
        end
    end
end

logic       ga_irq = 1'b0;
logic [9:0] ga_irq_t = 10'd0;
logic       ga_vbl_d = 1'b0;
logic       ga_vbl;
always_ff @(posedge clk) begin
    ga_vbl_d <= ga_vbl;
    if (reset || cpu_int_ack)                     ga_irq <= 1'b0;
    else if (ga_vbl && !ga_vbl_d)                 begin ga_irq <= 1'b1; ga_irq_t <= 10'd0; end
    else if (ga_irq && ce_ga) begin
        ga_irq_t <= ga_irq_t + 10'd1;
        if (ga_irq_t == 10'd687) ga_irq <= 1'b0;
    end
end
assign int_req = getaway ? ga_irq : in2[0];

always_ff @(posedge clk) begin
    if (reset) begin pedal <= 5'd0; wheel <= 8'd0; end
    else if (ga_vbl && !ga_vbl_d) begin
        if (!in1[0]) pedal <= (pedal >= 5'd29) ? 5'd31 : pedal + 5'd2;
        else         pedal <= (pedal <= 5'd2)  ? 5'd0  : pedal - 5'd2;
        if (!in1[1] && in1[2])       begin if ($signed(wheel) > -8'sd8) wheel <= wheel - 8'd1; end
        else if (!in1[2] && in1[1])  begin if ($signed(wheel) <  8'sd8) wheel <= wheel + 8'd1; end
        else if ($signed(wheel) > 0) wheel <= wheel - 8'd1;
        else if ($signed(wheel) < 0) wheel <= wheel + 8'd1;
    end
end

typedef enum logic [2:0] {B_IDLE, B_GFX, B_GFXW, B_RD0, B_WR0, B_RD1, B_WR1, B_NEXT} bstate_t;
bstate_t     bst = B_IDLE;
logic [12:0] b_src;
logic  [2:0] b_cmask;
logic  [7:0] b_x, b_y, b_h, b_yi;
logic  [4:0] b_w, b_c;
logic        b_fill, b_main;
logic  [7:0] b_g;
assign blit_busy = (bst != B_IDLE) || blit_go;

wire  [7:0] b_dy   = b_y + b_yi;
wire  [4:0] b_col0 = b_x[7:3];
wire  [4:0] b_col1 = b_x[7:3] + 5'd1;
wire  [7:0] b_v8   = b_fill ? 8'hFF : {b_g[0], b_g[1], b_g[2], b_g[3], b_g[4], b_g[5], b_g[6], b_g[7]};
wire [15:0] b_v16  = {8'd0, b_v8} << b_x[2:0];
wire [15:0] b_m16  = 16'h00FF << b_x[2:0];
wire        b_hi   = (bst == B_RD1 || bst == B_WR1);
wire  [4:0] b_col  = b_hi ? b_col1 : b_col0;
wire  [7:0] b_m    = b_hi ? b_m16[15:8] : b_m16[7:0];
wire  [7:0] b_v    = b_hi ? b_v16[15:8] : b_v16[7:0];
wire        bl_wr  = (bst == B_WR0 || bst == B_WR1);

wire [7:0] gfx_d = b_src[12] ? rom_chr_d[15:8] : rom_chr_d[7:0];

always_ff @(posedge clk) begin
    if (reset) bst <= B_IDLE;
    else case (bst)
        B_IDLE: if (blit_go) begin
                    b_src   <= {regs[6][4:0], regs[5]};
                    b_cmask <= regs[6][7:5] ^ 3'd7;
                    b_x     <= regs[4];
                    b_y     <= regs[3];
                    b_h     <= regs[8];
                    b_w     <= regs[7][4:0];
                    b_fill  <= regs[1][6];
                    b_main  <= regs[1][3];
                    b_yi    <= 8'd0;
                    b_c     <= 5'd0;
                    bst     <= (regs[7][4:0] == 5'd0 || regs[8] == 8'd0) ? B_IDLE : B_GFX;
                end
        B_GFX:  bst <= B_GFXW;
        B_GFXW: begin b_g <= gfx_d; bst <= B_RD0; end
        B_RD0:  bst <= B_WR0;
        B_WR0:  bst <= (b_x[2:0] != 3'd0) ? B_RD1 : B_NEXT;
        B_RD1:  bst <= B_WR1;
        B_WR1:  bst <= B_NEXT;
        B_NEXT: begin
                    b_src <= b_src + 13'd1;
                    if (b_yi == b_h - 8'd1) begin
                        b_yi <= 8'd0;
                        b_x  <= b_x - 8'd8;
                        b_c  <= b_c + 5'd1;
                        bst  <= (b_c == b_w - 5'd1) ? B_IDLE : B_GFX;
                    end
                    else begin
                        b_yi <= b_yi + 8'd1;
                        bst  <= B_GFX;
                    end
                end
        default: bst <= B_IDLE;
    endcase
end

logic [12:0] pl_ab;
logic  [7:0] pl_qb[3], sc_qa[3], sc_qb[3];
logic  [9:0] sc_ab;
wire  [12:0] pl_aa = getaway ? {b_col, b_dy} : ba[12:0];

genvar p;
generate
    for (p = 0; p < 3; p++) begin : planes
        wire       sel   = b_fill || b_cmask[p];
        wire [7:0] val   = b_fill ? ((!b_main && b_cmask[p]) ? 8'hFF : 8'h00) : b_v;
        wire [7:0] new_p = sel ? ((pl_qa[p] & ~b_m) | (val & b_m)) : pl_qa[p];
        wire [7:0] new_s = sel ? ((sc_qa[p] & ~b_m) | (val & b_m)) : sc_qa[p];

        assign pr_i[p].a_addr = {3'd0, (p == 0 && hs_own) ? hs_address[12:0] : pl_aa};
        assign pr_i[p].a_d    = (p == 0 && hs_own) ? hs_data_in : getaway ? new_p : b_do;
        assign pr_i[p].a_we   = (p == 0 && hs_own) ? hs_write :
                                getaway ? (bl_wr && b_main) : (p == 0 && cg_vram && b_wr);
        assign pr_i[p].b_addr = {3'd0, pl_ab};
        assign pr_i[p].b_d    = 8'd0;
        assign pr_i[p].b_we   = 1'b0;
        assign pl_qa[p] = pr_o[p].a_q;
        assign pl_qb[p] = pr_o[p].b_q;
        assign pr_i[4+p].a_addr = {6'd0, b_col[1:0], b_dy};  assign pr_i[4+p].a_d = new_s;
        assign pr_i[4+p].a_we   = getaway && bl_wr && !b_main && b_col[4:2] == 3'b111;
        assign pr_i[4+p].b_addr = {6'd0, sc_ab};            assign pr_i[4+p].b_d = 8'd0;  assign pr_i[4+p].b_we = 1'b0;
        assign sc_qa[p] = pr_o[4+p].a_q;  assign sc_qb[p] = pr_o[4+p].b_q;
    end
endgenerate
assign pr_i[12:7] = '0;

logic [2:0] chr = 3'd0;
always_ff @(posedge clk) if (ce_cg) chr <= chr + 3'd1;
wire crtc_ce = ce_cg && chr == 3'd7;
logic crtc_hs, crtc_vs, crtc_vbl, crtc_hbl, crtc_de;

assign mc6845_0_i.reset_n = ~reset;  assign mc6845_0_i.clken = crtc_ce;  assign mc6845_0_i.enable = crtc_en;
assign mc6845_0_i.r_nw = cpu_rd;  assign mc6845_0_i.rs = ba[2];  assign mc6845_0_i.di = b_do;
assign crtc_do = mc6845_0_o.dout;
assign crtc_vs = mc6845_0_o.vsync;  assign crtc_hs = mc6845_0_o.hsync;  assign crtc_vbl = mc6845_0_o.vblank;
assign crtc_hbl = mc6845_0_o.hblank;  assign crtc_de = mc6845_0_o.de;  assign crtc_ma = mc6845_0_o.ma;  assign crtc_ra = mc6845_0_o.ra;

logic [13:0] ma_first_c, ma_last_c, ma_sum = 14'd0;
logic  [4:0] ra_max_c = 5'd0, ra_max = 5'd0;
logic        first_de = 1'b1, cvbl_q = 1'b0;
always_ff @(posedge clk) begin
    if (crtc_ce) begin
        cvbl_q <= crtc_vbl;
        if (crtc_vbl && !cvbl_q) begin
            ma_sum <= ma_first_c + ma_last_c; ra_max <= ra_max_c;
            first_de <= 1'b1; ra_max_c <= 5'd0;
        end
        else if (crtc_de) begin
            if (first_de) ma_first_c <= crtc_ma;
            first_de  <= 1'b0;
            ma_last_c <= crtc_ma;
            if (crtc_ra > ra_max_c) ra_max_c <= crtc_ra;
        end
    end
end

wire        cg_flip = snd_out[10] && in2[1];
wire [13:0] ma_l = crt_flip ? ma_sum - crtc_ma : crtc_ma;
wire  [4:0] ra_l = crt_flip ? ra_max - crtc_ra : crtc_ra;
wire [12:0] offs_n = {ma_l[11:5], ra_l[0], ma_l[4:0]};
wire [11:0] cg_cmap_a = {2'b00, creg[1], creg[0], offs_n[12:9], offs_n[4:1]};
assign rom_chr_a = getaway ? b_src[11:0] : cg_cmap_a;

logic [8:0] hcnt = 9'd0, vcnt = 9'd0;
wire  [7:0] gx = crt_flip ? 8'd255 - hcnt[7:0] : hcnt[7:0] + 8'd8;
wire  [7:0] gy = crt_flip ? 8'd239 - vcnt[7:0] : vcnt[7:0];

assign pl_ab = getaway ? {gx[7:3], gy} : (cg_flip ? ~offs_n : offs_n);
assign sc_ab = {gx[4:3], gy};

logic [7:0] cd_lat, cc_lat;
logic       cde1 = 1'b0, chs1 = 1'b0, cvs1 = 1'b0, cvbl1 = 1'b1, crev = 1'b0, cfl1 = 1'b0;
always_ff @(posedge clk) begin
    if (ce_cg && chr == 3'd7) begin
        cd_lat <= pl_qb[0]; cc_lat <= rom_chr_d[7:0];
        cde1 <= crtc_de; chs1 <= crtc_hs; cvs1 <= crtc_vs; cvbl1 <= crtc_vbl;
        crev <= cg_flip ^ crt_flip; cfl1 <= cg_flip;
    end
end
wire [3:0] cg_col = cfl1 ? cc_lat[7:4] : cc_lat[3:0];
wire       cg_bit = crev ? cd_lat[chr] : cd_lat[3'd7 - chr];
wire [3:0] cg_pen = cg_bit ? cg_col : {cg_col[3], 3'd0};

always_ff @(posedge clk) begin
    if (ce_ga) begin
        if (hcnt == 9'd343) begin
            hcnt <= 9'd0;
            vcnt <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
        end
        else hcnt <= hcnt + 9'd1;
    end
end
assign ga_vbl = vcnt >= 9'd240;
wire [8:0] g_hs0 = 9'd280 + {{5{h_adj[3]}}, h_adj};
wire [8:0] g_vs0 = 9'd250 + {{5{v_adj[3]}}, v_adj};

logic [2:0] g_bits;
logic [3:0] g1_blk;
always_ff @(posedge clk) begin
    if (ce_ga) begin
        g_bits <= (gx >= 8'd231) ? {sc_qb[2][gx[2:0]], sc_qb[1][gx[2:0]], sc_qb[0][gx[2:0]]}
                                 : {pl_qb[2][gx[2:0]], pl_qb[1][gx[2:0]], pl_qb[0][gx[2:0]]};
        g1_blk <= {hcnt >= 9'd248, ga_vbl, hcnt >= g_hs0 && hcnt < g_hs0 + 9'd32, vcnt >= g_vs0 && vcnt < g_vs0 + 9'd3};
    end
end
logic [2:0] g_pen;
always_comb case (g_bits)
    3'd0: g_pen = 3'd0; 3'd1: g_pen = 3'd1; 3'd2: g_pen = 3'd6; 3'd3: g_pen = 3'd5;
    3'd4: g_pen = 3'd4; 3'd5: g_pen = 3'd3; 3'd6: g_pen = 3'd2; 3'd7: g_pen = 3'd7;
endcase

logic c_vis = 1'b0, c_hs = 1'b0, c_vs = 1'b0, c_vbl = 1'b1;

logic       chs_q = 1'b0, cvb_q = 1'b1;
logic [8:0] hc = 9'd0, ln = 9'd0;
wire  [8:0] hc_cur  = (c_hs && !chs_q) ? 9'd0 : hc + 9'd1;
wire  [8:0] ln_cur  = (c_vbl && !cvb_q) ? 9'd0 : (c_hs && !chs_q) ? ln + 9'd1 : ln;
wire  [8:0] hs_beg  = 9'd15 + {{5{h_adj[3]}}, h_adj};
wire  [8:0] vs_beg  = 9'd24 + {{5{v_adj[3]}}, v_adj};
always_ff @(posedge clk) begin
    if (ce_cg) begin
        chs_q <= c_hs; cvb_q <= c_vbl;
        hc <= hc_cur; ln <= ln_cur;
    end
end
wire cg_hs = (hc_cur >= hs_beg) && (hc_cur < hs_beg + 9'd24);
wire cg_vs = (ln_cur >= vs_beg) && (ln_cur < vs_beg + 9'd3);

always_ff @(posedge clk) begin
    if (getaway ? ce_ga : ce_cg) begin
        if (getaway) begin
            video_r <= {8{g_pen[1]}}; video_g <= {8{g_pen[2]}}; video_b <= {8{g_pen[0]}};
            video_hblank <= g1_blk[3]; video_vblank <= g1_blk[2];
            video_hs <= g1_blk[1]; video_vs <= g1_blk[0];
        end
        else begin
            video_r <= (cg_pen > 4'd8) ? 8'hFF : cg_pen[0] ? 8'hAA : 8'h00;
            video_g <= cg_pen[1] ? 8'hAA : 8'h00;
            video_b <= cg_pen[2] ? 8'hAA : 8'h00;
            c_vis <= cde1; c_hs <= chs1; c_vs <= cvs1; c_vbl <= cvbl1;
            video_hblank <= !cde1; video_vblank <= cvbl1;
            video_hs <= cg_hs; video_vs <= cg_vs;
        end
    end
end

logic signed [15:0] cg_snd;
cosmicg_sound cg_sound
(
    .clk   (clk),
    .reset (reset | getaway),
    .we    (cru_wr && !getaway && cb < 11'd16),
    .wa    (cb[3:0]),
    .wd    (cpu_cruout),
    .audio (cg_snd)
);
assign audio = getaway ? 16'sd0 : cg_snd;

endmodule
