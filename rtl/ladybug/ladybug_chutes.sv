//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_chutes.vhd,v 1.4 2005/10/10 21:21:20 arnim Exp $
//
// Pulse shaping for the two chute inputs.
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

module ladybug_chutes (
  input  logic clk_20mhz_i,
  input  logic res_n_i,
  input  logic right_chute_i,
  input  logic left_chute_i,
  input  logic cs8_n_i,
  output logic nmi_n_o,
  output logic int_n_o
);

  logic right_chute_s, left_chute_s;
  logic left_chute_q;

  // ---------------------------------------------------------------------------
  // Pulse shaper for Right Chute
  // ---------------------------------------------------------------------------
  ladybug_chute right_chute_b (
    .clk_20mhz_i (clk_20mhz_i),
    .res_n_i     (res_n_i),
    .chute_i     (right_chute_i),
    .chute_o     (right_chute_s)
  );

  // ---------------------------------------------------------------------------
  // Pulse shaper for Left Chute
  // ---------------------------------------------------------------------------
  ladybug_chute left_chute_b (
    .clk_20mhz_i (clk_20mhz_i),
    .res_n_i     (res_n_i),
    .chute_i     (left_chute_i),
    .chute_o     (left_chute_s)
  );

  // ---------------------------------------------------------------------------
  // Process left_edge
  //
  // Purpose:
  //   Implement the edge detector for the left chute.
  //   Only a rising edge of the filtered chute input can trigger a new
  //   interrupt to the CPU.
  //
  always_ff @(posedge clk_20mhz_i or negedge res_n_i) begin : left_edge
    if (!res_n_i) begin
      left_chute_q <= 1'b0;
      int_n_o      <= 1'b1;
    end
    else begin
      left_chute_q <= left_chute_s;

      if (cs8_n_i == 1'b0) begin
        // synchronous set, has priority over data path
        int_n_o <= 1'b1;
      end
      // edge detector
      else if (left_chute_s == 1'b1 && left_chute_q == 1'b0) begin
        int_n_o <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Output Mapping
  // ---------------------------------------------------------------------------
  assign nmi_n_o = ~right_chute_s;

endmodule
