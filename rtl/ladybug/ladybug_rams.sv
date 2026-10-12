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
  output logic [7:0] d2_o
);

  logic [7:0] d1_s;
  logic       we1_s;
  logic [7:0] d2_s;
  logic       we2_s;

  // generate write enable at same clock edge as controller logic
  // this might suppress intermediate writes when address bus changes
  // during write cycle
  assign we1_s = ~cs1_n_i & ~we1_n_i & clk_en1_i;
  assign we2_s = ~cs2_n_i & ~we2_n_i & clk_en2_i;

  dpram_dc #(.widthad_a(10), .width_a(8)) ram1_inst (
    .address_a (a1_i),
    .clock_a   (clk1_i),
    .data_a    (d1_i),
    .wren_a    (we1_s),
    .q_a       (d1_s),

    .address_b (a2_i),
    .clock_b   (clk2_i),
    .data_b    (d2_i),
    .wren_b    (we2_s),
    .q_b       (d2_s)
  );

  // gate the data output for and'ing on CPU bus
  assign d1_o = (cs1_n_i == 1'b0) ? d1_s : '1;
  assign d2_o = (cs2_n_i == 1'b0) ? d2_s : '1;

endmodule


// -----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_sprite_ram.vhd,v 1.1 2005/11/06 15:42:13 arnim Exp $
//
// Wrapper for technology dependent video sprite RAM.
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
// NOTE(translation): work.spram replaced by dpram_dc, port A only.
// -----------------------------------------------------------------------------
module ladybug_sprite_ram (
  input  logic       clk_i,
  input  logic       clk_en_i,
  input  logic [9:0] a_i,
  input  logic       cs_n_i,
  input  logic       we_n_i,
  input  logic [7:0] d_i,
  output logic [7:0] d_o
);

  logic       we_s;
  logic [7:0] qb_unused_s;

  // generate write enable at same clock edge as controller logic
  // this might suppress intermediate writes when address bus changes
  // during write cycle
  assign we_s = ~cs_n_i & ~we_n_i & clk_en_i;

  dpram_dc #(.widthad_a(10), .width_a(8)) ram_inst (
    .address_a (a_i),
    .clock_a   (clk_i),
    .data_a    (d_i),
    .wren_a    (we_s),
    .q_a       (d_o),

    .address_b (10'd0),
    .clock_b   (clk_i),
    .data_b    (8'd0),
    .wren_b    (1'b0),
    .q_b       (qb_unused_s)
  );

endmodule


// -----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_char_col_ram.vhd,v 1.1 2005/11/06 15:42:13 arnim Exp $
//
// Wrapper for technology dependent video character color RAM.
//
// Xilinx flavor.
//
// Instantiate 1 K x 4 synchronous RAM.
//
// The clock enable of the controller clock is not attached to the RAM to
// emulate the asynchronous read behavior of the original RAM. Read data is
// available within a clock cycle of the controller although it takes two
// cycles of the main clock to get the data from the RAM macro.
//
// NOTE(translation): work.spram (10,4) replaced by dpram_dc width_a=8, port A only,
// data padded with zeros, low 4 bits of q used.
// -----------------------------------------------------------------------------
module ladybug_char_col_ram (
  input  logic       clk_i,
  input  logic       clk_en_i,
  input  logic [9:0] a_i,
  input  logic       cs_n_i,
  input  logic       we_n_i,
  input  logic [3:0] d_i,
  output logic [3:0] d_o
);

  logic [3:0] d_s;
  logic       we_s;
  logic [7:0] qa_s;
  logic [7:0] qb_unused_s;

  // generate write enable at same clock edge as controller logic
  // this might suppress intermediate writes when address bus changes
  // during write cycle
  assign we_s = ~cs_n_i & ~we_n_i & clk_en_i;

  dpram_dc #(.widthad_a(10), .width_a(8)) ram_inst (
    .address_a (a_i),
    .clock_a   (clk_i),
    .data_a    ({4'b0000, d_i}),
    .wren_a    (we_s),
    .q_a       (qa_s),

    .address_b (10'd0),
    .clock_b   (clk_i),
    .data_b    (8'd0),
    .wren_b    (1'b0),
    .q_b       (qb_unused_s)
  );
  assign d_s = qa_s[3:0];

  // gate the data output for and'ing on CPU bus
  assign d_o = (cs_n_i == 1'b0) ? d_s : '1;

endmodule


// -----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_sprite_vram.vhd,v 1.1 2005/11/06 15:42:13 arnim Exp $
//
// Wrapper for technology dependent video sprite VRAM.
//
// Xilinx flavor.
//
// Instantiate 1 K x 4 synchronous RAM.
//
// The clock enable of the controller clock is not attached to the RAM to
// emulate the asynchronous read behavior of the original RAM. Read data is
// available within a clock cycle of the controller although it takes two
// cycles of the main clock to get the data from the RAM macro.
//
// NOTE(translation): work.spram (10,4) replaced by dpram_dc width_a=8, port A only,
// data padded with zeros, low 4 bits of q used.
// -----------------------------------------------------------------------------
module ladybug_sprite_vram (
  input  logic       clk_i,
  input  logic       clk_en_i,
  input  logic [9:0] a_i,
  input  logic       cs_n_i,
  input  logic       we_n_i,
  input  logic [3:0] d_i,
  output logic [3:0] d_o
);

  logic       we_s;
  logic [7:0] qa_s;
  logic [7:0] qb_unused_s;

  // generate write enable at same clock edge as controller logic
  // this might suppress intermediate writes when address bus changes
  // during write cycle
  assign we_s = ~cs_n_i & ~we_n_i & clk_en_i;

  dpram_dc #(.widthad_a(10), .width_a(8)) ram_inst (
    .address_a (a_i),
    .clock_a   (clk_i),
    .data_a    ({4'b0000, d_i}),
    .wren_a    (we_s),
    .q_a       (qa_s),

    .address_b (10'd0),
    .clock_b   (clk_i),
    .data_b    (8'd0),
    .wren_b    (1'b0),
    .q_b       (qb_unused_s)
  );
  assign d_o = qa_s[3:0];

endmodule


// -----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_cpu_ram.vhd,v 1.1 2005/11/06 15:43:38 arnim Exp $
//
// Wrapper for technology dependent CPU RAM.
//
// Xilinx flavor.
//
// Instantiate 4 K x 8 synchronous RAM.
//
// The clock enable of the controller clock is not attached to the RAM to
// emulate the asynchronous read behavior of the original RAM. Read data is
// available within a clock cycle of the controller although it takes two
// cycles of the main clock to get the data from the RAM macro.
//
// NOTE(translation): work.dpram replaced by dpram_dc.
// -----------------------------------------------------------------------------
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
  output logic [7:0]  d2_o
);

  logic [7:0] d1_s;
  logic       we1_s;
  logic [7:0] d2_s;
  logic       we2_s;

  // generate write enable at same clock edge as controller logic
  // this might suppress intermediate writes when address bus changes
  // during write cycle
  assign we1_s = ~cs1_n_i & ~we1_n_i & clk_en1_i;
  assign we2_s = ~cs2_n_i & ~we2_n_i & clk_en2_i;

  dpram_dc #(.widthad_a(12), .width_a(8)) ram1_inst (
    .address_a (a1_i),
    .clock_a   (clk1_i),
    .data_a    (d1_i),
    .wren_a    (we1_s),
    .q_a       (d1_s),

    .address_b (a2_i),
    .clock_b   (clk2_i),
    .data_b    (d2_i),
    .wren_b    (we2_s),
    .q_b       (d2_s)
  );

  // gate the data output for and'ing on CPU bus
  assign d1_o = (cs1_n_i == 1'b0) ? d1_s : '1;
  assign d2_o = (cs2_n_i == 1'b0) ? d2_s : '1;

endmodule
