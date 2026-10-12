//============================================================================
//
//  Universal No Man's Land sound board (8003)
//  Copyright (C) 2026 Rodimus
//
//  From the No Man's Land manual sound schematic (p.10); latch map as the Magical Spot main board (D7 of
//  4800-480F): 4800 attack march enable (1), 4801 L.S.B (2), 4802 G.S.B (3), 4803 tank drive (4), 4804 enemy
//  supplement (5), 4805 round clear (6), 4806 firing (7), 480E got enemy (8), 4809 player dead (9), 480A music
//  (10, MAME's DAC), 480B sound enable (11); pin 13 coin accept = the coin switch. No reference recordings
//  (MAME: 1-bit DAC only); component values from the schematic, VDD 12 V.
//    noise: 2SC945 x100 x1000 (a few kHz wide) -> R43 10k / C15 0.1u = pink (4 Vp-p)
//    attack march: IC13a 556 (1k / 75k / 1u) tempo, CV from L.S.B / G.S.B (100k / 51k); CD4040 Q1-Q8 through
//         eight 10k -> CV (1k / 10u) of IC13b 556 (1k / 200k / 0.01u); pin 1 low holds the 4040 in reset
//    tank drive: IC6a 556 (1k / 470k / 0.1u) / 2 (IC7a) through 51k / 1u -> CV of IC10a 556 (1k / 100k / 0.1u)
//         rumble, plus IC10b 556 (1k / 100k / 0.001u); both run while pin 4 is high
//    enemy supplement / round clear: 8-step pattern of the second 4040 (Q1-Q3 ^ round clear through 51k / 100k /
//         51k) on IC6b 556 (1k / 51k / 0.01u), clocked by IC6a
//    firing: IC11a 556 (1k / 200k / 0.01u) CV = C12 (1u, R33 330k), gated (R38 / R39 10k) by the same voltage
//    got enemy: IC11b 556 (1k / 100k / 0.01u) while pin 8 is high
//    player dead / coin: pink noise x10 / x4.7 gated by C16 (2.2u, 470k + 470k) / C18 (0.47u)
//    music: C35 / R60 straight into the bus; enable: IC16 shorts the bus after R50 / C17
//  Engine as rtl/zerohour/zerohour_sound.sv (32 clocks per step, v += (x * a) >> 32, 1 V = 2^24).
//
//============================================================================

module nomnlnd_sound
(
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic        [15:0] snd,            // D7 latched at 4800-480F
    input  logic               coin_sw,        // coin switch, active high
    output logic signed [15:0] audio
);

localparam logic [26:0] A_PINK  = 27'd6986525;      // R43 10k x C15 0.1u = 1 ms
localparam logic [26:0] A_10MS  = 27'd699164;
localparam logic [26:0] A_51MS  = 27'd137100;
localparam logic [26:0] A_0S1   = 27'd69922;
localparam logic [26:0] A_0S33  = 27'd21188;
localparam logic [26:0] A_FAST  = 27'd34819162;
localparam logic [26:0] A_HPF   = 27'd873938;
localparam logic [26:0] A_2S    = 27'd3496;         // C16 through 940k
localparam logic [26:0] A_0S44  = 27'd15887;        // C18 through 940k
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
function automatic logic signed [31:0] w(input logic signed [31:0] vv, input logic [15:0] k);   // (V - 6 V) x k / 2^16
    logic signed [47:0] p, d;
    d = {{16{vv[31]}}, vv} - {{16{V6[31]}}, V6};
    p = d * $signed({1'b0, k});
    w = p[47:16];
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
logic  [7:0] ac_n = 8'd0;                            // IC14 4040 Q1-Q8
logic        tk_t = 1'b0;                            // IC7a toggle
logic  [3:0] en_n = 4'd0;                            // second 4040 Q1-Q3 + running
logic        en_run = 1'b0, supp_d = 1'b0;

wire signed [31:0] white = nz[0] ? V10_5 : V0_5;
wire signed [31:0] pink  = vclip(V6 + ((v[PK] - 32'sd92274688) <<< 1), V0_5, V10_5);       // ~4 Vp-p

// attack march: tempo CV from L.S.B / G.S.B (inverters pull the 100k / 51k ends low when set)
wire signed [31:0] ac_vin = (lsb ? 32'sd0 : 32'sd68107000) + (gsb ? 32'sd0 : 32'sd133219592);   // 12 V x 0.338 / 0.662
wire signed [31:0] ac_cv  = (ac_vin >>> 1) + (ac_vin >>> 2) + (ac_vin >>> 6) + V1_85;           // through R15 1k
wire        [3:0] ac_pop = {3'd0, ac_n[0]} + {3'd0, ac_n[1]} + {3'd0, ac_n[2]} + {3'd0, ac_n[3]} + {3'd0, ac_n[4]}
                         + {3'd0, ac_n[5]} + {3'd0, ac_n[6]} + {3'd0, ac_n[7]};
wire signed [31:0] am_com = $signed({28'd0, ac_pop}) * 32'sd25165824;                            // 12 V x n / 8
// enemy supplement: Q1-Q3 ^ round clear through 51k / 100k / 51k (0.4 / 0.2 / 0.4)
wire        [2:0] en_b   = en_n[2:0] ^ {3{rclear}};
wire signed [31:0] en_cv = (en_b[0] ? 32'sd80530637 : 0) + (en_b[1] ? 32'sd40265318 : 0) + (en_b[2] ? 32'sd80530637 : 0);
wire signed [31:0] en_cv2 = (en_cv >>> 1) + (en_cv >>> 2) + (en_cv >>> 6) + V1_85;               // through R31 1k
wire signed [31:0] fi_vp = (v[FI_V] + V12) >>> 1;

wire signed [31:0] o_am = qAM ? V10_3 : V0_1;
wire signed [31:0] o_td = qTD ? V10_3 : V0_1;
wire signed [31:0] o_tw = qTW ? V10_3 : V0_1;
wire signed [31:0] o_en = qEN ? V10_3 : V0_1;
wire signed [31:0] o_fi = vclip((fi_vp <<< 1) - (qFI ? V10_3 : V0_1), 32'sd0, V10_5);
wire signed [31:0] o_ge = qGE ? V10_3 : V0_1;
wire signed [31:0] dev  = pink - V6;
// player dead / coin: inverting x10 / x4.7 noise stages whose + input is (C + 12 V) / 2. Taken literally they leak
// half the noise at rest (+ input at the rail); modelled as the evident intent: noise x (12 V - C) / 12 V
function automatic logic signed [31:0] ngate(input logic signed [31:0] c, input logic signed [31:0] n);
    logic signed [63:0] p, q;
    logic signed [31:0] g;
    g = vclip(V12 - c, 32'sd0, V12);
    p = {{32{n[31]}}, n} * {{32{g[31]}}, g};
    q = (p >>> 28) + (p >>> 30);                                            // g / 12 V ~ g / 2^27.6
    ngate = vclip(V6 + q[31:0], V0_5, V10_5);
endfunction
wire signed [31:0] o_de = ngate(v[DE_V], (dev <<< 3) + (dev <<< 1));                         // x10
wire signed [31:0] o_co = ngate(v[CO_V], (dev <<< 2) + (dev >>> 1) + (dev >>> 3));            // x4.7
wire signed [31:0] o_mu = music ? V10_3 : V0_1;

// bus: R53 470k, R54 330k, R55 200k, R56 470k, R57 100k, R58 200k, R59 100k, R60 100k, R61 10k (weights x 2^16)
wire signed [31:0] mix_raw = (march ? w(o_am, 16'd948) : 0) + (tank ? w(o_td, 16'd1348) + w(o_tw, 16'd2225) : 0)
                           + (en_run ? w(o_en, 16'd948) : 0) + w(o_fi, 16'd4449) + (gotem ? w(o_ge, 16'd2225) : 0)
                           + w(o_de, 16'd4449) + w(o_mu, 16'd4449) + w(o_co, 16'd44491);
wire signed [31:0] mix = (v[EN_M] > V6) ? mix_raw : 32'sd0;                                 // IC16 through R50 / C17

`define AST(CAP, Q, RST, ACH, ADIS) begin x = ((RST) && (Q)) ? V12 - v[CAP] : -v[CAP]; a = ((RST) && (Q)) ? ACH : ADIS; end

logic signed [31:0] x;
logic        [26:0] a;
logic        [4:0]  nd;
always_comb begin
    x = 32'sd0; a = 27'd0; nd = sl;
    case (sl)
        PK:    begin x = white - v[PK]; a = A_PINK; end
        AC_C:  `AST(AC_C, qAC, 1'b1, A_AC_CH, A_AC_DI)
        AM_CV: begin x = ((am_com >>> 1) + (am_com >>> 2) + (am_com >>> 6) + V1_85) - v[AM_CV]; a = A_10MS; end   // R23 1k / C4 10u
        AM_C:  `AST(AM_C, qAM, march, A_AM_CH, A_AM_DI)
        TC_C:  `AST(TC_C, qTC, 1'b1, A_TC_CH, A_TC_DI)
        TD_CV: begin x = (tk_t ? V10_3 : V0_1) - v[TD_CV]; a = A_51MS; end                 // R18 51k / C7 1u
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
    w_p <= p_x * $signed({1'b0, p_a});
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

        // attack march counter: reset while pin 1 is low, counts the tempo 556's falling edges
        if (!march) ac_n <= 8'd0; else if (qAC_d && !qAC) ac_n <= ac_n + 8'd1;
        // tank: IC7a toggles on IC6a
        if (qTC && !qTC_d) tk_t <= ~tk_t;
        // enemy supplement: 8 steps of IC6a from the pin 5 edge
        if (supp && !supp_d) begin en_run <= 1'b1; en_n <= 4'd0; end
        else if (en_run && qTC && !qTC_d) begin
            if (en_n == 4'd7) en_run <= 1'b0;
            en_n <= en_n + 4'd1;
        end
    end
end

wire signed [31:0] y  = mix - v[HPF];
wire signed [47:0] yo = y * 16'sd9000;
wire signed [23:0] yh = yo[47:24];
always_ff @(posedge clk) audio <= (yh > 24'sd32767) ? 16'sd32767 : (yh < -24'sd32768) ? -16'sd32768 : yh[15:0];

`undef AST

endmodule
