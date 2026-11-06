//  Copyright (C) 2026 Rodimus
// Based on MAME docastle.cpp (Brad Oliver, BSD-3-Clause)

module docastle_board
(
    output chip_pool_pkg::z80pa_i_t         z80pa_0_i,
    input  chip_pool_pkg::z80pa_o_t         z80pa_0_o,
    output chip_pool_pkg::z80pa_i_t         z80pa_1_i,
    input  chip_pool_pkg::z80pa_o_t         z80pa_1_o,
    output chip_pool_pkg::sn76489_i_t [3:0] sn76489_i,
    input  chip_pool_pkg::sn76489_o_t [3:0] sn76489_o,
    output chip_pool_pkg::jt5205_i_t        jt5205_0_i,
    input  chip_pool_pkg::jt5205_o_t        jt5205_0_o,
    output chip_pool_pkg::mc6845_i_t        mc6845_0_i,
    input  chip_pool_pkg::mc6845_o_t        mc6845_0_o,
    input  logic               clk,
    input  logic               reset,
    input  logic               pause,
    input  logic               map_mode,
    input  logic               idsoccer,
    input  logic               pri_low,
    input  logic               crt_flip,

    input  logic         [7:0] joys,
    input  logic         [7:0] buttons,
    input  logic         [7:0] system,
    input  logic         [7:0] dsw1,
    input  logic         [7:0] dsw2,
    input  logic         [7:0] joys2,

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

    output logic        [15:0] rom_main_a,
    input  logic         [7:0] rom_main_d,
    output logic        [13:0] rom_sub_a,
    input  logic         [7:0] rom_sub_d,
    output logic        [11:0] rom_tile_a,
    input  logic        [31:0] rom_tile_d,
    output logic        [11:0] rom_spr_a,
    input  logic        [63:0] rom_spr_d,
    output logic        [16:0] rom_spr8_a,
    output logic               rom_spr8_req,
    input  logic               rom_spr8_rdy,
    input  logic        [63:0] rom_spr8_q,
    output logic        [15:0] rom_adpcm_a,
    input  logic         [7:0] rom_adpcm_d,
    input  logic               rom_adpcm_rdy,

    output logic         [7:0] prom_a_o,
    input  logic         [7:0] prom_d_i,

    input  logic        [12:0] hs_address,
    output logic         [7:0] hs_data_out,
    input  logic         [7:0] hs_data_in,
    input  logic               hs_write,

    output ram_pool_pkg::pram_i_t [12:0] pr_i,
    input  ram_pool_pkg::pram_o_t [12:0] pr_o
);

logic [1:0] ph = 2'd0;
always_ff @(posedge clk) ph <= ph + 2'd1;
assign ce_pix = (ph == 2'd3);

logic [2:0] chr = 3'd0;
always_ff @(posedge clk) if (ce_pix) chr <= chr + 3'd1;
wire crtc_ce = ce_pix && chr == 3'd7;

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
wire cpu_p = cen_p & ~pause;
wire cpu_n = cen_n & ~pause;

logic        m_mreq_n, m_iorq_n, m_rd_n, m_wr_n, m_m1_n, m_rfsh_n;
logic [15:0] m_a;
logic  [7:0] m_di, m_do;
logic        m_wait_n, m_int_n;

assign z80pa_0_i.reset_n = ~reset;
assign z80pa_0_i.cen_p   = cpu_p;
assign z80pa_0_i.cen_n   = cpu_n;
assign z80pa_0_i.wait_n  = m_wait_n;
assign z80pa_0_i.int_n   = m_int_n;
assign z80pa_0_i.nmi_n   = 1'b1;
assign z80pa_0_i.di      = m_di;
assign m_m1_n   = z80pa_0_o.m1_n;
assign m_mreq_n = z80pa_0_o.mreq_n;
assign m_iorq_n = z80pa_0_o.iorq_n;
assign m_rd_n   = z80pa_0_o.rd_n;
assign m_wr_n   = z80pa_0_o.wr_n;
assign m_rfsh_n = z80pa_0_o.rfsh_n;
assign m_a      = z80pa_0_o.a;
assign m_do     = z80pa_0_o.dout;

wire m_mem = !m_mreq_n && m_rfsh_n;
wire m_io  = !m_iorq_n && m_m1_n;

wire m_rom  = m_mem && (idsoccer ? (m_a < 16'h4000 || (m_a >= 16'h6000 && m_a < 16'hA000)) :
                        map_mode ? (m_a < 16'h2000 || (m_a >= 16'h4000 && m_a < 16'hA000)) : !m_a[15]);
wire m_ram  = m_mem && (idsoccer ? (m_a >= 16'h4000 && m_a < 16'h5800) :
                        map_mode ? (m_a >= 16'h2000 && m_a < 16'h3800) : (m_a >= 16'h8000 && m_a < 16'h9800));
wire m_spr  = m_mem && (idsoccer ? (m_a[15:9] == 7'b0101100) :
                        map_mode ? (m_a[15:9] == 7'b0011100) : (m_a[15:9] == 7'b1001100));
wire m_lat  = m_mem && m_a[15:11] == 5'b10100;
wire m_vid  = m_mem && (map_mode ? (m_a[15:11] == 5'b10110) : (m_a[15:12] == 4'hB));
wire m_vram = m_vid && !m_a[10];
wire m_cram = m_vid &&  m_a[10];
wire m_nmi  = m_mem && !m_wr_n && (map_mode ? (m_a[15:11] == 5'b10111) : (m_a[15:12] == 4'hE));
wire m_adp  = m_mem && idsoccer && m_a[15:12] == 4'hC;
wire m_crtc = m_io && !m_wr_n && m_a[7:2] == 6'd0 && !m_a[0];

wire [12:0] m_ram_a = m_a[12:0];
assign rom_main_a   = m_a;

logic [7:0] m_ram_q, vram_q, cram_q;

assign pr_i[0].a_addr = {3'd0, m_ram_a};     assign pr_i[0].a_d = m_do;        assign pr_i[0].a_we = m_ram && !m_wr_n;
assign pr_i[0].b_addr = {3'd0, hs_address};  assign pr_i[0].b_d = hs_data_in;  assign pr_i[0].b_we = hs_write;
assign m_ram_q = pr_o[0].a_q;  assign hs_data_out = pr_o[0].b_q;

logic        s_mreq_n, s_iorq_n, s_rd_n, s_wr_n, s_m1_n, s_rfsh_n;
logic [15:0] s_a;
logic  [7:0] s_di, s_do;
logic        s_int_n = 1'b1, s_nmi_n = 1'b1;
logic  [3:0] sn_ready;

assign z80pa_1_i.reset_n = ~reset;
assign z80pa_1_i.cen_p   = cpu_p;
assign z80pa_1_i.cen_n   = cpu_n;
assign z80pa_1_i.wait_n  = &sn_ready;
assign z80pa_1_i.int_n   = s_int_n;
assign z80pa_1_i.nmi_n   = s_nmi_n;
assign z80pa_1_i.di      = s_di;
assign s_m1_n   = z80pa_1_o.m1_n;
assign s_mreq_n = z80pa_1_o.mreq_n;
assign s_iorq_n = z80pa_1_o.iorq_n;
assign s_rd_n   = z80pa_1_o.rd_n;
assign s_wr_n   = z80pa_1_o.wr_n;
assign s_rfsh_n = z80pa_1_o.rfsh_n;
assign s_a      = z80pa_1_o.a;
assign s_do     = z80pa_1_o.dout;

wire s_mem = !s_mreq_n && s_rfsh_n;
wire s_rom = s_mem && s_a[15:14] == 2'b00;
wire s_ram = s_mem && s_a[15:11] == 5'b10000;
wire s_lat = s_mem && (map_mode ? s_a[15:11] == 5'b11100 : s_a[15:11] == 5'b10100);
wire s_inp = s_mem && s_a[15:12] == 4'hC && s_a[11:8] == 4'h0 && s_a[6:3] == 4'd0;
wire s_snb = s_mem && (map_mode ? s_a[15:12] == 4'hA : s_a[15:12] == 4'hE);
wire [1:0] s_sn_n = s_a[11:10];

assign rom_sub_a = s_a[13:0];

logic [7:0] s_ram_q;
assign pr_i[1].a_addr = {5'd0, s_a[10:0]};  assign pr_i[1].a_d = s_do;  assign pr_i[1].a_we = s_ram && !s_wr_n;
assign pr_i[1].b_addr = 16'd0;              assign pr_i[1].b_d = 8'd0;  assign pr_i[1].b_we = 1'b0;
assign s_ram_q = pr_o[1].a_q;

logic [7:0] latch = 8'h00;
logic       busy = 1'b0, m_lat_d = 1'b0, s_lat_d = 1'b0;
always_ff @(posedge clk) begin
    m_lat_d <= m_lat;
    s_lat_d <= s_lat;
    if (reset) busy <= 1'b0;
    else if (s_lat && !s_lat_d) busy <= 1'b0;
    else if (m_lat && !m_lat_d) busy <= 1'b1;
    if (m_lat && !m_wr_n) latch <= m_do;
    if (s_lat && !s_wr_n) latch <= s_do;
end
assign m_wait_n = ~(busy && m_lat);

logic m_nmi_d = 1'b0;
always_ff @(posedge clk) begin
    m_nmi_d <= m_nmi;
    if (reset) s_nmi_n <= 1'b1;
    else if (m_nmi && !m_nmi_d) s_nmi_n <= 1'b0;
    else if (cpu_p) s_nmi_n <= 1'b1;
end

logic [2:0] tms_s = 3'd0;
logic [7:0] tms_h = 8'h00;
logic       flip  = 1'b0;
logic       s_inp_d = 1'b0;

function automatic [7:0] tms_port(input [2:0] s, input [7:0] j, input [7:0] b, input [7:0] sy, input [7:0] d1, input [7:0] d2, input [7:0] j2);
    case (s)
        3'd1: tms_port = d2;
        3'd2: tms_port = d1;
        3'd3: tms_port = j;
        3'd4: tms_port = j2;
        3'd5: tms_port = b;
        3'd7: tms_port = sy;
        default: tms_port = 8'h00;
    endcase
endfunction

wire [7:0] tms_now = (tms_s != 3'd0) ? tms_port(tms_s, joys, buttons, system, dsw1, dsw2, idsoccer ? joys2 : 8'h00) : tms_h;

always_ff @(posedge clk) begin
    s_inp_d <= s_inp;
    if (reset) begin
        tms_s <= 3'd0; flip <= 1'b0;
    end
    else if (s_inp && !s_inp_d) begin
        flip <= s_a[7];
        if (!s_rd_n) begin
            tms_h <= tms_now;
            tms_s <= s_a[2:0];
        end
    end
end

logic signed [10:0] sn_out[4];
genvar i;
generate
    for (i = 0; i < 4; i++) begin : sn
        assign sn76489_i[i].rst  = reset;
        assign sn76489_i[i].ce   = cpu_p;
        assign sn76489_i[i].wr_n = s_wr_n;
        assign sn76489_i[i].cs_n = ~(s_snb && s_sn_n == i);
        assign sn76489_i[i].din  = s_do;
        assign sn_out[i]   = sn76489_o[i].sound;
        assign sn_ready[i] = sn76489_o[i].ready;
    end
endgenerate
wire signed [12:0] snd_sum = sn_out[0] + sn_out[1] + sn_out[2] + sn_out[3];

wire         vck;

logic [16:0] adp_pos = 17'd0, adp_end = 17'd0;
logic        adp_idle = 1'b1, adp_rst = 1'b1, adp_wr_d = 1'b0;
logic  [7:0] adp_ctl = 8'h00;
logic  [3:0] adp_nib = 4'd0;
logic        adp_step = 1'b0;
wire         adp_wr = m_adp && !m_wr_n;
logic        adp_vpend = 1'b0;
wire         adp_go   = (vck || adp_vpend) && !pause;
wire         adp_need = !(adp_pos >= adp_end || adp_idle);

logic [11:0] msm_acc   = 12'd0;
wire  [11:0] msm_acc_n = msm_acc + 12'd48;
wire         msm_run   = !pause && !adp_vpend;
wire         msm_cen   = msm_run && msm_acc_n >= 12'd2457;
always_ff @(posedge clk) if (msm_run) msm_acc <= msm_cen ? msm_acc_n - 12'd2457 : msm_acc_n;

assign rom_adpcm_a = adp_pos[16:1];

always_ff @(posedge clk) begin
    adp_wr_d <= adp_wr;
    adp_step <= 1'b0;
    if (reset) begin
        adp_idle <= 1'b1; adp_rst <= 1'b1; adp_ctl <= 8'h00;
        adp_vpend <= 1'b0;
    end
    else begin
        if (adp_wr && !adp_wr_d) begin
            if (adp_ctl[7] && !m_do[7]) begin adp_idle <= 1'b1; adp_rst <= 1'b1; end
            if (adp_ctl[6] && !m_do[6]) begin
                adp_pos  <= {m_do[1:0], 15'd0};
                adp_end  <= {m_do[1:0], 15'd0} + 17'h08000;
                adp_idle <= 1'b0; adp_rst <= 1'b0;
            end
            adp_ctl <= m_do;
        end
        if (adp_go) begin
            if (adp_need && !rom_adpcm_rdy) adp_vpend <= 1'b1;
            else begin
                adp_vpend <= 1'b0;
                if (!adp_need) begin
                    adp_idle <= 1'b1; adp_rst <= 1'b1;
                end
                else begin
                    adp_nib <= adp_pos[0] ? rom_adpcm_d[3:0] : rom_adpcm_d[7:4];
                    adp_pos <= adp_pos + 17'd1;
                end
                adp_step <= 1'b1;
            end
        end
    end
end

logic signed [11:0] adp_sig;
assign jt5205_0_i.rst = adp_rst;  assign jt5205_0_i.cen = msm_cen;  assign jt5205_0_i.sel = 2'd2;  assign jt5205_0_i.din = adp_nib;
assign adp_sig = jt5205_0_o.sound;  assign vck = jt5205_0_o.irq;

wire signed [16:0] adp_w = $signed({{5{adp_sig[11]}}, adp_sig}) * 17'sd13;
wire signed [16:0] adp_s = adp_w >>> 2;
wire signed [16:0] sn_w  = $signed({{4{snd_sum[12]}}, snd_sum}) * 17'sd8;    // sn76489sv is unipolar 0..1020 (0 when silent): 4 chips max 4080, x8 = 32640 fits int16 (jt89 was +-, *4)
wire signed [16:0] mix   = sn_w + (idsoccer ? adp_s : 17'sd0);
assign audio = (mix > 17'sd32767) ? 16'sd32767 : (mix < -17'sd32768) ? -16'sd32768 : mix[15:0];

logic        crtc_vs, crtc_hs, crtc_vbl, crtc_hbl, crtc_de;
logic [13:0] crtc_ma;
logic  [4:0] crtc_ra;

assign mc6845_0_i.reset_n = ~reset;  assign mc6845_0_i.clken = crtc_ce;  assign mc6845_0_i.enable = m_crtc;
assign mc6845_0_i.r_nw = 1'b0;  assign mc6845_0_i.rs = m_a[1];  assign mc6845_0_i.di = m_do;
assign crtc_vs = mc6845_0_o.vsync;  assign crtc_hs = mc6845_0_o.hsync;  assign crtc_vbl = mc6845_0_o.vblank;
assign crtc_hbl = mc6845_0_o.hblank;  assign crtc_de = mc6845_0_o.de;  assign crtc_ma = mc6845_0_o.ma;  assign crtc_ra = mc6845_0_o.ra;

assign m_int_n = ~crtc_vs;
logic hs_d = 1'b0, ma6_prev = 1'b0;
always_ff @(posedge clk) begin
    hs_d <= crtc_hs;
    if (reset) s_int_n <= 1'b1;
    else if (!s_m1_n && !s_iorq_n) s_int_n <= 1'b1;
    else if (crtc_hs && !hs_d) begin
        if (crtc_ma[6] && !ma6_prev) s_int_n <= 1'b0;
        ma6_prev <= crtc_ma[6];
    end
end

logic [9:0] v_tile_a;
logic [7:0] v_code, v_attr;

assign pr_i[2].a_addr = {6'd0, m_a[9:0]};  assign pr_i[2].a_d = m_do;  assign pr_i[2].a_we = m_vram && !m_wr_n;
assign pr_i[2].b_addr = {6'd0, v_tile_a};  assign pr_i[2].b_d = 8'd0;  assign pr_i[2].b_we = 1'b0;
assign vram_q = pr_o[2].a_q;  assign v_code = pr_o[2].b_q;
assign pr_i[4].a_addr = {6'd0, m_a[9:0]};  assign pr_i[4].a_d = m_do;  assign pr_i[4].a_we = m_cram && !m_wr_n;
assign pr_i[4].b_addr = {6'd0, v_tile_a};  assign pr_i[4].b_d = 8'd0;  assign pr_i[4].b_we = 1'b0;
assign cram_q = pr_o[4].a_q;  assign v_attr = pr_o[4].b_q;

logic [6:0] spr_e;
logic [7:0] spr_q[4];
genvar l;
generate
    for (l = 0; l < 4; l++) begin : spr_lane
        assign pr_i[5+l].a_addr = {9'd0, m_a[8:2]};  assign pr_i[5+l].a_d = m_do;  assign pr_i[5+l].a_we = m_spr && !m_wr_n && m_a[1:0] == l;
        assign pr_i[5+l].b_addr = {9'd0, spr_e};     assign pr_i[5+l].b_d = 8'd0;  assign pr_i[5+l].b_we = 1'b0;
        assign spr_q[l] = pr_o[5+l].b_q;
    end
endgenerate

always_comb begin
    m_di = 8'hFF;
    if (m_rom)       m_di = rom_main_d;
    else if (m_ram)  m_di = m_ram_q;
    else if (m_lat)  m_di = latch;
    else if (m_vram) m_di = vram_q;
    else if (m_cram) m_di = cram_q;
    else if (m_adp)  m_di = adp_idle ? 8'h00 : 8'h80;
end

always_comb begin
    s_di = 8'hFF;
    if (s_rom)       s_di = rom_sub_d;
    else if (s_ram)  s_di = s_ram_q;
    else if (s_lat)  s_di = latch;
    else if (s_inp)  s_di = (s_inp_d ? tms_h : tms_now);
end

logic       hd_q = 1'b0, de_q = 1'b0;
logic [7:0] px = 8'd0, py = 8'd0;
logic       first_de = 1'b1, vbl_q = 1'b1;
wire        hd_pix = !crtc_hbl;
wire        de_pix = crtc_de;
always_ff @(posedge clk) begin
    if (ce_pix) begin
        hd_q  <= hd_pix;
        de_q  <= de_pix;
        vbl_q <= crtc_vbl;
        if (crtc_vbl) first_de <= 1'b1;
        if (hd_pix) begin
            if (!hd_q) begin
                px <= 8'd0;
                if (de_pix) begin
                    py <= first_de ? 8'd0 : py + 8'd1;
                    first_de <= 1'b0;
                end
            end
            else px <= px + 8'd1;
        end
    end
end

wire [7:0] lx = crt_flip ? ~px : px;
wire [7:0] ly = crt_flip ? (8'd191 - py) : py;
wire [7:0] tx = flip ? ~lx : lx;
wire [7:0] ty = flip ? (8'd191 - ly) : ly;
wire [7:0] tmy = ty + 8'd32;

assign v_tile_a = {tmy[7:3], tx[7:3]};

logic [7:0]   lb_q[2];
logic [7:0]   lb_wa, lb_wd, lb_ra;
logic         lb_we;
logic         build_buf = 1'b0;
// plain 256-bit registers: a bit-select write into an unpacked array of vectors crashes Quartus 17 elaboration
logic [255:0] lb_taken0 = '0, lb_taken1 = '0;
logic [255:0] lb_vis0   = '0, lb_vis1   = '0;
wire  [255:0] lb_taken_b = build_buf ? lb_taken1 : lb_taken0;

generate
    for (l = 0; l < 2; l++) begin : lbuf
        assign pr_i[9+l].a_addr = {8'd0, lb_wa};  assign pr_i[9+l].a_d = lb_wd;  assign pr_i[9+l].a_we = lb_we && build_buf == l;
        assign pr_i[9+l].b_addr = {8'd0, lb_ra};  assign pr_i[9+l].b_d = 8'd0;   assign pr_i[9+l].b_we = 1'b0;
        assign lb_q[l] = pr_o[9+l].b_q;
    end
endgenerate
assign pr_i[3] = '0;
assign pr_i[12:11] = '0;

typedef enum logic [2:0] {SP_IDLE, SP_ADDR, SP_CHK, SP_FETCH, SP_PIX} sp_state_t;
sp_state_t   sp_st = SP_IDLE;
logic  [6:0] sp_e7;
logic  [7:0] sp_line;
logic  [3:0] sp_px;
logic  [8:0] sp_x;
logic        sp_fx;
logic  [4:0] sp_color;
logic        sp_rom_ok;
logic [11:0] sp_rom_a;

assign spr_e     = sp_e7;
assign rom_spr_a = sp_rom_a;

wire  [7:0] sxp8 = spr_q[1] + 8'd8;
wire  [8:0] sx0  = {1'b0, sxp8} - 9'd8;
wire  [8:0] sy0  = {1'b0, spr_q[0]} - 9'd32;
wire  [8:0] sx   = flip ? 9'd240 - sx0 : sx0;
wire  [8:0] sy   = flip ? 9'd176 - sy0 : sy0;
wire        fx   = spr_q[2][6] ^ flip;
wire        fy   = (idsoccer ? 1'b0 : spr_q[2][7]) ^ flip;
wire  [9:0] sp_code10 = {spr_q[2][7], spr_q[2][4], spr_q[3]};

logic [16:0] sp_rom8_a;
logic  [3:0] sp_k;
logic [63:0] sp_row8;
assign rom_spr8_a = sp_rom8_a;
wire  [8:0] sr   = {1'b0, sp_line} - sy;
wire        on_line = !sr[8] && sr[7:4] == 4'd0;

wire  [3:0] sp_c    = sp_fx ? ~sp_px : sp_px;
wire [63:0] sp_rowd = idsoccer ? sp_row8 : rom_spr_d;
wire  [7:0] sp_byte = sp_rowd[{sp_c[3:1], 3'b000} +: 8];
wire  [3:0] sp_pen  = sp_c[0] ? sp_byte[3:0] : sp_byte[7:4];
wire  [8:0] sp_xp   = sp_x + {5'd0, sp_px};

logic       pend1 = 1'b0;
wire        go_vbl  = ce_pix && crtc_vbl && !vbl_q;
wire        go_line = ce_pix && de_q && !de_pix && py < 8'd190;

always_ff @(posedge clk) begin
    lb_we <= 1'b0;
    rom_spr8_req <= 1'b0;
    case (sp_st)
        SP_IDLE: if (go_vbl || go_line || pend1) begin : start_line
                     logic [7:0] phys;
                     phys  = go_vbl ? 8'd0 : go_line ? py + 8'd2 : 8'd1;
                     pend1 <= go_vbl;
                     sp_line   <= crt_flip ? 8'd191 - phys : phys;
                     build_buf <= phys[0];
                     if (phys[0]) begin lb_taken1 <= '0; lb_vis1 <= '0; end
                     else         begin lb_taken0 <= '0; lb_vis0 <= '0; end
                     sp_e7     <= 7'd127;
                     sp_st     <= SP_ADDR;
                 end
        SP_ADDR: sp_st <= SP_CHK;
        SP_CHK:  begin
                     if (on_line) begin
                         sp_rom_a  <= {spr_q[3], fy ? ~sr[3:0] : sr[3:0]};
                         sp_rom8_a <= {sp_code10, fy ? ~sr[3:0] : sr[3:0], 3'd0};
                         sp_k      <= 4'd0;
                         sp_x      <= sx;
                         sp_fx     <= fx;
                         sp_color  <= idsoccer ? {1'b0, spr_q[2][3:0]} : spr_q[2][4:0];
                         sp_px     <= 4'd0;
                         sp_rom_ok <= 1'b0;
                         sp_st     <= idsoccer ? SP_FETCH : SP_PIX;
                         rom_spr8_req <= idsoccer;
                     end
                     else if (sp_e7 == 7'd0) sp_st <= SP_IDLE;
                     else begin sp_e7 <= sp_e7 - 7'd1; sp_st <= SP_ADDR; end
                 end
        SP_FETCH: if (rom_spr8_rdy) begin
                     sp_row8 <= rom_spr8_q;
                     sp_st   <= SP_PIX;
                 end
        SP_PIX:  begin
                     if (!sp_rom_ok) sp_rom_ok <= 1'b1;
                     else begin
                         if (sp_pen[3] && !sp_xp[8] && !lb_taken_b[sp_xp[7:0]]) begin
                             if (build_buf) lb_taken1[sp_xp[7:0]] <= 1'b1;
                             else           lb_taken0[sp_xp[7:0]] <= 1'b1;
                             if (sp_pen != 4'hF) begin
                                 if (build_buf) lb_vis1[sp_xp[7:0]] <= 1'b1;
                                 else           lb_vis0[sp_xp[7:0]] <= 1'b1;
                                 lb_we <= 1'b1;
                                 lb_wa <= sp_xp[7:0];
                                 lb_wd <= {sp_color, sp_pen[2:0]};
                             end
                         end
                         sp_px <= sp_px + 4'd1;
                         if (sp_px == 4'd15) begin
                             if (sp_e7 == 7'd0) sp_st <= SP_IDLE;
                             else begin sp_e7 <= sp_e7 - 7'd1; sp_st <= SP_ADDR; end
                         end
                     end
                 end
    endcase
end

logic [7:0]  s1_code, s1_attr;
logic [2:0]  s1_tx, s1_ty;
logic [7:0]  s1_lx;
logic        s1_ln;
logic [31:0] s2_row;
logic [4:0]  s2_color;
logic [2:0]  s2_tx;
logic [7:0]  s2_lx;
logic        s2_ln;
logic [7:0]  s3_idx;
logic [3:0]  blk[3];

assign rom_tile_a = {s1_attr[5], s1_code, s1_ty};
assign lb_ra      = s2_lx;

wire [7:0] t_byte = s2_row[{s2_tx[2:1], 3'b000} +: 8];
wire [3:0] t_pen  = s2_tx[0] ? t_byte[3:0] : t_byte[7:4];
wire       t_front = pri_low ? !t_pen[3] : t_pen[3];
wire       s_vis   = s2_ln ? lb_vis1[s2_lx] : lb_vis0[s2_lx];

wire vis_s0 = hd_pix && px >= 8'd8 && px < 8'd248;

always_ff @(posedge clk) begin
    if (ce_pix) begin
        s1_code <= v_code; s1_attr <= v_attr; s1_tx <= tx[2:0]; s1_ty <= tmy[2:0]; s1_lx <= lx; s1_ln <= py[0];
        s2_row  <= rom_tile_d; s2_color <= s1_attr[4:0]; s2_tx <= s1_tx; s2_lx <= s1_lx; s2_ln <= s1_ln;

        if (t_front)    s3_idx <= {s2_color, t_pen[2:0]};
        else if (s_vis) s3_idx <= lb_q[s2_ln];
        else            s3_idx <= {s2_color, t_pen[2:0]};

        blk[0] <= {vis_s0, crtc_hs, crtc_vs, crtc_vbl};
        for (int k = 1; k < 3; k++) blk[k] <= blk[k-1];
    end
end

logic [7:0] pal_q;
assign prom_a_o = s3_idx;
assign pal_q    = prom_d_i;

wire [7:0] c_r = (pal_q[5] ? 8'h23 : 8'h00) + (pal_q[6] ? 8'h4B : 8'h00) + (pal_q[7] ? 8'h91 : 8'h00);
wire [7:0] c_g = (pal_q[2] ? 8'h23 : 8'h00) + (pal_q[3] ? 8'h4B : 8'h00) + (pal_q[4] ? 8'h91 : 8'h00);
wire [7:0] c_b = (pal_q[0] ? 8'h52 : 8'h00) + (pal_q[1] ? 8'hAD : 8'h00);

logic out_vis = 1'b0, out_hs = 1'b0, out_vs = 1'b0, out_vbl = 1'b1;
always_ff @(posedge clk) begin
    if (ce_pix) begin
        video_r <= c_r; video_g <= c_g; video_b <= c_b;
        {out_vis, out_hs, out_vs, out_vbl} <= blk[2];
    end
end
assign video_hblank = !out_vis;
assign video_vblank = out_vbl;

logic       hb_q = 1'b1, vb_q = 1'b1, chs_q = 1'b0, cvs_q = 1'b0;
logic [8:0] hc = 9'd0, ln = 9'd0;
logic [8:0] hs_pos = 9'd0, hs_len = 9'd16, vs_pos = 9'd0, vs_len = 9'd3;
logic [8:0] hs_t = 9'd0, vs_t = 9'd0;
wire        hbl_now = !out_vis;
wire  [8:0] hc_cur  = (hbl_now && !hb_q) ? 9'd0 : hc + 9'd1;
wire  [8:0] ln_cur  = (out_vbl && !vb_q) ? 9'd0 : (hbl_now && !hb_q) ? ln + 9'd1 : ln;
wire  [8:0] hs_beg  = hs_pos + {{5{h_adj[3]}}, h_adj};
wire  [8:0] vs_beg  = vs_pos + {{5{v_adj[3]}}, v_adj};
always_ff @(posedge clk) begin
    if (ce_pix) begin
        hb_q <= hbl_now; vb_q <= out_vbl; chs_q <= out_hs; cvs_q <= out_vs;
        hc <= hc_cur; ln <= ln_cur;
        if (out_hs && !chs_q) begin hs_pos <= hc_cur; hs_t <= 9'd0; end
        else if (out_hs) hs_t <= hs_t + 9'd1;
        if (!out_hs && chs_q) hs_len <= hs_t + 9'd1;
        if (out_vs && !cvs_q) begin vs_pos <= ln_cur; vs_t <= 9'd0; end
        if (out_vs && (hbl_now && !hb_q)) vs_t <= vs_t + 9'd1;
        if (!out_vs && cvs_q) vs_len <= vs_t + 9'd1;
    end
end
wire [8:0] hs_end = hs_beg + hs_len;
wire [8:0] vs_end = vs_beg + vs_len;
assign video_hs = (hc_cur >= hs_beg) && (hc_cur < hs_end);
assign video_vs = (ln_cur >= vs_beg) && (ln_cur < vs_end);

endmodule
