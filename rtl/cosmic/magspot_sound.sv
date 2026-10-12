//============================================================================
//
//  Universal Magical Spot / Devil Zone sound board (8013 / 8022, identical)
//  Copyright (C) 2026 Rodimus
//
//  From the Magical Spot manual sound schematic (p.16) and main block diagram (p.18): two LS259s latch D7 of
//  4800-480F; pins: 4800 music (1), 4801 BGM (2), 4802 firing (3), 4803 laser ship explosion (4), 4804 cocoon (5),
//  4805 hit 2nd (6), 4806 UFO (7), 480E Ultramoth (8), 4809 Ultramoth (9), 480A hit 1st (10), 480B enable (11);
//  pin 13 coin pattern = the coin switch. No reference recordings exist (MAME: 1-bit DAC only); component values
//  from the schematic, VDD 12 V, Vref 6 V.
//    noise: 2SC945 junction noise x100 x1000 = white (clipped); Sallen-Key 51k / 51k / 0.022u / 0.1u x11 = pink
//    BGM: IC12b 11.8 Hz pulse samples pink onto the IC12a 556 CV (1k / 470k / 0.01u); IC11 low-pass (100k || 6800p)
//         gated by C18 (re-armed through D1 at every sample, R21 100k): plucked random notes
//    firing: white noise band (1-3 kHz) gated by C23 (1u, 100k / 100k)
//    Ultramoth: IC15 555 (1k / 75k / 4700p) CV swept by C24 (2.2u, 100k), white-noise jitter (R99 510k),
//         heard while pin 8 is high (IC9)
//    coin pattern: IC3a starts the 4040 on the coin edge, clocked by the 11.8 Hz pulses; Q1-Q4 through
//         100k / 51k / 24k / 12k = 4-bit CV of IC16b (1k / 51k / 0.01u), 16 notes; R53 10k (the loudest input)
//    UFO: IC16a 556 (1k / 100k / 0.01u) CV warbled by the 5.9 Hz IC3b toggle (10k / 22u)
//    cocoon: IC18a 556 (1k / 51k / 3300p) gated by C38 (1u)
//    hit 1st: IC8 556 (1k / 51k / 0.047u) CV = C34 (1u, R70 100k) + pink; gated by the same voltage
//    laser ship explosion / hit 2nd: pink noise gated by C36 (4.7u) / C40 (1u)
//    music: the CPU's bit through 100k / 51k, low-passed (C42 read as 0.0022u: 0.022u would leave ~70 Hz)
//           mixed at twice the R92 220k weight (HW 2026-10-12: about half as loud as it should be)
//    enable: Q2 shorts the mix bus
//  Engine as rtl/zerohour/zerohour_sound.sv (32 clocks per step, v += (x * a) >> 32, 1 V = 2^24).
//
//============================================================================

module magspot_sound
(
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic        [15:0] snd,            // D7 latched at 4800-480F
    input  logic               coin_sw,        // coin switch, active high
    output logic signed [15:0] audio
);

localparam logic [26:0] A_PINK   = 27'd2900354;    // 2.41 ms (66 Hz)
localparam logic [26:0] A_BGLP   = 27'd10270368;   // R17 C17
localparam logic [26:0] A_BGENV  = 27'd317816;     // C18 recharge 22 ms
localparam logic [26:0] A_FAST   = 27'd34819162;   // diode / 4049 output into a cap
localparam logic [26:0] A_50MS   = 27'd139842;
localparam logic [26:0] A_0S1    = 27'd69922;
localparam logic [26:0] A_0S22   = 27'd31783;
localparam logic [26:0] A_0S235  = 27'd29754;
localparam logic [26:0] A_0S47   = 27'd14877;
localparam logic [26:0] A_55MS   = 27'd127129;
localparam logic [26:0] A_LP1K   = 27'd43709441;
localparam logic [26:0] A_LP3K   = 27'd129798370;
localparam logic [26:0] A_LP720  = 27'd31515832;
localparam logic [26:0] A_HPF    = 27'd873938;
localparam logic [26:0] A_BG_CH  = 27'd1484290,  A_BG_DI = 27'd1487447;
localparam logic [26:0] A_UM_CH  = 27'd19530526, A_UM_DI = 27'd19790332;
localparam logic [26:0] A_CP_CH  = 27'd13425538, A_CP_DI = 27'd13688364;
localparam logic [26:0] A_UF_CH  = 27'd6917407,  A_UF_DI = 27'd6986525;
localparam logic [26:0] A_CO_CH  = 27'd40554488, A_CO_DI = 27'd41345835;
localparam logic [26:0] A_H1_CH  = 27'd2860019,  A_H1_DI = 27'd2916078;

localparam logic signed [31:0] V0_1  = 32'sd1677722,   V0_5  = 32'sd8388608,   V1_85 = 32'sd31037850;
localparam logic signed [31:0] V5_4  = 32'sd90596966,  V6    = 32'sd100663296, V8    = 32'sd134217728;
localparam logic signed [31:0] V10_3 = 32'sd172805325, V10_5 = 32'sd176160768, V10_8 = 32'sd181193933;
localparam logic signed [31:0] V12   = 32'sd201326592;
localparam logic signed [31:0] V0_7  = 32'sd11744051;

localparam logic [16:0] T_SAMP = 17'd52055;          // IC12b period (11.8 Hz)
localparam logic [16:0] T_PULSE = 17'd424;           // IC12b low time (Rb 1k x 1u x ln 2)

wire music = snd[0], bgm = snd[1], fire = snd[2], laser = snd[3], cocoon = snd[4], hit2 = snd[5], ufo = snd[6];
wire um9 = snd[9], hit1 = snd[10], enable = snd[11], um8 = snd[14];

function automatic logic signed [31:0] vclip(input logic signed [31:0] a, input logic signed [31:0] lo, input logic signed [31:0] hi);
    vclip = (a < lo) ? lo : (a > hi) ? hi : a;
endfunction
// CV through 10k, loaded by the 555's internal divider: 0.25 V + 6 V
function automatic logic signed [31:0] cv10k(input logic signed [31:0] vf);
    cv10k = (vf >>> 2) + V6;
endfunction

// ------------------------------------------------------------------ engine nodes
localparam logic [4:0] P1 = 5'd0, P2 = 5'd1, BG_C = 5'd2, BG_L = 5'd3, BG_E = 5'd4, FI_V = 5'd5, FI_3 = 5'd6, FI_1 = 5'd7,
                       UM_V = 5'd8, UM_CV = 5'd9, UM_C = 5'd10, CP_C = 5'd11, UF_CV = 5'd12, UF_C = 5'd13, CO_C = 5'd14,
                       CO_V = 5'd15, H1_V = 5'd16, H1_C = 5'd17, LS_V = 5'd18, H2_V = 5'd19, MU_L = 5'd20, HPF = 5'd21;
logic signed [31:0] v[32];
logic  [4:0] sl = 5'd0;
wire         step_end = (sl == 5'd31);
always_ff @(posedge clk) sl <= sl + 5'd1;

// discrete state
logic [31:0] nz = 32'h1;
logic  [7:0] nz_div = 8'd0;                          // the x1000 LM324 stage limits the noise to a few kHz
logic [16:0] samp = 17'd0;
wire         pulse = samp < T_PULSE;                 // IC12b output low
logic        pulse_d = 1'b0;
logic signed [31:0] bg_cv = 32'sd134217728;          // C15 sample (IC11 follower)
logic        qBG = 0, qUM = 0, qCP = 0, qUF = 0, qCO = 0, qH1 = 0;
logic        uf_t = 1'b0;                             // IC3b toggle
logic        cp_run = 1'b0;                           // IC3a
logic  [4:0] cp_n = 5'd0;                             // 4040 Q1-Q5
logic        coin_d = 1'b0;

wire signed [31:0] white = nz[0] ? V10_5 : V0_5;
wire signed [31:0] pdev  = v[P2] - 32'sd92274688;     // 5.5 V = white average
wire signed [31:0] pink  = vclip(V6 + (pdev <<< 3) + (pdev <<< 1) + pdev, V0_5, V10_5);   // x11

// sources (op-amp outputs)
wire signed [31:0] sq_bg = qBG ? V10_3 : V0_1;
wire signed [31:0] o_bg  = vclip((v[BG_E] <<< 1) - v[BG_L], 32'sd0, V10_5);               // IC11b gate
wire signed [31:0] fi_in = vclip(V6 + ((v[FI_3] - v[FI_1]) <<< 2), V0_5, V10_5);       // IC11a output range
wire signed [31:0] o_fi  = vclip((v[FI_V] <<< 1) - fi_in, 32'sd0, V10_5);                 // IC11 gate
wire signed [31:0] o_um  = qUM ? V10_5 : V0_5;
wire signed [31:0] cp_dac = (cp_n[0] ? 32'sd13086720 : 0) + (cp_n[1] ? 32'sd25569280 : 0) + (cp_n[2] ? 32'sd54358016 : 0)
                          + (cp_n[3] ? 32'sd108514099 : 0);                                // 12 V x G / sum G
wire signed [31:0] cp_cv  = (cp_dac >>> 1) + (cp_dac >>> 2) + (cp_dac >>> 6) + V1_85;      // through R50 1k: 0.77 V + 1.85
wire signed [31:0] o_cp  = qCP ? V10_3 : V0_1;
wire signed [31:0] o_uf  = qUF ? V10_3 : V0_1;
wire signed [31:0] o_co  = vclip((v[CO_V] <<< 1) - (qCO ? V10_3 : V0_1), 32'sd0, V10_5);
wire signed [31:0] h1_cv = vclip(v[H1_V] + ((pink - V6) >>> 1), V0_5, V10_5);
wire signed [31:0] h1_vp = (v[H1_V] + V12) >>> 1;
wire signed [31:0] o_h1  = vclip((h1_vp <<< 1) - (qH1 ? V10_3 : V0_1), 32'sd0, V10_5);
wire signed [31:0] o_ls  = vclip((v[LS_V] <<< 1) - pink, 32'sd0, V10_5);
wire signed [31:0] o_h2  = vclip((v[H2_V] <<< 1) - pink, 32'sd0, V10_5);
wire signed [31:0] o_mu  = v[MU_L];

// mix bus: (V - 6 V) x G / sum G (R22 100k, R33 100k, R42 220k, R66 330k, R67 75k, R77 220k, R82 120k, R87 220k,
// R92 220k, R53 10k): weights x 2^16; switched sources (IC9) contribute only while on
function automatic logic signed [31:0] w(input logic signed [31:0] vv, input logic [15:0] k);
    logic signed [47:0] p, d;
    d = {{16{vv[31]}}, vv} - {{16{V6[31]}}, V6};
    p = d * $signed({1'b0, k});
    w = p[47:16];
endfunction
wire signed [31:0] mix_raw = (bgm ? w(o_bg, 16'd4024) : 0) + w(o_fi, 16'd4024) + (um8 ? w(o_um, 16'd1831) : 0)
                           + (ufo ? w(o_uf, 16'd1219) : 0) + w(o_co, 16'd5352) + w(o_h1, 16'd1831) + w(o_ls, 16'd3352)
                           + w(o_h2, 16'd1831) + w(o_mu, 16'd3662) + (cp_run ? w(o_cp, 16'd40238) : 0);
wire signed [31:0] mix = enable ? mix_raw : 32'sd0;                                         // Q2 shorts the bus

`define AST(CAP, Q, RST, ACH, ADIS, TGT) begin x = ((RST) && (Q)) ? (TGT) - v[CAP] : -v[CAP]; a = ((RST) && (Q)) ? ACH : ADIS; end

logic signed [31:0] x;
logic        [26:0] a;
logic        [4:0]  nd;
always_comb begin
    x = 32'sd0; a = 27'd0; nd = sl;
    case (sl)
        P1:    begin x = white - v[P1]; a = A_PINK; end
        P2:    begin x = v[P1] - v[P2]; a = A_PINK; end
        BG_C:  `AST(BG_C, qBG, 1'b1, A_BG_CH, A_BG_DI, V12)
        BG_L:  begin x = sq_bg - v[BG_L]; a = A_BGLP; end
        BG_E:  if (pulse) begin x = V0_7 - v[BG_E]; a = A_FAST; end else begin x = V12 - v[BG_E]; a = A_BGENV; end
        FI_V:  begin x = (fire ? V6 : V12) - v[FI_V]; a = A_50MS; end
        FI_3:  begin x = white - v[FI_3]; a = A_LP3K; end
        FI_1:  begin x = white - v[FI_1]; a = A_LP1K; end
        UM_V:  begin x = (um9 ? V5_4 : V10_8) - v[UM_V]; a = A_0S47; end
        UM_CV: if (um9) begin x = V0_5 - v[UM_CV]; a = A_0S22; end else begin x = V10_5 - v[UM_CV]; a = A_50MS; end
        UM_C:  `AST(UM_C, qUM, 1'b1, A_UM_CH, A_UM_DI, V12 + ((white - V6) >>> 3))   // R99 510k: noise into the timing node
        CP_C:  `AST(CP_C, qCP, cp_run, A_CP_CH, A_CP_DI, V12)
        UF_CV: begin x = cv10k(uf_t ? V10_3 : V0_1) - v[UF_CV]; a = A_55MS; end
        UF_C:  `AST(UF_C, qUF, 1'b1, A_UF_CH, A_UF_DI, V12)
        CO_C:  `AST(CO_C, qCO, 1'b1, A_CO_CH, A_CO_DI, V12)
        CO_V:  begin x = (cocoon ? V6 : V12) - v[CO_V]; a = A_50MS; end
        H1_V:  if (hit1) begin x = V0_7 - v[H1_V]; a = A_FAST; end else begin x = V12 - v[H1_V]; a = A_0S1; end
        H1_C:  `AST(H1_C, qH1, 1'b1, A_H1_CH, A_H1_DI, V12)
        LS_V:  begin x = (laser ? V6 : V12) - v[LS_V]; a = A_0S235; end
        H2_V:  begin x = (hit2 ? V6 : V12) - v[H2_V]; a = A_50MS; end
        MU_L:  begin x = (music ? 32'sd68350000 : 32'sd0) + V6 - 32'sd34175000 - v[MU_L]; a = A_LP720; end   // 4 V p-p around 6 V
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
        v[BG_E] <= V12; v[FI_V] <= V12; v[UM_V] <= V10_8; v[UM_CV] <= V10_5; v[CO_V] <= V12; v[H1_V] <= V12;
        v[LS_V] <= V12; v[H2_V] <= V12; v[P1] <= 32'sd92274688; v[P2] <= 32'sd92274688;
    end
    else if (w_n < 5'd22) v[w_n] <= w_sum;
end

// ------------------------------------------------------------------ comparators, counters (once per step)
function automatic logic q555(input logic q, input logic rst, input logic signed [31:0] vc, input logic signed [31:0] cv);
    if (!rst)                        q555 = 1'b0;
    else if (q && vc >= cv)          q555 = 1'b0;
    else if (!q && vc <= (cv >>> 1)) q555 = 1'b1;
    else                             q555 = q;
endfunction

wire signed [31:0] um_cv = cv10k(vclip(v[UM_CV], 32'sd0, V10_5));

always_ff @(posedge clk) begin
    if (reset) begin
        samp <= 17'd0; qBG <= 0; qUM <= 0; qCP <= 0; qUF <= 0; qCO <= 0; qH1 <= 0; uf_t <= 0; cp_run <= 0; cp_n <= 0;
    end
    else if (step_end) begin
        nz_div <= (nz_div == 8'd149) ? 8'd0 : nz_div + 8'd1;
        if (nz_div == 8'd0) nz <= {nz[30:0], nz[31] ^ nz[21] ^ nz[1] ^ nz[0]};   // ~4.1 kHz
        samp <= (samp == T_SAMP - 1'd1) ? 17'd0 : samp + 1'd1;
        pulse_d <= pulse;
        coin_d <= coin_sw;
        if (pulse) bg_cv <= vclip(pink, V0_5, V10_5);             // IC9 closed: C15 follows the pink noise

        qBG <= q555(qBG, 1'b1, v[BG_C], bg_cv);
        qUM <= q555(qUM, 1'b1, v[UM_C], um_cv);
        qCP <= q555(qCP, cp_run, v[CP_C], cp_cv);
        qUF <= q555(qUF, 1'b1, v[UF_C], v[UF_CV]);
        qCO <= q555(qCO, 1'b1, v[CO_C], V8);
        qH1 <= q555(qH1, 1'b1, v[H1_C], h1_cv);

        if (pulse && !pulse_d) uf_t <= ~uf_t;                       // IC3b toggles on each sample pulse

        // coin pattern: IC3a set by the coin edge; 4040 counts the sample pulses while set; Q5 resets IC3a
        if (coin_sw && !coin_d) begin cp_run <= 1'b1; cp_n <= 5'd0; end
        else if (cp_run && pulse && !pulse_d) begin
            if (cp_n == 5'd15) begin cp_run <= 1'b0; cp_n <= 5'd0; end
            else cp_n <= cp_n + 5'd1;
        end
    end
end

// ------------------------------------------------------------------ output: bus x 9000 per volt (coin pattern just under full scale)
wire signed [31:0] y  = mix - v[HPF];
wire signed [47:0] yo = y * 16'sd9000;
wire signed [23:0] yh = yo[47:24];                                   // signed copy before comparing
always_ff @(posedge clk) audio <= (yh > 24'sd32767) ? 16'sd32767 : (yh < -24'sd32768) ? -16'sd32768 : yh[15:0];

`undef AST

endmodule
