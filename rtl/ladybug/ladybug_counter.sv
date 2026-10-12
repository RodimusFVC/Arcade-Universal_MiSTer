//-----------------------------------------------------------------------------
//
// Synchronous 8-Bit Binary Counter with preset.
//
// $Id: ladybug_counter.vhd,v 1.9 2005/10/10 21:59:13 arnim Exp $
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

// NOTE(translation): VHDL entity name was "counter"; renamed to ladybug_counter.
module ladybug_counter (
  input  logic       ck_i,
  input  logic       ck_en_i,
  input  logic       reset_n_i,
  input  logic       load_i,
  input  logic [7:0] preset_i,
  output logic [7:0] q_o,
  output logic [7:0] rise_q_o,
  output logic [7:0] d_o,
  output logic       co_o
);

  logic [7:0] cnt_q;
  logic [7:0] cnt_s;

  always_ff @(posedge ck_i or negedge reset_n_i) begin : seq
    if (!reset_n_i)
      cnt_q <= '0;
    else
      cnt_q <= cnt_s;
  end

  always_comb begin : adder
    cnt_s = cnt_q;

    if (ck_en_i == 1'b1) begin
      if (load_i == 1'b1)
        cnt_s = preset_i;
      else
        cnt_s = cnt_q + 8'd1;
    end
  end

  assign co_o     = (cnt_q == 8'hFF) ? 1'b1 : 1'b0;
  assign rise_q_o = cnt_s & ~cnt_q;
  assign q_o      = cnt_q;
  assign d_o      = cnt_s;
endmodule
