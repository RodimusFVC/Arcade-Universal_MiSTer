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
    output logic        [13:0] z80_o,          // shared T80 (rtl/z80_socket.sv)
    input  logic        [29:0] z80_i,
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

    output logic signed [15:0] audio
);

logic        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n;
logic [15:0] a;
logic  [7:0] din, dout, ram_q;
logic        int_n = 1'b1, vbl_d = 1'b0;

z80_socket cpu
(
    .RESET_n   (res_n),
    .CLK       (clk),
    .CEN_p     (cen_p & ~pause),
    .CEN_n     (cen_n & ~pause),
    .WAIT_n    (1'b1),
    .INT_n     (int_n),
    .NMI_n     (1'b1),
    .BUSRQ_n   (1'b1),
    .M1_n      (m1_n),
    .MREQ_n    (mreq_n),
    .IORQ_n    (iorq_n),
    .RD_n      (rd_n),
    .WR_n      (wr_n),
    .RFSH_n    (rfsh_n),
    .HALT_n    (),
    .BUSAK_n   (),
    .OUT0      (1'b0),
    .A         (a),
    .DI        (din),
    .DO        (dout),
    .R800_mode (1'b0),
    .REG       (),
    .DIRSet    (1'b0),
    .DIR       (212'd0),
    .to_cpu    (z80_o),
    .from_cpu  (z80_i)
);

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

dpram_dc #(.widthad_a(10)) ram
(
    .clock_a(clk), .address_a(a[9:0]), .data_a(dout), .wren_a(ram_cs && !wr_n), .q_a(ram_q),
    .clock_b(clk)
);

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
        jt89 psg
        (
            .rst    (~res_n),
            .clk    (clk),
            .clk_en (cen_p & ~pause),
            .wr_n   (~(io_wr && a[7:3] == i)),
            .cs_n   (1'b0),
            .din    (dout),
            .sound  (sn_out[i]),
            .ready  ()
        );
    end
endgenerate

wire signed [13:0] sum = sn_out[0] + sn_out[1] + sn_out[2] + sn_out[3] + sn_out[4];
assign audio = {sum, 2'd0};

endmodule
