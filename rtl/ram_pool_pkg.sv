//============================================================================
//
//  ram_pool_pkg — bus types for the Universal core's shared board RAM pool
//  Copyright (C) 2026 Rodimus
//
//  Only one board runs at a time, so the boards' larger RAMs live in three 32K x 8 true dual-port blocks in
//  rtl/universal_board.sv (the Lady Bug CRT Flip frame buffer when a Lady Bug-video board runs). A board drives
//  up to three blocks through pram_i_t (both ports read / write, as dpram_dc) and reads pram_o_t; the block
//  owner is picked by variant. Same timing as a private dpram_dc: registered address, one clock to q.
//
//============================================================================

package ram_pool_pkg;

typedef struct packed {
    logic [14:0] a_addr;
    logic  [7:0] a_d;
    logic        a_we;
    logic [14:0] b_addr;
    logic  [7:0] b_d;
    logic        b_we;
} pram_i_t;

typedef struct packed {
    logic  [7:0] a_q;
    logic  [7:0] b_q;
} pram_o_t;

endpackage
