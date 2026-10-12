//============================================================================
//
//  Universal 8-bit arcade hardware — board top
//  Copyright (C) 2026 Rodimus
//
//  Variant 0: Lady Bug board (MAME ladybug.cpp: ladybug, snapjack, cavenger, dorodon)
//  Variant 1: Space Raider (8203 board + star board, MAME sraider.cpp sraider)
//  Variant 2: Mrs. Dynamite (8203 board, MAME sraider.cpp mrsdyna)
//  Variant 3: Mr. Do! 8201 board, U001 PAL with feedback (mrdo, mrdoy, yankeedo)
//  Variant 4: Mr. Do! with the Taito PAL (mrdot, mrdofix, mrdu, mrdofabr)
//  Variant 5: Mr. Lo! (no PAL)
//  Variant 6: Mr. Do! bootleg (mrdobl: 4.0 MHz CPU, PAL with feedback)
//  Variant 7: Mr. Do's Castle board, docastle_state map (docastle, Do! Run Run on Castle hardware, runrun)
//  Variant 8: Mr. Do's Castle board, dorunrun_state map (dorunrun, spiero, dowild, jjack, kickridr)
//  Variant 9: Mr. Do's Castle board, Indoor Soccer (idsoccer_state: MSM5205 ADPCM, twin joysticks)
//
//  ioctl index 0 (MRA), images stored as dumped, MAME region order:
//    0x00000 - 0x05FFF  maincpu
//    0x08000 - 0x09FFF  gfx1   (chars: 0x8000 plane 0 = low byte, 0x9000 plane 1 = high byte)
//    0x0A000 - 0x0BFFF  gfx2   (sprites: 0xA000 low byte, 0xB000 high byte)
//    0x0C000 - 0x0C05F  proms  (0x00 palette K1, 0x20 sprite lookup F4, 0x40 timing C4)
//    0x0C100 - 0x0C1FF  user1 high nibbles (Dorodon bp4, ROM_LOAD_NIB_HIGH)
//    0x0C200 - 0x0C2FF  user1 low nibbles  (Dorodon bp3, ROM_LOAD_NIB_LOW)
//    0x10000 - 0x15FFF  sub    (8203 sound / control CPU)
//    0x18000 - 0x18FFF  gfx3   (Space Raider fixed grid)
//    0x18000 - 0x19FFF  gfx3   (Mr. Do! sprites; gfx1 / gfx2 = fg / bg tiles, proms 0xC000-0xC07F)
//  Mr. Do's Castle board:
//    0x20000 - 0x29FFF  maincpu    0x30000 - 0x33FFF  subcpu     0x34000 - 0x37FFF  gfx1 (tiles)
//    0x3C000 - 0x3C0FF  proms      0x40000 - 0x47FFF  gfx2 (sprites)
//  Indoor Soccer: gfx2 0x40000 - 0x5FFFF (in the CRT Flip frame buffer RAM), adpcm 0x0000-0x7FFF -> 0x00000,
//    0x8000-0xFFFF -> 0x10000 (in the Lady Bug / Mr. Do! CPU ROMs, unused on this board)
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
wire load_sub  = ioctl_wr0 && ioctl_addr[24:15] == 10'h002;      // 0x10000-0x17FFF
wire load_grid = ioctl_wr0 && ioctl_addr[24:12] == 13'h0018;

wire board_8203  = (variant == 8'd1) || (variant == 8'd2);
wire sraider_ovl = (variant == 8'd1);
wire mrdo        = (variant >= 8'd3) && (variant <= 8'd6);
wire dcastle     = (variant == 8'd7) || (variant == 8'd8) || (variant == 8'd9);
wire idsoc       = (variant == 8'd9);
logic [15:0] dc_adpcm_a;
logic [16:0] dc_spr8_a;
logic  [7:0] dc_spr8_d;

logic [14:0] rom_cpu_a, lb_cpu_a, md_cpu_a;
logic [11:0] lb_char_a, lb_sprite_a, md_fg_a, md_bg_a;
logic  [7:0] rom_cpu_d;
logic  [7:0] dec_a;
logic  [7:0] dec_h, dec_l;
logic [11:0] rom_char_a, rom_sprite_a;

assign rom_cpu_a    = idsoc ? dc_adpcm_a[14:0] : mrdo ? md_cpu_a : lb_cpu_a;
assign rom_char_a   = mrdo ? md_fg_a  : lb_char_a;
assign rom_sprite_a = mrdo ? md_bg_a  : lb_sprite_a;
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

logic [14:0] rom_sub_a, lb_sub_a;
assign rom_sub_a = idsoc ? dc_adpcm_a[14:0] : lb_sub_a;
logic  [7:0] rom_sub_d;
logic [11:0] grid_rom_a;
logic  [7:0] grid_rom_d, grid_ram_a, grid_ram_d;
logic        grid_wr;
logic  [7:0] grid_a, grid_d;

dpram_dc #(.widthad_a(15)) rom_sub
(
    .clock_a(clk), .address_a(ioctl_addr[14:0]), .data_a(ioctl_dout), .wren_a(load_sub),
    .clock_b(clk), .address_b(rom_sub_a), .q_b(rom_sub_d)
);

dpram_dc #(.widthad_a(12)) rom_grid
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(load_grid),
    .clock_b(clk), .address_b(grid_rom_a), .q_b(grid_rom_d)
);

// Space Raider grid RAM (HD6148P @ D6): written by the sub CPU, read by the overlay
dpram_dc #(.widthad_a(8)) ram_grid
(
    .clock_a(clk), .address_a(grid_a), .data_a(grid_d), .wren_a(grid_wr),
    .clock_b(clk), .address_b(grid_ram_a), .q_b(grid_ram_d)
);

// Mr. Do! sprite ROM as 4 byte lanes (one 16-pixel row per read)
logic [10:0] md_spr_a;
logic [31:0] md_spr_d;
wire         load_mdspr = ioctl_wr0 && ioctl_addr[24:13] == 12'h00C;   // 0x18000-0x19FFF
genvar ln;
generate
    for (ln = 0; ln < 4; ln++) begin : mdspr
        dpram_dc #(.widthad_a(11)) rom
        (
            .clock_a(clk), .address_a(ioctl_addr[12:2]), .data_a(ioctl_dout), .wren_a(load_mdspr && ioctl_addr[1:0] == ln),
            .clock_b(clk), .address_b(md_spr_a), .q_b(md_spr_d[ln*8 +: 8])
        );
    end
endgenerate

// Mr. Do's Castle ROMs
logic [15:0] dc_main_a;
logic  [7:0] dc_main_lo_d, dc_main_hi_d;
logic [13:0] dc_sub_a;
logic  [7:0] dc_sub_d;
logic [11:0] dc_tile_a, dc_spr_a;
logic [31:0] dc_tile_d;
logic [63:0] dc_spr_d;
wire load_dc_mlo  = ioctl_wr0 && ioctl_addr[24:15] == 10'h004;   // 0x20000-0x27FFF
wire load_dc_mhi  = ioctl_wr0 && ioctl_addr[24:13] == 12'h014;   // 0x28000-0x29FFF
wire load_dc_sub  = ioctl_wr0 && ioctl_addr[24:14] == 11'h00C;   // 0x30000-0x33FFF
wire load_dc_tile = ioctl_wr0 && ioctl_addr[24:14] == 11'h00D;   // 0x34000-0x37FFF
wire load_dc_prom = ioctl_wr0 && ioctl_addr[24:8]  == 17'h003C0; // 0x3C000-0x3C0FF
wire load_dc_spr  = ioctl_wr0 && ioctl_addr[24:15] == 10'h008;   // 0x40000-0x47FFF

dpram_dc #(.widthad_a(15)) dc_main_lo
(
    .clock_a(clk), .address_a(ioctl_addr[14:0]), .data_a(ioctl_dout), .wren_a(load_dc_mlo),
    .clock_b(clk), .address_b(dc_main_a[14:0]), .q_b(dc_main_lo_d)
);
dpram_dc #(.widthad_a(13)) dc_main_hi
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(load_dc_mhi),
    .clock_b(clk), .address_b(dc_main_a[12:0]), .q_b(dc_main_hi_d)
);
dpram_dc #(.widthad_a(14)) dc_sub
(
    .clock_a(clk), .address_a(ioctl_addr[13:0]), .data_a(ioctl_dout), .wren_a(load_dc_sub),
    .clock_b(clk), .address_b(dc_sub_a), .q_b(dc_sub_d)
);
generate
    for (ln = 0; ln < 4; ln++) begin : dctile
        dpram_dc #(.widthad_a(12)) rom
        (
            .clock_a(clk), .address_a(ioctl_addr[13:2]), .data_a(ioctl_dout), .wren_a(load_dc_tile && ioctl_addr[1:0] == ln),
            .clock_b(clk), .address_b(dc_tile_a), .q_b(dc_tile_d[ln*8 +: 8])
        );
    end
    for (ln = 0; ln < 8; ln++) begin : dcspr
        dpram_dc #(.widthad_a(12)) rom
        (
            .clock_a(clk), .address_a(ioctl_addr[14:3]), .data_a(ioctl_dout), .wren_a(load_dc_spr && ioctl_addr[2:0] == ln),
            .clock_b(clk), .address_b(dc_spr_a), .q_b(dc_spr_d[ln*8 +: 8])
        );
    end
endgenerate

// Colour PROMs live in the video unit
wire prom_k1_wr = load_prom && ioctl_addr[6:5] == 2'd0;
wire prom_f4_wr = load_prom && ioctl_addr[6:5] == 2'd1;
wire prom_c4_wr = load_prom && ioctl_addr[6:5] == 2'd2;

/////////////////////////////  Lady Bug  /////////////////////////////

logic [1:0] lb_r, lb_g, lb_b;
logic       lb_hs_n, lb_vs_n, lb_hbl, lb_vbl, lb_bg;
logic [7:0] sub_ctrl;
logic       lb_ce;
logic signed [15:0] lb_audio;
logic [7:0] lb_hs_data;
logic [7:0] ov_code, fb_code;
logic       ov_hbl, ov_vbl, fb_hbl, fb_vbl;

ladybug_machine ladybug
(
    .clk_20mhz_i     (clk),
    .ext_res_n_i     (~reset & ~mrdo & ~dcastle),
    .pause_i         (pause),
    .decrypt_en_i    (rom_dec == 4'd1),
    .p2_follows_p1_i (game_flags2[0]),
    .board_8203_i    (board_8203),

    .in0_i           (in0),
    .in1_i           (in1),
    .in2_i           (in2),
    .dsw0_i          (dsw0),
    .dsw1_i          (dsw1),
    .coin1_i         (coin[0]),
    .coin2_i         (coin[1]),

    .clk_en_5mhz_o   (lb_ce),
    .rgb_r_o         (lb_r),
    .rgb_g_o         (lb_g),
    .rgb_b_o         (lb_b),
    .bg_o            (lb_bg),
    .ctrl_o          (sub_ctrl),
    .grid_wr_o       (grid_wr),
    .grid_a_o        (grid_a),
    .grid_d_o        (grid_d),
    .hsync_n_o       (lb_hs_n),
    .vsync_n_o       (lb_vs_n),
    .hblank_o        (lb_hbl),
    .vblank_o        (lb_vbl),
    .audio_o         (lb_audio),

    .rom_cpu_a_o     (lb_cpu_a),
    .rom_cpu_d_i     (rom_cpu_d),
    .dec_a_o         (dec_a),
    .dec_d_i         ({dec_h[3:0], dec_l[3:0]}),
    .rom_char_a_o    (lb_char_a),
    .rom_char_d_i    (rom_char_d),
    .rom_sprite_a_o  (lb_sprite_a),
    .rom_sprite_d_i  (rom_sprite_d),
    .rom_sub_a_o     (lb_sub_a),
    .rom_sub_d_i     (rom_sub_d),

    .prom_a_i        (ioctl_addr[4:0]),
    .prom_d_i        (ioctl_dout),
    .prom_k1_wr_i    (prom_k1_wr),
    .prom_f4_wr_i    (prom_f4_wr),
    .prom_c4_wr_i    (prom_c4_wr),

    .hs_address      (hs_address),
    .hs_data_out     (lb_hs_data),
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

// Space Raider stars + grid under the chars/sprites (pass-through for the other boards), then the CRT Flip
// frame buffer; 3 pixels of delay
sraider_overlay overlay
(
    .clk        (clk),
    .ce_pix     (lb_ce),
    .enable     (sraider_ovl),
    .ctrl       (sub_ctrl),
    .in_r       (lb_r),
    .in_g       (lb_g),
    .in_b       (lb_b),
    .in_bg      (lb_bg),
    .in_hbl     (lb_hbl),
    .in_vbl     (lb_vbl),
    .grid_rom_a (grid_rom_a),
    .grid_rom_d (grid_rom_d),
    .grid_ram_a (grid_ram_a),
    .grid_ram_d (grid_ram_d),
    .out_code   (ov_code),
    .out_hbl    (ov_hbl),
    .out_vbl    (ov_vbl)
);

crt_flip_fb flip_fb
(
    .clk     (clk),
    .ce_pix  (lb_ce),
    .en      (crt_flip),
    .din     (ov_code),
    .in_hbl  (ov_hbl),
    .in_vbl  (ov_vbl),
    .dout    (fb_code),
    .out_hbl (fb_hbl),
    .out_vbl (fb_vbl),
    .alt_en  (idsoc),
    .alt_wa  (ioctl_addr[16:0]),
    .alt_wd  (ioctl_dout),
    .alt_we  (ioctl_wr0 && ioctl_addr[24:17] == 8'h02),       // 0x40000-0x5FFFF
    .alt_ra  (dc_spr8_a),
    .alt_q   (dc_spr8_d)
);

// colour code -> RGB (see sraider_overlay.sv); star colours from MAME sraider_palette
function automatic [23:0] decode(input [7:0] c);
    case (c[7:6])
        2'b01:   decode = {{8{c[2]}}, {8{c[1]}}, {8{c[0]}}};
        2'b10:   decode = {c[0] ? 8'h97 : 8'h00,
                           (c[2] ? 8'h47 : 8'h00) + (c[1] ? 8'h97 : 8'h00),
                           (c[4] ? 8'h47 : 8'h00) + (c[3] ? 8'h97 : 8'h00)};
        default: decode = {dac2(c[5:4]), dac2(c[3:2]), dac2(c[1:0])};
    endcase
endfunction

wire [23:0] lb_rgb = decode(fb_code);

// Sync regenerated from the output blanking so H/V Position (CRT) works; setting 0 = the 8106-B timing as
// modelled by Arnim (measured in sim: HSYNC 14-29 px after hblank start, VSYNC from line 27 / px 310 to
// line 33 / px 310 after vblank start)
logic       hb_q = 1'b0, vb_q = 1'b0;
logic [8:0] hc_q = 9'd0;
logic [8:0] ln_q = 9'd0;
wire  [8:0] hc_cur = (fb_hbl && !hb_q) ? 9'd0 : hc_q + 9'd1;
wire  [8:0] ln_cur = (fb_vbl && !vb_q) ? 9'd0 : (fb_hbl && !hb_q) ? ln_q + 9'd1 : ln_q;
wire  [8:0] hs_beg = 9'd14 + {{5{h_adj[3]}}, h_adj};
wire  [8:0] vs_beg = 9'd27 + {{5{v_adj[3]}}, v_adj};
wire [17:0] vkey   = {ln_cur, hc_cur};
wire        lb_hs  = (hc_cur >= hs_beg) && (hc_cur < hs_beg + 9'd16);
wire  [8:0] vs_end = vs_beg + 9'd6;
wire        lb_vs  = (vkey >= {vs_beg, 9'd310}) && (vkey < {vs_end, 9'd310});
always_ff @(posedge clk) begin
    if (lb_ce) begin
        hb_q <= fb_hbl; vb_q <= fb_vbl;
        hc_q <= hc_cur; ln_q <= ln_cur;
    end
end

/////////////////////////////  Mr. Do!  /////////////////////////////

logic        md_ce, md_hs, md_vs, md_hbl, md_vbl;
logic  [7:0] md_r, md_g, md_b, md_hs_data;
logic signed [15:0] md_audio;

mrdo_board mrdo_b
(
    .clk          (clk),
    .reset        (reset | ~mrdo),
    .pause        (pause),
    .prot_mode    (variant == 8'd4 ? 2'd1 : variant == 8'd5 ? 2'd2 : 2'd0),
    .cpu_4m0      (variant == 8'd6),
    .crt_flip     (crt_flip),
    .p1           (in0),
    .p2           (in1),
    .dsw1         (dsw0),
    .dsw2         (dsw1),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (md_ce),
    .video_r      (md_r),
    .video_g      (md_g),
    .video_b      (md_b),
    .video_hs     (md_hs),
    .video_vs     (md_vs),
    .video_hblank (md_hbl),
    .video_vblank (md_vbl),
    .audio        (md_audio),
    .rom_cpu_a    (md_cpu_a),
    .rom_cpu_d    (rom_cpu_d),
    .rom_fg_a     (md_fg_a),
    .rom_fg_d     (rom_char_d),
    .rom_bg_a     (md_bg_a),
    .rom_bg_d     (rom_sprite_d),
    .rom_spr_a    (md_spr_a),
    .rom_spr_d    (md_spr_d),
    .prom_wr      (load_prom),
    .prom_a       (ioctl_addr[6:0]),
    .prom_d       (ioctl_dout),
    .hs_address   (hs_address[11:0]),
    .hs_data_out  (md_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & mrdo)
);

/////////////////////////////  Mr. Do's Castle  /////////////////////////////

logic        dc_ce, dc_hs, dc_vs, dc_hbl, dc_vbl;
logic  [7:0] dc_r, dc_g, dc_b, dc_hs_data;
logic signed [15:0] dc_audio;

docastle_board docastle_b
(
    .clk          (clk),
    .reset        (reset | ~dcastle),
    .pause        (pause),
    .map_mode     (variant == 8'd8),
    .idsoccer     (idsoc),
    .pri_low      (variant == 8'd8 || idsoc),
    .crt_flip     (crt_flip),
    .joys         (in0),
    .buttons      (in1),
    .system       (in2),
    .dsw1         (dsw0),
    .dsw2         (dsw1),
    .joys2        (coin),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (dc_ce),
    .video_r      (dc_r),
    .video_g      (dc_g),
    .video_b      (dc_b),
    .video_hs     (dc_hs),
    .video_vs     (dc_vs),
    .video_hblank (dc_hbl),
    .video_vblank (dc_vbl),
    .audio        (dc_audio),
    .rom_main_a   (dc_main_a),
    .rom_main_d   (dc_main_a[15] ? dc_main_hi_d : dc_main_lo_d),
    .rom_sub_a    (dc_sub_a),
    .rom_sub_d    (dc_sub_d),
    .rom_tile_a   (dc_tile_a),
    .rom_tile_d   (dc_tile_d),
    .rom_spr_a    (dc_spr_a),
    .rom_spr_d    (dc_spr_d),
    .rom_spr8_a   (dc_spr8_a),
    .rom_spr8_d   (dc_spr8_d),
    .rom_adpcm_a  (dc_adpcm_a),
    .rom_adpcm_d  (dc_adpcm_a[15] ? rom_sub_d : rom_cpu_d),
    .prom_wr      (load_dc_prom),
    .prom_a       (ioctl_addr[7:0]),
    .prom_d       (ioctl_dout),
    .hs_address   (hs_address[12:0]),
    .hs_data_out  (dc_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & dcastle)
);

/////////////////////////////  output select  /////////////////////////////

assign ce_pix       = dcastle ? dc_ce    : mrdo ? md_ce    : lb_ce;
assign video_r      = dcastle ? dc_r     : mrdo ? md_r     : lb_rgb[23:16];
assign video_g      = dcastle ? dc_g     : mrdo ? md_g     : lb_rgb[15:8];
assign video_b      = dcastle ? dc_b     : mrdo ? md_b     : lb_rgb[7:0];
assign video_hblank = dcastle ? dc_hbl   : mrdo ? md_hbl   : fb_hbl;
assign video_vblank = dcastle ? dc_vbl   : mrdo ? md_vbl   : fb_vbl;
assign video_hs     = dcastle ? dc_hs    : mrdo ? md_hs    : lb_hs;
assign video_vs     = dcastle ? dc_vs    : mrdo ? md_vs    : lb_vs;
assign audio        = dcastle ? dc_audio : mrdo ? md_audio : lb_audio;
assign hs_data_out  = dcastle ? dc_hs_data : mrdo ? md_hs_data : lb_hs_data;

endmodule
