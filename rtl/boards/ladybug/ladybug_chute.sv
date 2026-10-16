//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_chute.vhd,v 1.3 2005/10/10 21:21:20 arnim Exp $
//
// Pulse shaper for a chute input.
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

module ladybug_chute (
  input  logic clk_20mhz_i,
  input  logic res_n_i,
  input  logic chute_i,
  output logic chute_o
);

  // 2.35e-2 s = 1 / 20,000,000 Hz * 470000
  localparam logic [18:0] chute_delay_c = 19'd470000;

  logic [18:0] chute_cnt_q;

  logic [1:0]  chute_sync_q;

  // ---------------------------------------------------------------------------
  // Process sync
  //
  // Purpose:
  //  Synchronize the asynchronous chute input.
  //
  always_ff @(posedge clk_20mhz_i or negedge res_n_i) begin : sync
    if (!res_n_i) begin
      chute_sync_q <= '0;
    end
    else begin
      chute_sync_q[0] <= chute_i;
      chute_sync_q[1] <= chute_sync_q[0];
    end
  end

  // ---------------------------------------------------------------------------
  // Process cnt
  //
  // Purpose:
  //  Count the required number of 20 MHz clock cycles before emitting
  //  chute event. This is a low pass filter for the rising edge of chute_i.
  //
  always_ff @(posedge clk_20mhz_i or negedge res_n_i) begin : cnt
    if (!res_n_i) begin
      chute_cnt_q <= '0;
      chute_o     <= 1'b0;
    end
    else begin
      if (chute_sync_q[1] == 1'b1) begin
        if (chute_cnt_q == chute_delay_c)
          chute_o     <= 1'b1;
        else
          chute_cnt_q <= chute_cnt_q + 19'd1;
      end
      else begin
        // reset counter when chute input goes back to 0
        chute_cnt_q   <= '0;
        chute_o       <= 1'b0;
      end
    end
  end

endmodule
