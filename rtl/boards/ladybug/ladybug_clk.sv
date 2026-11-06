//  Copyright (C) 2026 Rodimus

module ladybug_clk
(
    input  logic clk_20mhz_i,
    input  logic por_n_i,
    output logic clk_en_10mhz_o,
    output logic clk_en_10mhz_n_o,
    output logic clk_en_5mhz_o,
    output logic clk_en_5mhz_n_o,
    output logic cpu_cen_p_o,
    output logic cpu_cen_n_o
);

logic [1:0] clk_cnt_5mhz_q;

always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin
    if (!por_n_i) begin
        clk_cnt_5mhz_q   <= 2'd0;
        clk_en_10mhz_o   <= 1'b0;
        clk_en_10mhz_n_o <= 1'b0;
        clk_en_5mhz_o    <= 1'b0;
        clk_en_5mhz_n_o  <= 1'b0;
    end
    else begin
        clk_cnt_5mhz_q   <= clk_cnt_5mhz_q + 2'd1;
        clk_en_10mhz_o   <=  clk_cnt_5mhz_q[0];
        clk_en_10mhz_n_o <= ~clk_cnt_5mhz_q[0];
        clk_en_5mhz_o    <= (clk_cnt_5mhz_q == 2'b11);
        clk_en_5mhz_n_o  <= (clk_cnt_5mhz_q == 2'b01);
    end
end

localparam logic [11:0] FRAC_N = 12'd1000;
localparam logic [11:0] FRAC_M = 12'd2457;

logic [11:0] frac_q;
logic        phase_q;

wire  [12:0] frac_sum = {1'b0, frac_q} + {1'b0, FRAC_N};
wire         edge_s   = (frac_sum >= {1'b0, FRAC_M});
wire  [12:0] frac_sub = frac_sum - {1'b0, FRAC_M};

always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin
    if (!por_n_i) begin
        frac_q      <= 12'd0;
        phase_q     <= 1'b0;
        cpu_cen_p_o <= 1'b0;
        cpu_cen_n_o <= 1'b0;
    end
    else begin
        frac_q      <= edge_s ? frac_sub[11:0] : frac_sum[11:0];
        cpu_cen_p_o <= edge_s & ~phase_q;
        cpu_cen_n_o <= edge_s &  phase_q;
        if (edge_s) phase_q <= ~phase_q;
    end
end

endmodule
