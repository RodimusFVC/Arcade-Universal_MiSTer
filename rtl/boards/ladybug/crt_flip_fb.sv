//  Copyright (C) 2026 Rodimus

module crt_flip_fb
(
    input  logic       clk,
    input  logic       reset,
    input  logic       ce_pix,
    input  logic       en,
    input  logic [7:0] din,
    input  logic       in_hbl,
    input  logic       in_vbl,
    output logic [7:0] dout,
    output logic       out_hbl,
    output logic       out_vbl,

    input  logic        alt_en,
    input  logic [16:0] alt_wa,
    input  logic  [7:0] alt_wd,
    input  logic        alt_we,
    input  logic [16:0] alt_ra,
    output logic  [7:0] alt_q,

    output ram_pool_pkg::pram_i_t [2:0] pr_i,
    input  ram_pool_pkg::pram_o_t [2:0] pr_o
);

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
wire [16:0] wa = base_w + {1'b0, y_q, 8'd0} - {5'd0, y_q, 4'd0} + {9'd0, x_q};
wire  [7:0] ry = 8'd191 - y_q;
wire  [7:0] rx = 8'd239 - x_q;
wire [16:0] ra = base_r + {1'b0, ry, 8'd0} - {5'd0, ry, 4'd0} + {9'd0, rx};

logic [7:0] q;
assign alt_q = q;

logic ce_d = 1'b0;
always_ff @(posedge clk) ce_d <= ce_pix;

wire [16:0] fa_w = (alt_en || alt_we) ? alt_wa : wa;
wire  [7:0] fd_w = (alt_en || alt_we) ? alt_wd : d_q;
wire        fwe  = alt_we || (!alt_en && !reset && ce_d && vis_q);
wire [16:0] fa_r = alt_en ? alt_ra : ra;
logic [1:0] r_blk = 2'd0;
always_ff @(posedge clk) r_blk <= fa_r[16:15];
assign q = pr_o[r_blk].b_q;
genvar k;
generate
    for (k = 0; k < 3; k++) begin : blk
        assign pr_i[k].a_addr = {1'b0, fa_w[14:0]};
        assign pr_i[k].a_d    = fd_w;
        assign pr_i[k].a_we   = fwe && fa_w[16:15] == k;
        assign pr_i[k].b_addr = {1'b0, fa_r[14:0]};
        assign pr_i[k].b_d    = 8'd0;
        assign pr_i[k].b_we   = 1'b0;
    end
endgenerate

always_ff @(posedge clk) begin
    if (ce_pix) begin
        dout    <= (en && vis_q) ? q : d_q;

        out_hbl <= hbl_q;
        out_vbl <= vbl_q;
    end
end

endmodule
