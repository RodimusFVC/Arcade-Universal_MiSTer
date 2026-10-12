//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_video_unit.vhd,v 1.22 2006/02/07 00:44:35 arnim Exp $
//
// The Video Unit of the Lady Bug Machine.
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

module ladybug_video_unit (
  // Clock and Reset Interface ------------------------------------------------
  input  logic        clk_20mhz_i,
  input  logic        por_n_i,
  input  logic        res_n_i,
  input  logic        clk_en_10mhz_i,
  input  logic        clk_en_10mhz_n_i,
  input  logic        clk_en_5mhz_i,
  input  logic        clk_en_5mhz_n_i,
  input  logic        clk_en_4mhz_i,
  // CPU Interface ------------------------------------------------------------
  input  logic        cs7_n_i,
  input  logic        cs10_n_i,
  input  logic        cs13_n_i,
  input  logic [10:0] a_i,
  input  logic        rd_n_i,
  input  logic        wr_n_i,
  output logic        wait_n_o,
  input  logic [7:0]  d_from_cpu_i,
  output logic [7:0]  d_from_video_o,
  output logic        vc_o,
  output logic        vbl_tick_n_o,
  output logic        vbl_buf_o,
  // RGB Video Interface ------------------------------------------------------
  output logic [1:0]  rgb_r_o,
  output logic [1:0]  rgb_g_o,
  output logic [1:0]  rgb_b_o,
  output logic [8:1]  rgb_n_o,        // Universal: raw latched PROM byte (inverted)
  output logic        bg_o,           // Universal: background pixel
  input  logic        flip_ext_en_i,  // Universal: flip source override (8203 board)
  input  logic        flip_ext_i,
  output logic        hsync_n_o,
  output logic        vsync_n_o,
  output logic        comp_sync_n_o,
  output logic        vblank_o,
  output logic        hblank_o,
  // Character ROM Interface --------------------------------------------------
  output logic [11:0] rom_char_a_o,
  input  logic [15:0] rom_char_d_i,
  // Sprite ROM Interface -----------------------------------------------------
  output logic [11:0] rom_sprite_a_o,
  input  logic [15:0] rom_sprite_d_i,

  // PROM download interface (replaces dn_* ports) ----------------------------
  input  logic [4:0]  prom_a_i,
  input  logic [7:0]  prom_d_i,
  input  logic        prom_k1_wr_i,
  input  logic        prom_f4_wr_i,
  input  logic        prom_c4_wr_i,

  input  logic        pause,

  input  logic [15:0] hs_address,
  output logic [7:0]  hs_data_out,
  input  logic [7:0]  hs_data_in,
  input  logic        hs_write
);

  logic [3:0] h_s, h_t_s;
  logic       ha_d_s, ha_t_rise_s;
  logic       hbl_s;
  logic       hx_s;

  logic [3:0] v_s, v_t_s;
  logic       vc_d_s;
  logic       vbl_n_s, vbl_d_n_s;

  logic       blank_flont_s;

  logic [7:0] d_from_char_s;

  logic       blank_s;
  logic [5:1] crg_s;

  logic [4:1] sig_s;

  logic       comp_sync_n;

  assign comp_sync_n_o = comp_sync_n & vbl_n_s;
  assign vbl_buf_o     = ~vbl_n_s;
  // ---------------------------------------------------------------------------
  // Horizontal and Vertical Timing Generator
  // ---------------------------------------------------------------------------
  ladybug_video_timing timing_b (
    .clk_20mhz_i   (clk_20mhz_i),
    .por_n_i       (por_n_i),
    .clk_en_5mhz_i (clk_en_5mhz_i),
    .h_o           (h_s),
    .h_t_o         (h_t_s),
    .hbl_o         (hbl_s),
    .hx_o          (hx_s),
    .ha_d_o        (ha_d_s),
    .ha_t_rise_o   (ha_t_rise_s),
    .v_o           (v_s),
    .v_t_o         (v_t_s),
    .vc_d_o        (vc_d_s),
    .vbl_n_o       (vbl_n_s),
    .vbl_d_n_o     (vbl_d_n_s),
    .vbl_t_n_o     (vbl_tick_n_o),
    .blank_flont_o (blank_flont_s),
    .hsync_n_o     (hsync_n_o),
    .vsync_n_o     (vsync_n_o),
    .comp_sync_n_o (comp_sync_n)
  );
  assign vc_o = v_s[2];

  // ---------------------------------------------------------------------------
  // Character Module
  // ---------------------------------------------------------------------------
  ladybug_char char_b (
    .clk_20mhz_i   (clk_20mhz_i),
    .por_n_i       (por_n_i),
    .res_n_i       (res_n_i),
    .clk_en_5mhz_i (clk_en_5mhz_i),
    .clk_en_4mhz_i (clk_en_4mhz_i),
    .cs10_n_i      (cs10_n_i),
    .cs13_n_i      (cs13_n_i),
    .flip_ext_en_i (flip_ext_en_i),
    .flip_ext_i    (flip_ext_i),
    .a_i           (a_i),
    .rd_n_i        (rd_n_i),
    .wr_n_i        (wr_n_i),
    .wait_n_o      (wait_n_o),
    .d_from_cpu_i  (d_from_cpu_i),
    .d_from_char_o (d_from_char_s),
    .h_i           (h_s),
    .h_t_i         (h_t_s),
    .ha_t_rise_i   (ha_t_rise_s),
    .hx_i          (hx_s),
    .v_i           (v_s),
    .v_t_i         (v_t_s),
    .hbl_i         (hbl_s),
    .blank_flont_i (blank_flont_s),
    .blank_o       (blank_s),
    .vblank_o      (vblank_o),
    .hblank_o      (hblank_o),
    .crg_o         (crg_s),
    .rom_char_a_o  (rom_char_a_o),
    .rom_char_d_i  (rom_char_d_i),
    .hs_address    (hs_address),
    .hs_data_in    (hs_data_in),
    .hs_data_out   (hs_data_out),
    .hs_write      (hs_write)
  );

  // ---------------------------------------------------------------------------
  // Sprite Module
  // ---------------------------------------------------------------------------
  ladybug_sprite sprite_b (
    .clk_20mhz_i      (clk_20mhz_i),
    .por_n_i          (por_n_i),
    .res_n_i          (res_n_i),
    .clk_en_10mhz_i   (clk_en_10mhz_i),
    .clk_en_10mhz_n_i (clk_en_10mhz_n_i),
    .clk_en_5mhz_i    (clk_en_5mhz_i),
    .clk_en_5mhz_n_i  (clk_en_5mhz_n_i),
    .cs7_n_i          (cs7_n_i),
    .a_i              (a_i[9:0]),
    .d_from_cpu_i     (d_from_cpu_i),
    .h_i              (h_s),
    .h_t_i            (h_t_s),
    .hx_i             (hx_s),
    .ha_d_i           (ha_d_s),
    .v_i              (v_s),
    .v_t_i            (v_t_s),
    .vbl_n_i          (vbl_n_s),
    .vbl_d_n_i        (vbl_d_n_s),
    .vc_d_i           (vc_d_s),
    .blank_flont_i    (blank_flont_s),
    .blank_i          (blank_s),
    .sig_o            (sig_s),
    .rom_sprite_a_o   (rom_sprite_a_o),
    .rom_sprite_d_i   (rom_sprite_d_i),
    .prom_f4_wr_i     (prom_f4_wr_i),
    .prom_c4_wr_i     (prom_c4_wr_i),
    .prom_a_i         (prom_a_i),
    .prom_d_i         (prom_d_i)
  );

  // ---------------------------------------------------------------------------
  // RGB Generator
  // ---------------------------------------------------------------------------
  ladybug_rgb rgb_b (
    .clk_20mhz_i   (clk_20mhz_i),
    .por_n_i       (por_n_i),
    .clk_en_5mhz_i (clk_en_5mhz_i),
    .crg_i         (crg_s),
    .sig_i         (sig_s),
    .rgb_r_o       (rgb_r_o),
    .rgb_g_o       (rgb_g_o),
    .rgb_b_o       (rgb_b_o),
    .rgb_n_o       (rgb_n_o),
    .bg_o          (bg_o),
    .prom_wr_i     (prom_k1_wr_i),
    .prom_a_i      (prom_a_i),
    .prom_d_i      (prom_d_i)
  );

  // ---------------------------------------------------------------------------
  // Bus Multiplexer
  // ---------------------------------------------------------------------------
  assign d_from_video_o = (cs13_n_i == 1'b0) ? d_from_char_s : '1;

endmodule
