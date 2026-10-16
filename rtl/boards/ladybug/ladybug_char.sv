//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_char.vhd,v 1.18 2005/10/10 22:02:14 arnim Exp $
//
// Character Video Module of Lady Bug Machine.
//
// This unit contains most of the logic found on schematic page three.
// Excluded parts are:
//   * the 10 MHz and 5 MHz clock generation
//     moved into separate module on toplevel of Lady Bug machine
//   * the video timing circuitry
//     moved into separate module on toplevel of video unit
//   * the video MUX and RGB conversion unit
//     moved into separate module at toplevel of video unit
//
//-----------------------------------------------------------------------------
//
// Copyright (c) 2005, Arnim Laeuger (arnim.laeuger@gmx.net)
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Please report bugs to the author, but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.
//
//-----------------------------------------------------------------------------
// SystemVerilog translation 2026 (Rodimus) of the MiSTer port by Sorgelig

module ladybug_char (
  // Clock and Reset Interface ------------------------------------------------
  input  logic        clk_20mhz_i,
  input  logic        por_n_i,
  input  logic        res_n_i,
  input  logic        clk_en_5mhz_i,
  input  logic        clk_en_4mhz_i,
  // CPU Interface ------------------------------------------------------------
  input  logic        cs10_n_i,
  input  logic        cs13_n_i,
  input  logic        flip_ext_en_i,  // Universal: 8203 board, flip from the sound CPU's LS273 (bit 7)
  input  logic        flip_ext_i,
  input  logic [10:0] a_i,
  input  logic        rd_n_i,
  input  logic        wr_n_i,
  output logic        wait_n_o,
  input  logic [7:0]  d_from_cpu_i,
  output logic [7:0]  d_from_char_o,
  // RGB Video Interface ------------------------------------------------------
  input  logic [3:0]  h_i,
  input  logic [3:0]  h_t_i,
  input  logic        ha_t_rise_i,
  input  logic        hx_i,
  input  logic [3:0]  v_i,
  input  logic [3:0]  v_t_i,
  input  logic        hbl_i,
  input  logic        blank_flont_i,
  output logic        blank_o,
  output logic [5:1]  crg_o,
  output logic        vblank_o,
  output logic        hblank_o,
  // Character ROM Interface --------------------------------------------------
  output logic [11:0] rom_char_a_o,
  input  logic [15:0] rom_char_d_i,

  input  logic [15:0] hs_address,
  output logic [7:0]  hs_data_out,
  input  logic [7:0]  hs_data_in,
  input  logic        hs_write
);

  logic       flip_screen_q;

  logic       h0_s, h1_s, h2_s;
  logic [3:0] h_flip_s, h_t_flip_s;
  logic [3:0] v_flip_s, v_t_flip_s;

  logic [4:1] h_ctrl_d_s,
              h_ctrl_s,
              h_ctrl_n_s,
              h_ctrl_d_out_s,
              h_ctrl_d_n_out_s,
              h_ctrl_rise_s,
              h_ctrl_n_rise_s;

  logic       hx_ctrl_q,
              hx_ctrl_s,
              hx_ctrl_n_rise_s;
  logic       hx_ctrl_clear_q;

  logic       b1_ff_q,
              b1_ff_s,
              b1_ff_n_rise_s;

  logic       wait_q;
  logic       wait_clear_q;

  logic       cgs_q,
              cgs_s,
              cgs_rise_s;

  logic [9:0] ram_addr_s;
  logic       select_a_s;

  logic       char_ram_cs_n_s,
              char_ram_we_n_s;
  logic       col_ram_cs_n_s,
              col_ram_we_n_s;
  logic [7:0] d_from_char_ram_s;
  logic [3:0] d_from_col_ram_s;

  logic [7:0] s_q;
  logic [7:0] d_char_ram_q;
  logic [3:0] d_col_ram_q;

  logic [15:0] d_char_rom_q;
  logic       crg1_s,
              crg2_s,
              crg3_q,
              crg4_q,
              crg5_q;

  logic       hbl_q, hbl_d;

  // NOTE(translation): VHDL "integer" signal, no reset and no initial value
  // (cleared only by the hbl falling-edge detect). Kept as 32-bit int.
  int         hcnt;
  logic       vdd_s;

  assign vdd_s = 1'b1;

  // ---------------------------------------------------------------------------
  // Process flip
  //
  // Purpose:
  //   Implement the flip_screen flag.
  //
  always_ff @(posedge clk_20mhz_i or negedge res_n_i) begin : flip
    if (!res_n_i) begin
      // Actually, this asynchronous reset of the ls259 is not 100%
      // equivalent to the real behavior of this circuit. However,
      // the flip_screen latch is modelled like this for the sake of
      // simplicity. It's sufficient for the purpose here.
      flip_screen_q <= 1'b0;
    end
    else begin
      if (flip_ext_en_i) begin
        flip_screen_q <= flip_ext_i;
      end
      else if (a_i[2:0] == 3'b000 && cs10_n_i == 1'b0) begin
        flip_screen_q <= d_from_cpu_i[0];
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Process h_flip
  //
  // Purpose:
  //   Build the flipped horizontal timing signals.
  //
  always_comb begin : h_flip
    logic [8:0] a_v, b_v, sum_v;

    // calculate sum
    a_v   = {1'b0, s_q};
    b_v   = {1'b0, h_t_i, h_i};
    sum_v = a_v + b_v;

    // h0,1,2 are taken from directly from sum
    h0_s  = sum_v[0];
    h1_s  = sum_v[1];
    h2_s  = sum_v[2];

    // now flip
    for (int idx = 3; idx >= 0; idx--) begin
      h_flip_s[idx]   = flip_screen_q ^ sum_v[idx];
      h_t_flip_s[idx] = flip_screen_q ^ sum_v[idx + 4];
    end
  end

  // ---------------------------------------------------------------------------
  // Process v_flip
  //
  // Purpose:
  //   Build the flipped horizontal timing signals.
  //
  always_comb begin : v_flip
    for (int idx = 3; idx >= 0; idx--) begin
      v_flip_s[idx]   = flip_screen_q ^ v_i[idx];
      v_t_flip_s[idx] = flip_screen_q ^ v_t_i[idx];
    end
  end

  // ---------------------------------------------------------------------------
  // The Horizontal Control Signals
  // Detailed purpose/meaning is unknown.
  // ---------------------------------------------------------------------------
  assign h_ctrl_d_s[1] = ~(~h2_s & (h1_s ^ h0_s));
  assign h_ctrl_d_s[2] = hx_i;
  assign h_ctrl_d_s[3] = ~((h1_s ^ h0_s) | (~h2_s ^ h1_s));
  assign h_ctrl_d_s[4] = 1'b0;
  ttl_175 h_ctrl_b (
    .ck_i    (clk_20mhz_i),
    .ck_en_i (clk_en_5mhz_i),
    .por_n_i (por_n_i),
    .cl_n_i  (vdd_s),
    .d_i     (h_ctrl_d_s),
    .q_o     (h_ctrl_s),
    .q_n_o   (h_ctrl_n_s),
    .d_o     (h_ctrl_d_out_s),
    .d_n_o   (h_ctrl_d_n_out_s)
  );
  assign h_ctrl_rise_s   = ~h_ctrl_s & h_ctrl_d_out_s;
  assign h_ctrl_n_rise_s = h_ctrl_s & ~h_ctrl_d_out_s;

  // ---------------------------------------------------------------------------
  // Process ctrl_seq
  //
  // Purpose:
  //   Implemente the various sequential elements for horizontal control.
  //
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : ctrl_seq
    if (!por_n_i) begin
      hx_ctrl_q        <= 1'b0;
      hx_ctrl_clear_q  <= 1'b0;
      b1_ff_q          <= 1'b0;
      wait_q           <= 1'b0;
      wait_clear_q     <= 1'b0;
      cgs_q            <= 1'b0;
    end
    else begin
      // the HX control flip-flop
      hx_ctrl_q <= hx_ctrl_s;

      // the clear counterpart of hx_ctrl_q
      if (h_ctrl_s[2] == 1'b0) begin
        // pseudo-asynchronous clear
        hx_ctrl_clear_q <= 1'b0;
      end
      else if (hx_ctrl_n_rise_s == 1'b1) begin
        // rising edge indicator acts as clock enable instead of clock
        hx_ctrl_clear_q <= 1'b1;
      end

      // the mysterious B1 flip-flop
      b1_ff_q <= b1_ff_s;

      // the CGS rising edge indicator support flip-flops
      cgs_q <= cgs_s;

      // the WAIT flip-flop
      if (wait_clear_q == 1'b1) begin
        // pseudo-asynchronous clear
        wait_q <= 1'b0;
      end
      else if (cgs_rise_s == 1'b1) begin
        // rising edge indicator acts as clock enable instead of clock
        wait_q <= 1'b1;
      end

      // the clear counterpart of wait_q
      if (clk_en_4mhz_i == 1'b1) begin
        wait_clear_q <= wait_q & (h_ctrl_s[3] & (b1_ff_q | hx_ctrl_q));
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Process ctrl_comp
  //
  // Purpose:
  //   Implements the combination logic for the horizontal control
  //   elements.
  //
  always_comb begin : ctrl_comp
    // default assignments
    hx_ctrl_s        = hx_ctrl_q;
    hx_ctrl_n_rise_s = 1'b0;
    b1_ff_s          = b1_ff_q;
    b1_ff_n_rise_s   = 1'b0;
    cgs_s            = cgs_q;
    cgs_rise_s       = 1'b0;

    // the HX control flip-flop -----------------------------------------------
    if (hx_ctrl_clear_q == 1'b1) begin
      // pseudo-asynchronous clear
      hx_ctrl_s          = 1'b0;

      if ((~hx_ctrl_q) == 1'b0) begin
        // detct rising edge of inverted ouput
        hx_ctrl_n_rise_s = 1'b1;
      end
    end
    else if (h_ctrl_rise_s[1] == 1'b1) begin
      // rising edge indicator acts as clock enable instead of clock
      if (hx_i == 1'b1) begin
        // toggle FF
        hx_ctrl_s        = ~hx_ctrl_q;

        if ((~hx_ctrl_q) == 1'b0) begin
          // detct rising edge of inverted ouput
          hx_ctrl_n_rise_s = 1'b1;
        end
      end
    end

    // the mysterious B1 flip-flop --------------------------------------------
    if (hx_ctrl_q == 1'b1) begin
      // pseudo-asynchronous clear
      b1_ff_s = 1'b0;

      if ((~b1_ff_q) == 1'b0) begin
        // detct rising edge of inverted ouput
        b1_ff_n_rise_s = 1'b1;
      end
    end
    else if (h_ctrl_n_rise_s[3] == 1'b1) begin
      // rising edge indicator acts as clock enable instead of clock
      b1_ff_s = 1'b1;
    end

    // the CGS rising edge indicator support flip-flop ------------------------
    cgs_s      = ~cs13_n_i;
    cgs_rise_s = ~cgs_q & ~cs13_n_i;
  end

  // ---------------------------------------------------------------------------
  // Process ram_addr
  //
  // Purpose:
  //   Multiplexes the CPU address bus and the h+v timing control signals to
  //   form the RAM address bus.
  //
  always_comb begin : ram_addr
    logic       a_v, b_v, g_n_v;
    logic [1:0] vec_v;

    // default assignment
    ram_addr_s = '0;

    // logic that drives A input of IC L4 and K4
    a_v = ~(h_ctrl_n_s[1] & (b1_ff_q | hx_ctrl_q));
    // logic that drives B input of IC L4 and K4
    b_v = hx_ctrl_q;
    // logic that drives /G input of IC J4
    g_n_v = hx_ctrl_q & (h_ctrl_n_s[1] & (b1_ff_q | hx_ctrl_q));

    // IC L4 and K4: Dual 4:1 Multiplexer -------------------------------------
    vec_v = {b_v, a_v};
    case (vec_v)
      2'b00: begin
        ram_addr_s[0] = h_flip_s  [3];
        ram_addr_s[1] = h_t_flip_s[0];
        //
        ram_addr_s[2] = h_t_flip_s[1];
        ram_addr_s[3] = h_t_flip_s[2];
      end
      2'b01: begin
        ram_addr_s[0] = a_i[0];
        ram_addr_s[1] = a_i[1];
        //
        ram_addr_s[2] = a_i[2];
        ram_addr_s[3] = a_i[3];
      end
      2'b10: begin
        ram_addr_s[0] = v_t_flip_s[1];
        ram_addr_s[1] = v_t_flip_s[2];
        //
        ram_addr_s[2] = v_t_flip_s[3];
        ram_addr_s[3] = 1'b0;
      end
      2'b11: begin
        ram_addr_s[0] = a_i[0];
        ram_addr_s[1] = a_i[1];
        //
        ram_addr_s[2] = a_i[2];
        ram_addr_s[3] = a_i[3];
      end
      default: ;
    endcase

    // IC J4 and H4: Quad 2:1 Multiplexer -------------------------------------
    case (a_v)
      1'b0: begin
        ram_addr_s[4] = h_t_flip_s[3] & ~g_n_v;
        ram_addr_s[7] = v_t_flip_s[1] & ~g_n_v;
        ram_addr_s[8] = v_t_flip_s[2] & ~g_n_v;
        ram_addr_s[9] = v_t_flip_s[3] & ~g_n_v;
        //
        ram_addr_s[5] = v_flip_s  [3];
        ram_addr_s[6] = v_t_flip_s[0];
      end
      1'b1: begin
        ram_addr_s[4] = a_i[4]      & ~g_n_v;
        ram_addr_s[7] = a_i[7]      & ~g_n_v;
        ram_addr_s[8] = a_i[8]      & ~g_n_v;
        ram_addr_s[9] = a_i[9]      & ~g_n_v;
        //
        ram_addr_s[5] = a_i[5];
        ram_addr_s[6] = a_i[6];
      end
      default: ;
    endcase

    select_a_s = a_v;
  end

  // ---------------------------------------------------------------------------
  // Process ram_ctrl
  //
  // Purpose:
  //   Generate the control signals for the character and color RAMs.
  //   This comprises:
  //     * reading RAMs while the beam sweeps the screen
  //     * reading RAMs to the CPU
  //     * writing RAMs from the CPU
  //
  always_comb begin : ram_ctrl
    logic       cpu_read_char_ram_v;
    logic       cpu_write_char_ram_v;
    logic       cpu_read_col_ram_v;
    logic       cpu_write_col_ram_v;
    logic [2:0] vec_v;

    // default assignments
    char_ram_cs_n_s      = 1'b1;
    char_ram_we_n_s      = 1'b1;
    col_ram_cs_n_s       = 1'b1;
    col_ram_we_n_s       = 1'b1;
    d_from_char_o        = '1;
    cpu_read_char_ram_v  = 1'b0;
    cpu_write_char_ram_v = 1'b0;
    cpu_read_col_ram_v   = 1'b0;
    cpu_write_col_ram_v  = 1'b0;
    vec_v                = '0;

    // detect and decode CPU access
    // Gating the RAM access here with clk_en_4mhz_i causes very short data output.
    //if clk_en_4mhz_i = '1' and          -- operate RAMs with CPU clock
    if ((~cs13_n_i & select_a_s & ~wait_q) == 1'b1) begin
      vec_v = {a_i[10], rd_n_i, wr_n_i};
      case (vec_v)
        3'b001: cpu_read_char_ram_v  = 1'b1;
        3'b010: cpu_write_char_ram_v = 1'b1;
        3'b101: cpu_read_col_ram_v   = 1'b1;
        3'b110: cpu_write_col_ram_v  = 1'b1;
        default: ;
      endcase
    end

    // now we are prepared to generate the /CS and /WE signals for the RAMs
    if (select_a_s == 1'b0 ||
        cpu_read_char_ram_v || cpu_write_char_ram_v) begin
      char_ram_cs_n_s = 1'b0;
    end
    if (select_a_s == 1'b0 ||
        cpu_read_col_ram_v || cpu_write_col_ram_v) begin
      col_ram_cs_n_s  = 1'b0;
    end
    if (cpu_write_char_ram_v) begin
      char_ram_we_n_s = 1'b0;
    end
    if (cpu_write_col_ram_v) begin
      col_ram_we_n_s  = 1'b0;
    end

    // and we can multiplex the data bus towards the CPU
    if (cpu_read_char_ram_v) begin
      d_from_char_o = d_from_char_ram_s;
    end
    else if (cpu_read_col_ram_v) begin
      d_from_char_o[3:0] = d_from_col_ram_s;
    end
  end

  // ---------------------------------------------------------------------------
  // The character RAM
  // ---------------------------------------------------------------------------
  ladybug_char_ram char_ram_b (
    .clk1_i    (clk_20mhz_i),
    .clk_en1_i (clk_en_4mhz_i),
    .a1_i      (ram_addr_s),
    .cs1_n_i   (char_ram_cs_n_s),
    .we1_n_i   (char_ram_we_n_s),
    .d1_i      (d_from_cpu_i),
    .d1_o      (d_from_char_ram_s),

    .clk2_i    (clk_20mhz_i),
    .clk_en2_i (1'b1),
    .a2_i      (hs_address[9:0]),
    .cs2_n_i   (1'b0),
    .we2_n_i   (~hs_write),
    .d2_i      (hs_data_in),
    .d2_o      (hs_data_out)
  );
  // ---------------------------------------------------------------------------
  // The color RAM
  // ---------------------------------------------------------------------------
  ladybug_char_col_ram col_ram_b (
    .clk_i    (clk_20mhz_i),
    .clk_en_i (clk_en_4mhz_i),
    .a_i      (ram_addr_s),
    .cs_n_i   (col_ram_cs_n_s),
    .we_n_i   (col_ram_we_n_s),
    .d_i      (d_from_cpu_i[3:0]),
    .d_o      (d_from_col_ram_s)
  );

  // ---------------------------------------------------------------------------
  // Process ram_d_seq
  //
  // Purpose:
  //   Implements three latch banks that save the output of the character
  //   and color RAMs.
  //
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : ram_d_seq
    logic complex_rising_edge_v;

    if (!por_n_i) begin
      s_q          <= '0;
      d_char_ram_q <= '0;
      d_col_ram_q  <= '0;
    end
    else begin
      // latch data from the character RAM to form input for h_flip -----------
      if (hx_ctrl_n_rise_s == 1'b1) begin
        s_q <= d_from_char_ram_s;
      end

      // latch data from the character RAM for ROM address generation ---------
      // there are three sources for a rising edge:
      //   1) falling edge of h_ctrl_n_s(1)
      //      => equivalen to rising edge of h_ctrl_s(1)
      //   2) rising edge of hx_ctrl_n_q
      //   3) rising edge of b1_ff_n
      // For each source, the two have to be in a defined state to let
      // the edge propage to the latches.
      complex_rising_edge_v = ((h_ctrl_rise_s[1] &
                                (b1_ff_q | hx_ctrl_q))              |
                               (hx_ctrl_n_rise_s &
                                (~b1_ff_q & ~h_ctrl_n_s[1]))        |
                               (b1_ff_n_rise_s &
                                (~hx_ctrl_q & ~h_ctrl_s[1]))) == 1'b1;
      if (complex_rising_edge_v) begin
        d_char_ram_q <= d_from_char_ram_s;
        d_col_ram_q  <= d_from_col_ram_s;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Process latch_rom_d
  //
  // Purpose:
  //   Latch the output of the character ROM.
  //
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : latch_rom_d
    if (!por_n_i) begin
      d_char_rom_q  <= '0;
      crg3_q        <= 1'b0;
      crg4_q        <= 1'b0;
      crg5_q        <= 1'b0;
    end
    else begin
      if ((clk_en_5mhz_i &
           h2_s & h1_s & h0_s) == 1'b1) begin
        d_char_rom_q <= rom_char_d_i;
        crg3_q       <= d_col_ram_q[0];
        crg4_q       <= d_col_ram_q[1];
        crg5_q       <= d_col_ram_q[2];
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Process hbl_seq
  //
  // Purpose:
  //   Implements the flip-flop that latches HBL.
  //
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : hbl_seq
    if (!por_n_i) begin
      hbl_q <= 1'b0;
    end
    else begin
      if (clk_en_5mhz_i == 1'b1) begin
        if (hcnt != 255) begin
          hcnt <= hcnt + 1;
        end
      end
      if (ha_t_rise_i == 1'b1) begin
        hbl_q <= hbl_i;
        if (hbl_q == 1'b1 && hbl_i == 1'b0) begin
          // last assignment wins (as in VHDL): overrides hcnt <= hcnt + 1
          hcnt <= 0;
        end
      end
    end
  end

  // NOTE(translation): unnamed process in VHDL (hblank/vblank generation, no reset)
  always_ff @(posedge clk_20mhz_i) begin : blank_seq
    if (clk_en_5mhz_i == 1'b1) begin
      hbl_d <= hbl_q;

      if (hcnt < 240) begin
        hblank_o <= 1'b0;
      end
      else begin
        hblank_o <= 1'b1;
      end

      if (hbl_d == 1'b0 && hbl_q == 1'b1) begin
        vblank_o <= ~blank_flont_i;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Process crg_mux
  //
  // Purpose:
  //   Multiplexes the latched character ROM data to CRG1 and CRG2.
  //
  always_comb begin : crg_mux
    logic       blank_v;
    logic [2:0] idx_v;

    blank_v = ~(blank_flont_i & ~hbl_q);
    idx_v   = h_flip_s[2:0];

    if (blank_v == 1'b0) begin
      crg1_s = d_char_rom_q[{1'b0, idx_v}];
      crg2_s = d_char_rom_q[{1'b1, idx_v}];
    end
    else begin
      crg1_s = 1'b0;
      crg2_s = 1'b0;
    end

    blank_o = blank_v;
  end

  // ---------------------------------------------------------------------------
  // Output Mapping
  // ---------------------------------------------------------------------------
  assign wait_n_o = ~wait_q;
  assign crg_o[5] = crg5_q;
  assign crg_o[4] = crg4_q;
  assign crg_o[3] = crg3_q;
  assign crg_o[2] = crg2_s;
  assign crg_o[1] = crg1_s;
  assign rom_char_a_o[2:0]   = v_flip_s[2:0];
  assign rom_char_a_o[10:3]  = d_char_ram_q;
  assign rom_char_a_o[11]    = d_col_ram_q[3];

endmodule
