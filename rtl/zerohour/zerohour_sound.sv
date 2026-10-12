//============================================================================
//
//  Universal Zero Hour sound board (8011), discrete
//  Copyright (C) 2026 Rodimus
//
//  From the Zero Hour manual sound schematic (p.25). Inputs from the main board LS259s (main block diagram):
//    latch 1 (5000) Q0-Q7 -> pins 1-8, latch 2 (5800) Q1-Q4 -> pins 10-13, VDD 12 V.
//    pin 1  shoot:          LM3900 VCO, C16 charged while high, falling sweep (C16 0.47u, ~91 ms)
//    pin 2  asteroid hit:   LFSR noise gated by C8 (400k * 1u); a CD4013 toggled at each end of pin 2 switches
//                           C7 (0.01u) onto the noise node (dull / bright halves)
//    pin 3  asteroid mod.:  phi1 + phi2 mixed into the asteroid noise (CD4016)
//    pin 4  enemy descend:  556 (C 0.1u), CV = C14 (1u, 1M) decaying after the trigger
//    pin 5  shield hit:     556 (C 3300p), CV = C21 (1u, 470k) charging after the trigger, phi7 warble
//    pin 6  noise burst:    LFSR noise (R1 C1 low-pass) through IC5a while high (16 ms pulses in MAME)
//    pin 7  enemy fire:     556 (C 2200p), CV = C9 (1u, 2.2M) rising while high, phi6 warble
//    pin 8  bonus warn:     556 one-shot (100k, 0.01u) fired by phi2, width set by alpha (phi9 low-passed)
//    pin 10 thrust:         LFSR stage 13 shifted through IC7 (2 stages) by an LM3900 VCO whose input is C6
//                           (22u, 150k): ~5.4 kHz falling to ~40 Hz over 10 s
//    pin 11 sound enable:   Q4 shorts the mix bus while low
//    pin 12 1-bit output:   straight into the mix (C25, R87)
//    pin 13 coin:           556 (C 3300p), CV = C24 (1u, 1M) decaying after the trigger, phi6 warble
//    (no pin)               556 (C18 3300p) gated by C20, restarted by every phi12 falling edge (~7.4 s)
//  Clock: CD4070 RC oscillator, 4.4 kHz (bonus warn = phi2 = f/16 = 275 Hz in the reference recording),
//  CD4020 phi1 = Q1, phi2-phi11 = Q4-Q13, phi12 = Q14 / 2; CD4006 LFSR, feedback stage 5 ^ stage 17.
//
//  Analog nodes: one RC / integrator engine, 32 clocks per step (dt = 1.628 us): v += (x * a) >> 32,
//  voltages in 2^24 units. 556s: cap between CV / 2 and CV; CV pin loading by the internal 5k divider.
//  Mix bus: R76 1k || R72 1k, x100 (R71 / R72): source weight 50k / R, C26 high-pass, LM324 swing.
//
//============================================================================

module zerohour_sound
(
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic         [7:0] latch1,
    input  logic         [7:0] latch2,
    output logic signed [15:0] audio
);

// ------------------------------------------------------------------ constants
localparam logic signed [31:0] VDD  = 32'sd201326592;         // 12 V
localparam logic signed [31:0] V0_1 = 32'sd1677722;
localparam logic signed [31:0] V0_14 = 32'sd2348810;
localparam logic signed [31:0] V0_3 = 32'sd5033165;
localparam logic signed [31:0] V0_5 = 32'sd8388608;
localparam logic signed [31:0] V0_6 = 32'sd10066330;
localparam logic signed [31:0] V0_97 = 32'sd16273900;         // LM3900 Schmitt low threshold (0.5 + 0.47)
localparam logic signed [31:0] V6   = 32'sd100663296;         // CMOS threshold
localparam logic signed [31:0] V6_14 = 32'sd103012434;        // LM3900 Schmitt high threshold (0.5 + 0.47 * 12)
localparam logic signed [31:0] V10_3 = 32'sd172805325;        // 556 output high
localparam logic signed [31:0] V10_5 = 32'sd176160768;        // LM324 output high
localparam logic signed [31:0] V11  = 32'sd184549376;         // LM3900 output high
localparam logic signed [31:0] V11_4 = 32'sd191260262;
localparam logic signed [31:0] V1_715 = 32'sd28772925;        // 556 CV through 909 ohm: 0.786 * Vext + 1.715 V
localparam logic signed [31:0] V0_857 = 32'sd14377758;        // ... phi (12 V) share through the 10k
localparam logic signed [31:0] V5   = 32'sd83886080;
localparam logic signed [31:0] V5_25 = 32'sd88080384;         // output amp swing

localparam logic [26:0] A_05MS    = 27'd13961686;   // tau 0.5 ms (CMOS output / diode into 1u)
localparam logic [26:0] A_1MS     = 27'd6986525;    // tau 1 ms
localparam logic [26:0] A_11MS    = 27'd635609;     // tau 11 ms (C6 through D3)
localparam logic [26:0] A_91MS    = 27'd76837;      // tau 91 ms (C16: R42 || R43 || R44)
localparam logic [26:0] A_0S1     = 27'd69922;      // tau 0.1 s (R34 C11)
localparam logic [26:0] A_0S4     = 27'd17480;      // tau 0.4 s (R27 + R28, C8)
localparam logic [26:0] A_0S47    = 27'd14877;      // tau 0.47 s (R59 C21)
localparam logic [26:0] A_1S      = 27'd6992;       // tau 1 s (R37 C14, R68 C24)
localparam logic [26:0] A_2S      = 27'd3496;       // tau 2 s (R57 + R58, C20)
localparam logic [26:0] A_2S2     = 27'd3178;       // tau 2.2 s (R31 C9)
localparam logic [26:0] A_3S3     = 27'd2119;       // tau 3.3 s (R16 C6)
localparam logic [26:0] A_CH22    = 27'd31353110;   // 556 101k * 2200p
localparam logic [26:0] A_DIS22   = 27'd31665483;   // 556 100k * 2200p
localparam logic [26:0] A_CH33    = 27'd20927587;   // 556 101k * 3300p
localparam logic [26:0] A_DIS33   = 27'd21136347;   // 556 100k * 3300p
localparam logic [26:0] A_CH100   = 27'd692243;     // 556 101k * 0.1u
localparam logic [26:0] A_DIS100  = 27'd699164;     // 556 100k * 0.1u
localparam logic [26:0] A_HPF     = 27'd36076715;   // C26 0.1u * (R72 + mix bus) 1.93k
localparam logic [26:0] A_MAX     = 27'd134217727;  // discharge pin shorting the cap
localparam logic [26:0] K_VCO     = 27'd31782790;   // dt / (1M * 220p)

// ------------------------------------------------------------------ clock, CD4020, CD4006
logic [12:0] osc_div = 13'd0;
logic        osc_tick;
logic [14:0] cnt = 15'd0;                           // CD4020 Q1-Q14 + IC14 toggle
logic [18:1] lfsr = 18'd1;
assign osc_tick = (osc_div == 13'd4466);            // 19.656 MHz / 4467 = 4400 Hz
always_ff @(posedge clk) begin
    osc_div <= osc_tick ? 13'd0 : osc_div + 13'd1;
    if (osc_tick) begin
        cnt  <= cnt + 15'd1;
        lfsr <= {lfsr[17:1], (lfsr[5] ^ lfsr[17]) | (lfsr[17:1] == 17'd0)};
    end
end
wire ph1 = cnt[0], ph2 = cnt[3], ph3 = cnt[4], ph6 = cnt[7], ph7 = cnt[8], ph8 = cnt[9], ph9 = cnt[10], ph12 = cnt[14];
wire n9  = lfsr[9];                                 // CD4006 pin 13 (D1 + 4)
wire n13 = lfsr[13];                                // CD4006 pin 10 (D3 + 4)

// ------------------------------------------------------------------ inputs
wire shoot  = latch1[0];
wire ast    = latch1[1];
wire astmod = latch1[2];
wire desc   = latch1[3];
wire shield = latch1[4];
wire burst  = latch1[5];
wire efire  = latch1[6];
wire bonus  = latch1[7];
wire thrust = latch2[1];
wire snd_en = latch2[2];
wire dac    = latch2[3];
wire coin   = latch2[4];

// ------------------------------------------------------------------ engine
localparam int NN = 21;
localparam logic [4:0] A_N1 = 5'd0, A_C2 = 5'd1, T_C6 = 5'd2, T_INT = 5'd3, B_C8 = 5'd4, B_N = 5'd5, C_C9 = 5'd6,
                      C_CAP = 5'd7, D_AL = 5'd8, D_CAP = 5'd9, E_C14 = 5'd10, E_CAP = 5'd11, F_C16 = 5'd12, F_INT = 5'd13,
                      G_C21 = 5'd14, G_CAP = 5'd15, H_C24 = 5'd16, H_CAP = 5'd17, I_C20 = 5'd18, I_CAP = 5'd19, HPF = 5'd20;
logic signed [31:0] v[NN];
logic  [4:0] sl = 5'd0;
wire         step_end = (sl == 5'd31);
always_ff @(posedge clk) sl <= sl + 5'd1;

// discrete state
logic sT = 1'b0, sF = 1'b0;                         // LM3900 Schmitt outputs (VCO square)
logic qC = 1'b0, qD = 1'b0, qE = 1'b0, qG = 1'b0, qH = 1'b0, qI = 1'b0;   // 556 outputs
logic qT = 1'b0, qT2 = 1'b0;                        // IC7: noise sample, previous sample
logic selB = 1'b0;                                  // IC14: C7 on the asteroid noise node
logic [12:0] disI = 13'd0;                          // IC16 low after a phi12 falling edge (R56 C19)
logic ast_d = 1'b0, ph2_d = 1'b0, ph12_d = 1'b0, sT_d = 1'b0;

function automatic logic signed [31:0] vmin(input logic signed [31:0] a, input logic signed [31:0] b);
    vmin = (a < b) ? a : b;
endfunction
function automatic logic signed [31:0] vclip(input logic signed [31:0] a, input logic signed [31:0] lo, input logic signed [31:0] hi);
    vclip = (a < lo) ? lo : (a > hi) ? hi : a;
endfunction
function automatic logic signed [31:0] pos(input logic signed [31:0] a);
    pos = a[31] ? 32'sd0 : a;
endfunction

// derived voltages
wire signed [31:0] vAp   = (v[A_C2] + VDD) >>> 1;                                        // R4 / R5 divider
wire signed [31:0] outA  = vclip((vAp <<< 1) - v[A_N1], 32'sd0, V10_5);                   // IC5a: 2 V+ - noise
wire signed [31:0] vBp   = (VDD + v[B_C8]) >>> 1;                                        // R27 / R28
wire signed [31:0] srcB  = n9 ? VDD : 32'sd0;
wire signed [31:0] nB_dc = (srcB + vBp) >>> 1;                                           // R13 / R24 divider
wire signed [31:0] nB    = selB ? v[B_N] : nB_dc;
wire signed [31:0] vphi  = (ph1 ? (VDD >>> 1) : 32'sd0) + (ph2 ? (VDD >>> 1) : 32'sd0);  // R22 / R23
wire signed [31:0] dphi  = vBp - vphi;
wire signed [31:0] outB  = vclip(vBp + (vBp - nB) + (astmod ? ((dphi >>> 2) + (dphi >>> 3) + (dphi >>> 6)) : 32'sd0),
                                 32'sd0, V10_5);                                          // R25 / R24, R25 / 250k
wire signed [31:0] alpha = vmin(v[D_AL], V10_5);
wire signed [31:0] fE    = vmin(v[E_C14], V10_5);
wire signed [31:0] fG    = vmin(v[G_C21], V10_5);
wire signed [31:0] fH    = vmin(v[H_C24], V10_5);
wire signed [31:0] fC    = vmin(v[C_C9], V10_5);

// CV through 1k (op-amp) + 10k (phi), loaded by the 556's internal divider: 0.7145 V + 0.857 phi + 1.715
function automatic logic signed [31:0] cv_rr(input logic signed [31:0] vf, input logic phi);
    cv_rr = (vf >>> 1) + (vf >>> 3) + (vf >>> 4) + (vf >>> 6) + (vf >>> 7) + (vf >>> 8) + (phi ? V0_857 : 32'sd0) + V1_715;
endfunction
wire signed [31:0] cvC = cv_rr(fC, ph6);
wire signed [31:0] cvG = cv_rr(fG, ph7);
wire signed [31:0] cvH = cv_rr(fH, ph6);
wire signed [31:0] cvE = fE;
wire signed [31:0] cvD = alpha;
// IC13b: (phi8 + phi3 + alpha) / 3
wire signed [31:0] sumI = (ph8 ? VDD : 32'sd0) + (ph3 ? VDD : 32'sd0) + alpha;
wire signed [31:0] cvI  = (sumI >>> 2) + (sumI >>> 4) + (sumI >>> 6) + (sumI >>> 8);
wire signed [31:0] vIp  = (v[I_C20] + VDD) >>> 1;

wire signed [31:0] out556C = qC ? V10_3 : V0_1;
wire signed [31:0] out556D = qD ? V10_3 : V0_1;
wire signed [31:0] out556E = qE ? V10_3 : V0_1;
wire signed [31:0] out556G = qG ? V10_3 : V0_1;
wire signed [31:0] out556H = qH ? V10_3 : V0_1;
wire signed [31:0] outI    = vclip((vIp <<< 1) - (qI ? V10_3 : V0_1), 32'sd0, V10_5);     // IC13c
wire signed [31:0] outF    = sF ? V11 : 32'sd0;
// IC5c: 6 V + (6 V - Q1) * 33k / 51k + (6 V - Q2) * 33k / 100k, clipped
wire signed [31:0] outT    = (qT && qT2) ? V0_14 : qT ? 32'sd68786586 : qT2 ? 32'sd132539023 : V10_5;   // 4.1 V / 7.9 V
wire signed [31:0] outDac  = dac ? V5 : 32'sd0;

// mix bus x 100: weights 50k / R (R77 22k, R79 51k, R78 100k, R82 100k, R87 100k, 200k, 470k)
wire signed [31:0] mix_raw = (outA <<< 1) + (outA >>> 2) + (outA >>> 6)                  // 2.27
                           + outB - (outB >>> 6)                                          // 0.98
                           + (outT >>> 1) + (out556E >>> 1) + (outDac >>> 1)              // 0.5
                           + ((out556C + out556D + outF + out556G + out556H) >>> 2)      // 0.25
                           + (outI >>> 4) + (outI >>> 5) + (outI >>> 7);                 // 0.106
wire signed [31:0] mix = snd_en ? mix_raw : 32'sd0;                                       // Q4 shorts the bus

// 556 astable cap: charge through Ra + Rb toward VDD, discharge through Rb
`define AST(CAP, Q, RST, ACH, ADIS) begin x = ((RST) && (Q)) ? VDD - v[CAP] : -v[CAP]; a = ((RST) && (Q)) ? ACH : ADIS; end

// LM3900 input currents (V - 0.5) / R, in units of 1M
wire signed [31:0] iT  = pos(v[T_C6] - V0_5);                                                    // R6 1M, R7 470k
wire signed [31:0] iF  = pos(v[F_C16] - V0_5);                                                   // R43 1M, R44 470k

logic signed [31:0] x;
logic        [26:0] a;
logic        [4:0]  nd;
always_comb begin
    x = 32'sd0; a = 27'd0; nd = sl;
    case (sl)
        A_N1:  begin x = ((n9 ? VDD : 32'sd0) + vAp) >>> 1; x = x - v[A_N1]; a = A_05MS; end   // R1 / R2, C1
        A_C2:  begin x = (burst ? 32'sd0 : VDD) - v[A_C2]; a = A_05MS; end                     // IC2 output into C2
        T_C6:  if (!thrust) begin x = VDD - v[T_C6]; a = A_11MS; end                           // D3
               else         begin x = -v[T_C6];      a = A_3S3;  end                           // R16
        T_INT: begin x = sT ? -iT : iT + (iT >>> 3); a = K_VCO; end                            // Q1 shorts the + input
        B_C8:  if (ast) begin x = V0_6 - v[B_C8]; a = A_05MS; end                              // D4
               else     begin x = VDD - v[B_C8];  a = A_0S4;  end
        B_N:   begin x = nB_dc - v[B_N]; a = A_05MS; end                                       // R13 || R24, C7
        C_C9:  if (!efire) begin x = V0_6 - v[C_C9]; a = A_05MS; end                           // D5
               else        begin x = VDD - v[C_C9];  a = A_2S2;  end                           // R31
        C_CAP: `AST(C_CAP, qC, efire, A_CH22, A_DIS22)
        D_AL:  begin x = (ph9 ? VDD : 32'sd0) - v[D_AL]; a = A_0S1; end
        D_CAP: if (qD) begin x = VDD - v[D_CAP]; a = A_1MS; end                                // R36 C13
               else    begin x = -v[D_CAP];      a = A_MAX; end
        E_C14: if (desc) begin x = VDD - v[E_C14]; a = A_05MS; end                             // D7
               else      begin x = -v[E_C14];      a = A_1S;   end                             // R37
        E_CAP: `AST(E_CAP, qE, fE > V6, A_CH100, A_DIS100)
        F_C16: if (shoot) begin x = V11_4 - v[F_C16]; a = A_1MS;  end                          // pull-up, D8
               else       begin x = V0_3 - v[F_C16];  a = A_91MS; end                          // Q2, R42
        F_INT: begin x = sF ? -iF : iF + (iF >>> 3); a = K_VCO; end                            // Q3 shorts the + input
        G_C21: if (shield) begin x = V0_6 - v[G_C21]; a = A_05MS; end                          // D11
               else        begin x = VDD - v[G_C21];  a = A_0S47; end                          // R59
        G_CAP: `AST(G_CAP, qG, v[G_C21] < V6, A_CH33, A_DIS33)
        H_C24: if (coin) begin x = V11_4 - v[H_C24]; a = A_05MS; end                           // D12
               else      begin x = -v[H_C24];        a = A_1S;   end                           // R68
        H_CAP: `AST(H_CAP, qH, fH > V6, A_CH33, A_DIS33)
        I_C20: if (disI != 13'd0) begin x = V0_6 - v[I_C20]; a = A_1MS; end                    // D10
               else               begin x = VDD - v[I_C20];  a = A_2S;  end                    // R57 + R58
        I_CAP: `AST(I_CAP, qI, 1'b1, A_CH33, A_DIS33)
        HPF:   begin x = mix - v[HPF]; a = A_HPF; end
        default: nd = 5'd31;
    endcase
end

logic signed [31:0] p_x;
logic        [26:0] p_a;
logic        [4:0]  p_n = 5'd31, w_n = 5'd31;
logic signed [58:0] w_p;
wire  signed [31:0] w_sum = v[w_n] + {{5{w_p[58]}}, w_p[58:32]};          // (x * a) >> 32
wire                w_int = (w_n == 5'd3) || (w_n == 5'd13);                                     // T_INT, F_INT
always_ff @(posedge clk) begin
    p_x <= x; p_a <= a; p_n <= nd;
    w_p <= p_x * $signed({1'b0, p_a});
    w_n <= p_n;
    if (reset) begin
        for (int i = 0; i < NN; i++) v[i] <= 32'sd0;
        v[A_C2] <= VDD; v[T_C6] <= VDD; v[B_C8] <= VDD; v[I_C20] <= VDD; v[G_C21] <= VDD;
    end
    else if (w_n < 5'd21)
        v[w_n] <= w_int ? vclip(w_sum, 32'sd0, V11) : w_sum;                                     // LM3900 output range
end

// ------------------------------------------------------------------ comparators, flip-flops (once per step)
always_ff @(posedge clk) begin
    if (reset) begin
        sT <= 1'b0; sF <= 1'b0; qC <= 1'b0; qD <= 1'b0; qE <= 1'b0; qG <= 1'b0; qH <= 1'b0; qI <= 1'b0;
        qT <= 1'b0; qT2 <= 1'b0; selB <= 1'b0; disI <= 13'd0;
    end
    else if (step_end) begin
        ast_d <= ast; ph2_d <= ph2; ph12_d <= ph12; sT_d <= sT;

        // LM3900 Schmitt triggers (R10 / R46 470k, R11 / R47 1M, R9 / R48 1M)
        if (sT && v[T_INT] < V0_97) sT <= 1'b0; else if (!sT && v[T_INT] > V6_14) sT <= 1'b1;
        if (sF && v[F_INT] < V0_97) sF <= 1'b0; else if (!sF && v[F_INT] > V6_14) sF <= 1'b1;

        // IC7: LFSR stage 13 clocked by the thrust VCO, reset while pin 10 is low
        if (!thrust) begin qT <= 1'b0; qT2 <= 1'b0; end
        else if (sT && !sT_d) begin qT <= n13; qT2 <= qT; end

        // IC14: toggles at the end of each asteroid trigger
        if (ast_d && !ast) selB <= ~selB;

        // 556 astables: threshold at CV, trigger at CV / 2; reset holds the output low
        if (!efire) qC <= 1'b0;      else if (qC && v[C_CAP] >= cvC) qC <= 1'b0; else if (!qC && v[C_CAP] <= (cvC >>> 1)) qC <= 1'b1;
        if (!(fE > V6)) qE <= 1'b0;  else if (qE && v[E_CAP] >= cvE) qE <= 1'b0; else if (!qE && v[E_CAP] <= (cvE >>> 1)) qE <= 1'b1;
        if (!(v[G_C21] < V6)) qG <= 1'b0; else if (qG && v[G_CAP] >= cvG) qG <= 1'b0; else if (!qG && v[G_CAP] <= (cvG >>> 1)) qG <= 1'b1;
        if (!(fH > V6)) qH <= 1'b0;  else if (qH && v[H_CAP] >= cvH) qH <= 1'b0; else if (!qH && v[H_CAP] <= (cvH >>> 1)) qH <= 1'b1;
        if (qI && v[I_CAP] >= cvI) qI <= 1'b0; else if (!qI && v[I_CAP] <= (cvI >>> 1)) qI <= 1'b1;

        // 556 one-shot (bonus): triggered by phi2 rising (C12 / R35 / IC3), ends at CV
        if (!bonus) qD <= 1'b0; else if (ph2 && !ph2_d) qD <= 1'b1; else if (qD && v[D_CAP] >= cvD) qD <= 1'b0;

        // IC16 low for R56 * C19 * ln 2 = 6.9 ms after each phi12 falling edge
        if (ph12_d && !ph12) disI <= 13'd4238; else if (disI != 13'd0) disI <= disI - 13'd1;
    end
end

// ------------------------------------------------------------------ output amplifier (LM324 swing) -> 16 bit
wire signed [31:0] y  = vclip(mix - v[HPF], -V5_25, V5_25);
wire signed [45:0] yo = y * 14'sd5617;                    // 5.25 V -> 0.9 full scale
always_ff @(posedge clk) audio <= yo[39:24];

`undef AST

endmodule
