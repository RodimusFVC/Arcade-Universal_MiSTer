//  Copyright (C) 2026 Rodimus
// Based on MAME cosmic.cpp, cosmic_v.cpp (Nicola Salmoria, Lee Taylor, BSD-3-Clause)

module cosmic_board
(
    output chip_pool_pkg::z80pa_i_t z80pa_0_i,
    input  chip_pool_pkg::z80pa_o_t z80pa_0_o,
    input  logic               clk,
    input  logic               reset,
    input  logic               pause,
    input  logic         [2:0] kind,
    input  logic               crt_flip,

    input  logic         [7:0] in0,
    input  logic         [7:0] in1,
    input  logic         [7:0] in2,
    input  logic         [7:0] dsw0,
    input  logic         [7:0] dsw1,
    input  logic         [7:0] coin,

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
    output logic        [13:0] snd_trig,

    output logic        [14:0] rom_cpu_a,
    input  logic         [7:0] rom_cpu_d,
    output logic        [11:0] rom_cmap_a,
    input  logic         [7:0] rom_cmap_d,
    output logic        [11:0] rom_u2_a,
    input  logic         [7:0] rom_u2_d,
    output logic        [11:0] rom_u2b_a,
    input  logic         [7:0] rom_u2b_d,
    output logic        [11:0] rom_spr_a,      // gfx1: [7:0] first half (pen bit 1), [15:8] second half (pen bit 0)
    input  logic        [15:0] rom_spr_d,

    input  logic               prom_wr,
    input  logic         [6:0] prom_a,
    input  logic         [7:0] prom_d,

    output logic        [12:0] grid_wa,
    output logic         [7:0] grid_wd,
    output logic               grid_we,
    output logic        [12:0] grid_ra,
    input  logic         [7:0] grid_q,

    output ram_pool_pkg::pram_i_t [12:0] pr_i,
    input  ram_pool_pkg::pram_o_t [12:0] pr_o,

    input  logic        [15:0] hs_address,
    output logic         [7:0] hs_data_out,
    input  logic         [7:0] hs_data_in,
    input  logic               hs_write
);

ram_pool_pkg::pram_i_t pr0_i;
ram_pool_pkg::pram_o_t pr0_o;
assign pr_i[0] = pr0_i;
assign pr0_o = pr_o[0];

wire k_panic = (kind == 3'd0);
wire k_cosa  = (kind == 3'd1);
wire k_mag   = (kind >= 3'd2);
wire k_dev   = (kind == 3'd3);
wire k_nml   = (kind == 3'd4);

logic [14:0] pix_acc = 15'd0;
wire  [15:0] pix_sum = {1'b0, pix_acc} + 16'd5408;
wire  [15:0] pix_sub = pix_sum - 16'd19656;
always_ff @(posedge clk) begin
    ce_pix  <= pix_sum >= 16'd19656;
    pix_acc <= (pix_sum >= 16'd19656) ? pix_sub[14:0] : pix_sum[14:0];
end

wire  [16:0] cpu_inc = k_mag ? 17'd16224 : 17'd10816;
logic [16:0] cpu_acc = 17'd0;
logic        cpu_ph = 1'b0, cen_p = 1'b0, cen_n = 1'b0;
wire  [17:0] cpu_sum  = {1'b0, cpu_acc} + {1'b0, cpu_inc};
wire         cpu_edge = cpu_sum >= 18'd58968;
wire  [17:0] cpu_sub  = cpu_sum - 18'd58968;
always_ff @(posedge clk) begin
    cpu_acc <= cpu_edge ? cpu_sub[16:0] : cpu_sum[16:0];
    cen_p   <= cpu_edge & ~cpu_ph;
    cen_n   <= cpu_edge &  cpu_ph;
    if (cpu_edge) cpu_ph <= ~cpu_ph;
end

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
wire line0   = ce_pix && hcnt == 9'd351 && vcnt == 9'd261;
wire line224 = ce_pix && hcnt == 9'd351 && vcnt == 9'd223;

logic [7:0] frame = 8'd0;
always_ff @(posedge clk) if (line224) frame <= frame + 8'd1;

logic        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n;
logic [15:0] a;
logic  [7:0] din, dout;
logic        int_n = 1'b1;
logic  [7:0] int_vec = 8'hFF;
wire         nmi_n = k_panic ? 1'b1 : (k_cosa || k_nml) ? ~coin[0] : ~coin[1];

assign z80pa_0_i.reset_n = ~reset;
logic [1:0] pause_d = 2'b00;
always_ff @(posedge clk) pause_d <= {pause_d[0], pause};
wire pause_x = pause | (|pause_d);
assign z80pa_0_i.cen_p   = cen_p & ~pause_x;
assign z80pa_0_i.cen_n   = cen_n & ~pause_x;
assign z80pa_0_i.wait_n  = 1'b1;
assign z80pa_0_i.int_n   = int_n;
assign z80pa_0_i.nmi_n   = nmi_n;
assign z80pa_0_i.di      = din;
assign m1_n = z80pa_0_o.m1_n;
assign mreq_n = z80pa_0_o.mreq_n;
assign iorq_n = z80pa_0_o.iorq_n;
assign rd_n = z80pa_0_o.rd_n;
assign wr_n = z80pa_0_o.wr_n;
assign rfsh_n = z80pa_0_o.rfsh_n;
assign a = z80pa_0_o.a;
assign dout = z80pa_0_o.dout;

wire mem  = !mreq_n && rfsh_n;
wire inta = !m1_n && !iorq_n && mreq_n;
wire wr   = !wr_n;

wire pc_rom  = mem && !k_mag && a[15:14] == 2'b00;
wire pc_vid  = mem && !k_mag && a[15:13] == 3'b010;
wire pc_spr  = mem && !k_mag && a[15:5] == 11'b01100000000;
wire pc_in   = mem && !k_mag && a[15:11] == 5'b01101;
wire pc_snd  = mem && !k_mag && a[15:11] == 5'b01110 && a[3:0] < 4'd12;
wire pc_col  = mem && !k_mag && a[15:11] == 5'b01110 && a[3:0] >= 4'd12 && a[3:0] <= (k_panic ? 4'd14 : 4'd13);
wire pc_flip = mem && !k_mag && a[15:11] == 5'b01110 && a[3:0] == 4'd15;
wire pc_snd2 = mem && k_panic && a[15:11] == 5'b01111 && !a[1];
wire mg_rom  = mem && k_mag && a < 16'h3000;
wire mg_dip  = mem && k_mag && a[15:11] == 5'b00111;
wire mg_spr  = mem && k_mag && a[15:5] == 11'b01000000000;
wire mg_io   = mem && k_mag && a[15:11] == 5'b01001;
wire mg_in   = mem && k_mag && a[15:11] == 5'b01010;
wire mg_vid  = mem && k_mag && a[15:13] == 3'b011;

wire vid_cs = pc_vid || mg_vid;
wire spr_cs = pc_spr || mg_spr;
assign rom_cpu_a = {1'b0, a[13:0]};

logic       flip = 1'b0, bg_en = 1'b0, dac = 1'b0;
logic [15:0] mg_snd = 16'd0;
logic [2:0] creg = 3'd0;
always_ff @(posedge clk) begin
    if (reset) begin
        flip <= 1'b0; bg_en <= 1'b0; dac <= 1'b0; creg <= 3'd0; snd_trig <= 14'd0; mg_snd <= 16'd0;
    end
    else if (wr) begin
        if (pc_snd)  snd_trig[a[3:0]] <= (dout != 8'd0);
        if (pc_snd2) snd_trig[4'd12 + {3'd0, a[0]}] <= (dout != 8'd0);
        if (pc_snd && a[3:0] == 4'd10) dac <= dout[7];
        if (pc_col)  creg[a[1:0]] <= (dout != 8'd0);
        if (pc_flip) flip <= dout[7];
        if (mg_io) begin
            mg_snd[a[3:0]] <= dout[7];
            if (a[3:0] == (k_nml ? 4'd10 : 4'd0)) dac <= dout[7];
            if (a[3:0] == 4'd7 && (k_dev || k_nml)) bg_en <= dout != 8'd0;
            if (a[3:1] == 3'd6) creg[{1'b0, a[0]}] <= (dout != 8'd0);
            if (a[3:0] == 4'd15) flip <= dout[7];
        end
    end
end

// pooled multiplier operands come from registers / plain logic, never from another pooled product (timing)
logic        [31:0] pn_ea, ca_ea, ms_ea, nm_ea;
logic        [27:0] pn_eb, ca_eb, ms_eb, nm_eb;
logic [3:0]  [31:0] pn_xa, ca_xa, ms_xa, nm_xa, pn_xb, ca_xb, ms_xb, nm_xb;
logic [9:0]  [33:0] pn_wa , ca_wa , ms_wa ,
                    nm_wa ;
logic [9:0]  [16:0] pn_wb, ca_wb, ms_wb, nm_wb;
wire         [31:0] sel_ea = k_panic ? pn_ea : k_cosa ? ca_ea : k_nml ? nm_ea : ms_ea;
wire         [27:0] sel_eb = k_panic ? pn_eb : k_cosa ? ca_eb : k_nml ? nm_eb : ms_eb;
wire  [3:0]  [31:0] sel_xa = k_panic ? pn_xa : k_cosa ? ca_xa : k_nml ? nm_xa : ms_xa;
wire  [3:0]  [31:0] sel_xb = k_panic ? pn_xb : k_cosa ? ca_xb : k_nml ? nm_xb : ms_xb;
wire  [9:0]  [33:0] sel_wa  = k_panic ? pn_wa : k_cosa ? ca_wa : k_nml ? nm_wa : ms_wa;
wire  [9:0]  [16:0] sel_wb = k_panic ? pn_wb : k_cosa ? ca_wb : k_nml ? nm_wb : ms_wb;
logic [59:0]  mp_ep;
logic [3:0]  [63:0] mp_xp;
logic [9:0]  [50:0] mp_wp ;
assign mp_ep = $signed(sel_ea) * $signed(sel_eb);
genvar mk;
generate
    for (mk = 0; mk < 4; mk++) begin : mpx
        assign mp_xp[mk] = $signed(sel_xa[mk]) * $signed(sel_xb[mk]);
    end
    for (mk = 0; mk < 10; mk++) begin : mpw
        assign mp_wp[mk] = $signed(sel_wa[mk]) * $signed(sel_wb[mk]);
    end
endgenerate

logic signed [15:0] panic_snd;
panic_sound panic_snd_b
(
    .clk    (clk),
    .reset  (reset | ~k_panic),
    .trig   (snd_trig),
    .music  (dac),
    .coin_n (in2[6] & in2[7]),
    .audio  (panic_snd),
    .mp_ea  (pn_ea), .mp_eb(pn_eb), .mp_ep(mp_ep), .mp_xa(pn_xa), .mp_xb(pn_xb), .mp_xp(mp_xp),
    .mp_wa  (pn_wa), .mp_wb(pn_wb), .mp_wp(mp_wp)
);
logic signed [15:0] cosa_snd;
cosmica_sound cosa_snd_b
(
    .clk    (clk),
    .reset  (reset | ~k_cosa),
    .trig   (snd_trig[11:0]),
    .coin   (coin[0]),
    .audio  (cosa_snd),
    .mp_ea  (ca_ea), .mp_eb(ca_eb), .mp_ep(mp_ep), .mp_xa(ca_xa), .mp_xb(ca_xb), .mp_xp(mp_xp),
    .mp_wa  (ca_wa), .mp_wb(ca_wb), .mp_wp(mp_wp)
);
logic signed [15:0] ms_snd, nml_snd;
magspot_sound ms_snd_b
(
    .clk     (clk),
    .reset   (reset | ~(k_mag & ~k_nml)),
    .snd     (mg_snd),
    .coin_sw (coin[0] | coin[1]),
    .audio   (ms_snd),
    .mp_ea   (ms_ea), .mp_eb(ms_eb), .mp_ep(mp_ep), .mp_xa(ms_xa), .mp_xb(ms_xb), .mp_xp(mp_xp),
    .mp_wa   (ms_wa), .mp_wb(ms_wb), .mp_wp(mp_wp)
);
nomnlnd_sound nml_snd_b
(
    .clk     (clk),
    .reset   (reset | ~k_nml),
    .snd     (mg_snd),
    .coin_sw (coin[0]),
    .audio   (nml_snd),
    .mp_ea   (nm_ea), .mp_eb(nm_eb), .mp_ep(mp_ep), .mp_xa(nm_xa), .mp_xb(nm_xb), .mp_xp(mp_xp),
    .mp_wa   (nm_wa), .mp_wb(nm_wb), .mp_wp(mp_wp)
);
assign audio = k_panic ? panic_snd : k_cosa ? cosa_snd : k_nml ? nml_snd : ms_snd;

logic [1:0] coin_d = 2'b00;
always_ff @(posedge clk) begin
    coin_d <= coin[1:0];
    if (reset)                                    begin int_n <= 1'b1; int_vec <= 8'hFF; end
    else if (inta)                                int_n <= 1'b1;
    else if (k_panic && line0)                    begin int_n <= 1'b0; int_vec <= 8'hCF; end
    else if (k_panic && line224)                  begin int_n <= 1'b0; int_vec <= 8'hD7; end
    else if ((kind == 3'd2 || k_dev) && coin[0] && !coin_d[0]) begin int_n <= 1'b0; int_vec <= 8'hFF; end
end

logic  [7:0] vram_q, vram_vq;
logic [12:0] vram_va;
assign pr0_i.a_addr = {3'd0, pause ? hs_address[12:0] : a[12:0]};
assign pr0_i.a_d    = pause ? hs_data_in : dout;
assign pr0_i.a_we   = pause ? hs_write : vid_cs && wr;
assign hs_data_out  = pr0_o.a_q;
assign pr0_i.b_addr = {3'd0, vram_va};  assign pr0_i.b_d = 8'd0;  assign pr0_i.b_we = 1'b0;
assign vram_q = pr0_o.a_q;  assign vram_vq = pr0_o.b_q;

logic [7:0] spram[32];
always_ff @(posedge clk) if (spr_cs && wr) spram[a[4:0]] <= dout;

wire  [7:0] in3 = {dsw0[7:1], k_dev ? ~vbl_s0 : vbl_s0};
function automatic [7:0] nml_remap(input [7:0] ctl, input [7:0] fire);
    if ((fire & 8'hC0) == 8'd0)          nml_remap = 8'hFF;
    else if ((ctl & 8'h82) == 8'd0)      nml_remap = 8'hFE;
    else if ((ctl & 8'h0A) == 8'd0)      nml_remap = 8'hFB;
    else if ((ctl & 8'h28) == 8'd0)      nml_remap = 8'hEF;
    else if ((ctl & 8'hA0) == 8'd0)      nml_remap = 8'hBF;
    else                                 nml_remap = ctl;
endfunction

always_comb begin
    din = 8'hFF;
    if (inta)                     din = int_vec;
    else if (pc_rom || mg_rom)    din = rom_cpu_d;
    else if (vid_cs)              din = vram_q;
    else if (pc_in)
        case (a[1:0])
            2'd0: din = in0;
            2'd1: din = in1;
            2'd2: din = dsw0;
            2'd3: din = k_panic ? in2 : {2'b00, vcnt[7:2]};
        endcase
    else if (mg_dip)              din = k_nml ? 8'd1 : {7'd0, ~dsw1[3'd7 - a[2:0]]};
    else if (mg_in)
        case (a[1:0])
            2'd0: din = k_nml ? nml_remap(in0, in3) : in0;
            2'd1: din = k_nml ? nml_remap(in1, in3) : in1;
            2'd2: din = in2;
            2'd3: din = in3;
        endcase
end

logic [7:0] prom[32], vprom[32];
always_ff @(posedge clk) begin
    if (prom_wr && prom_a[6:5] == 2'd0) prom[prom_a[4:0]]  <= prom_d;
    if (prom_wr && prom_a[6:5] == 2'd2) vprom[prom_a[4:0]] <= prom_d;
end

typedef enum logic [2:0] {G_IDLE, G_GROUP, G_AW, G_A, G_BW, G_B, G_OUT} gstate_t;
gstate_t     gs = G_IDLE;
logic [10:0] g_addr;
logic  [7:0] g_count, g_horz;
logic [12:0] g_pos;
logic [10:0] g_rda;

always_ff @(posedge clk) begin
    grid_we <= 1'b0;
    case (gs)
        G_IDLE:  if (line224 && k_dev) begin g_addr <= 11'd0; g_count <= 8'd0; g_pos <= 13'd0; gs <= G_GROUP; end
        G_GROUP: begin
                     g_horz <= 8'hFF;
                     if (g_count == 8'd0) begin g_rda <= g_addr; g_addr <= g_addr + 11'd1; gs <= G_AW; end
                     else if (g_count == 8'hFF) begin g_count <= 8'd0; g_rda <= g_addr; g_addr <= g_addr + 11'd1; gs <= G_BW; end
                     else begin g_count <= g_count + 8'd1; gs <= G_OUT; end
                 end
        G_AW:    gs <= G_A;
        G_A:     if (rom_u2_d == 8'hFF) begin g_count <= 8'd0; g_rda <= g_addr; g_addr <= g_addr + 11'd1; gs <= G_BW; end
                 else begin g_count <= rom_u2_d + 8'd1; gs <= G_OUT; end
        G_BW:    gs <= G_B;
        G_B:     begin g_horz <= rom_u2_d; gs <= G_OUT; end
        G_OUT:   begin
                     grid_we <= 1'b1;
                     grid_wa <= g_pos;
                     grid_wd <= ~(vprom[g_pos[4:0]] & g_horz);
                     g_pos   <= g_pos + 13'd1;
                     gs      <= (g_pos == 13'd6143) ? G_IDLE : G_GROUP;
                 end
        default: gs <= G_IDLE;
    endcase
end

logic [6:0] lb_q[2];
logic [7:0] lb_q_w[2];
logic [7:0] lb_wa, lb_ra;
logic [6:0] lb_wd;
logic       lb_we = 1'b0;
logic       lb_clr;
logic       build_buf = 1'b0;
wire        disp_buf;

genvar l;
generate
    for (l = 0; l < 2; l++) begin : lbuf
        assign pr_i[4+l].a_addr = {8'd0, lb_wa};  assign pr_i[4+l].a_d = {1'b0, lb_wd};  assign pr_i[4+l].a_we = lb_we && build_buf == l;
        assign pr_i[4+l].b_addr = {8'd0, lb_ra};  assign pr_i[4+l].b_d = 8'd0;           assign pr_i[4+l].b_we = lb_clr && disp_buf == l;
        assign lb_q_w[l] = pr_o[4+l].b_q;
    end
endgenerate
assign pr_i[3] = '0;
assign pr_i[12:6] = '0;
assign pr_i[2:1] = '0;
assign lb_q[0] = lb_q_w[0][6:0];
assign lb_q[1] = lb_q_w[1][6:0];

typedef enum logic [2:0] {S_IDLE, S_SPR, S_COL, S_ROW_W, S_ROW_R, S_PIX, S_NEXT} sstate_t;
sstate_t    ss = S_IDLE;
wire  [8:0] tgt = (vcnt >= 9'd260) ? vcnt - 9'd260 : vcnt + 9'd2;
logic [7:0] sl_line;
logic [2:0] s_n;
logic [1:0] s_col;
logic [2:0] s_px;
logic [8:0] s_x;
logic [4:0] s_rr;
logic [3:0] s_color;
logic [6:0] s_code;
logic       s_big;
logic [15:0] s_d;

wire  [7:0] sb0 = spram[{s_n, 2'd0}], sb1 = spram[{s_n, 2'd1}], sb2 = spram[{s_n, 2'd2}], sb3 = spram[{s_n, 2'd3}];
wire        e_big = !sb0[7];
wire  [8:0] e_r   = {1'b0, sl_line} - {1'b0, sb1};
wire        e_vis = sb0 != 8'd0 && !e_r[8] && (e_big ? e_r[7:5] == 3'd0 : e_r[7:4] == 4'd0);
wire  [4:0] e_rr  = !sb0[6] ? ((e_big ? 5'd31 : 5'd15) - e_r[4:0]) : e_r[4:0];
wire  [3:0] cmask = k_cosa ? 4'hF : 4'h7;

wire  [2:0] pb    = 3'd7 - s_px;
wire  [1:0] s_pen = {s_d[{1'b0, pb}], s_d[{1'b1, pb}]};
wire  [8:0] wx    = s_x + {4'd0, s_col, s_px};

always_ff @(posedge clk) begin
    lb_we <= 1'b0;
    if (ce_pix && hcnt == 9'd351) begin
        sl_line   <= crt_flip ? ~tgt[7:0] : tgt[7:0];
        build_buf <= vcnt[0];
        s_n <= 3'd7;
        ss  <= S_SPR;
    end
    else case (ss)
        S_IDLE:  ;
        S_SPR:   if (e_vis) begin
                     s_code  <= {k_panic ? sb3[3] : 1'b0, ~sb0[5:0]};
                     s_color <= ~sb3[3:0] & cmask;
                     s_big   <= e_big;
                     s_rr    <= e_rr;
                     s_x     <= 9'd256 - {1'b0, sb2};
                     s_col   <= 2'd0;
                     ss      <= S_COL;
                 end
                 else ss <= S_NEXT;
        S_COL:   begin
                     rom_spr_a <= s_big ? {s_code[6:2], s_col, s_rr} : {s_code, s_col[0], s_rr[3:0]};
                     ss <= S_ROW_W;
                 end
        S_ROW_W: ss <= S_ROW_R;
        S_ROW_R: begin s_d <= rom_spr_d; s_px <= 3'd0; ss <= S_PIX; end
        S_PIX:   begin
                     if (s_pen != 2'd0 && !wx[8]) begin
                         lb_we <= 1'b1; lb_wa <= wx[7:0]; lb_wd <= {1'b1, s_color, s_pen};
                     end
                     s_px <= s_px + 3'd1;
                     if (s_px == 3'd7) begin
                         if (s_col == (s_big ? 2'd3 : 2'd1)) ss <= S_NEXT;
                         else begin s_col <= s_col + 2'd1; ss <= S_COL; end
                     end
                 end
        S_NEXT:  if (s_n == 3'd0) ss <= S_IDLE; else begin s_n <= s_n - 3'd1; ss <= S_SPR; end
        default: ss <= S_IDLE;
    endcase
end

wire [7:0] lx = crt_flip ? ~hcnt[7:0] : hcnt[7:0];
wire [7:0] ly = crt_flip ? ~vcnt[7:0] : vcnt[7:0];
wire [7:0] bx = flip ? ~lx : lx;
wire [7:0] by = flip ? ~ly : ly;

assign vram_va    = {by, bx[7:3]};
assign rom_cmap_a = k_panic ? {1'b0, creg[2], creg[0], bx[7:4], by[7:3]} :
                    k_cosa  ? {2'b00, creg[0], bx[7:4], by[7:3]} :
                              {2'b00, creg[0], bx[7:3], by[7:4]};
wire [7:0] gy = by - 8'd32;
assign grid_ra = {gy, bx[7:3]};

wire [7:0] x1   = flip ? lx - frame : lx + frame;
wire [7:0] x1e  = flip ? 8'd255 - frame : 8'd255 + frame;
wire [7:0] lym1 = ly - 8'd1;
wire       xcur = {3'b000, x1[4:0]} <= lx;
wire [9:0] st_a = xcur ? {ly[7:1], x1[7:5]} : {lym1[7:1], x1e[7:5]};

wire [7:0] water   = frame + by;
wire       t_rows  = ((!by[5] && by[6] && !by[7]) ^ (by[5] && !by[6] && by[7]));
wire       t_cols  = !bx[7] && bx[6] && !bx[5];
wire       w_cols  = bx[7] && !bx[6] && bx[5] && !bx[4];
wire [9:0] t_offs  = t_rows ? {2'b00, flip, by[4:0], bx[4:3]} : {1'b1, water, bx[3]};
wire [1:0] t_sel   = t_rows ? (t_cols ? 2'd1 : 2'd0) : (w_cols ? 2'd2 : 2'd0);

assign rom_u2_a  = k_nml ? {2'b00, t_offs} : k_cosa ? {2'b00, st_a} : {1'b0, g_rda};
assign rom_u2b_a = {1'b0, 1'b1, t_offs};

logic [7:0] s1_vq, s1_cm, s1_u2, s1_u2b, s1_gq;
logic [2:0] s1_b3;
logic [7:0] s1_x1, s1_lx;
logic [1:0] s1_ly, s1_tsel;
logic       s1_hd, s1_gvis, s1_ln, s1_clr;
logic [3:0] s2_c;
logic [1:0] s2_pal;
logic [3:0] blk_d[2];

assign lb_ra    = s1_lx;
assign lb_clr   = ce_pix && s1_clr;
assign disp_buf = s1_ln;

wire        bm_on  = s1_vq[3'd7 - s1_b3];
wire  [3:0] cm_nib = creg[1] ? s1_cm[7:4] : s1_cm[3:0];
wire  [3:0] bm_pen = k_cosa ? {1'b0, cm_nib[2:0]} : cm_nib;
wire        star_on = k_cosa && !(s1_x1[2] && s1_ly[0]) && (s1_ly[1] ^ s1_lx[5]) &&
                      (((s1_x1 ^ s1_u2) & {3'b000, 4'hF, s1_x1[2]}) == 8'h1E);
wire  [2:0] star_c  = {s1_u2[5], s1_u2[6], s1_u2[7]};
wire        grid_on = k_dev && bg_en && s1_gvis && s1_gq[3'd7 - s1_b3];
wire        tp1 = s1_u2[3'd7 - s1_b3], tp2 = s1_u2b[3'd7 - s1_b3];
wire  [2:0] tree_c  = (s1_tsel == 2'd1) ? {tp1 & ~tp2, tp2, tp1 & tp2} :
                      (s1_tsel == 2'd2) ? {~tp1 & s1_hd, tp1 | tp2, tp1 & tp2} : 3'd0;
wire  [6:0] lbq     = lb_q[disp_buf];
wire  [5:0] sp_idx  = lbq[5:0];
wire  [7:0] sp_pr   = prom[sp_idx[4:0]];
wire  [3:0] sp_c    = k_cosa ? {1'b0, sp_idx[5] ? sp_pr[6:4] : sp_pr[2:0]} : k_panic ? {1'b0, sp_pr[2:0]} : sp_pr[3:0];
wire  [1:0] pal_k   = k_panic ? 2'd1 : k_cosa ? 2'd2 : 2'd3;

always_ff @(posedge clk) begin
    if (ce_pix) begin
        s1_vq <= vram_vq;  s1_cm <= rom_cmap_d;  s1_u2 <= rom_u2_d;  s1_u2b <= rom_u2b_d;  s1_gq <= grid_q;
        s1_b3 <= bx[2:0];  s1_x1 <= x1;  s1_lx <= lx;  s1_ly <= ly[1:0];  s1_tsel <= t_sel;  s1_hd <= bx[3];
        s1_gvis <= (by >= 8'd32) && (by < 8'd224);
        s1_ln <= vcnt[0];  s1_clr <= !hcnt[8];

        if (k_nml && bg_en && tree_c != 3'd0)  begin s2_c <= {1'b0, tree_c}; s2_pal <= 2'd3; end
        else if (lbq[6])                       begin s2_c <= sp_c;            s2_pal <= pal_k; end
        else if (bm_on)                        begin s2_c <= bm_pen;          s2_pal <= pal_k; end
        else if (star_on)                      begin s2_c <= {1'b0, star_c};  s2_pal <= 2'd2; end
        else if (grid_on)                      begin s2_c <= 4'd4;            s2_pal <= 2'd3; end
        else                                   begin s2_c <= 4'd0;            s2_pal <= 2'd0; end

        blk_d[0] <= {hbl_s0, vbl_s0, hs_s0, vs_s0};
        blk_d[1] <= blk_d[0];
    end
end

wire [7:0] r_p = s2_c[0] ? 8'hFF : 8'h00;
wire [7:0] g_p = s2_c[1] ? 8'hFF : 8'h00;
wire [7:0] b_p = s2_c[2] ? 8'hFF : 8'h00;
always_ff @(posedge clk) begin
    if (ce_pix) begin
        case (s2_pal)
            2'd1:    begin video_r <= r_p; video_g <= g_p; video_b <= (s2_c[3:2] == 2'b10) ? 8'hAA : b_p; end
            2'd2:    begin video_r <= r_p; video_g <= g_p; video_b <= b_p; end
            2'd3:    begin video_r <= (s2_c[3] && !s2_c[0]) ? 8'hAA : r_p; video_g <= g_p; video_b <= b_p; end
            default: begin video_r <= 8'h00; video_g <= 8'h00; video_b <= 8'h00; end
        endcase
        {video_hblank, video_vblank, video_hs, video_vs} <= blk_d[1];
    end
end

endmodule
