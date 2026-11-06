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


//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_char_ram.vhd,v 1.1 2005/11/06 15:42:13 arnim Exp $
//
// Wrapper for technology dependent video character RAM.
//
// Xilinx flavor.
//
// Instantiate 1 K x 8 synchronous RAM.
//
// The clock enable of the controller clock is not attached to the RAM to
// emulate the asynchronous read behavior of the original RAM. Read data is
// available within a clock cycle of the controller although it takes two
// cycles of the main clock to get the data from the RAM macro.
//
// SystemVerilog translation 2026 (Rodimus) of the MiSTer port by Sorgelig

// -----------------------------------------------------------------------------
// ladybug_char_ram
//
// NOTE(translation): work.dpram (altsyncram BIDIR_DUAL_PORT) replaced by dpram_dc.
// -----------------------------------------------------------------------------
module ladybug_char_ram (
  input  logic       clk1_i,
  input  logic       clk_en1_i,
  input  logic [9:0] a1_i,
  input  logic       cs1_n_i,
  input  logic       we1_n_i,
  input  logic [7:0] d1_i,
  output logic [7:0] d1_o,

  input  logic       clk2_i,
  input  logic       clk_en2_i,
  input  logic [9:0] a2_i,
  input  logic       cs2_n_i,
  input  logic       we2_n_i,
  input  logic [7:0] d2_i,
  output logic [7:0] d2_o,

  output ram_pool_pkg::pram_i_t pr_i,
  input  ram_pool_pkg::pram_o_t pr_o
);

  logic [7:0] d1_s;
  logic       we1_s;
  logic [7:0] d2_s;
  logic       we2_s;

  assign we1_s = ~cs1_n_i & ~we1_n_i & clk_en1_i;
  assign we2_s = ~cs2_n_i & ~we2_n_i & clk_en2_i;

  assign pr_i.a_addr = {6'd0, a1_i};  assign pr_i.a_d = d1_i;  assign pr_i.a_we = we1_s;
  assign pr_i.b_addr = {6'd0, a2_i};  assign pr_i.b_d = d2_i;  assign pr_i.b_we = we2_s;
  assign d1_s = pr_o.a_q;  assign d2_s = pr_o.b_q;

  assign d1_o = (cs1_n_i == 1'b0) ? d1_s : '1;
  assign d2_o = (cs2_n_i == 1'b0) ? d2_s : '1;

endmodule

module ladybug_sprite_ram (
  input  logic       clk_i,
  input  logic       clk_en_i,
  input  logic [9:0] a_i,
  input  logic       cs_n_i,
  input  logic       we_n_i,
  input  logic [7:0] d_i,
  output logic [7:0] d_o,

  output ram_pool_pkg::pram_i_t pr_i,
  input  ram_pool_pkg::pram_o_t pr_o
);

  logic       we_s;
  logic [7:0] qb_unused_s;

  assign we_s = ~cs_n_i & ~we_n_i & clk_en_i;

  assign pr_i.a_addr = {6'd0, a_i};  assign pr_i.a_d = d_i;  assign pr_i.a_we = we_s;
  assign pr_i.b_addr = 16'd0;  assign pr_i.b_d = 8'd0;  assign pr_i.b_we = 1'b0;
  assign d_o = pr_o.a_q;

endmodule

module ladybug_char_col_ram (
  input  logic       clk_i,
  input  logic       clk_en_i,
  input  logic [9:0] a_i,
  input  logic       cs_n_i,
  input  logic       we_n_i,
  input  logic [3:0] d_i,
  output logic [3:0] d_o,

  output ram_pool_pkg::pram_i_t pr_i,
  input  ram_pool_pkg::pram_o_t pr_o
);

  logic [3:0] d_s;
  logic       we_s;
  logic [7:0] qa_s;
  logic [7:0] qb_unused_s;

  assign we_s = ~cs_n_i & ~we_n_i & clk_en_i;

  assign pr_i.a_addr = {6'd0, a_i};  assign pr_i.a_d = {4'b0000, d_i};  assign pr_i.a_we = we_s;
  assign pr_i.b_addr = 16'd0;  assign pr_i.b_d = 8'd0;  assign pr_i.b_we = 1'b0;
  assign qa_s = pr_o.a_q;
  assign d_s = qa_s[3:0];

  assign d_o = (cs_n_i == 1'b0) ? d_s : '1;

endmodule

module ladybug_sprite_vram (
  input  logic       clk_i,
  input  logic       clk_en_i,
  input  logic [9:0] a_i,
  input  logic       cs_n_i,
  input  logic       we_n_i,
  input  logic [3:0] d_i,
  output logic [3:0] d_o,

  output ram_pool_pkg::pram_i_t pr_i,
  input  ram_pool_pkg::pram_o_t pr_o
);

  logic       we_s;
  logic [7:0] qa_s;
  logic [7:0] qb_unused_s;

  assign we_s = ~cs_n_i & ~we_n_i & clk_en_i;

  assign pr_i.a_addr = {6'd0, a_i};  assign pr_i.a_d = {4'b0000, d_i};  assign pr_i.a_we = we_s;
  assign pr_i.b_addr = 16'd0;  assign pr_i.b_d = 8'd0;  assign pr_i.b_we = 1'b0;
  assign qa_s = pr_o.a_q;
  assign d_o = qa_s[3:0];

endmodule

module ladybug_cpu_ram (
  input  logic        clk1_i,
  input  logic        clk_en1_i,
  input  logic [11:0] a1_i,
  input  logic        cs1_n_i,
  input  logic        we1_n_i,
  input  logic [7:0]  d1_i,
  output logic [7:0]  d1_o,

  input  logic        clk2_i,
  input  logic        clk_en2_i,
  input  logic [11:0] a2_i,
  input  logic        cs2_n_i,
  input  logic        we2_n_i,
  input  logic [7:0]  d2_i,
  output logic [7:0]  d2_o,

  output ram_pool_pkg::pram_i_t pr_i,
  input  ram_pool_pkg::pram_o_t pr_o
);

  logic [7:0] d1_s;
  logic       we1_s;
  logic [7:0] d2_s;
  logic       we2_s;

  assign we1_s = ~cs1_n_i & ~we1_n_i & clk_en1_i;
  assign we2_s = ~cs2_n_i & ~we2_n_i & clk_en2_i;

  assign pr_i.a_addr = {4'd0, a1_i};  assign pr_i.a_d = d1_i;  assign pr_i.a_we = we1_s;
  assign pr_i.b_addr = {4'd0, a2_i};  assign pr_i.b_d = d2_i;  assign pr_i.b_we = we2_s;
  assign d1_s = pr_o.a_q;  assign d2_s = pr_o.b_q;

  assign d1_o = (cs1_n_i == 1'b0) ? d1_s : '1;
  assign d2_o = (cs2_n_i == 1'b0) ? d2_s : '1;

endmodule
