//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_addr_dec.vhd,v 1.10 2005/12/10 14:51:46 arnim Exp $
//
// Address decoder of the CPU Unit.
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

module ladybug_addr_dec (
  input  logic        clk_20mhz_i,
  input  logic        res_n_i,
  input  logic [15:12] a_i,
  input  logic        rd_n_i,
  input  logic        wr_n_i,
  input  logic        mreq_n_i,
  input  logic        rfsh_n_i,
  output logic [15:0] cs_n_o,
  output logic        ram_cpu_cs_n_o
);

  // ---------------------------------------------------------------------------
  // Process adec
  //
  // Purpose:
  //   Decode the CPU address and generate one-hot chip select signals.
  //   Each chip select enables a 4 KByte address segment.
  //
  //   The chip select outputs are registered with the 20 MHz clock to
  //   break potentially long combinational paths here.
  //
  always_ff @(posedge clk_20mhz_i or negedge res_n_i) begin : adec
    if (!res_n_i) begin
      cs_n_o <= '1;
    end
    else begin
      // default assignment
      cs_n_o <= '1;

      if (a_i[15] == 1'b0) begin
        if (rd_n_i == 1'b0 || wr_n_i == 1'b0) begin
          cs_n_o[{1'b0, a_i[14:12]}] <= 1'b0;
        end
      end
      else begin
        if (mreq_n_i == 1'b0 && rfsh_n_i == 1'b1) begin
          cs_n_o[{1'b1, a_i[14:12]}] <= 1'b0;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Process cs_ext_ram
  //
  // Purpose:
  //   Builds the combinational chip select signal for the external CPU RAM.
  //
  always_comb begin : cs_ext_ram
    if ((rd_n_i == 1'b0 || wr_n_i == 1'b0) &&
        a_i[15:12] == 4'b0110) begin
      ram_cpu_cs_n_o = 1'b0;
    end
    else begin
      ram_cpu_cs_n_o = 1'b1;
    end
  end

endmodule
