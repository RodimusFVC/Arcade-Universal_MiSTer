//  Copyright (C) 2026 Rodimus

module nomnlnd_sound
(
    input  logic               clk,
    input  logic               reset,
    input  logic        [15:0] snd,
    input  logic               coin_sw,
    output logic signed [15:0] audio,

    output logic        [31:0]       mp_ea,
    output logic        [27:0]       mp_eb,
    input  logic        [59:0]       mp_ep,
    output logic [3:0]  [31:0]       mp_xa,
    output logic [3:0]  [31:0]       mp_xb,
    input  logic [3:0]  [63:0]       mp_xp,
    output logic [9:0]  [33:0]       mp_wa,
    output logic [9:0]  [16:0]       mp_wb,
    input  logic [9:0]  [50:0]       mp_wp
);

localparam logic [26:0] A_PINK  = 27'd6986525;
localparam logic [26:0] A_10MS  = 27'd699164;
localparam logic [26:0] A_51MS  = 27'd137100;
localparam logic [26:0] A_0S1   = 27'd69922;
localparam logic [26:0] A_0S33  = 27'd21188;
localparam logic [26:0] A_FAST  = 27'd34819162;
localparam logic [26:0] A_HPF   = 27'd873938;
localparam logic [26:0] A_2S    = 27'd3496;
localparam logic [26:0] A_0S44  = 27'd15887;
localparam logic [26:0] A_AC_CH = 27'd92002,    A_AC_DI = 27'd93229;
localparam logic [26:0] A_AM_CH = 27'd3477305,  A_AM_DI = 27'd3494684;
localparam logic [26:0] A_TC_CH = 27'd148452,   A_TC_DI = 27'd148768;
localparam logic [26:0] A_TD_CH = 27'd692243,   A_TD_DI = 27'd699164;
localparam logic [26:0] A_TW_CH = 27'd68674873, A_TW_DI = 27'd69356047;
localparam logic [26:0] A_EN_CH = 27'd13425538, A_EN_DI = 27'd13688364;
localparam logic [26:0] A_FI_CH = 27'd3477305,  A_FI_DI = 27'd3494684;
localparam logic [26:0] A_GE_CH = 27'd6917407,  A_GE_DI = 27'd6986525;

localparam logic signed [31:0] V0_1  = 32'sd1677722,   V0_5 = 32'sd8388608,  V0_7 = 32'sd11744051, V1_85 = 32'sd31037850;
localparam logic signed [31:0] V6    = 32'sd100663296, V8   = 32'sd134217728, V10_3 = 32'sd172805325;
localparam logic signed [31:0] V10_5 = 32'sd176160768, V12  = 32'sd201326592;

wire march = snd[0], lsb = snd[1], gsb = snd[2], tank = snd[3], supp = snd[4], rclear = snd[5], fire = snd[6];
wire gotem = snd[14], dead = snd[9], music = snd[10], enable = snd[11];

function automatic logic signed [31:0] vclip(input logic signed [31:0] a, input logic signed [31:0] lo, input logic signed [31:0] hi);
    vclip = (a < lo) ? lo : (a > hi) ? hi : a;
endfunction
function automatic logic signed [31:0] w(input logic signed [31:0] vv, input logic [15:0] k);
    logic signed [47:0] p, d;
    d = {{16{vv[31]}}, vv} - {{16{V6[31]}}, V6};
    p = d * $signed({1'b0, k});
    w = p[47:16];
endfunction
function automatic logic signed [33:0] w_a(input logic signed [31:0] vv);
    logic signed [47:0] d;
    d = {{16{vv[31]}}, vv} - {{16{V6[31]}}, V6};
    w_a = d[33:0];
endfunction
function automatic logic signed [31:0] w_r(input logic [50:0] pp);
    w_r = pp[47:16];
endfunction

localparam logic [4:0] PK = 5'd0, AC_C = 5'd1, AM_CV = 5'd2, AM_C = 5'd3, TC_C = 5'd4, TD_CV = 5'd5, TD_C = 5'd6, TW_C = 5'd7,
                       EN_C = 5'd8, FI_V = 5'd9, FI_C = 5'd10, GE_C = 5'd11, DE_V = 5'd12, CO_V = 5'd13, EN_M = 5'd14, HPF = 5'd15;
logic signed [31:0] v[32];
logic  [4:0] sl = 5'd0;
wire         step_end = (sl == 5'd31);
always_ff @(posedge clk) sl <= sl + 5'd1;

logic [31:0] nz = 32'h1;
logic  [7:0] nz_div = 8'd0;
logic        qAC = 0, qAM = 0, qTC = 0, qTD = 0, qTW = 0, qEN = 0, qFI = 0, qGE = 0, qAC_d = 0, qTC_d = 0;
logic  [7:0] ac_n = 8'd0;
logic        tk_t = 1'b0;
logic  [3:0] en_n = 4'd0;
logic        en_run = 1'b0, supp_d = 1'b0;

wire signed [31:0] white = nz[0] ? V10_5 : V0_5;
wire signed [31:0] pink  = vclip(V6 + ((v[PK] - 32'sd92274688) <<< 1), V0_5, V10_5);

wire signed [31:0] ac_vin = (lsb ? 32'sd0 : 32'sd68107000) + (gsb ? 32'sd0 : 32'sd133219592);
wire signed [31:0] ac_cv  = (ac_vin >>> 1) + (ac_vin >>> 2) + (ac_vin >>> 6) + V1_85;
wire        [3:0] ac_pop = {3'd0, ac_n[0]} + {3'd0, ac_n[1]} + {3'd0, ac_n[2]} + {3'd0, ac_n[3]} + {3'd0, ac_n[4]}
                         + {3'd0, ac_n[5]} + {3'd0, ac_n[6]} + {3'd0, ac_n[7]};
wire signed [31:0] am_com = $signed({4'd0, ac_pop, 24'd0}) + $signed({5'd0, ac_pop, 23'd0});
wire        [2:0] en_b   = en_n[2:0] ^ {3{rclear}};
wire signed [31:0] en_cv = (en_b[0] ? 32'sd80530637 : 0) + (en_b[1] ? 32'sd40265318 : 0) + (en_b[2] ? 32'sd80530637 : 0);
wire signed [31:0] en_cv2 = (en_cv >>> 1) + (en_cv >>> 2) + (en_cv >>> 6) + V1_85;
wire signed [31:0] fi_vp = (v[FI_V] + V12) >>> 1;

wire signed [31:0] o_am = qAM ? V10_3 : V0_1;
wire signed [31:0] o_td = qTD ? V10_3 : V0_1;
wire signed [31:0] o_tw = qTW ? V10_3 : V0_1;
wire signed [31:0] o_en = qEN ? V10_3 : V0_1;
wire signed [31:0] o_fi = vclip((fi_vp <<< 1) - (qFI ? V10_3 : V0_1), 32'sd0, V10_5);
wire signed [31:0] o_ge = qGE ? V10_3 : V0_1;
wire signed [31:0] dev  = pink - V6;
function automatic logic signed [31:0] ng_g(input logic signed [31:0] c);
    ng_g = vclip(V12 - c, 32'sd0, V12);
endfunction
function automatic logic signed [31:0] ng_r(input logic [63:0] pp);
    logic signed [63:0] p, q;
    p = pp;
    q = (p >>> 28) + (p >>> 30);
    ng_r = vclip(V6 + q[31:0], V0_5, V10_5);
endfunction
assign mp_xa[0] = (dev <<< 3) + (dev <<< 1);                       assign mp_xb[0] = ng_g(v[DE_V]);
assign mp_xa[1] = (dev <<< 2) + (dev >>> 1) + (dev >>> 3);         assign mp_xb[1] = ng_g(v[CO_V]);
assign mp_xa[2] = 32'd0;  assign mp_xb[2] = 32'd0;
assign mp_xa[3] = 32'd0;  assign mp_xb[3] = 32'd0;
wire signed [31:0] o_de = ng_r(mp_xp[0]);
wire signed [31:0] o_co = ng_r(mp_xp[1]);
wire signed [31:0] o_mu = music ? V10_3 : V0_1;

assign mp_wa[0] = w_a(o_am);  assign mp_wb[0] = 17'd948;
assign mp_wa[1] = w_a(o_td);  assign mp_wb[1] = 17'd1348;
assign mp_wa[2] = w_a(o_tw);  assign mp_wb[2] = 17'd2225;
assign mp_wa[3] = w_a(o_en);  assign mp_wb[3] = 17'd948;
assign mp_wa[4] = w_a(o_fi);  assign mp_wb[4] = 17'd4449;
assign mp_wa[5] = w_a(o_ge);  assign mp_wb[5] = 17'd2225;
assign mp_wa[6] = w_a(o_mu);  assign mp_wb[6] = 17'd4449;
assign mp_wa[7] = 34'd0;      assign mp_wb[7] = 17'd0;
assign mp_wa[8] = 34'd0;      assign mp_wb[8] = 17'd0;
assign mp_wa[9] = 34'd0;      assign mp_wb[9] = 17'd0;
wire signed [31:0] mix_raw = (march ? w_r(mp_wp[0]) : 0) + (tank ? w_r(mp_wp[1]) + w_r(mp_wp[2]) : 0)
                           + (en_run ? w_r(mp_wp[3]) : 0) + w_r(mp_wp[4]) + (gotem ? w_r(mp_wp[5]) : 0)
                           + w(o_de, 16'd4449) + w_r(mp_wp[6]) + w(o_co, 16'd44491);
wire signed [31:0] mix = (v[EN_M] > V6) ? mix_raw : 32'sd0;

`define AST(CAP, Q, RST, ACH, ADIS) begin x = ((RST) && (Q)) ? V12 - v[CAP] : -v[CAP]; a = ((RST) && (Q)) ? ACH : ADIS; end

logic signed [31:0] x;
logic        [26:0] a;
logic        [4:0]  nd;
always_comb begin
    x = 32'sd0; a = 27'd0; nd = sl;
    case (sl)
        PK:    begin x = white - v[PK]; a = A_PINK; end
        AC_C:  `AST(AC_C, qAC, 1'b1, A_AC_CH, A_AC_DI)
        AM_CV: begin x = ((am_com >>> 1) + (am_com >>> 2) + (am_com >>> 6) + V1_85) - v[AM_CV]; a = A_10MS; end
        AM_C:  `AST(AM_C, qAM, march, A_AM_CH, A_AM_DI)
        TC_C:  `AST(TC_C, qTC, 1'b1, A_TC_CH, A_TC_DI)
        TD_CV: begin x = (tk_t ? V10_3 : V0_1) - v[TD_CV]; a = A_51MS; end
        TD_C:  `AST(TD_C, qTD, tank, A_TD_CH, A_TD_DI)
        TW_C:  `AST(TW_C, qTW, tank, A_TW_CH, A_TW_DI)
        EN_C:  `AST(EN_C, qEN, en_run, A_EN_CH, A_EN_DI)
        FI_V:  if (fire) begin x = V0_7 - v[FI_V]; a = A_FAST; end else begin x = V12 - v[FI_V]; a = A_0S33; end
        FI_C:  `AST(FI_C, qFI, 1'b1, A_FI_CH, A_FI_DI)
        GE_C:  `AST(GE_C, qGE, gotem, A_GE_CH, A_GE_DI)
        DE_V:  if (dead) begin x = V0_7 - v[DE_V]; a = A_FAST; end else begin x = V12 - v[DE_V]; a = A_2S; end
        CO_V:  if (coin_sw) begin x = V0_7 - v[CO_V]; a = A_FAST; end else begin x = V12 - v[CO_V]; a = A_0S44; end
        EN_M:  begin x = (enable ? V12 : 32'sd0) - v[EN_M]; a = A_0S1; end
        HPF:   begin x = mix - v[HPF]; a = A_HPF; end
        default: nd = 5'd31;
    endcase
end

logic signed [31:0] p_x;
logic        [26:0] p_a;
logic        [4:0]  p_n = 5'd31, w_n = 5'd31;
logic signed [58:0] w_p;
wire  signed [31:0] w_sum = v[w_n] + {{5{w_p[58]}}, w_p[58:32]};
always_ff @(posedge clk) begin
    p_x <= x; p_a <= a; p_n <= nd;
    w_p <= mp_ep[58:0];
    w_n <= p_n;
    if (reset) begin
        for (int i = 0; i < 32; i++) v[i] <= 32'sd0;
        v[FI_V] <= V12; v[DE_V] <= V12; v[CO_V] <= V12; v[PK] <= 32'sd92274688; v[TD_CV] <= V6;
    end
    else if (w_n < 5'd16) v[w_n] <= w_sum;
end

function automatic logic q555(input logic q, input logic rst, input logic signed [31:0] vc, input logic signed [31:0] cv);
    if (!rst)                        q555 = 1'b0;
    else if (q && vc >= cv)          q555 = 1'b0;
    else if (!q && vc <= (cv >>> 1)) q555 = 1'b1;
    else                             q555 = q;
endfunction

always_ff @(posedge clk) begin
    if (reset) begin
        qAC <= 0; qAM <= 0; qTC <= 0; qTD <= 0; qTW <= 0; qEN <= 0; qFI <= 0; qGE <= 0; ac_n <= 0; tk_t <= 0; en_n <= 0; en_run <= 0;
    end
    else if (step_end) begin
        nz_div <= (nz_div == 8'd149) ? 8'd0 : nz_div + 8'd1;
        if (nz_div == 8'd0) nz <= {nz[30:0], nz[31] ^ nz[21] ^ nz[1] ^ nz[0]};
        qAC_d <= qAC; qTC_d <= qTC; supp_d <= supp;

        qAC <= q555(qAC, 1'b1,   v[AC_C], ac_cv);
        qAM <= q555(qAM, march,  v[AM_C], v[AM_CV]);
        qTC <= q555(qTC, 1'b1,   v[TC_C], V8);
        qTD <= q555(qTD, tank,   v[TD_C], v[TD_CV]);
        qTW <= q555(qTW, tank,   v[TW_C], V8);
        qEN <= q555(qEN, en_run, v[EN_C], en_cv2);
        qFI <= q555(qFI, 1'b1,   v[FI_C], vclip(v[FI_V], V0_5, V10_5));
        qGE <= q555(qGE, gotem,  v[GE_C], V8);

        if (!march) ac_n <= 8'd0; else if (qAC_d && !qAC) ac_n <= ac_n + 8'd1;
        if (qTC && !qTC_d) tk_t <= ~tk_t;
        if (supp && !supp_d) begin en_run <= 1'b1; en_n <= 4'd0; end
        else if (en_run && qTC && !qTC_d) begin
            if (en_n == 4'd7) en_run <= 1'b0;
            en_n <= en_n + 4'd1;
        end
    end
end

wire signed [31:0] y  = mix - v[HPF];
wire signed [47:0] y48 = {{16{y[31]}}, y};
wire signed [47:0] yo = (y48 <<< 13) + (y48 <<< 9) + (y48 <<< 8) + (y48 <<< 5) + (y48 <<< 3);
assign mp_ea = p_x;
assign mp_eb = {1'b0, p_a};
wire signed [23:0] yh = yo[47:24];
always_ff @(posedge clk) audio <= (yh > 24'sd32767) ? 16'sd32767 : (yh < -24'sd32768) ? -16'sd32768 : yh[15:0];

`undef AST

endmodule
