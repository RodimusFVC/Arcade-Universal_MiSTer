//============================================================================
//
//  ddr_arb.sv - the MiSTer DDRAM port shared by three clients, all DDRAM_* on clk (= DDRAM_CLK)
//  Copyright (C) 2026 Rodimus
//
//  clk = CLK_2X (39.312 MHz), clk_sys = CLK_SYS (19.656 MHz): same PLL VCO, rising edges aligned 2:1, so every
//  crossing below is a plain register path that STA times (sys_top.sdc groups the core PLL's outputs).
//
//  Clients, fixed priority at each command slot:
//    S  screen_rotate (clk): single-beat writes, ignores BUSY -> SDEPTH-deep FIFO (full: newest replaces the last entry)
//    G  ddr_rom's own DDRAM port (clk_sys): single beats, at most one read outstanding (game ROM data, index-0
//       download mirror). Bridged: the command is taken on the clk edge in the middle of a clk_sys cycle (BUSY to
//       ddr_rom low for that one clk_sys cycle); read data is handed back held for exactly one clk_sys cycle.
//    A  artwork (clk): bursts up to 127 beats. A read burst is accepted at once and issued as CHUNK-beat reads,
//       at most RWIN beats in flight (RWIN_G while the game has used the port in the last G_HOLD clocks); a write
//       burst is forwarded beat by beat (artwork data straight to DDRAM) as CHUNK-beat sub-bursts. Between chunks
//       S and G go first: a G read waits for at most one write chunk plus the artwork beats already in flight
//       (RWIN_G, or RWIN for the first read after G_HOLD quiet clocks). The artwork only loses throughput.
//  Read data comes back in issue order (Avalon): a tag FIFO routes each beat to G or A.
//
//  Redistribution and use in source and synthesized forms, with or without modification, are permitted
//  provided that the above copyright notice is retained. THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY.
//
//============================================================================

module ddr_arb #(parameter int CHUNK  = 8,      // artwork sub-burst length (beats)
                 parameter int RWIN   = 64,     // artwork read beats in flight at most (>= CHUNK)
                 parameter int RWIN_G = 32,     // ... while the game reads (>= CHUNK)
                 parameter int G_HOLD = 4096,   // clocks after a game read that count as "the game reads" (~104 us)
                 parameter int SDEPTH = 8)      // screen_rotate write FIFO (power of 2)
(
    input             clk,
    input             clk_sys,

    // S: screen_rotate (clk)
    input             sr_we,
    input      [28:0] sr_addr,
    input      [63:0] sr_din,
    input       [7:0] sr_be,

    // G: ddr_rom DDRAM port (clk_sys timing)
    input             g_rd,
    input             g_we,
    input      [28:0] g_addr,
    input      [63:0] g_din,
    input       [7:0] g_be,
    output reg        g_busy = 1'b1,
    output reg [63:0] g_dout = 64'd0,
    output reg        g_dout_ready = 1'b0,

    // A: artwork DDRAM port (clk)
    input             a_rd,
    input             a_we,
    input       [7:0] a_burstcnt,
    input      [28:0] a_addr,
    input      [63:0] a_din,
    input       [7:0] a_be,
    output            a_busy,
    output     [63:0] a_dout,
    output            a_dout_ready,

    output            DDRAM_CLK,
    input             DDRAM_BUSY,
    output      [7:0] DDRAM_BURSTCNT,
    output     [28:0] DDRAM_ADDR,
    input      [63:0] DDRAM_DOUT,
    input             DDRAM_DOUT_READY,
    output            DDRAM_RD,
    output     [63:0] DDRAM_DIN,
    output      [7:0] DDRAM_BE,
    output            DDRAM_WE
);

// ------------------------------------------------------------------ clk_sys phase
// tog flips on every clk_sys edge; on clk it differs from its 1-clock delay exactly in the clk cycle that starts at a
// clk_sys edge, so the clk edge with mid = 1 is the one in the middle of a clk_sys cycle.
reg  tog = 1'b0, tog_q = 1'b0;
always @(posedge clk_sys) tog <= ~tog;
always @(posedge clk) tog_q <= tog;
wire mid = tog != tog_q;

// ------------------------------------------------------------------ command slot (S, G, A reads)
reg         c_rd = 1'b0, c_we = 1'b0;
reg  [28:0] c_addr = 29'd0;
reg   [7:0] c_len = 8'd1;
reg  [63:0] c_din = 64'd0;
reg   [7:0] c_be = 8'hFF;
wire        c_free = !(c_rd || c_we) || !DDRAM_BUSY;   // a new command can be loaded at this edge

// artwork write forwarding (one CHUNK sub-burst at a time)
reg         aw_on = 1'b0;
reg  [28:0] aw_caddr = 29'd0;
reg   [7:0] aw_clen = 8'd1, aw_cleft = 8'd0, aw_done = 8'd0;
wire        aw_beat = aw_on && a_we && !DDRAM_BUSY;
wire  [7:0] aw_rem  = a_burstcnt - aw_done;              // beats of the artwork burst not yet sent
wire  [7:0] aw_n    = (aw_rem > 8'(CHUNK)) ? 8'(CHUNK) : aw_rem;

assign DDRAM_CLK      = clk;
assign DDRAM_RD       = !aw_on && c_rd;
assign DDRAM_WE       = aw_on ? a_we     : c_we;
assign DDRAM_ADDR     = aw_on ? aw_caddr : c_addr;
assign DDRAM_BURSTCNT = aw_on ? aw_clen  : c_len;
assign DDRAM_DIN      = aw_on ? a_din    : c_din;
assign DDRAM_BE       = aw_on ? a_be     : c_be;

// ------------------------------------------------------------------ S FIFO
localparam int SB = $clog2(SDEPTH);
reg  [28:0] sf_a [SDEPTH];
reg  [63:0] sf_d [SDEPTH];
reg   [7:0] sf_b [SDEPTH];
reg  [SB-1:0] sf_wp = '0, sf_rp = '0;
reg    [SB:0] sf_n = '0;
wire        sf_full = sf_n == (SB + 1)'(SDEPTH);

// ------------------------------------------------------------------ G bridge
reg         gq_v = 1'b0, gq_rd = 1'b0;
reg  [28:0] gq_a = 29'd0;
reg  [63:0] gq_d = 64'd0;
reg   [7:0] gq_b = 8'hFF;
reg         gr_v = 1'b0;
reg  [63:0] gr_d = 64'd0;

// ------------------------------------------------------------------ A read job
reg         aj_v = 1'b0;
reg  [28:0] aj_addr = 29'd0;
reg   [7:0] aj_left = 8'd0;
localparam int IW = $clog2(RWIN + 1);
reg  [IW-1:0] a_inf = '0;                                // artwork read beats issued, not yet returned
reg    [12:0] g_act = 13'd0;                             // game read activity (counts down from G_HOLD)
wire  [8:0] a_win = (g_act != 13'd0 || gq_v) ? 9'(RWIN_G) : 9'(RWIN);
wire  [7:0] aj_n = (aj_left > 8'(CHUNK)) ? 8'(CHUNK) : aj_left;

assign a_busy = a_we ? !aw_beat : a_rd ? aj_v : 1'b1;

// ------------------------------------------------------------------ read tags (in issue order)
// in flight: one artwork burst's chunks (<= RWIN / CHUNK + 1) and one G read
localparam int TB = $clog2(RWIN / CHUNK + 2);
localparam int TN = 1 << TB;
reg         t_g [TN];                                    // 1 = G, 0 = A
reg   [7:0] t_n [TN];
reg  [TB-1:0] t_wp = '0, t_rp = '0;
reg    [TB:0] t_cnt = '0;
wire        t_full = t_cnt == (TB + 1)'(TN);
reg   [7:0] t_beat = 8'd0;
wire        t_head_g = t_g[t_rp];
wire        r_beat = DDRAM_DOUT_READY && t_cnt != '0;
wire        g_beat = r_beat && t_head_g;
wire        a_beat = r_beat && !t_head_g;

assign a_dout       = DDRAM_DOUT;
assign a_dout_ready = a_beat;

always @(posedge clk) begin
    reg          pop, push, sf_pop, g_iss;
    reg [IW-1:0] inf_add;
    pop = 1'b0; push = 1'b0; sf_pop = 1'b0; g_iss = 1'b0; inf_add = '0;

    // ---- read data routing
    if (r_beat) begin
        if (t_head_g || t_beat == t_n[t_rp] - 8'd1) begin pop = 1'b1; t_beat <= 8'd0; end
        else t_beat <= t_beat + 8'd1;
    end
    if (g_beat && !mid) begin gr_v <= 1'b1; gr_d <= DDRAM_DOUT; end

    // ---- G: clk_sys-facing registers change only on the mid edge
    if (mid) begin
        g_dout_ready <= gr_v || g_beat;
        if (g_beat) g_dout <= DDRAM_DOUT; else if (gr_v) g_dout <= gr_d;
        gr_v <= 1'b0;
    end

    // ---- artwork read: accept the burst at once (artwork has one burst at a time)
    if (a_rd && !aj_v) begin aj_v <= 1'b1; aj_addr <= a_addr; aj_left <= a_burstcnt; end

    // ---- artwork write sub-burst
    if (aw_beat) begin
        aw_cleft <= aw_cleft - 8'd1;
        aw_done  <= (aw_done + 8'd1 == a_burstcnt) ? 8'd0 : aw_done + 8'd1;
        if (aw_cleft == 8'd1) begin
            // chunk done: chain the next one only when nobody else waits
            if (aw_done + 8'd1 != a_burstcnt && sf_n == '0 && !gq_v && !aj_v) begin
                aw_caddr <= a_addr + 29'(aw_done) + 29'd1;
                aw_clen  <= (a_burstcnt - aw_done - 8'd1 > 8'(CHUNK)) ? 8'(CHUNK) : a_burstcnt - aw_done - 8'd1;
                aw_cleft <= (a_burstcnt - aw_done - 8'd1 > 8'(CHUNK)) ? 8'(CHUNK) : a_burstcnt - aw_done - 8'd1;
            end
            else aw_on <= 1'b0;
        end
    end

    // ---- command slot
    if (!aw_on && c_free) begin
        c_rd <= 1'b0; c_we <= 1'b0; c_len <= 8'd1;
        if (sf_n != '0) begin
            c_we <= 1'b1; c_addr <= sf_a[sf_rp]; c_din <= sf_d[sf_rp]; c_be <= sf_b[sf_rp];
            sf_pop = 1'b1;
        end
        else if (gq_v && (!gq_rd || !t_full)) begin
            c_rd <= gq_rd; c_we <= !gq_rd; c_addr <= gq_a; c_din <= gq_d; c_be <= gq_b;
            gq_v <= 1'b0; g_iss = 1'b1;
            if (gq_rd) begin t_g[t_wp] <= 1'b1; t_n[t_wp] <= 8'd1; push = 1'b1; g_act <= 13'(G_HOLD); end
        end
        else if (aj_v && 9'(a_inf) + {1'b0, aj_n} <= a_win && !t_full) begin
            c_rd <= 1'b1; c_addr <= aj_addr; c_len <= aj_n; c_be <= 8'hFF;
            t_g[t_wp] <= 1'b0; t_n[t_wp] <= aj_n; push = 1'b1;
            inf_add = IW'(aj_n);
            aj_addr <= aj_addr + 29'(aj_n);
            aj_left <= aj_left - aj_n;
            if (aj_left == aj_n) aj_v <= 1'b0;
        end
        else if (a_we) begin
            aw_on <= 1'b1; aw_caddr <= a_addr + 29'(aw_done); aw_clen <= aw_n; aw_cleft <= aw_n;
        end
    end

    // ---- G: take ddr_rom's command on the mid edge (ddr_rom sees BUSY low at the next clk_sys edge)
    if (mid) begin
        g_busy <= 1'b1;
        if ((g_rd || g_we) && (!gq_v || g_iss)) begin
            gq_v <= 1'b1; gq_rd <= g_rd; gq_a <= g_addr; gq_d <= g_din; gq_b <= g_be;
            g_busy <= 1'b0;
        end
    end

    // ---- S FIFO
    if (sf_pop) sf_rp <= sf_rp + SB'(1);
    if (sr_we) begin
        if (sf_full && !sf_pop) begin                          // full: the newest write replaces the last one
            sf_a[sf_wp - SB'(1)] <= sr_addr; sf_d[sf_wp - SB'(1)] <= sr_din; sf_b[sf_wp - SB'(1)] <= sr_be;
        end
        else begin
            sf_a[sf_wp] <= sr_addr; sf_d[sf_wp] <= sr_din; sf_b[sf_wp] <= sr_be;
            sf_wp <= sf_wp + SB'(1);
        end
    end
    sf_n <= sf_n + (SB + 1)'(sr_we && !(sf_full && !sf_pop)) - (SB + 1)'(sf_pop);

    // ---- tags / in-flight count
    if (push) t_wp <= t_wp + TB'(1);
    if (pop)  t_rp <= t_rp + TB'(1);
    t_cnt <= t_cnt + (TB + 1)'(push) - (TB + 1)'(pop);
    a_inf <= a_inf + inf_add - IW'(a_beat);
    if (g_act != 13'd0 && !(gq_v && gq_rd && g_iss)) g_act <= g_act - 13'd1;
end

endmodule
