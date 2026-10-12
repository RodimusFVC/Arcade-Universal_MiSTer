//============================================================================
//
//  CRT Flip for the Lady Bug video unit (Lady Bug, 8203 boards)
//  Copyright (C) 2026 Rodimus
//
//  The 8106-B / 8203-B sprite engine renders bands ahead of the beam from
//  block-chained sprite RAM, so its picture cannot be mirrored by remapping
//  coordinates (as on Mr. Do!). Instead the visible 240 x 192 picture (8-bit
//  colour codes) is double-buffered and, with CRT Flip on, read back from the
//  opposite corner: one frame of delay, flipped only. Off = straight through.
//  One pixel of latency either way.
//
//============================================================================

module crt_flip_fb
(
    input  logic       clk,
    input  logic       ce_pix,
    input  logic       en,
    input  logic [7:0] din,
    input  logic       in_hbl,
    input  logic       in_vbl,
    output logic [7:0] dout,
    output logic       out_hbl,
    output logic       out_vbl
);

// visible 240 x 192; two frames of 46080 codes

logic [7:0] d_q;
logic       hbl_q = 1'b1, vbl_q = 1'b1;
logic [7:0] x_q, y_q;
logic       first_line = 1'b1;
logic       wbuf = 1'b0;

always_ff @(posedge clk) begin
    if (ce_pix) begin
        d_q <= din; hbl_q <= in_hbl; vbl_q <= in_vbl;
        if (in_vbl && !vbl_q) wbuf <= ~wbuf;
        if (in_vbl) first_line <= 1'b1;
        else if (!in_hbl) begin
            if (hbl_q) begin
                x_q        <= 8'd0;
                y_q        <= first_line ? 8'd0 : y_q + 8'd1;
                first_line <= 1'b0;
            end
            else x_q <= x_q + 8'd1;
        end
    end
end

wire        vis_q = !hbl_q && !vbl_q && x_q < 8'd240 && y_q < 8'd192;
wire [16:0] base_w = wbuf ? 17'd46080 : 17'd0;
wire [16:0] base_r = wbuf ? 17'd0 : 17'd46080;
wire [16:0] wa = base_w + {1'b0, y_q, 8'd0} - {5'd0, y_q, 4'd0} + {9'd0, x_q};                   // y * 240 + x
wire  [7:0] ry = 8'd191 - y_q;
wire  [7:0] rx = 8'd239 - x_q;
wire [16:0] ra = base_r + {1'b0, ry, 8'd0} - {5'd0, ry, 4'd0} + {9'd0, rx};

logic [7:0] q;

// write once per pixel, on the clock after the pixel arrives in d_q
logic ce_d = 1'b0;
always_ff @(posedge clk) ce_d <= ce_pix;

dpram_dc #(.widthad_a(17)) fb
(
    .clock_a(clk), .address_a(wa), .data_a(d_q), .wren_a(ce_d && vis_q),
    .clock_b(clk), .address_b(ra), .q_b(q)
);

always_ff @(posedge clk) begin
    if (ce_pix) begin
        dout    <= (en && vis_q) ? q : d_q;
        out_hbl <= hbl_q;
        out_vbl <= vbl_q;
    end
end

endmodule
