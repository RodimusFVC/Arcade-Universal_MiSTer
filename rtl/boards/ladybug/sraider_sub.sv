//  Copyright (C) 2026 Rodimus
// Based on MAME sraider.cpp (Frank Palazzolo, BSD-3-Clause)

module sraider_sub
(
    output chip_pool_pkg::z80pa_i_t         z80pa_1_i,
    input  chip_pool_pkg::z80pa_o_t         z80pa_1_o,
    output chip_pool_pkg::sn76489_i_t [4:0] sn76489_i,
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

    output ram_pool_pkg::pram_i_t pr_i,
    input  ram_pool_pkg::pram_o_t pr_o
);

logic        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n;
logic [15:0] a;
logic  [7:0] din, dout, ram_q;
logic        int_n = 1'b1, vbl_d = 1'b0;

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

assign pr_i.a_addr = {6'd0, a[9:0]};  assign pr_i.a_d = dout;  assign pr_i.a_we = ram_cs && !wr_n;
assign pr_i.b_addr = 16'd0;           assign pr_i.b_d = 8'd0;  assign pr_i.b_we = 1'b0;
assign ram_q = pr_o.a_q;

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

wire io_wr = !iorq_n && m1_n && !wr_n;
logic signed [10:0] sn_out[5];

genvar i;
generate
    for (i = 0; i < 5; i++) begin : sn
        assign sn76489_i[i].rst  = ~res_n;
        assign sn76489_i[i].ce   = cen_p & ~pause;
        assign sn76489_i[i].wr_n = ~(io_wr && a[7:3] == i);
        assign sn76489_i[i].cs_n = 1'b0;
        assign sn76489_i[i].din  = dout;
        assign sn_out[i] = sn76489_o[i].sound;
    end
endgenerate

// sn76489sv sound is unipolar 0..1020 (0 when silent, no DC at rest): 5 chips max 5100, x6 = 30600 fits int16, no clamp needed
wire        [12:0] sum   = {2'b0, sn_out[0]} + {2'b0, sn_out[1]} + {2'b0, sn_out[2]} + {2'b0, sn_out[3]} + {2'b0, sn_out[4]};
wire        [15:0] sum_x = sum * 16'd6;
assign audio = $signed(sum_x);

endmodule
