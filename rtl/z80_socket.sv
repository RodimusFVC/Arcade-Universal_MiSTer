//============================================================================
//
//  z80_socket - stands in for a board's T80pa and routes its pins to a T80 shared between boards
//  Copyright (C) 2026 Rodimus
//
//  Same port names as T80pa (Mode 0), so a board swaps the module name and adds two bundles. Only one board
//  runs at a time, so universal_board.sv owns one T80pa per CPU role and muxes the boards' inputs by variant.
//  BUSRQ_n, OUT0, R800_mode, DIRSet and DIR are tied off identically on every board and are not routed.
//
//    to_cpu   = {RESET_n, CEN_p, CEN_n, WAIT_n, INT_n, NMI_n, DI[7:0]}
//    from_cpu = {M1_n, MREQ_n, IORQ_n, RD_n, WR_n, RFSH_n, A[15:0], DO[7:0]}
//
//============================================================================

module z80_socket
(
    input  logic          RESET_n,
    input  logic          CLK,
    input  logic          CEN_p,
    input  logic          CEN_n,
    input  logic          WAIT_n,
    input  logic          INT_n,
    input  logic          NMI_n,
    input  logic          BUSRQ_n,
    output logic          M1_n,
    output logic          MREQ_n,
    output logic          IORQ_n,
    output logic          RD_n,
    output logic          WR_n,
    output logic          RFSH_n,
    output logic          HALT_n,
    output logic          BUSAK_n,
    input  logic          OUT0,
    output logic   [15:0] A,
    input  logic    [7:0] DI,
    output logic    [7:0] DO,
    input  logic          R800_mode,
    output logic  [211:0] REG,
    input  logic          DIRSet,
    input  logic  [211:0] DIR,

    output logic   [13:0] to_cpu,
    input  logic   [29:0] from_cpu
);

assign to_cpu = {RESET_n, CEN_p, CEN_n, WAIT_n, INT_n, NMI_n, DI};
assign {M1_n, MREQ_n, IORQ_n, RD_n, WR_n, RFSH_n, A, DO} = from_cpu;
assign HALT_n  = 1'b1;
assign BUSAK_n = 1'b1;
assign REG     = 212'd0;

endmodule
