//-----------------------------------------------------------------------------
//
// TTL 74LS393 - Dual 4-Bit Binary Counter
//
// $Id: ttl_393.vhd,v 1.3 2005/10/10 21:59:13 arnim Exp $
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

module ttl_393 (
  input  logic       ck_i,
  input  logic [2:1] ck_en_i,
  input  logic       por_n_i,
  input  logic [2:1] cl_i,
  output logic [2:1] qa_o,
  output logic [2:1] qb_o,
  output logic [2:1] qc_o,
  output logic [2:1] qd_o,
  output logic [2:1] da_o,
  output logic [2:1] db_o,
  output logic [2:1] dc_o,
  output logic [2:1] dd_o
);

  logic [2:1][3:0] cnt_q;
  logic [2:1][4:0] cnt_s;

  // ---------------------------------------------------------------------------
  // Process seq
  //
  // Purpose:
  //   Implements the flip-flops.
  //
  //   Note: We assume that the sequential elements power-up to the same state
  //         as forced into by cl_i.
  //
  always_ff @(posedge ck_i or negedge por_n_i) begin : seq
    if (!por_n_i) begin
      cnt_q[1] <= '0;
      cnt_q[2] <= '0;
    end
    else begin
      cnt_q[1] <= cnt_s[1][3:0];
      cnt_q[2] <= cnt_s[2][3:0];
    end
  end

  // ---------------------------------------------------------------------------
  // Process adder
  //
  // Purpose:
  //   Implements the adder.
  //
  always_comb begin : adder
    for (int idx = 2; idx >= 1; idx--) begin
      cnt_s[idx] = {1'b0, cnt_q[idx]};

      if (cl_i[idx] == 1'b0) begin
        if (ck_en_i[idx] == 1'b1) begin
          // increment upon enable
          cnt_s[idx] = {1'b0, cnt_q[idx]} + 5'd1;
        end
      end
      else begin
        // pseudo-asynchronous clear
        cnt_s[idx] = '0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Output Mapping
  // ---------------------------------------------------------------------------
  assign qa_o[1] = cnt_q[1][0];
  assign qb_o[1] = cnt_q[1][1];
  assign qc_o[1] = cnt_q[1][2];
  assign qd_o[1] = cnt_q[1][3];
  assign qa_o[2] = cnt_q[2][0];
  assign qb_o[2] = cnt_q[2][1];
  assign qc_o[2] = cnt_q[2][2];
  assign qd_o[2] = cnt_q[2][3];
  assign da_o[1] = cnt_s[1][0];
  assign db_o[1] = cnt_s[1][1];
  assign dc_o[1] = cnt_s[1][2];
  assign dd_o[1] = cnt_s[1][3];
  assign da_o[2] = cnt_s[2][0];
  assign db_o[2] = cnt_s[2][1];
  assign dc_o[2] = cnt_s[2][2];
  assign dd_o[2] = cnt_s[2][3];

endmodule
