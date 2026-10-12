//-----------------------------------------------------------------------------
//
// TTL 74175 - Quad D-Type Flip-Flops with Clear
//
// $Id: ttl_175.vhd,v 1.5 2005/10/10 21:59:13 arnim Exp $
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

module ttl_175 (
  input  logic       ck_i,
  input  logic       ck_en_i,
  input  logic       por_n_i,
  input  logic       cl_n_i,
  input  logic [4:1] d_i,
  output logic [4:1] q_o,
  output logic [4:1] q_n_o,
  output logic [4:1] d_o,
  output logic [4:1] d_n_o
);

  logic [4:1] flops_q;
  logic [4:1] flops_s;

  // ---------------------------------------------------------------------------
  // Process flops
  //
  // Purpose:
  //   Implement the sequential elements.
  //
  //   Note: We assume that the sequential elements power-up to the same state
  //         as forced into by cl_n_i.
  //
  always_ff @(posedge ck_i or negedge por_n_i) begin : flops
    if (!por_n_i)
      flops_q <= '0;
    else
      flops_q <= flops_s;
  end

  // ---------------------------------------------------------------------------
  // Process comb
  //
  // Purpose:
  //   Implements the combinational logic.
  //
  always_comb begin : comb
    // default assignments
    flops_s = flops_q;

    if (cl_n_i == 1'b1) begin
      if (ck_en_i == 1'b1)
        flops_s = d_i;
    end
    else begin
      // pseudo-asynchronous clear
      flops_s = '0;
    end
  end

  // ---------------------------------------------------------------------------
  // Output Mapping
  // ---------------------------------------------------------------------------
  assign q_o   = flops_q;
  assign q_n_o = ~flops_q;
  assign d_o   = flops_s;
  assign d_n_o = ~flops_s;

endmodule
