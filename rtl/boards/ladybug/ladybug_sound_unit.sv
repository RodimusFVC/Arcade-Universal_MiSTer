//  After Arnim Laeuger's ladybug_sound_unit.vhd
//  Copyright (C) 2026 Rodimus

module ladybug_sound_unit
(
    output chip_pool_pkg::sn76489_i_t [1:0] sn76489_i,
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

// sn76489sv sound is unipolar 0..1020 (0 when silent, no DC at rest): 2 chips max 2040, x16 = 32640 fits int16, no clamp needed
wire        [11:0] sum_s = {1'b0, aout_b1_s} + {1'b0, aout_c1_s};
assign audio_o = $signed({sum_s, 4'd0});

assign sound_wait_n_o = ready_b1_s & ready_c1_s;

endmodule
