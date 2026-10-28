//============================================================================
//
//  Universal 8203-A sound / video-control CPU (Space Raider, Mrs. Dynamite)
//  Copyright (C) 2026 Rodimus
//
//  From MAME sraider.cpp (Frank Palazzolo) cpu2_map / cpu2_io_map:
//    0000-5FFF ROM (H6, J6, L6)          6000-63FF RAM, mirrored at 6400 (2x 2114)
//    8000 read sound latch low (P6)      A000 read sound latch high (R6)
//    C000 read 556 outputs on D1-D0      E000-E0FF grid RAM (mirror 0x300), write only
//    E800-EFFF control (LS273 D4): [2:0] star speed, [3] star enable, [6:4] grid R/G/B, [7] flip
//    I/O 00-27 five SN76489 (8 ports each), 28-3F sound-resistor latches (not emulated, as MAME)
//  IRQ on vblank, held until acknowledged (MAME irq0_line_hold).
//
//============================================================================

module sraider_sub
(
    output chip_pool_pkg::z80pa_i_t         z80pa_1_i,   // shared Z80 (rtl/universal_board.sv)
    input  chip_pool_pkg::z80pa_o_t         z80pa_1_o,
    output chip_pool_pkg::sn76489_i_t [4:0] sn76489_i,   // shared SN76489s 2-6
    input  chip_pool_pkg::sn76489_o_t [4:0] sn76489_o,
    input  logic               clk,
    input  logic               cen_p,
    input  logic               cen_n,
    input  logic               res_n,
    input  logic               pause,
    input  logic               vblank,

    input  logic         [7:0] latch_lo,
    input  logic         [7:0] latch_hi,

    output logic        [14:0] rom_a,
    input  logic         [7:0] rom_d,

    output logic               grid_wr,
    output logic         [7:0] grid_a,
    output logic         [7:0] grid_d,
    output logic         [7:0] ctrl,

    output logic signed [15:0] audio,

    // RAMPOOL-2026-10-27: board RAM pool blocks (rtl/universal_board.sv); local index = RAM within this module
    output ram_pool_pkg::pram_i_t pr_i,
    input  ram_pool_pkg::pram_o_t pr_o
);

logic        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n;
logic [15:0] a;
logic  [7:0] din, dout, ram_q;
logic        int_n = 1'b1, vbl_d = 1'b0;

// the shared T80pa in rtl/universal_board.sv
assign z80pa_1_i.reset_n = res_n;
assign z80pa_1_i.cen_p   = cen_p & ~pause;
assign z80pa_1_i.cen_n   = cen_n & ~pause;
assign z80pa_1_i.wait_n  = 1'b1;
assign z80pa_1_i.int_n   = int_n;
assign z80pa_1_i.nmi_n   = 1'b1;
assign z80pa_1_i.di      = din;
assign m1_n   = z80pa_1_o.m1_n;
assign mreq_n = z80pa_1_o.mreq_n;
assign iorq_n = z80pa_1_o.iorq_n;
assign rd_n   = z80pa_1_o.rd_n;
assign wr_n   = z80pa_1_o.wr_n;
assign rfsh_n = z80pa_1_o.rfsh_n;
assign a      = z80pa_1_o.a;
assign dout   = z80pa_1_o.dout;

always_ff @(posedge clk) begin
    vbl_d <= vblank;
    if (!res_n)                  int_n <= 1'b1;
    else if (!m1_n && !iorq_n)   int_n <= 1'b1;
    else if (vblank && !vbl_d)   int_n <= 1'b0;
end

wire mem    = !mreq_n && rfsh_n;
wire rom_cs = mem && a[15:13] <  3'd3;
wire ram_cs = mem && a[15:11] == 5'b01100;
wire grid_cs = mem && a[15:10] == 6'b111000;
wire ctrl_cs = mem && a[15:11] == 5'b11101;

assign rom_a = a[14:0];

// RAMPOOL-2026-10-27: original instance below; now board RAM pool block (universal_board.sv)
// dpram_dc #(.widthad_a(10)) ram
// (
//     .clock_a(clk), .address_a(a[9:0]), .data_a(dout), .wren_a(ram_cs && !wr_n), .q_a(ram_q),
//     .clock_b(clk)
// );
assign pr_i.a_addr = {5'd0, a[9:0]};  assign pr_i.a_d = dout;  assign pr_i.a_we = ram_cs && !wr_n;
assign pr_i.b_addr = 15'd0;           assign pr_i.b_d = 8'd0;  assign pr_i.b_we = 1'b0;
assign ram_q = pr_o.a_q;

// 556 dual timer on D1-D0: MAME returns random bits; a free-running LFSR stands in
logic [15:0] rnd = 16'hACE1;
always_ff @(posedge clk) rnd <= {rnd[14:0], rnd[15] ^ rnd[13] ^ rnd[12] ^ rnd[10]};

always_comb begin
    din = 8'hFF;
    if (rom_cs)                               din = rom_d;
    else if (ram_cs)                          din = ram_q;
    else if (mem && a[15:13] == 3'd4)         din = latch_lo;
    else if (mem && a[15:13] == 3'd5)         din = latch_hi;
    else if (mem && a[15:13] == 3'd6)         din = {6'd0, rnd[1:0]};
end

assign grid_wr = grid_cs && !wr_n;
assign grid_a  = a[7:0];
assign grid_d  = dout;

always_ff @(posedge clk) begin
    if (!res_n)                ctrl <= 8'h00;
    else if (ctrl_cs && !wr_n) ctrl <= dout;
end

// Five SN76489 on I/O 00-27
wire io_wr = !iorq_n && m1_n && !wr_n;
logic signed [10:0] sn_out[5];

genvar i;
generate
    for (i = 0; i < 5; i++) begin : sn
        // the shared SN76489s in rtl/universal_board.sv
        assign sn76489_i[i].rst  = ~res_n;
        assign sn76489_i[i].ce   = cen_p & ~pause;
        assign sn76489_i[i].wr_n = ~(io_wr && a[7:3] == i);
        assign sn76489_i[i].cs_n = 1'b0;
        assign sn76489_i[i].din  = dout;
        assign sn_out[i] = sn76489_o[i].sound;
    end
endgenerate

wire signed [13:0] sum = sn_out[0] + sn_out[1] + sn_out[2] + sn_out[3] + sn_out[4];
assign audio = {sum, 2'd0};

endmodule
