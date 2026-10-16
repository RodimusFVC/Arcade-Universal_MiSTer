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
    output chip_pool_pkg::sn76489_i_t [1:0] sn76489_i,   // shared SN76489s (rtl/universal_board.sv)
    input  chip_pool_pkg::sn76489_o_t [1:0] sn76489_o,
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

// B1 = shared SN76489 0, C1 = 1 (rtl/universal_board.sv)
assign sn76489_i[0].rst  = ~por_n_i;
assign sn76489_i[0].ce   = clk_en_4mhz_i;
assign sn76489_i[0].wr_n = wr_n_i;
assign sn76489_i[0].cs_n = cs11_n_i;
assign sn76489_i[0].din  = d_from_cpu_i;
assign aout_b1_s  = sn76489_o[0].sound;
assign ready_b1_s = sn76489_o[0].ready;

assign sn76489_i[1].rst  = ~por_n_i;
assign sn76489_i[1].ce   = clk_en_4mhz_i;
assign sn76489_i[1].wr_n = wr_n_i;
assign sn76489_i[1].cs_n = cs12_n_i;
assign sn76489_i[1].din  = d_from_cpu_i;
assign aout_c1_s  = sn76489_o[1].sound;
assign ready_c1_s = sn76489_o[1].ready;

// Equal mix (MAME routes both at 0.5)
wire signed [11:0] sum_s = {aout_b1_s[10], aout_b1_s} + {aout_c1_s[10], aout_c1_s};
assign audio_o = {sum_s, 4'd0};

assign sound_wait_n_o = ready_b1_s & ready_c1_s;

endmodule
