//============================================================================
//
//  Universal Space Panic sound board (8015)
//  Copyright (C) 2026 Rodimus
//
//  Effect structure from the Space Panic manual sound schematic (p.20): pins 1-12 = 7000-700B (data != 0),
//  pin 16 player die = 7800, pin 19 enemy laugh = 7801, pin 13 coin = the coin switch, pin 11 music = 700A D7.
//  The scan does not resolve every value, so pitches and time constants are fitted to recordings of the board
//  (MAME 'panic' samples): 556 tones -> square voices, transistor noise -> white noise through one-pole filters,
//  the op-amp gates -> RC envelopes. One-shot effects follow the sample lengths; held ones (falling, oxygen,
//  escape, extend) sound while their input is high, as on the board.
//    walk 882 Hz 25 % pulse (15 ms pulses + ~8 ms tail)      up/down 75 Hz, 35 ms        enemy die 1/2: high-pass noise 1.1 s
//    falling 1700 -> 90 Hz (tau 0.69 s)           oxygen 130 Hz, 0.4 s on / 0.2 s off
//    hang 280 Hz, 0.42 s                          escape low noise chopped at 3.2 Hz
//    extend 2594 Hz                               player die low noise, up 0.4 s then down
//    enemy laugh 1-3 kHz noise chopped at 4.4 Hz, 2.78 s                    coin 1026 Hz, 0.5 s
//  Engine as rtl/zerohour/zerohour_sound.sv (32 clocks per step, v += (x * a) >> 32); envelopes 1.0 = 2^24.
//
//============================================================================

module panic_sound
(
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic        [13:0] trig,           // [11:0] 7000-700B, [12] 7800 player die, [13] 7801 enemy laugh
    input  logic               music,          // 700A D7
    input  logic               coin_n,         // coin switch (SYSTEM bit 6 / 7, active low)
    output logic signed [15:0] audio
);

localparam logic [26:0] A_1MS    = 27'd6986525;
localparam logic [26:0] A_5MS    = 27'd1398215;
localparam logic [26:0] A_8MS    = 27'd873938;
localparam logic [26:0] A_10MS   = 27'd699164;
localparam logic [26:0] A_20MS   = 27'd349596;
localparam logic [26:0] A_50MS   = 27'd139842;
localparam logic [26:0] A_0S12   = 27'd58268;
localparam logic [26:0] A_0S15   = 27'd46615;
localparam logic [26:0] A_0S2    = 27'd34961;
localparam logic [26:0] A_0S35   = 27'd19978;
localparam logic [26:0] A_0S69   = 27'd10134;
localparam logic [26:0] A_0S7    = 27'd9989;
localparam logic [26:0] A_LP700  = 27'd30643523;
localparam logic [26:0] A_LP1K   = 27'd43709441;
localparam logic [26:0] A_LP2K   = 27'd86974055;
localparam logic [26:0] A_LP3K   = 27'd129798370;
localparam logic [26:0] A_HPF    = 27'd873938;

localparam logic [31:0] INC_WALK = 32'd6167133;    // 882 Hz
localparam logic [31:0] INC_UPD  = 32'd524416;     // 75 Hz
localparam logic [31:0] INC_OXY  = 32'd908988;     // 130 Hz
localparam logic [31:0] INC_HANG = 32'd1957820;    // 280 Hz
localparam logic [31:0] INC_EXT  = 32'd18137802;   // 2594 Hz
localparam logic [31:0] INC_COIN = 32'd7174011;    // 1026 Hz
localparam logic [31:0] INC_F0   = 32'd11886763;   // 1700 Hz
localparam logic [31:0] INC_F1   = 32'd629299;     // 90 Hz

localparam logic [20:0] T_UPD     = 21'd21499;
localparam logic [20:0] T_KILL    = 21'd92138;
localparam logic [20:0] T_FALL1   = 21'd184275;
localparam logic [20:0] T_OXY_P   = 21'd368550;
localparam logic [20:0] T_OXY_ON  = 21'd245700;
localparam logic [20:0] T_HANG    = 21'd257985;
localparam logic [20:0] T_ESC_P   = 21'd191953;
localparam logic [20:0] T_ESC_ON  = 21'd122850;
localparam logic [20:0] T_DIE1    = 21'd245700;
localparam logic [20:0] T_LAUGH   = 21'd1707615;
localparam logic [20:0] T_LAUGH_P = 21'd139602;
localparam logic [20:0] T_COIN    = 21'd307125;

localparam logic signed [31:0] ONE  = 32'sd16777216;   // envelope 1.0
localparam logic signed [31:0] F0_3 = 32'sd5033165;    // 0.3

wire walk = trig[0], kill1 = trig[1], fall = trig[2], oxy = trig[3], kill2 = trig[5], hang = trig[6], esc = trig[7];
wire upd  = trig[8], ext = trig[9], enable = trig[11], die = trig[12], laugh = trig[13];

// ------------------------------------------------------------------ engine
localparam logic [4:0] E_WALK = 5'd0, E_UPD = 5'd1, E_KILL = 5'd2, E_FALL = 5'd3, P_FALL = 5'd4, E_OXY = 5'd5,
                       E_HANG = 5'd6, E_ESC = 5'd7, E_EXT = 5'd8, E_DIE = 5'd9, E_LAUGH = 5'd10, E_COIN = 5'd11,
                       N_LP7 = 5'd12, N_LP1 = 5'd13, N_LP2 = 5'd14, N_LP3 = 5'd15, HPF = 5'd16;
logic signed [31:0] v[32];
logic  [4:0] sl = 5'd0;
wire         step_end = (sl == 5'd31);
always_ff @(posedge clk) sl <= sl + 5'd1;

// timers / state (step rate)
logic [20:0] t_upd = 0, t_kill = 0, t_fall = 0, t_oxy = 0, t_hang = 0, t_esc = 0, t_die = 0, t_laugh = 0, t_lch = 0, t_coin = 0;
logic        die_ph = 1'b0;
logic        walk_d = 0, upd_d = 0, kill_d = 0, fall_d = 0, hang_d = 0, die_d = 0, laugh_d = 0, coin_d = 0;
logic        fall_set = 1'b0;
logic [31:0] ph_walk = 0, ph_upd = 0, ph_oxy = 0, ph_hang = 0, ph_ext = 0, ph_coin = 0, ph_fall = 0;
logic [31:0] nz = 32'h1;

wire coin  = ~coin_n;
wire kill  = kill1 | kill2;
wire white_p = nz[0];

// envelope targets / speeds
wire oxy_on   = oxy && t_oxy < T_OXY_ON;
wire esc_on   = esc && t_esc < T_ESC_ON;
wire laugh_on = (t_laugh != 0) && t_lch < (T_LAUGH_P >> 1);

// ------------------------------------------------------------------ voices -> mix (counts of 16-bit full scale)
function automatic logic signed [31:0] sq(input logic s, input logic signed [31:0] env, input logic [14:0] amp);
    logic signed [45:0] p, t, e;
    e = {{14{env[31]}}, env};
    p = (s ? e : -e) * $signed({1'b0, amp});
    t = p >>> 24;                                                   // env (2^24) * amp >> 24, on the signed product
    sq = t[31:0];
endfunction
function automatic logic signed [31:0] nzv(input logic signed [31:0] n, input logic signed [31:0] env, input logic [14:0] amp);
    logic signed [63:0] p;
    logic signed [31:0] q;
    p = n * env;                                                    // 2^24 * 2^24
    q = p[55:24];
    nzv = sq(1'b1, q, amp);
endfunction

// noise sources normalised to about unit RMS
wire signed [31:0] n_low = v[N_LP7] <<< 4;                          // ~700 Hz low-pass
wire signed [31:0] n_esc = (v[N_LP1] <<< 4) - (v[N_LP1] <<< 1);      // ~1 kHz low-pass x 14
wire signed [31:0] n_hp  = (white_p ? ONE : -ONE) - v[N_LP2];        // ~2 kHz high-pass
wire signed [31:0] d_bp  = v[N_LP3] - v[N_LP1];
wire signed [31:0] n_bp  = (d_bp <<< 3) + (d_bp <<< 1);              // 1-3 kHz band x 10

wire signed [31:0] mix_v = sq(ph_walk[31:30] == 2'd0, v[E_WALK], 15'd3440) + sq(ph_upd[31], v[E_UPD], 15'd2460)
                         + sq(ph_fall[31:30] == 2'd0, v[E_FALL], 15'd2950) + sq(ph_oxy[31], v[E_OXY], 15'd4500)
                         + sq(ph_hang[31], v[E_HANG], 15'd2700) + sq(ph_ext[31], v[E_EXT], 15'd3930)
                         + sq(ph_coin[31:30] == 2'd0, v[E_COIN], 15'd6700)
                         + nzv(n_hp, v[E_KILL], 15'd16000) + nzv(n_esc, v[E_ESC], 15'd2880)
                         + nzv(n_low, v[E_DIE], 15'd6300) + nzv(n_bp, v[E_LAUGH], 15'd1800)
                         + (music ? 32'sd4100 : -32'sd4100);
wire signed [31:0] mix_s = enable ? (mix_v <<< 8) : 32'sd0;            // x 256 for the high-pass node's resolution

logic signed [31:0] x;
logic        [26:0] a;
logic        [4:0]  nd;
always_comb begin
    x = 32'sd0; a = 27'd0; nd = sl;
    case (sl)
        E_WALK:  begin x = (walk ? ONE : 32'sd0) - v[E_WALK]; a = walk ? A_1MS : A_8MS; end
        E_UPD:   begin x = ((upd || t_upd != 0) ? ONE : 32'sd0) - v[E_UPD]; a = (upd || t_upd != 0) ? A_1MS : A_5MS; end
        E_KILL:  begin x = ((t_kill != 0) ? ONE : 32'sd0) - v[E_KILL]; a = (t_kill != 0) ? A_50MS : A_0S35; end
        E_FALL:  if (fall) begin x = ((t_fall < T_FALL1) ? ONE : F0_3) - v[E_FALL]; a = (t_fall < T_FALL1) ? A_0S12 : A_0S7; end
                 else      begin x = -v[E_FALL]; a = A_20MS; end
        P_FALL:  begin x = $signed(INC_F1) - v[P_FALL]; a = A_0S69; end
        E_OXY:   begin x = (oxy_on ? ONE : 32'sd0) - v[E_OXY]; a = A_10MS; end
        E_HANG:  begin x = ((t_hang != 0) ? ONE : 32'sd0) - v[E_HANG]; a = A_5MS; end
        E_ESC:   begin x = (esc_on ? ONE : 32'sd0) - v[E_ESC]; a = A_5MS; end
        E_EXT:   begin x = (ext ? ONE : 32'sd0) - v[E_EXT]; a = A_5MS; end
        E_DIE:   begin x = ((t_die != 0 && !die_ph) ? ONE : 32'sd0) - v[E_DIE]; a = (t_die != 0 && !die_ph) ? A_0S15 : A_0S2; end
        E_LAUGH: begin x = (laugh_on ? ONE : 32'sd0) - v[E_LAUGH]; a = A_5MS; end
        E_COIN:  begin x = ((t_coin != 0) ? ONE : 32'sd0) - v[E_COIN]; a = (t_coin != 0) ? A_20MS : A_10MS; end
        N_LP7:   begin x = (white_p ? ONE : -ONE) - v[N_LP7]; a = A_LP700; end
        N_LP1:   begin x = (white_p ? ONE : -ONE) - v[N_LP1]; a = A_LP1K; end
        N_LP2:   begin x = (white_p ? ONE : -ONE) - v[N_LP2]; a = A_LP2K; end
        N_LP3:   begin x = (white_p ? ONE : -ONE) - v[N_LP3]; a = A_LP3K; end
        HPF:     begin x = mix_s - v[HPF]; a = A_HPF; end
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
        v[P_FALL] <= $signed(INC_F1);
    end
    else if (w_n == P_FALL && fall_set) v[P_FALL] <= $signed(INC_F0);
    else if (w_n < 5'd17) v[w_n] <= w_sum;
end

// ------------------------------------------------------------------ oscillators, timers (once per step)
always_ff @(posedge clk) begin
    if (reset) begin
        t_upd <= 0; t_kill <= 0; t_fall <= 0; t_oxy <= 0; t_hang <= 0; t_esc <= 0; t_die <= 0; t_laugh <= 0; t_lch <= 0; t_coin <= 0;
        fall_set <= 1'b0; die_ph <= 1'b0;
    end
    else if (step_end) begin
        nz <= {nz[30:0], nz[31] ^ nz[21] ^ nz[1] ^ nz[0]};
        walk_d <= walk; upd_d <= upd; kill_d <= kill; fall_d <= fall; hang_d <= hang; die_d <= die; laugh_d <= laugh; coin_d <= coin;

        ph_walk <= ph_walk + INC_WALK;   ph_upd <= ph_upd + INC_UPD;   ph_oxy <= ph_oxy + INC_OXY;
        ph_hang <= ph_hang + INC_HANG;   ph_ext <= ph_ext + INC_EXT;   ph_coin <= ph_coin + INC_COIN;
        ph_fall <= ph_fall + v[P_FALL];

        if (upd && !upd_d)     t_upd <= T_UPD;     else if (t_upd != 0) t_upd <= t_upd - 1'd1;
        if (kill && !kill_d)   t_kill <= T_KILL;   else if (t_kill != 0) t_kill <= t_kill - 1'd1;
        if (hang && !hang_d)   t_hang <= T_HANG;   else if (t_hang != 0) t_hang <= t_hang - 1'd1;
        if (coin && !coin_d)   t_coin <= T_COIN;   else if (t_coin != 0) t_coin <= t_coin - 1'd1;
        if (laugh && !laugh_d) begin t_laugh <= T_LAUGH; t_lch <= 0; end
        else if (t_laugh != 0) begin t_laugh <= t_laugh - 1'd1; t_lch <= (t_lch == T_LAUGH_P) ? 21'd0 : t_lch + 1'd1; end
        if (die && !die_d)     begin t_die <= T_DIE1; die_ph <= 1'b0; end
        else if (t_die != 0)   t_die <= t_die - 1'd1;
        else                   die_ph <= 1'b1;                       // after the rise: decay

        fall_set <= fall && !fall_d;
        t_fall <= fall ? ((t_fall == 21'h1FFFFF) ? t_fall : t_fall + 1'd1) : 21'd0;
        t_oxy  <= oxy ? ((t_oxy == T_OXY_P) ? 21'd0 : t_oxy + 1'd1) : 21'd0;
        t_esc  <= esc ? ((t_esc == T_ESC_P) ? 21'd0 : t_esc + 1'd1) : 21'd0;
    end
end

wire signed [31:0] y  = (mix_s - v[HPF]) >>> 8;
always_ff @(posedge clk) audio <= (y > 32'sd32767) ? 16'sd32767 : (y < -32'sd32768) ? -16'sd32768 : y[15:0];

endmodule
