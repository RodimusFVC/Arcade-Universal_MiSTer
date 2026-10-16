//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_gpio.vhd,v 1.3 2005/10/10 21:21:20 arnim Exp $
//
// General purpose IO input for CPU Main Unit.
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

module ladybug_gpio (
  input  logic [1:0] a_i,
  input  logic       cs_in_n_i,
  input  logic       cs_extra_n_i,
  input  logic [7:0] in0_i,
  input  logic [7:0] in1_i,
  input  logic [7:0] in2_i,
  input  logic [7:0] in3_i,
  input  logic [7:0] extra_i,
  output logic [7:0] d_o
);

  // ---------------------------------------------------------------------------
  // Process gpio
  //
  // Purpose:
  //   Multiplex the IN and EXTRA inputs onto the data bus for CPU.
  //
  always_comb begin : gpio
    logic [1:0] cs_n_v;

    // default assignment with inactive bus value
    d_o = '1;

    cs_n_v = {cs_extra_n_i, cs_in_n_i};
    case (cs_n_v)
      // IN ports and DIP switches selected -----------------------------------
      2'b10: begin
        case (a_i)
          // IN 0 addressed
          2'b00: d_o = in0_i;
          // IN 1 addressed
          2'b01: d_o = in1_i;
          // DIP 0 addressed
          2'b10: d_o = in2_i;
          // DIP 1 addressed
          2'b11: d_o = in3_i;
          default: ;
        endcase
      end

      // Extra bank selected --------------------------------------------------
      2'b01: begin
        case (a_i)
          2'b00: begin
            d_o[1] = extra_i[7];
            d_o[0] = extra_i[3];
          end
          2'b01: begin
            d_o[1] = extra_i[6];
            d_o[0] = extra_i[2];
          end
          2'b10: begin
            d_o[1] = extra_i[5];
            d_o[0] = extra_i[1];
          end
          2'b11: begin
            d_o[1] = extra_i[4];
            d_o[0] = extra_i[0];
          end
          default: ;
        endcase
      end

      default: ;
    endcase
  end

endmodule
