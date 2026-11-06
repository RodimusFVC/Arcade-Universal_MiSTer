//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_video_timing.vhd,v 1.16 2006/02/07 19:27:38 arnim Exp $
//
// The Video Timing Module of Lady Bug Machine.
//
// It implements the horizontal and vertical timing signals including composite
// sync information.
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

module ladybug_video_timing (
  input  logic       clk_20mhz_i,
  input  logic       por_n_i,
  input  logic       clk_en_5mhz_i,
  output logic [3:0] h_o,
  output logic [3:0] h_t_o,
  output logic       hbl_o,
  output logic       hx_o,
  output logic       ha_d_o,
  output logic       ha_t_rise_o,
  output logic [3:0] v_o,
  output logic [3:0] v_t_o,
  output logic       vc_d_o,
  output logic       vbl_n_o,
  output logic       vbl_d_n_o,
  output logic       vbl_t_n_o,
  output logic       blank_flont_o,
  output logic       hsync_n_o,
  output logic       vsync_n_o,
  output logic       comp_sync_n_o
);

  logic [7:0] h_preset;
  logic [7:0] h_rise;
  logic [7:0] h_do;
  logic [7:0] h_j2_h2;
  logic [7:0] h_s;
  logic       hx_q, hx_s, hx_n_s;
  logic       hx_rise_s;
  logic       hbl_q;
  logic       hsync_n_q;
  logic       h_carry_s;
  logic       hd_rise_s;

  logic [7:0] v_preset;
  logic [7:0] v_rise;
  logic [7:0] v_do;
  logic [7:0] v_s;
  logic       vx_q, vx_n_s;
  logic       vbl_q, vbl_s, vbl_n_s;
  logic       vbl_t_q, vbl_t_s, vbl_t_n_s;
  logic       vsync_n_q;
  logic       v_carry_s;
  logic       vc_rise_s, vd_rise_s;
  logic       vb_t_rise_s;

  assign hd_rise_s   = h_rise[3];
  assign ha_t_rise_o = h_rise[4];
  assign ha_d_o      = h_do[0];
  assign h_preset    = {hx_n_s, hx_n_s, 2'b00, hx_n_s, 3'b000};

  ladybug_counter h_counter (
    .ck_i      (clk_20mhz_i),
    .ck_en_i   (clk_en_5mhz_i),
    .reset_n_i (por_n_i),
    .load_i    (h_carry_s),
    .preset_i  (h_preset),
    .q_o       (h_s),
    .co_o      (h_carry_s),
    .rise_q_o  (h_rise),
    .d_o       (h_do)
  );

  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : h_timing
    if (!por_n_i) begin
      hx_q      <= 1'b0;
      hbl_q     <= 1'b0;
      hsync_n_q <= 1'b1;
    end
    else begin
      hx_q <= hx_s;

      if ((hx_q & ~h_s[3]) == 1'b1) begin
        hbl_q <= 1'b1;
      end
      else if (hd_rise_s == 1'b1) begin
        hbl_q <= hx_q;
      end

      if (hx_q == 1'b0) begin
        hsync_n_q <= 1'b1;
      end
      else if (hd_rise_s == 1'b1) begin
        hsync_n_q <= h_s[5];
      end
    end
  end

  assign hx_n_s = ~hx_q;

  always_comb begin : hx_comb
    hx_s      = hx_q;
    hx_rise_s = 1'b0;

    if (clk_en_5mhz_i == 1'b1) begin
      if (h_carry_s == 1'b1) begin
        hx_s = ~hx_q;

        if (hx_q == 1'b0) begin
          hx_rise_s = 1'b1;
        end
      end
    end
  end

  assign vb_t_rise_s = v_rise[5];
  assign vd_rise_s   = v_rise[3];
  assign vc_rise_s   = v_rise[2];
  assign vc_d_o      = v_do[2];
  assign v_preset    = {vx_n_s, vx_n_s, vx_n_s, vx_q, vx_n_s, 1'b0, vx_n_s, 1'b0};

  ladybug_counter v_counter (
    .ck_i      (clk_20mhz_i),
    .ck_en_i   (hx_rise_s),
    .reset_n_i (por_n_i),
    .load_i    (v_carry_s),
    .preset_i  (v_preset),
    .q_o       (v_s),
    .co_o      (v_carry_s),
    .rise_q_o  (v_rise),
    .d_o       (v_do)
  );

  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : v_timing
    if (!por_n_i) begin
      vx_q      <= 1'b0;
      vbl_q     <= 1'b0;
      vsync_n_q <= 1'b1;
      vbl_t_q   <= 1'b0;
    end
    else begin
      if (hx_rise_s == 1'b1) begin
        if (v_carry_s == 1'b1) begin
          vx_q <= vx_n_s;
        end
      end

      if (vc_rise_s == 1'b1) begin
        vsync_n_q <= ~(v_s[7] & v_s[6] & v_s[5] & v_s[4] & v_s[3] & vx_n_s);
      end

      vbl_q   <= vbl_s;

      vbl_t_q <= vbl_t_s;
    end
  end

  assign vx_n_s    = ~vx_q;
  assign vbl_n_s   = ~vbl_q;
  assign vbl_t_n_s = ~vbl_t_q;

  always_comb begin : vbl_comb
    logic preset_v;

    preset_v = ((v_s[5] & v_s[6] & v_s[7]) == 1'b1);
    vbl_s = vbl_q;
    if (preset_v) begin
      vbl_s = 1'b1;
    end
    else if (vb_t_rise_s == 1'b1) begin
      vbl_s = vx_q;
    end

    vbl_t_s = vbl_t_q;
    if (preset_v) begin
      vbl_t_s = 1'b1;
    end
    else if (vd_rise_s == 1'b1) begin
      vbl_t_s = vx_q;
    end
  end

  assign h_o           = h_s[3:0];
  assign h_t_o         = h_s[7:4];
  assign hbl_o         = hbl_q;
  assign hx_o          = hx_q;
  assign v_o           = v_s[3:0];
  assign v_t_o         = v_s[7:4];
  assign vbl_n_o       = vbl_n_s;
  assign vbl_t_n_o     = vbl_t_n_s;
  assign vbl_d_n_o     = ~vbl_s;
  assign hsync_n_o     = hsync_n_q;
  assign vsync_n_o     = vsync_n_q;
  assign comp_sync_n_o = ~hsync_n_q ^ vsync_n_q;

  assign blank_flont_o = vbl_n_s;

endmodule
