//============================================================================
//
//  Lady Bug board clock enables
//  Copyright (C) 2026 Rodimus
//
//  Video enables follow Arnim Laeuger's ladybug_clk.vhd (FPGA Lady Bug, 2005):
//  the system clock is 4x the pixel clock, so clk_en_10mhz / clk_en_5mhz keep
//  their original names but run at 9.828 MHz / 4.914 MHz from a 19.656 MHz clock
//  (board: 9.828 MHz crystal / 2).
//
//  The CPU has its own 4 MHz crystal on the 8106-A2 board, so its enables come
//  from a fractional accumulator instead of the video divider: 4 MHz average,
//  cpu_cen_p = rising edge, cpu_cen_n = falling edge (T80pa), half a period apart.
//
//============================================================================

module ladybug_clk
(
    input  logic clk_20mhz_i,           // 19.656 MHz
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

// 8 MHz edge stream = 19.656 MHz * 1000 / 2457; edges alternate rising / falling
localparam logic [11:0] FRAC_N = 12'd1000;
localparam logic [11:0] FRAC_M = 12'd2457;

logic [11:0] frac_q;
logic        phase_q;               // 0: next edge is rising

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
