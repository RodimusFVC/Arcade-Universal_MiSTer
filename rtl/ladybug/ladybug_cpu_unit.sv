//============================================================================
//
//  Lady Bug CPU unit (Universal 8106-A2 CPU board)
//  Copyright (C) 2026 Rodimus
//
//  Structure from Arnim Laeuger's ladybug_cpu_unit.vhd (FPGA Lady Bug, 2005)
//  and its MiSTer port by Sorgelig. The Z80 is T80pa with real rising/falling
//  half-cycles at 4 MHz (the old port used a patched T80a whose half-cycle
//  was one 20 MHz clock).
//
//  Dorodon: opcode fetches (M1) go through the bp3/bp4 PROM pair (MAME
//  init_dorodon); every other set fetches opcodes undecoded.
//
//  board_8203_i (Space Raider / Mrs. Dynamite, MAME sraider.cpp cpu1_map):
//  8000-9FFF I/O (x0-x3 IN0/IN1/DSW0/DSW1, x5 PAL protection 0x3E, x6/x7 sound
//  latches low/high), no flip latch / sound chips at A000-CFFF, IRQ on vblank
//  held until acknowledged (MAME irq0_line_hold), no coin chutes.
//
//============================================================================

module ladybug_cpu_unit
(
    output logic [13:0] z80_o,          // shared T80 (rtl/z80_socket.sv)
    input  logic [29:0] z80_i,
    input  logic        clk_20mhz_i,
    input  logic        cpu_cen_p_i,
    input  logic        cpu_cen_n_i,
    input  logic        res_n_i,
    input  logic        pause_i,
    input  logic        decrypt_en_i,
    input  logic        board_8203_i,
    input  logic        vblank_i,
    output logic  [7:0] snd_latch_lo_o,
    output logic  [7:0] snd_latch_hi_o,

    output logic [14:0] rom_cpu_a_o,
    input  logic  [7:0] rom_cpu_d_i,
    output logic  [7:0] dec_a_o,        // decryption PROM address = fetched byte
    input  logic  [7:0] dec_d_i,

    input  logic        sound_wait_n_i,
    input  logic        wait_n_i,
    input  logic        right_chute_i,  // NMI (MAME coin 1)
    input  logic        left_chute_i,   // IRQ (MAME coin 2)
    input  logic  [7:0] gpio_in0_i,
    input  logic  [7:0] gpio_in1_i,
    input  logic  [7:0] gpio_in2_i,
    input  logic  [7:0] gpio_in3_i,
    input  logic  [7:0] gpio_extra_i,

    output logic [10:0] a_o,
    input  logic  [7:0] d_to_cpu_i,
    output logic  [7:0] d_from_cpu_o,
    output logic        rd_n_o,
    output logic        wr_n_o,
    output logic        cs7_n_o,
    output logic        cs10_n_o,
    output logic        cs11_n_o,
    output logic        cs12_n_o,
    output logic        cs13_n_o,

    input  logic [15:0] hs_address,
    output logic  [7:0] hs_data_out,
    input  logic  [7:0] hs_data_in,
    input  logic        hs_write
);

logic        wait_n_s;
logic        int_n_s, nmi_n_s;
logic        chute_int_n_s, chute_nmi_n_s;
logic        mreq_n_s, iorq_n_s, rd_n_s, wr_n_s, rfsh_n_s, m1_n_s;
logic [15:0] a_s;
logic  [7:0] d_to_cpu_s, d_from_cpu_s;
logic  [7:0] d_rom_mux_s, d_from_rom_s, d_from_ram_s, d_from_gpio_s;
logic [15:0] cs_n_s;
logic        ram_cpu_cs_n_s;

assign wait_n_s = sound_wait_n_i & wait_n_i;

z80_socket T80pa_b
(
    .RESET_n   (res_n_i),
    .CLK       (clk_20mhz_i),
    .CEN_p     (cpu_cen_p_i & ~pause_i),
    .CEN_n     (cpu_cen_n_i & ~pause_i),
    .WAIT_n    (wait_n_s),
    .INT_n     (int_n_s),
    .NMI_n     (nmi_n_s),
    .BUSRQ_n   (1'b1),
    .M1_n      (m1_n_s),
    .MREQ_n    (mreq_n_s),
    .IORQ_n    (iorq_n_s),
    .RD_n      (rd_n_s),
    .WR_n      (wr_n_s),
    .RFSH_n    (rfsh_n_s),
    .HALT_n    (),
    .BUSAK_n   (),
    .OUT0      (1'b0),
    .A         (a_s),
    .DI        (d_to_cpu_s),
    .DO        (d_from_cpu_s),
    .R800_mode (1'b0),
    .REG       (),
    .DIRSet    (1'b0),
    .DIR       (212'd0),
    .to_cpu    (z80_o),
    .from_cpu  (z80_i)
);

assign d_from_cpu_o = d_from_cpu_s;

ladybug_cpu_ram cpu_ram_b
(
    .clk1_i    (clk_20mhz_i),
    .clk_en1_i (cpu_cen_p_i),
    .a1_i      (a_s[11:0]),
    .cs1_n_i   (cs_n_s[6]),
    .we1_n_i   (wr_n_s),
    .d1_i      (d_from_cpu_s),
    .d1_o      (d_from_ram_s),
    .clk2_i    (clk_20mhz_i),
    .clk_en2_i (1'b1),
    .a2_i      (hs_address[11:0]),
    .cs2_n_i   (1'b0),
    .we2_n_i   (~hs_write),
    .d2_i      (hs_data_in),
    .d2_o      (hs_data_out)
);

ladybug_addr_dec addr_dec_b
(
    .clk_20mhz_i    (clk_20mhz_i),
    .res_n_i        (res_n_i),
    .a_i            (a_s[15:12]),
    .rd_n_i         (rd_n_s),
    .wr_n_i         (wr_n_s),
    .mreq_n_i       (mreq_n_s),
    .rfsh_n_i       (rfsh_n_s),
    .cs_n_o         (cs_n_s),
    .ram_cpu_cs_n_o (ram_cpu_cs_n_s)
);

ladybug_gpio gpio_b
(
    .a_i          (a_s[1:0]),
    .cs_in_n_i    (cs_n_s[9]),
    .cs_extra_n_i (cs_n_s[14]),
    .in0_i        (gpio_in0_i),
    .in1_i        (gpio_in1_i),
    .in2_i        (gpio_in2_i),
    .in3_i        (gpio_in3_i),
    .extra_i      (gpio_extra_i),
    .d_o          (d_from_gpio_s)
);

ladybug_chutes coin_chutes_b
(
    .clk_20mhz_i   (clk_20mhz_i),
    .res_n_i       (res_n_i),
    .right_chute_i (right_chute_i),
    .left_chute_i  (left_chute_i),
    .cs8_n_i       (cs_n_s[8]),
    .nmi_n_o       (chute_nmi_n_s),
    .int_n_o       (chute_int_n_s)
);

// 8203 board: vblank IRQ, cleared by the interrupt acknowledge cycle
logic vbl_d = 1'b0, vbl_int_n = 1'b1;
always_ff @(posedge clk_20mhz_i) begin
    vbl_d <= vblank_i;
    if (!res_n_i)                     vbl_int_n <= 1'b1;
    else if (!m1_n_s && !iorq_n_s)    vbl_int_n <= 1'b1;
    else if (vblank_i && !vbl_d)      vbl_int_n <= 1'b0;
end

assign int_n_s = board_8203_i ? vbl_int_n : chute_int_n_s;
assign nmi_n_s = board_8203_i ? 1'b1      : chute_nmi_n_s;

// 8203 board I/O block at 8000-9FFF
wire io8203_s = board_8203_i && !(cs_n_s[8] && cs_n_s[9]);
logic [7:0] d_from_io8203_s;
always_comb begin
    d_from_io8203_s = 8'hFF;
    if (io8203_s && !rd_n_s)
        case (a_s[2:0])
            3'd0: d_from_io8203_s = gpio_in0_i;
            3'd1: d_from_io8203_s = gpio_in1_i;
            3'd2: d_from_io8203_s = gpio_in2_i;
            3'd3: d_from_io8203_s = gpio_in3_i;
            3'd5: d_from_io8203_s = 8'h3E;          // PAL K2: must read X011111X (MAME protection_r)
            default: ;
        endcase
end

always_ff @(posedge clk_20mhz_i) begin
    if (!res_n_i) begin
        snd_latch_lo_o <= 8'h00;
        snd_latch_hi_o <= 8'h00;
    end
    else if (io8203_s && !wr_n_s) begin
        if (a_s[2:0] == 3'd6) snd_latch_lo_o <= d_from_cpu_s;
        if (a_s[2:0] == 3'd7) snd_latch_hi_o <= d_from_cpu_s;
    end
end

// Opcode decryption on read (Dorodon only)
assign dec_a_o      = rom_cpu_d_i;
assign d_rom_mux_s  = (decrypt_en_i && !m1_n_s) ? dec_d_i : rom_cpu_d_i;
assign d_from_rom_s = (cs_n_s[5:0] != 6'b111111) ? d_rom_mux_s : 8'hFF;

assign d_to_cpu_s = d_to_cpu_i & d_from_rom_s & d_from_ram_s & (board_8203_i ? d_from_io8203_s : d_from_gpio_s);

assign a_o         = a_s[10:0];
assign rom_cpu_a_o = a_s[14:0];
assign rd_n_o      = rd_n_s;
assign wr_n_o      = wr_n_s;
assign cs7_n_o     = cs_n_s[7];
assign cs10_n_o    = cs_n_s[10] | board_8203_i;
assign cs11_n_o    = cs_n_s[11] | board_8203_i;
assign cs12_n_o    = cs_n_s[12] | board_8203_i;
assign cs13_n_o    = cs_n_s[13];

endmodule
