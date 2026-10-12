//============================================================================
//
//  Universal Cosmic Alien sound board (7910-S)
//  Copyright (C) 2026 Rodimus
//
//  Effect structure from the Cosmic Alien manual sound schematic (p.26): pins 1-12 = 7000-700B (data != 0),
//  pin 13 = the coin switch. Pitches and time constants fitted to recordings of the board (MAME 'cosmica'
//  samples), as for rtl/cosmic/panic_sound.sv:
//    background (while enabled): IC5b ~11 Hz samples the noise onto the IC5a 556 CV -> random pitch steps
//    dive A (pin 1): 3150 Hz, falling to ~2300 Hz after 1.5 s of hold
//    dive B (pin 3, select G.S.B / M.S.B / L.S.B on pins 4-6): one-shot sweep 5.6 kHz -> 700 Hz (tau 0.69 s);
//      L.S.B adds noise FM, G.S.B + L.S.B adds a 7 Hz chop (IC11b)
//    fire (pin 7): high noise burst; explosions: pin 8 loud (low noise, 2.3 s), pin 9 small (0.26 s) per the
//      schematic labels (MAME's cosmica_sound_output_w has offsets 7 / 8 the other way round)
//    extend (pin 10) / coin (pin 13): IC7b 556 tone, 1026 Hz 25 % pulse (as measured on the Space Panic copy
//      of the same circuit)
//    pin 12 sound enable: IC1 shorts the mix bus while low
//  Engine as rtl/zerohour/zerohour_sound.sv (32 clocks per step, v += (x * a) >> 32); envelopes 1.0 = 2^24.
//
//============================================================================

module cosmica_sound
(
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic        [11:0] trig,           // 7000-700B
    input  logic               coin,           // coin switch, active high
    output logic signed [15:0] audio
);

localparam logic [26:0] A_5MS    = 27'd1398215;
localparam logic [26:0] A_20MS   = 27'd349596;
localparam logic [26:0] A_80MS   = 27'd87402;
localparam logic [26:0] A_0S2    = 27'd34961;
localparam logic [26:0] A_0S3    = 27'd23307;
localparam logic [26:0] A_0S69   = 27'd10134;
localparam logic [26:0] A_0S7    = 27'd9989;
localparam logic [26:0] A_LP800  = 27'd35003284;
localparam logic [26:0] A_LP1K2  = 27'd52397804;
localparam logic [26:0] A_LP3K   = 27'd129798370;
localparam logic [26:0] A_HPF    = 27'd873938;
localparam logic [26:0] A_15MS   = 27'd466140;     // background CV settling (C21)

localparam logic [31:0] INC_DA    = 32'd22025473;   // 3150 Hz
localparam logic [31:0] INC_DA1   = 32'd16082092;   // 2300 Hz
localparam logic [31:0] INC_DB0   = 32'd39156397;   // 5600 Hz
localparam logic [31:0] INC_DB1   = 32'd4894550;    // 700 Hz
localparam logic [31:0] INC_COIN  = 32'd7174011;    // 1026 Hz
localparam logic [31:0] INC_BGMIN = 32'd3146496;    // 450 Hz

localparam logic [20:0] T_DA1  = 21'd921375;
localparam logic [20:0] T_DB   = 21'd1105650;
localparam logic [20:0] T_LFO  = 21'd87750;
localparam logic [20:0] T_FIRE = 21'd61425;
localparam logic [20:0] T_SEXP = 21'd73710;
localparam logic [20:0] T_LEXP = 21'd184275;
localparam logic [20:0] T_COIN = 21'd307125;
localparam logic [20:0] T_BG   = 21'd56353;

localparam logic signed [31:0] ONE = 32'sd16777216;

wire dive_a = trig[0], dive_b = trig[2], gsb = trig[3], msb = trig[4], lsb = trig[5], fire = trig[6];
wire lexp = trig[7], sexp = trig[8], ext = trig[9], enable = trig[11];

// ------------------------------------------------------------------ engine
localparam logic [4:0] E_DA = 5'd0, P_DA = 5'd1, E_DB = 5'd2, P_DB = 5'd3, E_FIRE = 5'd4, E_SEXP = 5'd5, E_LEXP = 5'd6,
                       E_COIN = 5'd7, N_LP8 = 5'd8, N_LP12 = 5'd9, N_LP3 = 5'd10, HPF = 5'd11, P_BG = 5'd12;
logic signed [31:0] v[32];
logic  [4:0] sl = 5'd0;
wire         step_end = (sl == 5'd31);
always_ff @(posedge clk) sl <= sl + 5'd1;

logic [20:0] t_da = 0, t_db = 0, t_lfo = 0, t_fire = 0, t_sexp = 0, t_lexp = 0, t_coin = 0, t_bg = 0;
logic        da_d = 0, db_d = 0, fire_d = 0, sexp_d = 0, lexp_d = 0, coin_d = 0;
logic        db_set = 1'b0, da_set = 1'b0;
logic  [2:0] db_sel = 3'd0;                                       // {G, M, L} latched at the trigger
logic [31:0] ph_da = 0, ph_db = 0, ph_coin = 0, ph_bg = 0, inc_bg = INC_BGMIN;
logic [31:0] nz = 32'h1;
wire         white_p = nz[0];

// ------------------------------------------------------------------ voices -> mix
function automatic logic signed [31:0] sq(input logic s, input logic signed [31:0] env, input logic [14:0] amp);
    logic signed [45:0] p, t, e;
    e = {{14{env[31]}}, env};
    p = (s ? e : -e) * $signed({1'b0, amp});
    t = p >>> 24;
    sq = t[31:0];
endfunction
function automatic logic signed [31:0] nzv(input logic signed [31:0] n, input logic signed [31:0] env, input logic [14:0] amp);
    logic signed [63:0] p;
    logic signed [31:0] q;
    p = n * env;
    q = p[55:24];
    nzv = sq(1'b1, q, amp);
endfunction

wire signed [31:0] n_hp  = (white_p ? ONE : -ONE) - v[N_LP3];       // above ~3 kHz
wire signed [31:0] n_mid = (v[N_LP12] <<< 3) + (v[N_LP12] <<< 2);   // ~1.2 kHz low-pass x 12
wire signed [31:0] n_low = (v[N_LP8] <<< 4) - (v[N_LP8] <<< 1);     // ~800 Hz low-pass x 14
wire               db_chop = db_sel[2] && db_sel[0] && t_lfo >= (T_LFO >> 1);
wire signed [31:0] db_env  = db_chop ? 32'sd0 : v[E_DB];

wire signed [31:0] mix_v = sq(ph_bg[31], ONE, 15'd1000)
                         + sq(ph_da[31], v[E_DA], 15'd2600) + nzv(n_hp, v[E_DA], 15'd1200) + sq(ph_db[31], db_env, 15'd2200)
                         + sq(ph_coin[31:30] == 2'd0, v[E_COIN], 15'd5000)
                         + nzv(n_hp, v[E_FIRE], 15'd2400) + nzv(n_mid, v[E_SEXP], 15'd2400)
                         + nzv(n_low, v[E_LEXP], 15'd4000);
wire signed [31:0] mix_s = enable ? (mix_v <<< 8) : 32'sd0;         // enable low: IC1 shorts the mix bus

logic signed [31:0] x;
logic        [26:0] a;
logic        [4:0]  nd;
always_comb begin
    x = 32'sd0; a = 27'd0; nd = sl;
    case (sl)
        E_DA:   begin x = (dive_a ? ONE : 32'sd0) - v[E_DA]; a = dive_a ? A_5MS : A_20MS; end
        P_DA:   begin x = $signed(INC_DA1) - v[P_DA]; a = (t_da >= T_DA1) ? A_0S3 : 27'd0; end
        E_DB:   begin x = ((t_db != 0) ? ONE : 32'sd0) - v[E_DB]; a = (t_db != 0) ? A_5MS : A_80MS; end
        P_DB:   begin x = $signed(INC_DB1) - v[P_DB]; a = A_0S69; end
        E_FIRE: begin x = ((t_fire != 0) ? ONE : 32'sd0) - v[E_FIRE]; a = (t_fire != 0) ? A_5MS : A_0S2; end
        E_SEXP: begin x = ((t_sexp != 0) ? ONE : 32'sd0) - v[E_SEXP]; a = (t_sexp != 0) ? A_5MS : A_80MS; end
        E_LEXP: begin x = ((t_lexp != 0) ? ONE : 32'sd0) - v[E_LEXP]; a = (t_lexp != 0) ? A_5MS : A_0S7; end
        E_COIN: begin x = ((ext || t_coin != 0) ? ONE : 32'sd0) - v[E_COIN]; a = A_20MS; end
        N_LP8:  begin x = (white_p ? ONE : -ONE) - v[N_LP8]; a = A_LP800; end
        N_LP12: begin x = (white_p ? ONE : -ONE) - v[N_LP12]; a = A_LP1K2; end
        N_LP3:  begin x = (white_p ? ONE : -ONE) - v[N_LP3]; a = A_LP3K; end
        HPF:    begin x = mix_s - v[HPF]; a = A_HPF; end
        P_BG:   begin x = $signed(inc_bg) - v[P_BG]; a = A_15MS; end
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
        v[P_DA] <= $signed(INC_DA); v[P_DB] <= $signed(INC_DB1); v[P_BG] <= $signed(INC_BGMIN);
    end
    else if (w_n == P_DA && da_set) v[P_DA] <= $signed(INC_DA);
    else if (w_n == P_DB && db_set) v[P_DB] <= $signed(INC_DB0);
    else if (w_n < 5'd13) v[w_n] <= w_sum;
end

// ------------------------------------------------------------------ oscillators, timers (once per step)
wire [31:0] db_inc = v[P_DB];
wire [31:0] db_fm  = (db_sel[0] ? (nz[1] ? db_inc + (db_inc >> 2) : db_inc - (db_inc >> 2)) : db_inc);   // L.S.B: noise FM

always_ff @(posedge clk) begin
    if (reset) begin
        t_da <= 0; t_db <= 0; t_lfo <= 0; t_fire <= 0; t_sexp <= 0; t_lexp <= 0; t_coin <= 0; t_bg <= 0;
        da_set <= 1'b0; db_set <= 1'b0; db_sel <= 3'd0;
    end
    else if (step_end) begin
        nz <= {nz[30:0], nz[31] ^ nz[21] ^ nz[1] ^ nz[0]};
        da_d <= dive_a; db_d <= dive_b; fire_d <= fire; sexp_d <= sexp; lexp_d <= lexp; coin_d <= coin;

        ph_da   <= ph_da + v[P_DA];
        ph_db   <= ph_db + db_fm;
        ph_coin <= ph_coin + INC_COIN;
        ph_bg   <= ph_bg + v[P_BG];

        // background: new random pitch about 11 times a second (noise sampled onto the 556 CV)
        if (t_bg == 0) begin t_bg <= T_BG; inc_bg <= INC_BGMIN + {7'd0, nz[24:0]}; end
        else t_bg <= t_bg - 1'd1;

        da_set <= dive_a && !da_d;
        t_da   <= dive_a ? ((t_da == 21'h1FFFFF) ? t_da : t_da + 1'd1) : 21'd0;

        db_set <= dive_b && !db_d;
        if (dive_b && !db_d) begin t_db <= T_DB; db_sel <= {gsb, msb, lsb}; t_lfo <= 0; end
        else if (t_db != 0)  begin t_db <= t_db - 1'd1; t_lfo <= (t_lfo == T_LFO) ? 21'd0 : t_lfo + 1'd1; end

        if (fire && !fire_d) t_fire <= T_FIRE; else if (t_fire != 0) t_fire <= t_fire - 1'd1;
        if (sexp && !sexp_d) t_sexp <= T_SEXP; else if (t_sexp != 0) t_sexp <= t_sexp - 1'd1;
        if (lexp && !lexp_d) t_lexp <= T_LEXP; else if (t_lexp != 0) t_lexp <= t_lexp - 1'd1;
        if (coin && !coin_d) t_coin <= T_COIN; else if (t_coin != 0) t_coin <= t_coin - 1'd1;
    end
end

wire signed [31:0] y = (mix_s - v[HPF]) >>> 8;
always_ff @(posedge clk) audio <= (y > 32'sd32767) ? 16'sd32767 : (y < -32'sd32768) ? -16'sd32768 : y[15:0];

endmodule
