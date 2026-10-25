//============================================================================
//
//  Artwork on a slower video clock: the board runs on clk_sys, the artwork module (and the video back end) on
//  clk_art, a PLL output from the same VCO whose rising edges coincide with clk_sys edges (e.g. 80 / 40 MHz).
//  The clocks are related, so every crossing here is a plain register path that STA times normally.
//
//  Video: each board pixel (bd_ce) is held beside a toggle; clk_art registers both together and turns the toggle
//  change into its own pixel enable (ce_art), with the pixel in px until the next one.
//  Download: each ioctl byte for index IDX is held beside a toggle; clk_art turns it into a one-clock a_wr. ioctl_wait
//  (to hps_io) stays high until clk_art has taken the byte and while the artwork module waits (art_wait).
//  Needs clk_art >= 2 x the board pixel rate.
//
//  Copyright (C) 2026 Rodimus
//  Redistribution and use in source and synthesized forms, with or without modification, are permitted
//  provided that the above copyright notice is retained. THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY.
//
//============================================================================

module art_xclk #(parameter [7:0] IDX = 8'd5, parameter int VW = 28)
(
    input               clk_sys,
    input               clk_art,

    input               bd_ce,          // clk_sys: board pixel enable
    input      [VW-1:0] bd_px,          // clk_sys: board pixel (sync, blanks, RGB), valid at bd_ce
    output              ce_art,         // clk_art: pixel enable
    output reg [VW-1:0] px,             // clk_art: pixel

    input               ioctl_wr,       // clk_sys (hps_io)
    input        [7:0]  ioctl_index,
    input       [26:0]  ioctl_addr,
    input        [7:0]  ioctl_dout,
    output              ioctl_wait,     // clk_sys, to hps_io
    output              a_wr,           // clk_art
    output reg  [26:0]  a_addr,         // held from a_wr until the next byte
    output reg   [7:0]  a_dout,
    input               art_wait        // clk_art, from the artwork module
);

reg          v_tgl = 1'b0;
reg [VW-1:0] v_hold;
always @(posedge clk_sys) if (bd_ce) begin v_tgl <= ~v_tgl; v_hold <= bd_px; end
reg          v_t1 = 1'b0, v_t2 = 1'b0;
always @(posedge clk_art) begin v_t1 <= v_tgl; v_t2 <= v_t1; px <= v_hold; end
assign ce_art = v_t1 ^ v_t2;

reg  a_tgl = 1'b0, a_pend = 1'b0;
reg  a_ack1 = 1'b0, a_ack2 = 1'b0, a_wait1 = 1'b0, a_wait2 = 1'b0;
reg  a_t1 = 1'b0, a_t2 = 1'b0, a_ack = 1'b0;
always @(posedge clk_sys) begin
    {a_ack2, a_ack1}   <= {a_ack1, a_ack};
    {a_wait2, a_wait1} <= {a_wait1, art_wait};
    if (ioctl_wr && ioctl_index == IDX) begin a_tgl <= ~a_tgl; a_addr <= ioctl_addr; a_dout <= ioctl_dout; a_pend <= 1'b1; end
    else if (a_ack2 == a_tgl) a_pend <= 1'b0;
end
always @(posedge clk_art) begin a_t1 <= a_tgl; a_t2 <= a_t1; if (a_t1 != a_t2) a_ack <= a_t1; end
assign a_wr       = a_t1 != a_t2;
assign ioctl_wait = a_pend | a_wait2;

endmodule
