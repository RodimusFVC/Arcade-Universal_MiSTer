//============================================================================
//
//  Lady Bug machine (Universal 8106-A2 CPU board + 8106-B video board)
//  Copyright (C) 2026 Rodimus
//
//  Structure from Arnim Laeuger's ladybug_machine.vhd (FPGA Lady Bug, 2005)
//  and its MiSTer port by Sorgelig. Input ports follow MAME ladybug.cpp:
//  IN0 9000, IN1 9001 (bits 7-5 from the video timing), DSW0 9002, DSW1 9003,
//  IN2 E000 (bits 1-0); coin 1 -> NMI chute, coin 2 -> IRQ chute.
//
//  board_8203_i: Universal 8203-A/B (Space Raider, Mrs. Dynamite, MAME sraider.cpp):
//  same video, main CPU I/O at 8000, a second Z80 with five SN76489, and the
//  palette PROM wired to the DACs differently (mrsdyna_palette).
//
//============================================================================

module ladybug_machine
(
    output logic        [13:0] z80m_o,         // shared T80s (rtl/z80_socket.sv): main
    input  logic        [29:0] z80m_i,
    output logic        [13:0] z80s_o,         // 8203 sub
    input  logic        [29:0] z80s_i,
    input  logic               clk_20mhz_i,     // 19.656 MHz
    input  logic               ext_res_n_i,
    input  logic               pause_i,
    input  logic               decrypt_en_i,
    input  logic               p2_follows_p1_i, // MAME ladybug_p2_control_r: upright cabinet reads P1 controls for P2
    input  logic               board_8203_i,

    input  logic         [7:0] in0_i,
    input  logic         [7:0] in1_i,
    input  logic         [7:0] in2_i,
    input  logic         [7:0] dsw0_i,
    input  logic         [7:0] dsw1_i,
    input  logic               coin1_i,
    input  logic               coin2_i,

    output logic               clk_en_5mhz_o,   // pixel clock enable
    output logic         [1:0] rgb_r_o,
    output logic         [1:0] rgb_g_o,
    output logic         [1:0] rgb_b_o,
    output logic               bg_o,            // background pixel (8203 overlay)
    output logic         [7:0] ctrl_o,          // 8203 sub CPU control latch
    output logic               grid_wr_o,
    output logic         [7:0] grid_a_o,
    output logic         [7:0] grid_d_o,
    output logic               hsync_n_o,
    output logic               vsync_n_o,
    output logic               hblank_o,
    output logic               vblank_o,
    output logic signed [15:0] audio_o,

    output logic        [14:0] rom_cpu_a_o,
    input  logic         [7:0] rom_cpu_d_i,
    output logic         [7:0] dec_a_o,
    input  logic         [7:0] dec_d_i,
    output logic        [11:0] rom_char_a_o,
    input  logic        [15:0] rom_char_d_i,
    output logic        [11:0] rom_sprite_a_o,
    input  logic        [15:0] rom_sprite_d_i,
    output logic        [14:0] rom_sub_a_o,
    input  logic         [7:0] rom_sub_d_i,

    input  logic         [4:0] prom_a_i,
    input  logic         [7:0] prom_d_i,
    input  logic               prom_k1_wr_i,
    input  logic               prom_f4_wr_i,
    input  logic               prom_c4_wr_i,

    input  logic        [15:0] hs_address,
    output logic         [7:0] hs_data_out,
    input  logic         [7:0] hs_data_in,
    input  logic               hs_write
);

logic        clk_en_10mhz_s, clk_en_10mhz_n_s, clk_en_5mhz_s, clk_en_5mhz_n_s;
logic        cpu_cen_p_s, cpu_cen_n_s;
logic        por_n_s, res_n_s;
logic        sound_wait_n_s, wait_n_s;
logic [10:0] a_s;
logic  [7:0] d_to_cpu_s, d_from_cpu_s, d_from_video_s;
logic        rd_n_s, wr_n_s;
logic        cs7_n_s, cs10_n_s, cs11_n_s, cs12_n_s, cs13_n_s;
logic        vc_s, vbl_tick_n_s, vbl_buf_s;
logic  [7:0] gpio_in0_s, gpio_in1_s, gpio_extra_s;
logic        hs_cs_cpu, hs_cs_vram;
logic  [7:0] snd_latch_lo_s, snd_latch_hi_s;
logic  [8:1] rgb_n_s;
logic  [1:0] lb_r_s, lb_g_s, lb_b_s;
logic signed [15:0] audio_lb_s, audio_sub_s;
logic  [7:0] hs_data_out_cpu, hs_data_out_vram;

ladybug_clk clk_b
(
    .clk_20mhz_i      (clk_20mhz_i),
    .por_n_i          (por_n_s),
    .clk_en_10mhz_o   (clk_en_10mhz_s),
    .clk_en_10mhz_n_o (clk_en_10mhz_n_s),
    .clk_en_5mhz_o    (clk_en_5mhz_s),
    .clk_en_5mhz_n_o  (clk_en_5mhz_n_s),
    .cpu_cen_p_o      (cpu_cen_p_s),
    .cpu_cen_n_o      (cpu_cen_n_s)
);

assign clk_en_5mhz_o = clk_en_5mhz_s;

ladybug_res res_b
(
    .clk_20mhz_i (clk_20mhz_i),
    .ext_res_n_i (ext_res_n_i),
    .res_n_o     (res_n_s),
    .por_n_o     (por_n_s)
);

assign gpio_in0_s   = in0_i;
assign gpio_in1_s   = board_8203_i ? in1_i :
                      {vbl_buf_s, vbl_tick_n_s, vc_s, p2_follows_p1_i && !dsw0_i[5] ? in0_i[4:0] : in1_i[4:0]};
// E000-E003 read bit pairs {extra[7-n], extra[3-n]}; only E000 carries inputs (MAME IN2 bits 1-0)
assign gpio_extra_s = {in2_i[1], 3'b111, in2_i[0], 3'b111};

assign hs_cs_cpu   = (hs_address[15:12] == 4'h6);
assign hs_cs_vram  = (hs_address[15:12] == 4'hD);
assign hs_data_out = hs_cs_cpu ? hs_data_out_cpu : hs_data_out_vram;

ladybug_cpu_unit cpu_b
(
    .z80_o          (z80m_o),
    .z80_i          (z80m_i),
    .clk_20mhz_i    (clk_20mhz_i),
    .cpu_cen_p_i    (cpu_cen_p_s),
    .cpu_cen_n_i    (cpu_cen_n_s),
    .res_n_i        (res_n_s),
    .pause_i        (pause_i),
    .decrypt_en_i   (decrypt_en_i),
    .board_8203_i   (board_8203_i),
    .vblank_i       (vbl_buf_s),
    .snd_latch_lo_o (snd_latch_lo_s),
    .snd_latch_hi_o (snd_latch_hi_s),
    .rom_cpu_a_o    (rom_cpu_a_o),
    .rom_cpu_d_i    (rom_cpu_d_i),
    .dec_a_o        (dec_a_o),
    .dec_d_i        (dec_d_i),
    .sound_wait_n_i (sound_wait_n_s),
    .wait_n_i       (wait_n_s),
    .right_chute_i  (coin1_i),
    .left_chute_i   (coin2_i),
    .gpio_in0_i     (gpio_in0_s),
    .gpio_in1_i     (gpio_in1_s),
    .gpio_in2_i     (dsw0_i),
    .gpio_in3_i     (dsw1_i),
    .gpio_extra_i   (gpio_extra_s),
    .a_o            (a_s),
    .d_to_cpu_i     (d_to_cpu_s),
    .d_from_cpu_o   (d_from_cpu_s),
    .rd_n_o         (rd_n_s),
    .wr_n_o         (wr_n_s),
    .cs7_n_o        (cs7_n_s),
    .cs10_n_o       (cs10_n_s),
    .cs11_n_o       (cs11_n_s),
    .cs12_n_o       (cs12_n_s),
    .cs13_n_o       (cs13_n_s),
    .hs_address     (hs_address),
    .hs_data_out    (hs_data_out_cpu),
    .hs_data_in     (hs_data_in),
    .hs_write       (hs_write & hs_cs_cpu)
);

assign d_to_cpu_s = (!(cs7_n_s & cs13_n_s)) ? d_from_video_s : 8'hFF;

ladybug_video_unit video_b
(
    .clk_20mhz_i      (clk_20mhz_i),
    .por_n_i          (por_n_s),
    .res_n_i          (res_n_s),
    .clk_en_10mhz_i   (clk_en_10mhz_s),
    .clk_en_10mhz_n_i (clk_en_10mhz_n_s),
    .clk_en_5mhz_i    (clk_en_5mhz_s),
    .clk_en_5mhz_n_i  (clk_en_5mhz_n_s),
    .clk_en_4mhz_i    (cpu_cen_p_s),
    .cs7_n_i          (cs7_n_s),
    .cs10_n_i         (cs10_n_s),
    .cs13_n_i         (cs13_n_s),
    .a_i              (a_s),
    .rd_n_i           (rd_n_s),
    .wr_n_i           (wr_n_s),
    .wait_n_o         (wait_n_s),
    .d_from_cpu_i     (d_from_cpu_s),
    .d_from_video_o   (d_from_video_s),
    .vc_o             (vc_s),
    .vbl_tick_n_o     (vbl_tick_n_s),
    .vbl_buf_o        (vbl_buf_s),
    .rgb_r_o          (lb_r_s),
    .rgb_g_o          (lb_g_s),
    .rgb_b_o          (lb_b_s),
    .rgb_n_o          (rgb_n_s),
    .bg_o             (bg_o),
    .flip_ext_en_i    (board_8203_i),
    .flip_ext_i       (ctrl_o[7]),
    .hsync_n_o        (hsync_n_o),
    .vsync_n_o        (vsync_n_o),
    .comp_sync_n_o    (),
    .vblank_o         (vblank_o),
    .hblank_o         (hblank_o),
    .rom_char_a_o     (rom_char_a_o),
    .rom_char_d_i     (rom_char_d_i),
    .rom_sprite_a_o   (rom_sprite_a_o),
    .rom_sprite_d_i   (rom_sprite_d_i),
    .prom_a_i         (prom_a_i),
    .prom_d_i         (prom_d_i),
    .prom_k1_wr_i     (prom_k1_wr_i),
    .prom_f4_wr_i     (prom_f4_wr_i),
    .prom_c4_wr_i     (prom_c4_wr_i),
    .pause            (pause_i),
    .hs_address       (hs_address),
    .hs_data_in       (hs_data_in),
    .hs_data_out      (hs_data_out_vram),
    .hs_write         (hs_write & hs_cs_vram)
);

ladybug_sound_unit sound_b
(
    .clk_20mhz_i    (clk_20mhz_i),
    .clk_en_4mhz_i  (cpu_cen_p_s & ~pause_i),
    .por_n_i        (por_n_s),
    .cs11_n_i       (cs11_n_s),
    .cs12_n_i       (cs12_n_s),
    .wr_n_i         (wr_n_s),
    .d_from_cpu_i   (d_from_cpu_s),
    .sound_wait_n_o (sound_wait_n_s),
    .audio_o        (audio_lb_s)
);

// 8203 palette PROM to DAC wiring (MAME mrsdyna_palette): {220 ohm, 470 ohm} = R {D0, D3}, G {D4, D5}, B {D6, D7}
assign rgb_r_o = board_8203_i ? {rgb_n_s[1], rgb_n_s[4]} : lb_r_s;
assign rgb_g_o = board_8203_i ? {rgb_n_s[5], rgb_n_s[6]} : lb_g_s;
assign rgb_b_o = board_8203_i ? {rgb_n_s[7], rgb_n_s[8]} : lb_b_s;

sraider_sub sub_b
(
    .z80_o    (z80s_o),
    .z80_i    (z80s_i),
    .clk      (clk_20mhz_i),
    .cen_p    (cpu_cen_p_s),
    .cen_n    (cpu_cen_n_s),
    .res_n    (res_n_s & board_8203_i),
    .pause    (pause_i),
    .vblank   (vbl_buf_s),
    .latch_lo (snd_latch_lo_s),
    .latch_hi (snd_latch_hi_s),
    .rom_a    (rom_sub_a_o),
    .rom_d    (rom_sub_d_i),
    .grid_wr  (grid_wr_o),
    .grid_a   (grid_a_o),
    .grid_d   (grid_d_o),
    .ctrl     (ctrl_o),
    .audio    (audio_sub_s)
);

assign audio_o = board_8203_i ? audio_sub_s : audio_lb_s;

endmodule
