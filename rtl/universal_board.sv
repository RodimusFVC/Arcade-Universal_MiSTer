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
//  Variant 10: Zero Hour (zerohour_state)
//  Variant 11: Red Clash (redclash_state)
//  Variant 12: Cheeky Mouse (cheekyms_state)
//  Variants 13-17: Cosmic boards: Space Panic, Cosmic Alien, Magical Spot, Devil Zone, No Man's Land
//  Variants 18-19: TMS99xx boards: Cosmic Guerilla (TMS9980A), Get A Way (TMS9900)
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
//  Indoor Soccer: gfx2 0x40000 - 0x5FFFF, adpcm 0x0000-0x7FFF -> 0x00000, 0x8000-0xFFFF -> 0x10000. Both are
//    read from the DDR3 copy of index 0 (ddr_rom.sv, top level) since 2026-10-23; the BRAM writes are unused.
//    (Before: gfx2 in the CRT Flip frame buffer RAM, adpcm in the Lady Bug / Mr. Do! CPU ROMs.)
//  Zero Hour / Red Clash: maincpu 0x00000, gfx1 0x08000, proms 0x0C000, gfx2 0x1C000 (Castle sprite ROM lanes at
//    offset 0x800; was 0x40000 until 2026-10-23 - the image must end below the Castle windows, see rom_audit.py)
//  Cheeky Mouse: maincpu 0x00000, chars 0x08000 / 0x09000 (cm02 / cm01), sprites 0x0A000 / 0x0B000 (cm07 / cm08),
//    proms 0x0C000
//  Cosmic boards: maincpu 0x00000, user1 colour map 0x08000, user2 0x09000, gfx1 0x0A000 / 0x0B000 (halves),
//    proms 0x0C000, user3 0x0C040; Devil Zone grid frame in the CRT Flip frame buffer RAM
//  Cosmic Guerilla: program 0x00000, colour map 0x08000
//  Get A Way: program high bytes 0x00000, low bytes 0x02000 (ROM_LOAD16_BYTE planes), gfx 0x08000 / 0x09000
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

    // DDR3 copy of index 0 (ddr_rom.sv): Indoor Soccer sprite rows and ADPCM, by index-0 byte address
    output logic        ddr_row_req,    // pulse; ddr_row_addr held until ddr_row_rdy
    output logic [24:0] ddr_row_addr,
    input  logic        ddr_row_rdy,
    input  logic [63:0] ddr_row_q,
    output logic        ddr_byte_en,
    output logic [24:0] ddr_byte_addr,
    input  logic  [7:0] ddr_byte_q,
    input  logic        ddr_byte_rdy,

    input  logic [15:0] hs_address,
    input  logic  [7:0] hs_data_in,
    output logic  [7:0] hs_data_out,
    input  logic        hs_write
);

/////////////////////////////  Shared ROM blocks  /////////////////////////////

wire load_cpu  = ioctl_wr0 && ioctl_addr < 25'h08000;
wire load_chl  = ioctl_wr0 && ioctl_addr[24:12] == 13'h0008;
wire load_chh  = ioctl_wr0 && ioctl_addr[24:12] == 13'h0009;
wire load_spl  = ioctl_wr0 && ioctl_addr[24:12] == 13'h000A;
wire load_sph  = ioctl_wr0 && ioctl_addr[24:12] == 13'h000B;
wire load_prom = ioctl_wr0 && ioctl_addr[24:7]  == 18'h00180;   // 0xC000-0xC07F
wire load_dech = ioctl_wr0 && ioctl_addr[24:8]  == 17'h000C1;
wire load_decl = ioctl_wr0 && ioctl_addr[24:8]  == 17'h000C2;
wire load_sub  = ioctl_wr0 && ioctl_addr[24:15] == 10'h002;      // 0x10000-0x17FFF

wire board_8203  = (variant == 8'd1) || (variant == 8'd2);
wire sraider_ovl = (variant == 8'd1);
wire mrdo        = (variant >= 8'd3) && (variant <= 8'd6);
wire dcastle     = (variant == 8'd7) || (variant == 8'd8) || (variant == 8'd9);
wire idsoc       = (variant == 8'd9);
wire zhour       = (variant == 8'd10) || (variant == 8'd11);
wire cheeky      = (variant == 8'd12);
wire cosmic      = (variant >= 8'd13) && (variant <= 8'd17);
wire cs_grid     = (variant == 8'd16);
wire tms         = (variant == 8'd18) || (variant == 8'd19);
logic [15:0] dc_adpcm_a;
logic [16:0] dc_spr8_a;
logic  [7:0] dc_spr8_d;          // crt_flip_fb alt read data (Devil Zone grid since 2026-10-23)
logic        dc_spr8_req;

// DDR3-2026-10-23: Indoor Soccer gfx2 at index-0 0x40000, ADPCM at 0x60000 (gen_mra; no BRAM behind it)
assign ddr_row_req   = dc_spr8_req;
assign ddr_row_addr  = 25'h40000 + {8'd0, dc_spr8_a};
assign ddr_byte_en   = idsoc;
// ROMSHARE-2026-10-23: original (ADPCM split over 0x00000 / 0x10000)
// assign ddr_byte_addr = {8'd0, dc_adpcm_a[15], 1'b0, dc_adpcm_a[14:0]};
assign ddr_byte_addr = 25'h60000 + {9'd0, dc_adpcm_a};

// Mr. Do's Castle ROM ports + load decodes (ROMSHARE-2026-10-23: moved up from the Castle ROM block, which now
// shares the Lady Bug-group RAMs: no set loads both windows of a pair, tools/rom_audit.py)
logic [15:0] dc_main_a;
logic  [7:0] dc_main_lo_d, dc_main_hi_d;
logic [13:0] dc_sub_a;
logic  [7:0] dc_sub_d;
logic [11:0] dc_tile_a, dc_spr_a;
logic [31:0] dc_tile_d;
logic [63:0] dc_spr_d;
wire win_dc_mhi   = ioctl_addr[24:13] == 12'h014;                // 0x28000-0x29FFF
wire win_dc_sub   = ioctl_addr[24:14] == 11'h00C;                // 0x30000-0x33FFF
wire win_dc_tile  = ioctl_addr[24:14] == 11'h00D;                // 0x34000-0x37FFF
wire load_dc_mlo  = ioctl_wr0 && ioctl_addr[24:15] == 10'h004;   // 0x20000-0x27FFF
wire load_dc_mhi  = ioctl_wr0 && win_dc_mhi;
wire load_dc_sub  = ioctl_wr0 && win_dc_sub;
wire load_dc_tile = ioctl_wr0 && win_dc_tile;
wire load_dc_prom = ioctl_wr0 && ioctl_addr[24:8]  == 17'h003C0; // 0x3C000-0x3C0FF
wire load_dc_spr  = ioctl_wr0 && ioctl_addr[24:15] == 10'h008;   // 0x40000-0x47FFF

logic [14:0] rom_cpu_a, lb_cpu_a, md_cpu_a, zh_cpu_a, cm_cpu_a, cs_cpu_a, tm_cpu_a;
logic [11:0] tm_chr_a;
logic [11:0] lb_char_a, lb_sprite_a, md_fg_a, md_bg_a, zh_chr_a, zh_spr_a, cm_chr_a, cm_spr_a;
logic [11:0] cs_cmap_a, cs_u2_a, cs_u2b_a, cs_spr_a;
logic  [7:0] cs_u2_d, cs_u2b_d;
logic  [7:0] rom_cpu_d;
logic  [7:0] dec_a;
logic  [7:0] dec_h, dec_l;
logic [11:0] rom_char_a, rom_sprite_a;

// ROMSHARE-2026-10-23: original (Indoor Soccer ADPCM read through rom_cpu)
// assign rom_cpu_a    = idsoc ? dc_adpcm_a[14:0] : mrdo ? md_cpu_a : zhour ? zh_cpu_a : cheeky ? cm_cpu_a :
//                       cosmic ? cs_cpu_a : tms ? tm_cpu_a : lb_cpu_a;
assign rom_cpu_a    = mrdo ? md_cpu_a : zhour ? zh_cpu_a : cheeky ? cm_cpu_a :
                      cosmic ? cs_cpu_a : tms ? tm_cpu_a : lb_cpu_a;
assign rom_char_a   = mrdo ? md_fg_a  : zhour ? zh_chr_a : cheeky ? cm_chr_a : cosmic ? cs_cmap_a : tms ? tm_chr_a : lb_char_a;
assign rom_sprite_a = mrdo ? md_bg_a  : cheeky ? cm_spr_a : cosmic ? cs_spr_a : lb_sprite_a;
logic [15:0] rom_char_d, rom_sprite_d;

// ROMSHARE-2026-10-23: original Lady Bug-group CPU / char / sprite RAMs below; each now also holds a Castle ROM
// dpram_dc #(.widthad_a(15)) rom_cpu
// (
//     .clock_a(clk), .address_a(ioctl_addr[14:0]), .data_a(ioctl_dout), .wren_a(load_cpu),
//     .clock_b(clk), .address_b(rom_cpu_a), .q_b(rom_cpu_d)
// );
//
// dpram_dc #(.widthad_a(12)) rom_char_l
// (
//     .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(load_chl),
//     .clock_b(clk), .address_b(rom_char_a), .q_b(rom_char_d[7:0])
// );
//
// // Cosmic boards: user2 with two read ports (port A is free once the download is over)
// dpram_dc #(.widthad_a(12)) rom_char_h
// (
//     .clock_a(clk), .address_a(reset ? ioctl_addr[11:0] : cs_u2b_a), .data_a(ioctl_dout), .wren_a(load_chh), .q_a(cs_u2b_d),
//     .clock_b(clk), .address_b(cosmic ? cs_u2_a : rom_char_a), .q_b(rom_char_d[15:8])
// );
// assign cs_u2_d = rom_char_d[15:8];
//
// dpram_dc #(.widthad_a(12)) rom_sprite_l
// (
//     .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(load_spl),
//     .clock_b(clk), .address_b(rom_sprite_a), .q_b(rom_sprite_d[7:0])
// );
//
// dpram_dc #(.widthad_a(12)) rom_sprite_h
// (
//     .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(load_sph),
//     .clock_b(clk), .address_b(rom_sprite_a), .q_b(rom_sprite_d[15:8])
// );

// ROMSHARE-2026-10-23: rom_cpu = Lady Bug-group CPU ROM (0x00000) or Castle main 0000-7FFF (0x20000)
dpram_dc #(.widthad_a(15)) rom_cpu
(
    .clock_a(clk), .address_a(ioctl_addr[14:0]), .data_a(ioctl_dout), .wren_a(load_cpu || load_dc_mlo),
    .clock_b(clk), .address_b(dcastle ? dc_main_a[14:0] : rom_cpu_a), .q_b(rom_cpu_d)
);
assign dc_main_lo_d = rom_cpu_d;

// ROMSHARE-2026-10-23: char / sprite ROMs = Castle tile ROM lanes 0-3 (0x34000-0x37FFF, byte k of each 4)
wire [11:0] chsp_wa = win_dc_tile ? ioctl_addr[13:2] : ioctl_addr[11:0];

dpram_dc #(.widthad_a(12)) rom_char_l
(
    .clock_a(clk), .address_a(chsp_wa), .data_a(ioctl_dout), .wren_a(load_chl || (load_dc_tile && ioctl_addr[1:0] == 2'd0)),
    .clock_b(clk), .address_b(dcastle ? dc_tile_a : rom_char_a), .q_b(rom_char_d[7:0])
);

// Cosmic boards: user2 with two read ports (port A is free once the download is over)
dpram_dc #(.widthad_a(12)) rom_char_h
(
    .clock_a(clk), .address_a(reset ? chsp_wa : cs_u2b_a), .data_a(ioctl_dout),
    .wren_a(load_chh || (load_dc_tile && ioctl_addr[1:0] == 2'd1)), .q_a(cs_u2b_d),
    .clock_b(clk), .address_b(cosmic ? cs_u2_a : dcastle ? dc_tile_a : rom_char_a), .q_b(rom_char_d[15:8])
);
assign cs_u2_d = rom_char_d[15:8];

dpram_dc #(.widthad_a(12)) rom_sprite_l
(
    .clock_a(clk), .address_a(chsp_wa), .data_a(ioctl_dout), .wren_a(load_spl || (load_dc_tile && ioctl_addr[1:0] == 2'd2)),
    .clock_b(clk), .address_b(dcastle ? dc_tile_a : rom_sprite_a), .q_b(rom_sprite_d[7:0])
);

dpram_dc #(.widthad_a(12)) rom_sprite_h
(
    .clock_a(clk), .address_a(chsp_wa), .data_a(ioctl_dout), .wren_a(load_sph || (load_dc_tile && ioctl_addr[1:0] == 2'd3)),
    .clock_b(clk), .address_b(dcastle ? dc_tile_a : rom_sprite_a), .q_b(rom_sprite_d[15:8])
);
assign dc_tile_d = {rom_sprite_d[15:8], rom_sprite_d[7:0], rom_char_d[15:8], rom_char_d[7:0]};

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
// ROMSHARE-2026-10-23: original (Indoor Soccer ADPCM read through rom_sub)
// assign rom_sub_a = idsoc ? dc_adpcm_a[14:0] : lb_sub_a;
assign rom_sub_a = lb_sub_a;
logic  [7:0] rom_sub_d;
logic [11:0] grid_rom_a;
logic  [7:0] grid_rom_d, grid_ram_a, grid_ram_d;
logic        grid_wr;
logic  [7:0] grid_a, grid_d;

// ROMSHARE-2026-10-23: original below
// dpram_dc #(.widthad_a(15)) rom_sub
// (
//     .clock_a(clk), .address_a(ioctl_addr[14:0]), .data_a(ioctl_dout), .wren_a(load_sub),
//     .clock_b(clk), .address_b(rom_sub_a), .q_b(rom_sub_d)
// );

// ROMSHARE-2026-10-23: rom_sub = 8203 sub CPU ROM (0x10000), or Castle sub ROM at 0000-3FFF (0x30000) + Castle
// main 8000-9FFF at 4000-5FFF (0x28000). The two Castle CPUs fetch at once: port A (free after the download)
// reads the main CPU's upper ROM.
wire [14:0] sub_wa = win_dc_sub ? {1'b0, ioctl_addr[13:0]} : win_dc_mhi ? {2'b10, ioctl_addr[12:0]} : ioctl_addr[14:0];

dpram_dc #(.widthad_a(15)) rom_sub
(
    .clock_a(clk), .address_a(reset ? sub_wa : {2'b10, dc_main_a[12:0]}), .data_a(ioctl_dout),
    .wren_a(load_sub || load_dc_sub || load_dc_mhi), .q_a(dc_main_hi_d),
    .clock_b(clk), .address_b(dcastle ? {1'b0, dc_sub_a} : rom_sub_a), .q_b(rom_sub_d)
);
assign dc_sub_d = rom_sub_d;

// Space Raider grid RAM (HD6148P @ D6): written by the sub CPU, read by the overlay
dpram_dc #(.widthad_a(8)) ram_grid
(
    .clock_a(clk), .address_a(grid_a), .data_a(grid_d), .wren_a(grid_wr),
    .clock_b(clk), .address_b(grid_ram_a), .q_b(grid_ram_d)
);

// 0x18000-0x19FFF as 4 byte lanes: Mr. Do! sprite ROM (one 16-pixel row per read); Space Raider grid ROM
// (0x18000-0x18FFF, byte-wide: lane picked by the registered address)
logic [10:0] md_spr_a;
logic [31:0] md_spr_d;
logic  [1:0] grid_lane = 2'd0;
always_ff @(posedge clk) grid_lane <= grid_rom_a[1:0];
assign grid_rom_d = md_spr_d[grid_lane*8 +: 8];
wire         load_mdspr = ioctl_wr0 && ioctl_addr[24:13] == 12'h00C;   // 0x18000-0x19FFF
// ROMSHARE-2026-10-23: original mdspr lanes and Castle ROM RAMs below (Castle ROMs now share the Lady Bug-group
// RAMs above; Mr. Do! sprite / Space Raider grid ROM = low half of dcspr lanes 0-3)
// genvar ln;
// generate
//     for (ln = 0; ln < 4; ln++) begin : mdspr
//         dpram_dc #(.widthad_a(11)) rom
//         (
//             .clock_a(clk), .address_a(ioctl_addr[12:2]), .data_a(ioctl_dout), .wren_a(load_mdspr && ioctl_addr[1:0] == ln),
//             .clock_b(clk), .address_b(board_8203 ? {1'b0, grid_rom_a[11:2]} : md_spr_a), .q_b(md_spr_d[ln*8 +: 8])
//         );
//     end
// endgenerate
//
// // Mr. Do's Castle ROMs
// logic [15:0] dc_main_a;
// logic  [7:0] dc_main_lo_d, dc_main_hi_d;
// logic [13:0] dc_sub_a;
// logic  [7:0] dc_sub_d;
// logic [11:0] dc_tile_a, dc_spr_a;
// logic [31:0] dc_tile_d;
// logic [63:0] dc_spr_d;
// wire load_dc_mlo  = ioctl_wr0 && ioctl_addr[24:15] == 10'h004;   // 0x20000-0x27FFF
// wire load_dc_mhi  = ioctl_wr0 && ioctl_addr[24:13] == 12'h014;   // 0x28000-0x29FFF
// wire load_dc_sub  = ioctl_wr0 && ioctl_addr[24:14] == 11'h00C;   // 0x30000-0x33FFF
// wire load_dc_tile = ioctl_wr0 && ioctl_addr[24:14] == 11'h00D;   // 0x34000-0x37FFF
// wire load_dc_prom = ioctl_wr0 && ioctl_addr[24:8]  == 17'h003C0; // 0x3C000-0x3C0FF
// wire load_dc_spr  = ioctl_wr0 && ioctl_addr[24:15] == 10'h008;   // 0x40000-0x47FFF
//
// dpram_dc #(.widthad_a(15)) dc_main_lo
// (
//     .clock_a(clk), .address_a(ioctl_addr[14:0]), .data_a(ioctl_dout), .wren_a(load_dc_mlo),
//     .clock_b(clk), .address_b(dc_main_a[14:0]), .q_b(dc_main_lo_d)
// );
// dpram_dc #(.widthad_a(13)) dc_main_hi
// (
//     .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(load_dc_mhi),
//     .clock_b(clk), .address_b(dc_main_a[12:0]), .q_b(dc_main_hi_d)
// );
// dpram_dc #(.widthad_a(14)) dc_sub
// (
//     .clock_a(clk), .address_a(ioctl_addr[13:0]), .data_a(ioctl_dout), .wren_a(load_dc_sub),
//     .clock_b(clk), .address_b(dc_sub_a), .q_b(dc_sub_d)
// );
// generate
//     for (ln = 0; ln < 4; ln++) begin : dctile
//         dpram_dc #(.widthad_a(12)) rom
//         (
//             .clock_a(clk), .address_a(ioctl_addr[13:2]), .data_a(ioctl_dout), .wren_a(load_dc_tile && ioctl_addr[1:0] == ln),
//             .clock_b(clk), .address_b(dc_tile_a), .q_b(dc_tile_d[ln*8 +: 8])
//         );
//     end
//     for (ln = 0; ln < 8; ln++) begin : dcspr
//         dpram_dc #(.widthad_a(12)) rom
//         (
//             .clock_a(clk), .address_a(ioctl_addr[14:3]), .data_a(ioctl_dout), .wren_a(load_dc_spr && ioctl_addr[2:0] == ln),
//             .clock_b(clk), .address_b(zhour ? zh_spr_a : dc_spr_a), .q_b(dc_spr_d[ln*8 +: 8])
//         );
//     end
// endgenerate

genvar ln;

// ROMSHARE-2026-10-23: dcspr lanes 0-3 also hold the Mr. Do! sprite / Space Raider grid ROM (0x18000-0x19FFF, 2K
// per lane at 000-7FF); Castle gfx2 (0x40000-0x47FFF) as before; Zero Hour / Red Clash gfx2 now at 0x1C000-0x1DFFF
// -> lane offset 800-BFF (gen_mra: its image must end below the Castle windows). No set loads two (rom_audit.py).
wire load_zhspr = ioctl_wr0 && ioctl_addr[24:13] == 12'h00E;   // 0x1C000-0x1DFFF
generate
    for (ln = 0; ln < 8; ln++) begin : dcspr
        dpram_dc #(.widthad_a(12)) rom
        (
            .clock_a(clk),
            .address_a(load_mdspr ? {1'b0, ioctl_addr[12:2]} : load_zhspr ? {2'b10, ioctl_addr[12:3]} : ioctl_addr[14:3]),
            .data_a(ioctl_dout),
            .wren_a(((load_dc_spr || load_zhspr) && ioctl_addr[2:0] == ln) ||
                    (ln < 4 && load_mdspr && {30'd0, ioctl_addr[1:0]} == ln)),
            .clock_b(clk),
            .address_b(board_8203 ? {2'b00, grid_rom_a[11:2]} : mrdo ? {1'b0, md_spr_a} :
                       zhour ? {1'b1, zh_spr_a[10:0]} : dc_spr_a),
            .q_b(dc_spr_d[ln*8 +: 8])
        );
    end
endgenerate
assign md_spr_d = dc_spr_d[31:0];

// Colour PROMs live in the video unit
wire prom_k1_wr = load_prom && ioctl_addr[6:5] == 2'd0;
wire prom_f4_wr = load_prom && ioctl_addr[6:5] == 2'd1;
wire prom_c4_wr = load_prom && ioctl_addr[6:5] == 2'd2;

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////
// Only one board runs at a time, so each CPU / sound chip is instanced once here and driven by the active board's
// bus (rtl/chip_pool_pkg.sv), selected by variant; outputs fan out to every board. Unselected boards stay in reset.
// Lady Bug is the default (its reset is held for the other boards). RESET_n / rst are on the bus (see the package).

// z80pa_0: Lady Bug / Space Raider / Mrs. Dynamite main, Mr. Do!, Castle main, Zero Hour / Red Clash, Cheeky Mouse, Cosmic boards
chip_pool_pkg::z80pa_i_t lb_z80pa_0_i, md_z80pa_0_i, dc_z80pa_0_i, zh_z80pa_0_i, cm_z80pa_0_i, cs_z80pa_0_i, z80pa_0_i;
chip_pool_pkg::z80pa_o_t z80pa_0_o;
assign z80pa_0_i = mrdo ? md_z80pa_0_i : dcastle ? dc_z80pa_0_i : zhour ? zh_z80pa_0_i : cheeky ? cm_z80pa_0_i :
                   cosmic ? cs_z80pa_0_i : lb_z80pa_0_i;

wire [15:0] z80pa_0_a;
wire  [7:0] z80pa_0_do;
wire        z80pa_0_m1_n, z80pa_0_mreq_n, z80pa_0_iorq_n, z80pa_0_rd_n, z80pa_0_wr_n, z80pa_0_rfsh_n;

T80pa #(.Mode(0)) z80pa_0
(
    .RESET_n (z80pa_0_i.reset_n), .CLK(clk), .CEN_p(z80pa_0_i.cen_p), .CEN_n(z80pa_0_i.cen_n),
    .WAIT_n  (z80pa_0_i.wait_n), .INT_n(z80pa_0_i.int_n), .NMI_n(z80pa_0_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80pa_0_m1_n), .MREQ_n(z80pa_0_mreq_n), .IORQ_n(z80pa_0_iorq_n), .RD_n(z80pa_0_rd_n), .WR_n(z80pa_0_wr_n),
    .RFSH_n(z80pa_0_rfsh_n), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(z80pa_0_a), .DI(z80pa_0_i.di), .DO(z80pa_0_do),
    .R800_mode(1'b0), .REG(), .DIRSet(1'b0), .DIR(212'd0)
);

assign z80pa_0_o.a = z80pa_0_a;           assign z80pa_0_o.dout = z80pa_0_do;
assign z80pa_0_o.m1_n = z80pa_0_m1_n;     assign z80pa_0_o.mreq_n = z80pa_0_mreq_n; assign z80pa_0_o.iorq_n = z80pa_0_iorq_n;
assign z80pa_0_o.rd_n = z80pa_0_rd_n;     assign z80pa_0_o.wr_n = z80pa_0_wr_n;     assign z80pa_0_o.rfsh_n = z80pa_0_rfsh_n;

// z80pa_1: Space Raider / Mrs. Dynamite 8203 sub, Castle sub
chip_pool_pkg::z80pa_i_t lb_z80pa_1_i, dc_z80pa_1_i, z80pa_1_i;
chip_pool_pkg::z80pa_o_t z80pa_1_o;
assign z80pa_1_i = dcastle ? dc_z80pa_1_i : lb_z80pa_1_i;

wire [15:0] z80pa_1_a;
wire  [7:0] z80pa_1_do;
wire        z80pa_1_m1_n, z80pa_1_mreq_n, z80pa_1_iorq_n, z80pa_1_rd_n, z80pa_1_wr_n, z80pa_1_rfsh_n;

T80pa #(.Mode(0)) z80pa_1
(
    .RESET_n (z80pa_1_i.reset_n), .CLK(clk), .CEN_p(z80pa_1_i.cen_p), .CEN_n(z80pa_1_i.cen_n),
    .WAIT_n  (z80pa_1_i.wait_n), .INT_n(z80pa_1_i.int_n), .NMI_n(z80pa_1_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80pa_1_m1_n), .MREQ_n(z80pa_1_mreq_n), .IORQ_n(z80pa_1_iorq_n), .RD_n(z80pa_1_rd_n), .WR_n(z80pa_1_wr_n),
    .RFSH_n(z80pa_1_rfsh_n), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(z80pa_1_a), .DI(z80pa_1_i.di), .DO(z80pa_1_do),
    .R800_mode(1'b0), .REG(), .DIRSet(1'b0), .DIR(212'd0)
);

assign z80pa_1_o.a = z80pa_1_a;           assign z80pa_1_o.dout = z80pa_1_do;
assign z80pa_1_o.m1_n = z80pa_1_m1_n;     assign z80pa_1_o.mreq_n = z80pa_1_mreq_n; assign z80pa_1_o.iorq_n = z80pa_1_iorq_n;
assign z80pa_1_o.rd_n = z80pa_1_rd_n;     assign z80pa_1_o.wr_n = z80pa_1_wr_n;     assign z80pa_1_o.rfsh_n = z80pa_1_rfsh_n;

// SN76489 x 7 (jt89, Jose Tejada, unmodified): Lady Bug sound unit (Lady Bug + 8203 boards) 0-1, 8203 sub 2-6,
// Mr. Do! 0-1, Castle 0-3
chip_pool_pkg::sn76489_i_t [6:0] lb_sn76489_i;
chip_pool_pkg::sn76489_i_t [1:0] md_sn76489_i;
chip_pool_pkg::sn76489_i_t [3:0] dc_sn76489_i;
chip_pool_pkg::sn76489_o_t [6:0] sn76489_o;

genvar si;
generate
    for (si = 0; si < 7; si = si + 1) begin : g_sn76489
        chip_pool_pkg::sn76489_i_t i;
        if (si < 2)      begin : g0 assign i = mrdo ? md_sn76489_i[si] : dcastle ? dc_sn76489_i[si] : lb_sn76489_i[si]; end
        else if (si < 4) begin : g1 assign i = dcastle ? dc_sn76489_i[si] : lb_sn76489_i[si]; end
        else             begin : gn assign i = lb_sn76489_i[si]; end
        wire [10:0] sound;
        wire        ready;
        jt89 sn76489
        (
            .rst(i.rst), .clk(clk), .clk_en(i.ce), .wr_n(i.wr_n), .cs_n(i.cs_n), .din(i.din), .sound(sound), .ready(ready)
        );
        assign sn76489_o[si].sound = sound; assign sn76489_o[si].ready = ready;
    end
endgenerate

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
    .z80pa_0_i       (lb_z80pa_0_i),
    .z80pa_0_o       (z80pa_0_o),
    .z80pa_1_i       (lb_z80pa_1_i),
    .z80pa_1_o       (z80pa_1_o),
    .sn76489_i       (lb_sn76489_i),
    .sn76489_o       (sn76489_o),
    .clk_20mhz_i     (clk),
    .ext_res_n_i     (~reset & ~mrdo & ~dcastle & ~zhour & ~cheeky & ~cosmic & ~tms),
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
    .reset   (reset),
    .ce_pix  (lb_ce),
    .en      (crt_flip),
    .din     (ov_code),
    .in_hbl  (ov_hbl),
    .in_vbl  (ov_vbl),
    .dout    (fb_code),
    .out_hbl (fb_hbl),
    .out_vbl (fb_vbl),
    // DDR3-2026-10-23: Indoor Soccer's gfx2 left this RAM for DDR3; only the Devil Zone grid uses the alt port now.
    // Previous lines (incl. the FIX-REVERT block) kept below.
    // .alt_en  (idsoc || cs_grid),
    // FIX-REVERT-2026-10-23: originals below. The Devil Zone grid writer runs on every variant (cs_kind = variant - 13
    // wraps to 3 = devzone, cosmic timing has no reset), so it wrote 6144 bytes into Lady Bug's flip buffer 0 per frame.
    // .alt_wa  (cs_grid_we ? {4'd0, cs_grid_wa} : ioctl_addr[16:0]),
    // .alt_wd  (cs_grid_we ? cs_grid_wd : ioctl_dout),
    // .alt_we  ((ioctl_wr0 && ioctl_addr[24:17] == 8'h02) || cs_grid_we),       // 0x40000-0x5FFFF / Devil Zone grid
    // .alt_wa  ((cs_grid && cs_grid_we) ? {4'd0, cs_grid_wa} : ioctl_addr[16:0]),
    // .alt_wd  ((cs_grid && cs_grid_we) ? cs_grid_wd : ioctl_dout),
    // .alt_we  ((ioctl_wr0 && ioctl_addr[24:17] == 8'h02) || (cs_grid && cs_grid_we)),   // 0x40000-0x5FFFF / Devil Zone grid (variant 16 only)
    // .alt_ra  (idsoc ? dc_spr8_a : {4'd0, cs_grid_ra}),
    .alt_en  (cs_grid),
    .alt_wa  ({4'd0, cs_grid_wa}),
    .alt_wd  (cs_grid_wd),
    .alt_we  (cs_grid && cs_grid_we),                       // Devil Zone grid (variant 16 only)
    .alt_ra  ({4'd0, cs_grid_ra}),
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
    .z80pa_0_i    (md_z80pa_0_i),
    .z80pa_0_o    (z80pa_0_o),
    .sn76489_i    (md_sn76489_i),
    .sn76489_o    (sn76489_o[1:0]),
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
    .z80pa_0_i    (dc_z80pa_0_i),
    .z80pa_0_o    (z80pa_0_o),
    .z80pa_1_i    (dc_z80pa_1_i),
    .z80pa_1_o    (z80pa_1_o),
    .sn76489_i    (dc_sn76489_i),
    .sn76489_o    (sn76489_o[3:0]),
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
    // DDR3-2026-10-23: originals
    // .rom_spr8_a   (dc_spr8_a),
    // .rom_spr8_d   (dc_spr8_d),
    // .rom_adpcm_a  (dc_adpcm_a),
    // .rom_adpcm_d  (dc_adpcm_a[15] ? rom_sub_d : rom_cpu_d),
    .rom_spr8_a   (dc_spr8_a),
    .rom_spr8_req (dc_spr8_req),
    .rom_spr8_rdy (ddr_row_rdy),
    .rom_spr8_q   (ddr_row_q),
    .rom_adpcm_a  (dc_adpcm_a),
    .rom_adpcm_d  (ddr_byte_q),
    .rom_adpcm_rdy(ddr_byte_rdy),
    .prom_wr      (load_dc_prom),
    .prom_a       (ioctl_addr[7:0]),
    .prom_d       (ioctl_dout),
    .hs_address   (hs_address[12:0]),
    .hs_data_out  (dc_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & dcastle)
);

/////////////////////////////  Zero Hour / Red Clash  /////////////////////////////

logic        zh_ce, zh_hs, zh_vs, zh_hbl, zh_vbl;
logic  [7:0] zh_r, zh_g, zh_b, zh_hs_data;
logic signed [15:0] zh_audio;

zerohour_board zerohour_b
(
    .z80pa_0_i    (zh_z80pa_0_i),
    .z80pa_0_o    (z80pa_0_o),
    .clk          (clk),
    .reset        (reset | ~zhour),
    .pause        (pause),
    .redclash     (variant == 8'd11),
    .crt_flip     (crt_flip),
    .in0          (in0),
    .in1          (in1),
    .dsw1         (dsw0),
    .dsw2         (dsw1),
    .coin         (coin),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (zh_ce),
    .video_r      (zh_r),
    .video_g      (zh_g),
    .video_b      (zh_b),
    .video_hs     (zh_hs),
    .video_vs     (zh_vs),
    .video_hblank (zh_hbl),
    .video_vblank (zh_vbl),
    .audio        (zh_audio),
    .rom_cpu_a    (zh_cpu_a),
    .rom_cpu_d    (rom_cpu_d),
    .rom_chr_a    (zh_chr_a),
    .rom_chr_d    (rom_char_d[7:0]),
    .rom_spr_a    (zh_spr_a),
    .rom_spr_d    (dc_spr_d),
    .prom_wr      (load_prom),
    .prom_a       (ioctl_addr[6:0]),
    .prom_d       (ioctl_dout),
    .hs_address   (hs_address[10:0]),
    .hs_data_out  (zh_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & zhour)
);

/////////////////////////////  Cheeky Mouse  /////////////////////////////

logic        cm_ce, cm_hs, cm_vs, cm_hbl, cm_vbl;
logic  [7:0] cm_r, cm_g, cm_b, cm_hs_data, cm_p40;
logic  [1:0] cm_p80;
logic signed [15:0] cm_audio;

cheekyms_board cheekyms_b
(
    .z80pa_0_i    (cm_z80pa_0_i),
    .z80pa_0_o    (z80pa_0_o),
    .clk          (clk),
    .reset        (reset | ~cheeky),
    .pause        (pause),
    .crt_flip     (crt_flip),
    .inputs       (in0),
    .dsw          (dsw0),
    .coin         (coin),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (cm_ce),
    .video_r      (cm_r),
    .video_g      (cm_g),
    .video_b      (cm_b),
    .video_hs     (cm_hs),
    .video_vs     (cm_vs),
    .video_hblank (cm_hbl),
    .video_vblank (cm_vbl),
    .port40       (cm_p40),
    .port80_snd   (cm_p80),
    .rom_cpu_a    (cm_cpu_a),
    .rom_cpu_d    (rom_cpu_d),
    .rom_chr_a    (cm_chr_a),
    .rom_chr_d    (rom_char_d),
    .rom_spr_a    (cm_spr_a),
    .rom_spr_d    (rom_sprite_d),
    .prom_wr      (load_prom),
    .prom_a       (ioctl_addr[6:0]),
    .prom_d       (ioctl_dout),
    .hs_address   (hs_address[9:0]),
    .hs_data_out  (cm_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & cheeky)
);

cheekyms_sound cheekyms_snd
(
    .clk    (clk),
    .reset  (reset | ~cheeky),
    .port40 (cm_p40),
    .port80 (cm_p80),
    .audio  (cm_audio)
);

/////////////////////////////  Cosmic boards  /////////////////////////////

logic        cs_ce, cs_hs, cs_vs, cs_hbl, cs_vbl, cs_grid_we;
logic  [7:0] cs_r, cs_g, cs_b, cs_grid_wd;
logic [12:0] cs_grid_wa, cs_grid_ra;
logic [13:0] cs_snd;
logic signed [15:0] cs_audio;
wire   [7:0] cs_kind = variant - 8'd13;

cosmic_board cosmic_b
(
    .z80pa_0_i    (cs_z80pa_0_i),
    .z80pa_0_o    (z80pa_0_o),
    .clk          (clk),
    .reset        (reset | ~cosmic),
    .pause        (pause),
    .kind         (cs_kind[2:0]),
    .crt_flip     (crt_flip),
    .in0          (in0),
    .in1          (in1),
    .in2          (in2),
    .dsw0         (dsw0),
    .dsw1         (dsw1),
    .coin         (coin),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (cs_ce),
    .video_r      (cs_r),
    .video_g      (cs_g),
    .video_b      (cs_b),
    .video_hs     (cs_hs),
    .video_vs     (cs_vs),
    .video_hblank (cs_hbl),
    .video_vblank (cs_vbl),
    .audio        (cs_audio),
    .snd_trig     (cs_snd),
    .rom_cpu_a    (cs_cpu_a),
    .rom_cpu_d    (rom_cpu_d),
    .rom_cmap_a   (cs_cmap_a),
    .rom_cmap_d   (rom_char_d[7:0]),
    .rom_u2_a     (cs_u2_a),
    .rom_u2_d     (cs_u2_d),
    .rom_u2b_a    (cs_u2b_a),
    .rom_u2b_d    (cs_u2b_d),
    .rom_spr_a    (cs_spr_a),
    .rom_spr_d    (rom_sprite_d),
    .prom_wr      (load_prom),
    .prom_a       (ioctl_addr[6:0]),
    .prom_d       (ioctl_dout),
    .grid_wa      (cs_grid_wa),
    .grid_wd      (cs_grid_wd),
    .grid_we      (cs_grid_we),
    .grid_ra      (cs_grid_ra),
    .grid_q       (dc_spr8_d)
);

/////////////////////////////  TMS99xx boards  /////////////////////////////

logic        tm_ce, tm_hs, tm_vs, tm_hbl, tm_vbl;
logic  [7:0] tm_r, tm_g, tm_b;
logic [15:0] tm_snd;
logic signed [15:0] tm_audio;

tms_board tms_b
(
    .clk          (clk),
    .reset        (reset | ~tms),
    .pause        (pause),
    .getaway      (variant == 8'd19),
    .crt_flip     (crt_flip),
    .in0          (in0),
    .in1          (in1),
    .in2          (in2),
    .dsw0         (dsw0),
    .dsw1         (dsw1),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (tm_ce),
    .video_r      (tm_r),
    .video_g      (tm_g),
    .video_b      (tm_b),
    .video_hs     (tm_hs),
    .video_vs     (tm_vs),
    .video_hblank (tm_hbl),
    .video_vblank (tm_vbl),
    .audio        (tm_audio),
    .snd_out      (tm_snd),
    .rom_cpu_a    (tm_cpu_a),
    .rom_cpu_d    (rom_cpu_d),
    .rom_chr_a    (tm_chr_a),
    .rom_chr_d    (rom_char_d)
);

/////////////////////////////  output select  /////////////////////////////

assign ce_pix       = tms ? tm_ce    : cosmic ? cs_ce    : cheeky ? cm_ce    : zhour ? zh_ce    : dcastle ? dc_ce    : mrdo ? md_ce    : lb_ce;
assign video_r      = tms ? tm_r     : cosmic ? cs_r     : cheeky ? cm_r     : zhour ? zh_r     : dcastle ? dc_r     : mrdo ? md_r     : lb_rgb[23:16];
assign video_g      = tms ? tm_g     : cosmic ? cs_g     : cheeky ? cm_g     : zhour ? zh_g     : dcastle ? dc_g     : mrdo ? md_g     : lb_rgb[15:8];
assign video_b      = tms ? tm_b     : cosmic ? cs_b     : cheeky ? cm_b     : zhour ? zh_b     : dcastle ? dc_b     : mrdo ? md_b     : lb_rgb[7:0];
assign video_hblank = tms ? tm_hbl   : cosmic ? cs_hbl   : cheeky ? cm_hbl   : zhour ? zh_hbl   : dcastle ? dc_hbl   : mrdo ? md_hbl   : fb_hbl;
assign video_vblank = tms ? tm_vbl   : cosmic ? cs_vbl   : cheeky ? cm_vbl   : zhour ? zh_vbl   : dcastle ? dc_vbl   : mrdo ? md_vbl   : fb_vbl;
assign video_hs     = tms ? tm_hs    : cosmic ? cs_hs    : cheeky ? cm_hs    : zhour ? zh_hs    : dcastle ? dc_hs    : mrdo ? md_hs    : lb_hs;
assign video_vs     = tms ? tm_vs    : cosmic ? cs_vs    : cheeky ? cm_vs    : zhour ? zh_vs    : dcastle ? dc_vs    : mrdo ? md_vs    : lb_vs;
assign audio        = tms ? tm_audio : cosmic ? cs_audio : cheeky ? cm_audio : zhour ? zh_audio : dcastle ? dc_audio : mrdo ? md_audio : lb_audio;
assign hs_data_out  = (tms | cosmic) ? 8'd0 : cheeky ? cm_hs_data : zhour ? zh_hs_data : dcastle ? dc_hs_data : mrdo ? md_hs_data : lb_hs_data;

endmodule
