//============================================================================
//  board_template.sv - start a new Universal-core board by copying this file (NOT in files.qip, never compiled).
//  Copyright (C) 2026 Rodimus
//
//  Boards never instantiate a CPU, sound chip, ROM store or board RAM. They live ONCE in the dispatcher
//  rtl/universal_dispatcher.sv: Z80s z80pa_0 / z80pa_1, SN76489 bank sn76489[6:0], MC6845 mc6845_0, MSM5205 jt5205_0, TMS9900
//  tms9900_0 (chip_pool_pkg buses), the shared ROM blocks (rom_cpu, rom_char_*, rom_sprite_*, rom_sub, dcspr lanes, rom_dec_*,
//  PROM blocks rom_k1 / rom_f4 / rom_c4 / rom_dcprom, DDR3 rows/bytes) and the 13 board RAM pool blocks (ram_pool_pkg:
//  0-2 = 32K, 3 = 4K, 4-12 = 1K; map in the dispatcher's "Board RAM pool" section).
//  To add the board: copy this file to rtl/boards/<board>/<board>_board.sv, add it to files.qip + verilator/Makefile +
//  verilator/lint.sh, instance it in the dispatcher, put its buses on the variant muxes (z80pa_*_i, sn76489_i, pool_i,
//  mc6845_0_i, ...) and tie the pool blocks it doesn't use to '0. A RAM bigger than its block = grow the block, never a
//  private dpram_dc. ROM / PROM images: an index-0 window + a read port exported to the dispatcher (load decode by the
//  index-0 address only, NEVER by variant: the variant byte arrives after the ROMs).
//  A RAM / chip that truly can't pool = "// POOL-EXCEPTION: <reason>" on its instance line + a Pool contract row
//  (Claude/universal_core note). verilator/common/pool_check.sh (POOL_MODS in verilator/Makefile) enforces it.
//============================================================================

module board_template
(
    input  logic        clk,            // 19.656 MHz
    input  logic        reset,          // core reset | ~this board's variants (the board is held in reset when inactive)
    input  logic        pause,

    // shared Z80 (pool slot z80pa_0, driven through the dispatcher's variant mux)
    output chip_pool_pkg::z80pa_i_t         z80pa_0_i,
    input  chip_pool_pkg::z80pa_o_t         z80pa_0_o,
    // shared SN76489 bank slots this board uses (dispatcher: sn76489[n])
    output chip_pool_pkg::sn76489_i_t [1:0] sn76489_i,
    input  chip_pool_pkg::sn76489_o_t [1:0] sn76489_o,
    // optional: CRTC / MSM5205 / TMS9900 slots
    // output chip_pool_pkg::mc6845_i_t        mc6845_0_i,
    // input  chip_pool_pkg::mc6845_o_t        mc6845_0_o,

    // shared ROM blocks (read ports)
    output logic [14:0] rom_cpu_a,      // rom_cpu
    input  logic  [7:0] rom_cpu_d,

    // board RAM pool (rtl/ram_pool_pkg.sv): 13 blocks, tie the unused ones to '0
    output ram_pool_pkg::pram_i_t [12:0] pr_i,
    input  ram_pool_pkg::pram_o_t [12:0] pr_o,

    input  logic  [7:0] in0,
    input  logic  [7:0] dsw0,

    output logic        ce_pix,
    output logic  [7:0] video_r,
    output logic  [7:0] video_g,
    output logic  [7:0] video_b,
    output logic        video_hs,
    output logic        video_vs,
    output logic        video_hblank,
    output logic        video_vblank,
    output logic signed [15:0] audio
);

endmodule
