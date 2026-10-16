//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_rgb.vhd,v 1.4 2005/10/10 22:02:14 arnim Exp $
//
// RGB Generation Module of the Lady Bug Machine.
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

module ladybug_rgb (
  input  logic       clk_20mhz_i,
  input  logic       por_n_i,
  input  logic       clk_en_5mhz_i,
  input  logic [5:1] crg_i,
  input  logic [4:1] sig_i,
  output logic [1:0] rgb_r_o,
  output logic [1:0] rgb_g_o,
  output logic [1:0] rgb_b_o,
  output logic [8:1] rgb_n_o,     // Universal: latched inverted PROM byte (8203 board wires it differently)
  output logic       bg_o,        // Universal: pixel is background (no char pen, no sprite)
  // PROM download interface (replaces dn_* ports)
  input  logic       prom_wr_i,
  input  logic [4:0] prom_a_i,
  input  logic [7:0] prom_d_i
);

  logic [5:1] a_s;
  logic [8:1] rgb_s;
  logic [8:1] rgb_n_q;
  logic       bg_d, bg_q;

  // ---------------------------------------------------------------------------
  // Process addr
  //
  // Purpose:
  //   Generates the PROM address.
  //
  always_comb begin : addr
    logic sig_and_v;

    sig_and_v = sig_i[1] & sig_i[2] & sig_i[3] & sig_i[4];

    a_s[5] = crg_i[1] & sig_and_v;

    if ((~(sig_and_v & (crg_i[1] | crg_i[2]))) == 1'b0) begin
      a_s[4:1] = {crg_i[2], crg_i[5], crg_i[4], crg_i[3]};
    end
    else begin
      a_s[4:1] = sig_i;
    end
  end

  // ---------------------------------------------------------------------------
  // The RGB Conversion PROM
  // ---------------------------------------------------------------------------
  logic [7:0] rgb_prom_qa_unused_s;
  dpram_dc #(.widthad_a(5), .width_a(8)) rgb_prom_b (
    .clock_a   (clk_20mhz_i),
    .address_a (prom_a_i),
    .data_a    (prom_d_i),
    .wren_a    (prom_wr_i),
    .q_a       (rgb_prom_qa_unused_s),

    .clock_b   (clk_20mhz_i),
    .address_b (a_s),
    .data_b    (8'd0),
    .wren_b    (1'b0),
    .q_b       (rgb_s)
  );

  // ---------------------------------------------------------------------------
  // Process rgb_latch
  //
  // Purpose:
  //   Implements the output latch for the RGB values.
  //
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : rgb_latch
    if (!por_n_i) begin
      rgb_n_q <= '1;
    end
    else begin
      if (clk_en_5mhz_i == 1'b1) begin
        rgb_n_q <= ~rgb_s;
      end
    end
  end

  // Universal: background flag, delayed like the PROM read and latched with the colour
  always_ff @(posedge clk_20mhz_i) begin : bg_latch
    bg_d <= (&sig_i) & ~(crg_i[1] | crg_i[2]);
    if (clk_en_5mhz_i == 1'b1)
      bg_q <= bg_d;
  end
  assign bg_o    = bg_q;
  assign rgb_n_o = rgb_n_q;

  // ---------------------------------------------------------------------------
  // Output Mapping
  // ---------------------------------------------------------------------------
  assign rgb_r_o = {rgb_n_q[5+1], rgb_n_q[0+1]};
  assign rgb_g_o = {rgb_n_q[6+1], rgb_n_q[2+1]};
  assign rgb_b_o = {rgb_n_q[7+1], rgb_n_q[4+1]};

endmodule
