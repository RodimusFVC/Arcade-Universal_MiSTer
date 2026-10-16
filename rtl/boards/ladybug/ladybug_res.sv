//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_res.vhd,v 1.8 2005/10/10 20:52:04 arnim Exp $
//
// Reset generator for the Lady Bug machine.
//
// This module generates a reset signal for the whole system synchronous to
// the main clock.
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

module ladybug_res (
  input  logic clk_20mhz_i,
  input  logic ext_res_n_i,
  output logic res_n_o,
  output logic por_n_o
);

  // 4.7e-2 s = 1 / 20,000,000 Hz * 940000
  localparam logic [19:0] res_delay_c = 20'd940000;

  logic [1:0]  res_sync_n_q;

  logic [19:0] res_delay_q;
  logic        res_n_q;

  logic [1:0]  por_cnt_q = 2'b00;
  logic        por_n_q   = 1'b0;

  assign por_n_o = por_n_q;
  assign res_n_o = res_n_q;

  // ---------------------------------------------------------------------------
  // Process por_cnt
  //
  // Purpose:
  //   Generate a power-on reset for 4 clock cycles.
  //
  always_ff @(posedge clk_20mhz_i) begin : por_cnt
    if (por_cnt_q == 2'b11)
      por_n_q   <= 1'b1;
    else
      por_cnt_q <= por_cnt_q + 2'd1;
  end

  // ---------------------------------------------------------------------------
  // Process res_sync
  //
  // Purpose:
  //   Synchronize asynchronous external reset to main 20 MHz clock.
  //
  always_ff @(posedge clk_20mhz_i or negedge ext_res_n_i or negedge por_n_q) begin : res_sync
    if (ext_res_n_i == 1'b0 || por_n_q == 1'b0) begin
      res_sync_n_q <= '0;
    end
    else begin
      res_sync_n_q[0] <= 1'b1;
      res_sync_n_q[1] <= res_sync_n_q[0];
    end
  end

  // ---------------------------------------------------------------------------
  // Process res_delay
  //
  // Purpose:
  //   Delay reset event (external or power-on) by 4.7e-2 s.
  //   Reset delay is taken from Lady Bug reset circuit using NE555.
  //   This duration might be too long for the actual requirements of the
  //   FPGA circuit.
  //
  always_ff @(posedge clk_20mhz_i or negedge res_sync_n_q[1]) begin : res_delay
    if (res_sync_n_q[1] == 1'b0) begin
      res_delay_q <= '0;
      res_n_q     <= 1'b0;
    end
    else begin
      if (res_delay_q == res_delay_c)
        res_n_q     <= 1'b1;
      else
        res_delay_q <= res_delay_q + 20'd1;
    end
  end

endmodule
