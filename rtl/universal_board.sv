//============================================================================
//
//  Universal 8-bit arcade hardware — board top
//  Copyright (C) 2026 Rodimus
//
//  Variant 0: Lady Bug board (MAME ladybug.cpp: ladybug, snapjack, cavenger, dorodon)
//
//  ioctl index 0 (MRA), images stored as dumped, MAME region order:
//    0x00000 - 0x05FFF  maincpu
//    0x08000 - 0x09FFF  gfx1   (chars: 0x8000 plane 0 = low byte, 0x9000 plane 1 = high byte)
//    0x0A000 - 0x0BFFF  gfx2   (sprites: 0xA000 low byte, 0xB000 high byte)
//    0x0C000 - 0x0C05F  proms  (0x00 palette K1, 0x20 sprite lookup F4, 0x40 timing C4)
//    0x0C100 - 0x0C1FF  user1 high nibbles (Dorodon bp4, ROM_LOAD_NIB_HIGH)
//    0x0C200 - 0x0C2FF  user1 low nibbles  (Dorodon bp3, ROM_LOAD_NIB_LOW)
//
//============================================================================

module universal_board
(
    input  logic        clk,            // 19.656 MHz
    input  logic        reset,
    input  logic        pause,
    input  logic  [7:0] variant,
    input  logic  [3:0] rom_dec,        // 1: Dorodon opcode PROMs
    input  logic  [7:0] game_flags2,    // [0] P2 controls follow P1 in upright (MAME ladybug_p2_control_r)
    output logic        ce_pix,

    input  logic  [7:0] in0,
    input  logic  [7:0] in1,
    input  logic  [7:0] in2,
    input  logic  [7:0] dsw0,
    input  logic  [7:0] dsw1,
    input  logic  [7:0] coin,           // [0] coin 1, [1] coin 2 (active high)

    input  logic [24:0] ioctl_addr,
    input  logic  [7:0] ioctl_dout,
    input  logic        ioctl_wr0,

    input  logic        crt_flip,
    input  logic  [3:0] h_adj,
    input  logic  [3:0] v_adj,

    output logic  [7:0] video_r,
    output logic  [7:0] video_g,
    output logic  [7:0] video_b,
    output logic        video_hs,
    output logic        video_vs,
    output logic        video_hblank,
    output logic        video_vblank,

    output logic signed [15:0] audio,

    input  logic [15:0] hs_address,
    input  logic  [7:0] hs_data_in,
    output logic  [7:0] hs_data_out,
    input  logic        hs_write
);

/////////////////////////////  ROM storage  /////////////////////////////

wire load_cpu  = ioctl_wr0 && ioctl_addr < 25'h08000;
wire load_chl  = ioctl_wr0 && ioctl_addr[24:12] == 13'h0008;
wire load_chh  = ioctl_wr0 && ioctl_addr[24:12] == 13'h0009;
wire load_spl  = ioctl_wr0 && ioctl_addr[24:12] == 13'h000A;
wire load_sph  = ioctl_wr0 && ioctl_addr[24:12] == 13'h000B;
wire load_prom = ioctl_wr0 && ioctl_addr[24:7]  == 18'h00180;   // 0xC000-0xC07F
wire load_dech = ioctl_wr0 && ioctl_addr[24:8]  == 17'h000C1;
wire load_decl = ioctl_wr0 && ioctl_addr[24:8]  == 17'h000C2;

logic [14:0] rom_cpu_a;
logic  [7:0] rom_cpu_d;
logic  [7:0] dec_a;
logic  [7:0] dec_h, dec_l;
logic [11:0] rom_char_a, rom_sprite_a;
logic [15:0] rom_char_d, rom_sprite_d;

dpram_dc #(.widthad_a(15)) rom_cpu
(
    .clock_a(clk), .address_a(ioctl_addr[14:0]), .data_a(ioctl_dout), .wren_a(load_cpu),
    .clock_b(clk), .address_b(rom_cpu_a), .q_b(rom_cpu_d)
);

dpram_dc #(.widthad_a(12)) rom_char_l
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(load_chl),
    .clock_b(clk), .address_b(rom_char_a), .q_b(rom_char_d[7:0])
);

dpram_dc #(.widthad_a(12)) rom_char_h
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(load_chh),
    .clock_b(clk), .address_b(rom_char_a), .q_b(rom_char_d[15:8])
);

dpram_dc #(.widthad_a(12)) rom_sprite_l
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(load_spl),
    .clock_b(clk), .address_b(rom_sprite_a), .q_b(rom_sprite_d[7:0])
);

dpram_dc #(.widthad_a(12)) rom_sprite_h
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(load_sph),
    .clock_b(clk), .address_b(rom_sprite_a), .q_b(rom_sprite_d[15:8])
);

// Dorodon opcode PROMs, nibble-wide: decoded byte = {bp4[x], bp3[x]}
dpram_dc #(.widthad_a(8)) rom_dec_h
(
    .clock_a(clk), .address_a(ioctl_addr[7:0]), .data_a(ioctl_dout), .wren_a(load_dech),
    .clock_b(clk), .address_b(dec_a), .q_b(dec_h)
);

dpram_dc #(.widthad_a(8)) rom_dec_l
(
    .clock_a(clk), .address_a(ioctl_addr[7:0]), .data_a(ioctl_dout), .wren_a(load_decl),
    .clock_b(clk), .address_b(dec_a), .q_b(dec_l)
);

// Colour PROMs live in the video unit
wire prom_k1_wr = load_prom && ioctl_addr[6:5] == 2'd0;
wire prom_f4_wr = load_prom && ioctl_addr[6:5] == 2'd1;
wire prom_c4_wr = load_prom && ioctl_addr[6:5] == 2'd2;

/////////////////////////////  Lady Bug  /////////////////////////////

logic [1:0] lb_r, lb_g, lb_b;
logic       lb_hs_n, lb_vs_n, lb_hbl, lb_vbl;

ladybug_machine ladybug
(
    .clk_20mhz_i     (clk),
    .ext_res_n_i     (~reset),
    .pause_i         (pause),
    .decrypt_en_i    (rom_dec == 4'd1),
    .p2_follows_p1_i (game_flags2[0]),

    .in0_i           (in0),
    .in1_i           (in1),
    .in2_i           (in2),
    .dsw0_i          (dsw0),
    .dsw1_i          (dsw1),
    .coin1_i         (coin[0]),
    .coin2_i         (coin[1]),

    .clk_en_5mhz_o   (ce_pix),
    .rgb_r_o         (lb_r),
    .rgb_g_o         (lb_g),
    .rgb_b_o         (lb_b),
    .hsync_n_o       (lb_hs_n),
    .vsync_n_o       (lb_vs_n),
    .hblank_o        (lb_hbl),
    .vblank_o        (lb_vbl),
    .audio_o         (audio),

    .rom_cpu_a_o     (rom_cpu_a),
    .rom_cpu_d_i     (rom_cpu_d),
    .dec_a_o         (dec_a),
    .dec_d_i         ({dec_h[3:0], dec_l[3:0]}),
    .rom_char_a_o    (rom_char_a),
    .rom_char_d_i    (rom_char_d),
    .rom_sprite_a_o  (rom_sprite_a),
    .rom_sprite_d_i  (rom_sprite_d),

    .prom_a_i        (ioctl_addr[4:0]),
    .prom_d_i        (ioctl_dout),
    .prom_k1_wr_i    (prom_k1_wr),
    .prom_f4_wr_i    (prom_f4_wr),
    .prom_c4_wr_i    (prom_c4_wr),

    .hs_address      (hs_address),
    .hs_data_out     (hs_data_out),
    .hs_data_in      (hs_data_in),
    .hs_write        (hs_write)
);

// 2-bit DAC per gun, MAME ladybug_palette weights (470 / 220 ohm, 470 ohm pull-down)
function automatic [7:0] dac2(input [1:0] v);
    case (v)
        2'd0: dac2 = 8'd0;
        2'd1: dac2 = 8'd81;
        2'd2: dac2 = 8'd174;
        2'd3: dac2 = 8'd255;
    endcase
endfunction

always_ff @(posedge clk) begin
    if (ce_pix) begin
        video_r      <= dac2(lb_r);
        video_g      <= dac2(lb_g);
        video_b      <= dac2(lb_b);
        video_hs     <= ~lb_hs_n;
        video_vs     <= ~lb_vs_n;
        video_hblank <= lb_hbl;
        video_vblank <= lb_vbl;
    end
end

endmodule
