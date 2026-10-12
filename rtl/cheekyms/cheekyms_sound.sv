//============================================================================
//
//  Universal Cheeky Mouse sound board, discrete (5 V)
//  Copyright (C) 2026 Rodimus
//
//  From MAME nl_cheekyms.cpp (Vas Crabb, Couriersud): the schematic transcribed as a netlist.
//    port 40: D7 music (straight into the mix), D6 cheese, D5 hammer, D4 mouse dies, D3 pest dies, D2 mouse, D1 pest
//    port 80: D1 coin / extra, D0 mute (0 = Q1 shorts mix node A)
//  cheese:     transistor B-E noise, x101 then x1000 (LM324, ~1 kHz bandwidth), clipped; IC1 sets the bias so it
//              only swings while cheese = 1
//  mouse:      555 1k / 68k / 0.01u, RESET = mouse, CONT from RESET through R14 4.7k || D4 (C13 10u): rising glide
//  hammer:     free-running 555 1k / 150k / 0.01u through IC5b: out = 2 V+ - V, V+ = C16 (0.1u, R23 1M) pulled to
//              ~1.4 V by IC1 / D5 / D6 while hammer = 1
//  pest:       free-running 555 1k / 68k / 0.01u, CONT warbled by a 16 Hz 555 (20k / 10k / 2.2u) through D7 /
//              R28 / R29 (C18 10u); IC5a gate as hammer (C20 0.22u, R35 1M)
//  mouse dies: 555 1k / 33k / 0.01u, RESET = mouse dies, CONT from RESET through R38 560 (C22 47u)
//  pest dies:  555 1k / 47k / 0.033u, RESET = pest dies;   coin / extra: 555 1k / 47k / 0.01u, RESET = coin
//  Mix: node A (R12 / R13 / R17 / R39 / R42 100k, R24 / R34 51k, Q1) -> R43 10k -> node B (R46 100k coin,
//  VR1 1k); solved: VB = 500 * sum(V / R) + 0.00946 * Vcoin. Output = VR1 wiper (VB / 2), MAME scale.
//  Engine: as rtl/zerohour/zerohour_sound.sv (32 clocks per step, v += (x * a) >> 32, 1 V = 2^24).
//
//============================================================================

module cheekyms_sound
(
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic         [7:0] port40,
    input  logic         [1:0] port80,
    output logic signed [15:0] audio
);

localparam logic signed [31:0] V0_1   = 32'sd1677722;
localparam logic signed [31:0] V0_2   = 32'sd3355443;
localparam logic signed [31:0] V0_6   = 32'sd10066330;
localparam logic signed [31:0] V0_65  = 32'sd10905190;
localparam logic signed [31:0] V0_7   = 32'sd11744051;
localparam logic signed [31:0] V1_13  = 32'sd18958254;
localparam logic signed [31:0] V1_4   = 32'sd23488102;
localparam logic signed [31:0] V2_6   = 32'sd43620762;
localparam logic signed [31:0] V3_3   = 32'sd55364813;     // 555 output high (NE555 at 5 V)
localparam logic signed [31:0] V3_333 = 32'sd55924053;     // 555 internal CV (2/3 VCC)
localparam logic signed [31:0] V3_36  = 32'sd56371446;
localparam logic signed [31:0] V3_39  = 32'sd56874762;
localparam logic signed [31:0] V3_4   = 32'sd57042534;     // TTL high
localparam logic signed [31:0] V3_5   = 32'sd58720256;     // LM324 output high at 5 V
localparam logic signed [31:0] V4_01  = 32'sd67276636;
localparam logic signed [31:0] V4_2   = 32'sd70464307;
localparam logic signed [31:0] V5     = 32'sd83886080;

localparam logic [26:0] A_0S1     = 27'd69922;      // 100 ms
localparam logic [26:0] A_0S22    = 27'd31783;      // 220 ms
localparam logic [26:0] A_LP1K    = 27'd43479757;   // 0.16 ms (LM324 x1000 bandwidth)
localparam logic [26:0] A_19M5    = 27'd358560;     // 19.5 ms
localparam logic [26:0] A_19M1    = 27'd366069;     // 19.1 ms
localparam logic [26:0] A_1M97    = 27'd3547881;    // 1.97 ms
localparam logic [26:0] A_0M5     = 27'd13961686;   // 0.5 ms
localparam logic [26:0] A_1MS     = 27'd6986525;    // 1 ms
localparam logic [26:0] A_0M1     = 27'd69356047;   // 0.1 ms
localparam logic [26:0] A_22M5    = 27'd310754;     // 22.5 ms
localparam logic [26:0] A_8MS     = 27'd873938;     // 8 ms (output high-pass, 20 Hz)
localparam logic [26:0] A_CH69    = 27'd10121698;   // 555 69k * 0.01u
localparam logic [26:0] A_DI68    = 27'd10270368;   //     68k * 0.01u
localparam logic [26:0] A_CH151   = 27'd4628110;    //     151k * 0.01u
localparam logic [26:0] A_DI150   = 27'd4658947;    //     150k * 0.01u
localparam logic [26:0] A_CH66M   = 27'd105941;     //     30k * 2.2u
localparam logic [26:0] A_DI22M   = 27'd317816;     //     10k * 2.2u
localparam logic [26:0] A_CH34    = 27'd20516177;   //     34k * 0.01u
localparam logic [26:0] A_DI33    = 27'd21136347;   //     33k * 0.01u
localparam logic [26:0] A_CH48_33 = 27'd4412009;    //     48k * 0.033u
localparam logic [26:0] A_DI47_33 = 27'd4505832;    //     47k * 0.033u
localparam logic [26:0] A_CH48    = 27'd14542436;   //     48k * 0.01u
localparam logic [26:0] A_DI47    = 27'd14851314;   //     47k * 0.01u

wire music  = port40[7];
wire cheese = port40[6];
wire hammer = port40[5];
wire mdies  = port40[4];
wire pdies  = port40[3];
wire mouse  = port40[2];
wire pest   = port40[1];
wire coin   = port80[1];
wire mute_n = port80[0];

// ------------------------------------------------------------------ engine
localparam logic [4:0] MU_B = 5'd0, CH_LP = 5'd1, MO_CV = 5'd2, MO_C = 5'd3, HA_C = 5'd4, HA_F = 5'd5, HA_VP = 5'd6,
                       PE_S = 5'd7, PE_CV = 5'd8, PE_C = 5'd9, PE_VP = 5'd10, MD_CV = 5'd11, MD_C = 5'd12,
                       PD_C = 5'd13, CO_C = 5'd14, HPF = 5'd15;
logic signed [31:0] v[32];                     // 16 used
logic  [4:0] sl = 5'd0;
wire         step_end = (sl == 5'd31);
always_ff @(posedge clk) sl <= sl + 5'd1;

logic qMO = 1'b0, qHA = 1'b0, qPS = 1'b0, qPE = 1'b0, qMD = 1'b0, qPD = 1'b0, qCO = 1'b0;   // 555 outputs
logic [22:0] nz = 23'd1;                                                                   // B-E noise stand-in

function automatic logic signed [31:0] vclip(input logic signed [31:0] a, input logic signed [31:0] lo, input logic signed [31:0] hi);
    vclip = (a < lo) ? lo : (a > hi) ? hi : a;
endfunction

wire signed [31:0] o_mo = qMO ? V3_3 : V0_1;
wire signed [31:0] o_ha = qHA ? V3_3 : V0_1;
wire signed [31:0] o_ps = qPS ? V3_3 : V0_1;
wire signed [31:0] o_pe = qPE ? V3_3 : V0_1;
wire signed [31:0] o_md = qMD ? V3_3 : V0_1;
wire signed [31:0] o_pd = qPD ? V3_3 : V0_1;
wire signed [31:0] o_co = qCO ? V3_3 : V0_1;
wire signed [31:0] o_mus = music ? V3_4 : V0_2;
wire signed [31:0] o_ham = vclip((v[HA_VP] <<< 1) - v[HA_F], 32'sd0, V3_5);               // IC5b
wire signed [31:0] o_pst = vclip((v[PE_VP] <<< 1) - o_pe, 32'sd0, V3_5);                   // IC5a
wire signed [31:0] o_chs = (cheese && !v[CH_LP][31] && v[CH_LP] != 32'sd0) ? 32'sd0 : V3_5; // IC5d clipped noise

// 555 astable cap: charge through Ra + Rb toward VCC, discharge through Rb; reset holds discharge on
`define AST(CAP, Q, RST, ACH, ADIS) begin x = ((RST) && (Q)) ? V5 - v[CAP] : -v[CAP]; a = ((RST) && (Q)) ? ACH : ADIS; end

// mix node B (see header), weights x 2^16: 100k 0.005, 51k 0.0098, coin 0.00946 (Q1 on: 0.00901)
wire signed [47:0] sumA = {{16{o_chs[31]}}, o_chs} * 48'sd328 + {{16{o_mus[31]}}, o_mus} * 48'sd328 + {{16{o_mo[31]}}, o_mo} * 48'sd328 + {{16{o_md[31]}}, o_md} * 48'sd328
                        + {{16{o_pd[31]}}, o_pd} * 48'sd328 + {{16{o_ham[31]}}, o_ham} * 48'sd642 + {{16{o_pst[31]}}, o_pst} * 48'sd642;
wire               muted = v[MU_B] > V0_65;
wire signed [47:0] sumB = (muted ? 48'sd0 : sumA) + {{16{o_co[31]}}, o_co} * (muted ? 48'sd590 : 48'sd620);
wire signed [31:0] vb   = sumB[47:16];

logic signed [31:0] x;
logic        [26:0] a;
logic        [4:0]  nd;
always_comb begin
    x = 32'sd0; a = 27'd0; nd = sl;
    case (sl)
        MU_B:  begin x = (mute_n ? V0_2 : V3_4) - v[MU_B]; a = A_0S1; end                       // IC1 -> R1 -> C10
        CH_LP: begin x = (nz[0] ? V0_2 : -V0_2) - v[CH_LP]; a = A_LP1K; end
        MO_CV: if (mouse) begin x = V3_36 - v[MO_CV]; a = A_19M5; end                            // R14 4.7k || 3.33k
               else       begin x = V0_6 - v[MO_CV];  a = A_0M5;  end                            // D4
        MO_C:  `AST(MO_C, qMO, mouse, A_CH69, A_DI68)
        HA_C:  `AST(HA_C, qHA, 1'b1, A_CH151, A_DI150)
        HA_F:  begin x = o_ha - v[HA_F]; a = A_0M1; end                                          // R20 C15
        HA_VP: if (hammer) begin x = V1_4 - v[HA_VP]; a = A_1MS; end                             // IC1 / D5 / D6
               else        begin x = V5 - v[HA_VP];   a = A_0S1; end                             // R23 1M, C16
        PE_S:  `AST(PE_S, qPS, 1'b1, A_CH66M, A_DI22M)
        PE_CV: if (qPS) begin x = V4_01 - v[PE_CV]; a = A_19M1; end                              // R28 / R29 / 3.33k
               else     begin x = V1_13 - v[PE_CV]; a = A_1M97; end                              // R27 / D7
        PE_C:  `AST(PE_C, qPE, 1'b1, A_CH69, A_DI68)
        PE_VP: if (pest) begin x = V1_4 - v[PE_VP]; a = A_1MS;  end                              // IC1 / D8 / D9
               else      begin x = V5 - v[PE_VP];   a = A_0S22; end                              // R35 1M, C20
        MD_CV: begin x = (mdies ? V3_39 : V0_65) - v[MD_CV]; a = A_22M5; end                     // R38 560, C22
        MD_C:  `AST(MD_C, qMD, mdies, A_CH34, A_DI33)
        PD_C:  `AST(PD_C, qPD, pdies, A_CH48_33, A_DI47_33)
        CO_C:  `AST(CO_C, qCO, coin, A_CH48, A_DI47)
        HPF:   begin x = vb - v[HPF]; a = A_8MS; end
        default: nd = 5'd31;
    endcase
end

logic signed [31:0] p_x;
logic        [26:0] p_a;
logic        [4:0]  p_n = 5'd31, w_n = 5'd31;
logic signed [58:0] w_p;
wire  signed [31:0] w_sum = v[w_n] + {{5{w_p[58]}}, w_p[58:32]};           // (x * a) >> 32
always_ff @(posedge clk) begin
    p_x <= x; p_a <= a; p_n <= nd;
    w_p <= p_x * $signed({1'b0, p_a});
    w_n <= p_n;
    if (reset) begin
        for (int i = 0; i < 16; i++) v[i] <= 32'sd0;
        v[HA_VP] <= V5; v[PE_VP] <= V5; v[MU_B] <= V0_7;
    end
    else if (w_n < 5'd16)
        v[w_n] <= (w_n == MU_B) ? vclip(w_sum, 32'sd0, V0_7) : w_sum;            // Q1 B-E clamps C10
end

// ------------------------------------------------------------------ 555 comparators (once per step)
function automatic logic q555(input logic q, input logic rst, input logic signed [31:0] vc, input logic signed [31:0] cv);
    if (!rst)                 q555 = 1'b0;
    else if (q && vc >= cv)   q555 = 1'b0;
    else if (!q && vc <= (cv >>> 1)) q555 = 1'b1;
    else                      q555 = q;
endfunction

always_ff @(posedge clk) begin
    if (reset) begin
        qMO <= 1'b0; qHA <= 1'b0; qPS <= 1'b0; qPE <= 1'b0; qMD <= 1'b0; qPD <= 1'b0; qCO <= 1'b0;
    end
    else if (step_end) begin
        nz  <= {nz[21:0], nz[22] ^ nz[17]};
        qMO <= q555(qMO, mouse, v[MO_C], v[MO_CV]);
        qHA <= q555(qHA, 1'b1,  v[HA_C], V3_333);
        qPS <= q555(qPS, 1'b1,  v[PE_S], V3_333);
        qPE <= q555(qPE, 1'b1,  v[PE_C], v[PE_CV]);
        qMD <= q555(qMD, mdies, v[MD_C], v[MD_CV]);
        qPD <= q555(qPD, pdies, v[PD_C], V3_333);
        qCO <= q555(qCO, coin,  v[CO_C], V3_333);
    end
end

// ------------------------------------------------------------------ output: VR1 wiper (VB / 2) x MAME's 30000 * 10 / 32768
wire signed [31:0] y  = vb - v[HPF];
wire signed [49:0] yo = y * 18'sd150000;
wire signed [25:0] yh = yo[49:24];                        // part-selects are unsigned: compare a signed copy
always_ff @(posedge clk) audio <= (yh > 26'sd32767) ? 16'sd32767 : (yh < -26'sd32768) ? -16'sd32768 : yh[15:0];

`undef AST

endmodule
