//============================================================================
//
//  Lady Bug sound unit: two SN76489 at the 4 MHz CPU clock (B1 at B000, C1 at C000)
//  Copyright (C) 2026 Rodimus
//
//  After Arnim Laeuger's ladybug_sound_unit.vhd: both chips' READY outputs
//  drive the CPU WAIT line. Chips are jt89 (Jose Tejada) instead of the
//  original VHDL SN76489 model.
//
//============================================================================

module ladybug_sound_unit
(
    input  logic               clk_20mhz_i,
    input  logic               clk_en_4mhz_i,
    input  logic               por_n_i,
    input  logic               cs11_n_i,
    input  logic               cs12_n_i,
    input  logic               wr_n_i,
    input  logic         [7:0] d_from_cpu_i,
    output logic               sound_wait_n_o,
    output logic signed [15:0] audio_o
);

logic               ready_b1_s, ready_c1_s;
logic signed [10:0] aout_b1_s, aout_c1_s;

jt89 snd_b1_b
(
    .rst    (~por_n_i),
    .clk    (clk_20mhz_i),
    .clk_en (clk_en_4mhz_i),
    .wr_n   (wr_n_i),
    .cs_n   (cs11_n_i),
    .din    (d_from_cpu_i),
    .sound  (aout_b1_s),
    .ready  (ready_b1_s)
);

jt89 snd_c1_b
(
    .rst    (~por_n_i),
    .clk    (clk_20mhz_i),
    .clk_en (clk_en_4mhz_i),
    .wr_n   (wr_n_i),
    .cs_n   (cs12_n_i),
    .din    (d_from_cpu_i),
    .sound  (aout_c1_s),
    .ready  (ready_c1_s)
);

// Equal mix (MAME routes both at 0.5)
wire signed [11:0] sum_s = {aout_b1_s[10], aout_b1_s} + {aout_c1_s[10], aout_c1_s};
assign audio_o = {sum_s, 4'd0};

assign sound_wait_n_o = ready_b1_s & ready_c1_s;

endmodule
