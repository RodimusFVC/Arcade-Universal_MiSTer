//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_sprite.vhd,v 1.12 2005/10/10 22:02:14 arnim Exp $
//
// Sprite Video Module of Lady Bug Machine.
//
// This unit contains the whole sprite logic which is distributed on the
// CPU and video boards.
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

module ladybug_sprite (
  // Clock and Reset Interface ------------------------------------------------
  input  logic        clk_20mhz_i,
  input  logic        por_n_i,
  input  logic        res_n_i,
  input  logic        clk_en_10mhz_i,
  input  logic        clk_en_10mhz_n_i,
  input  logic        clk_en_5mhz_i,
  input  logic        clk_en_5mhz_n_i,
  // CPU Interface ------------------------------------------------------------
  input  logic        cs7_n_i,
  input  logic [9:0]  a_i,
  input  logic [7:0]  d_from_cpu_i,
  // RGB Video Interface ------------------------------------------------------
  input  logic [3:0]  h_i,
  input  logic [3:0]  h_t_i,
  input  logic        hx_i,
  input  logic        ha_d_i,
  input  logic [3:0]  v_i,
  input  logic [3:0]  v_t_i,
  input  logic        vbl_n_i,
  input  logic        vbl_d_n_i,
  input  logic        vc_d_i,
  input  logic        blank_flont_i,
  input  logic        blank_i,
  output logic [4:1]  sig_o,
  // Sprite ROM Interface -----------------------------------------------------
  output logic [11:0] rom_sprite_a_o,
  input  logic [15:0] rom_sprite_d_i,

  // PROM download interface (replaces dn_* ports) ----------------------------
  input  logic        prom_f4_wr_i,
  input  logic        prom_c4_wr_i,
  input  logic [4:0]  prom_a_i,
  input  logic [7:0]  prom_d_i
);

  logic sprite_ram_cs_n_s,
        sprite_ram_we_n_s,
        clk_5mhz_n_q,
        clk_en_eck_s,
        clk_en_rd_s,
        clk_en_5ck_n_s,
        clk_en_6ck_n_s,
        clk_en_7ck_n_s,
        clk_en_b7_p3_s,
        clk_en_e7_3_s,
        s6ck_n_s,
        s7ck_n_s,
        e5_p8_s,
        a8_p5_n_s,
        ct0_s,
        ct1_s,
        cr_mux_sel_s,
        ck_inh_s,
        ck_inh_n_q,
        qh1_s,
        qh2_s;

  logic [7:0]  rb_s,
               rb_unflip_s,
               rc_s;

  logic [10:0] c_s;
  logic [4:0]  v_cnt_s;
  logic [9:0]  ra_s;

  logic [11:0] ma_s;
  logic [11:6] ma_q;
  logic [1:0]  mb_q;
  logic [6:0]  mc_q;
  logic [4:0]  cl_q;

  logic [2:0]  j7_s;
  logic [7:0]  df_muxed_s;

  logic [4:0]  lu_a_s;
  logic [7:0]  lu_d_s;
  logic [3:0]  lu_d_mux_s;

  logic [15:0] rd_shift_s,
               rd_shift_int,
               rd_vram_s;
  logic [3:0]  rs_s,
               rs_int,
               rs_n_s;
  logic        rs_enable_s;
  logic        shift_oc_n_s;

  logic [3:0]  j6_shifter;
  logic [3:0]  h6_shifter;
  logic [4:0]  ctrl_lu_a_s;
  logic [7:0]  ctrl_lu_d_s;
  logic [7:0]  v_cnt_a5_a6_s;

  logic [6:1]  ctrl_lu_q_d_s,
               ctrl_lu_q;

  logic        vram_we_n_s;
  logic [3:0]  vram_a6_in_s,
               vram_a6_out_s,
               vram_b6_in_s,
               vram_b6_out_s,
               vram_c6_in_s,
               vram_c6_out_s,
               vram_d6_in_s,
               vram_d6_out_s;

  logic [3:1]  ca_q;
  logic        ca6_s,
               ca7_s,
               ca8_s;
  logic [5:0]  x_s;

  logic [9:0]  cr_s;

  logic [15:0] vram_q;

  // ---------------------------------------------------------------------------
  // The Vertical Counters C5 D5
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : v_cnt_c5_c6_b
    if (!por_n_i) begin
      v_cnt_s <= '0;
    end
    else begin
      if (clk_en_b7_p3_s == 1'b1) begin
        if (e5_p8_s == 1'b0) begin
          v_cnt_s <= {v_t_i, 1'b0};
        end
        else begin
          v_cnt_s <= v_cnt_s + 5'd1;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Counter J7
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : j7_b
    if (!por_n_i) begin
      j7_s <= '0;
    end
    else begin
      if (clk_en_10mhz_i == 1'b1) begin
        if (s6ck_n_s == 1'b0) begin
          j7_s <= {~mc_q[6], mc_q[6], 1'b0};
        end
        else if ((ct0_s | ct1_s | a8_p5_n_s | ck_inh_s) == 1'b0) begin
          j7_s <= j7_s + 3'd1;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Sprite VRAM Counters A5 A6
  // ---------------------------------------------------------------------------
  assign ct0_s = v_cnt_a5_a6_s[0];
  assign ct1_s = v_cnt_a5_a6_s[1];
  assign x_s   = v_cnt_a5_a6_s[7:2];

  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : v_cnt_a5_a6_b
    if (!por_n_i) begin
      v_cnt_a5_a6_s <= '0;
    end
    else begin
      if (clk_en_10mhz_i == 1'b1) begin
        if (s7ck_n_s == 1'b0) begin
          v_cnt_a5_a6_s[7:4] <= rb_s[7:4];
          v_cnt_a5_a6_s[3:0] <= {rb_s[3:2], ~rc_s[7], ~rc_s[6]};
        end
        else if (ck_inh_n_q == 1'b1) begin
          v_cnt_a5_a6_s <= v_cnt_a5_a6_s + 8'd1;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Process sprite_ram_ctrl
  //
  // Purpose:
  //   Generates the control signals for the sprite RAM.
  //
  always_comb begin : sprite_ram_ctrl
    logic cpu_access_v;

    cpu_access_v      = ~cs7_n_i & ~vbl_n_i;

    sprite_ram_we_n_s = ~cpu_access_v;
    sprite_ram_cs_n_s = ~(cpu_access_v | vbl_n_i);

    if (vbl_n_i == 1'b0) begin
      ra_s = a_i;
    end
    else begin
      ra_s = {v_cnt_s[4:0], c_s[4:0]};
    end
  end

  // ---------------------------------------------------------------------------
  // The Sprite RAM P5 N5
  // ---------------------------------------------------------------------------
  ladybug_sprite_ram sprite_ram_b (
    .clk_i    (clk_20mhz_i),
    .clk_en_i (clk_en_5mhz_i),
    .a_i      (ra_s),
    .cs_n_i   (sprite_ram_cs_n_s),
    .we_n_i   (sprite_ram_we_n_s),
    .d_i      (d_from_cpu_i),
    .d_o      (rb_s)
  );

  // ---------------------------------------------------------------------------
  // Process rc_add
  //
  // Purpose:
  //   Implements IC N6 and E6 which add sprite RAM data and Cx signals to
  //   form RCx bus.
  //
  always_comb begin : rc_add
    logic [7:0] a_v, b_v, sum_v;

    // prepare the inputs of the adder
    a_v[3:0] = rb_s[3:0];
    a_v[4]   = 1'b1;
    a_v[5]   = 1'b0;
    a_v[7:6] = rb_s[1:0];

    b_v[0]   = ~c_s[6];
    b_v[1]   = ~c_s[7];
    b_v[2]   = ~c_s[8];
    b_v[3]   = ~v_i[3];
    b_v[4]   = c_s[10];
    b_v[5]   = 1'b0;
    b_v[7:6] = 2'b11;

    sum_v = a_v + b_v;

    rc_s  = sum_v;
  end

  // ---------------------------------------------------------------------------
  // Sprite Control Logic
  // ---------------------------------------------------------------------------
  ladybug_sprite_ctrl sprite_ctrl_b (
    .clk_20mhz_i     (clk_20mhz_i),
    .clk_en_5mhz_i   (clk_en_5mhz_i),
    .clk_en_5mhz_n_i (clk_en_5mhz_n_i),
    .por_n_i         (por_n_i),
    .vbl_n_i         (vbl_n_i),
    .vbl_d_n_i       (vbl_d_n_i),
    .vc_i            (v_i[2]),
    .vc_d_i          (vc_d_i),
    .ha_i            (h_i[0]),
    .ha_d_i          (ha_d_i),
    .rb6_i           (rb_s[6]),
    .rb7_i           (rb_s[7]),
    .rc3_i           (rc_s[3]),
    .rc4_i           (rc_s[4]),
    .rc5_i           (rc_s[5]),
    .j7_b_i          (j7_s[1]),
    .j7_c_i          (j7_s[2]),
    .clk_en_eck_i    (clk_en_eck_s),
    .c_o             (c_s),
    .clk_en_5ck_n_o  (clk_en_5ck_n_s),
    .clk_en_6ck_n_o  (clk_en_6ck_n_s),
    .clk_en_7ck_n_o  (clk_en_7ck_n_s),
    .s6ck_n_o        (s6ck_n_s),
    .s7ck_n_o        (s7ck_n_s),
    .clk_en_b7_p3_o  (clk_en_b7_p3_s),
    .e5_p8_o         (e5_p8_s),
    .clk_en_e7_3_o   (clk_en_e7_3_s),
    .a8_p5_n_o       (a8_p5_n_s)
  );

  // ---------------------------------------------------------------------------
  // Process misc_seq
  //
  // Purpose:
  //   Implements several sequential elements.
  //
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : misc_seq
    if (!por_n_i) begin
      clk_5mhz_n_q <= 1'b0;
      ma_q         <= '0;
      mb_q         <= '0;
      mc_q         <= '0;
      cl_q         <= '0;
      ck_inh_n_q   <= 1'b1;
    end
    else begin
      // Turn clk_5mhz_n into clock waveform ----------------------------------
      if (clk_en_5mhz_n_i == 1'b1) begin
        clk_5mhz_n_q <= 1'b1;
      end
      else if (clk_en_5mhz_i == 1'b1) begin
        clk_5mhz_n_q <= 1'b0;
      end

      // 8-Bit Register M6 ----------------------------------------------------
      if (clk_en_5ck_n_s == 1'b1) begin
        mb_q <= rb_s[1:0];
        ma_q <= rb_s[7:2];
      end

      // 8-Bit Register P6 ----------------------------------------------------
      if (clk_en_e7_3_s == 1'b1) begin
        // these are inverted based on mc_q(4)
        mc_q[3:0] <= rc_s[3:0];
        // inverts sprites horizontally
        mc_q[4]   <= rb_s[4];
        // inverts sprites vertically
        mc_q[5]   <= rb_s[5];
        //
        mc_q[6]   <= rb_s[6];
      end

      // 6-Bit Register B6 ----------------------------------------------------
      if (clk_en_6ck_n_s == 1'b1) begin
        cl_q <= rb_s[4:0];
      end

      // Flip-Flop H8 ---------------------------------------------------------
      if (clk_en_10mhz_n_i == 1'b1) begin
        ck_inh_n_q <= ~ck_inh_s;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Process ma_vec
  //
  // Purpose:
  //   Build the ma_s vector.
  //
  always_comb begin : ma_vec
    ma_s[11:6] = ma_q;

    if (mc_q[6] == 1'b0) begin
      ma_s[5] = mb_q[1];
      ma_s[4] = mb_q[0];
    end
    else begin
      ma_s[5] = mc_q[3] ^ mc_q[4];
      ma_s[4] = mc_q[5] ^ j7_s[2];
    end

    ma_s[3]    = mc_q[2] ^ mc_q[4];
    ma_s[2]    = mc_q[1] ^ mc_q[4];
    ma_s[1]    = mc_q[0] ^ mc_q[4];
    ma_s[0]    = mc_q[5] ^ j7_s[0];
  end

  // ---------------------------------------------------------------------------
  // Process df_mux
  //
  // Purpose:
  //   Builds the multiplexed data from Sprite ROM.
  //   Two-stage multiplexer:
  //     1) ROM data to DFx: 16->8
  //     2) DF to input for shift register: 8->8
  //        This is actually a scrambler.
  //
  always_comb begin : df_mux
    logic [7:0] df_v;

    if (cl_q[4] == 1'b0) begin
      // ROM L7
      df_v = rom_sprite_d_i[7:0];
    end
    else begin
      // ROM M7
      df_v = rom_sprite_d_i[15:8];
    end

    if (mc_q[5] == 1'b0) begin
      df_muxed_s[0] = df_v[1];
      df_muxed_s[1] = df_v[3];
      df_muxed_s[2] = df_v[5];
      df_muxed_s[3] = df_v[7];
      //
      df_muxed_s[4] = df_v[0];
      df_muxed_s[5] = df_v[2];
      df_muxed_s[6] = df_v[4];
      df_muxed_s[7] = df_v[6];
    end
    else begin
      df_muxed_s[0] = df_v[7];
      df_muxed_s[1] = df_v[5];
      df_muxed_s[2] = df_v[3];
      df_muxed_s[3] = df_v[1];
      //
      df_muxed_s[4] = df_v[6];
      df_muxed_s[5] = df_v[4];
      df_muxed_s[6] = df_v[2];
      df_muxed_s[7] = df_v[0];
    end
  end

  // ---------------------------------------------------------------------------
  // The Two 8-Bit Shift Registers H6 J6
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : shifters_h6_j6
    if (!por_n_i) begin
      h6_shifter <= '0;
      j6_shifter <= '0;
    end
    else begin
      if ((clk_en_10mhz_i & ~ck_inh_s) == 1'b1) begin
        if ((ct0_s | ct1_s | a8_p5_n_s) == 1'b0) begin
          h6_shifter <= df_muxed_s[3:0];
          j6_shifter <= df_muxed_s[7:4];
        end
        else begin
          h6_shifter <= {h6_shifter[2:0], 1'b0};
          j6_shifter <= {j6_shifter[2:0], 1'b0};
        end
      end
    end
  end

  assign qh1_s = h6_shifter[3];
  assign qh2_s = j6_shifter[3];

  // ---------------------------------------------------------------------------
  // Sprite Look-up PROM F4
  // ---------------------------------------------------------------------------
  assign lu_a_s[4:2] = cl_q[2:0];
  assign lu_a_s[1]   = qh2_s;
  assign lu_a_s[0]   = qh1_s;

  logic [7:0] prom_F4_qa_unused_s;
  dpram_dc #(.widthad_a(5), .width_a(8)) prom_F4 (
    .clock_a   (clk_20mhz_i),
    .address_a (prom_a_i),
    .data_a    (prom_d_i),
    .wren_a    (prom_f4_wr_i),
    .q_a       (prom_F4_qa_unused_s),

    .clock_b   (clk_20mhz_i),
    .address_b (lu_a_s),
    .data_b    (8'd0),
    .wren_b    (1'b0),
    .q_b       (lu_d_s)
  );

  assign lu_d_mux_s = (cl_q[3] == 1'b0) ? lu_d_s[3:0] : lu_d_s[7:4];

  // ---------------------------------------------------------------------------
  // Sprite Control Look-up PROM C4
  // ---------------------------------------------------------------------------
  assign ctrl_lu_a_s[0] = 1'b1;
  assign ctrl_lu_a_s[1] = hx_i;
  assign ctrl_lu_a_s[2] = clk_5mhz_n_q;
  assign ctrl_lu_a_s[3] = h_i[0];
  assign ctrl_lu_a_s[4] = h_i[1];

  logic [7:0] prom_C4_qa_unused_s;
  dpram_dc #(.widthad_a(5), .width_a(8)) prom_C4 (
    .clock_a   (clk_20mhz_i),
    .address_a (prom_a_i),
    .data_a    (prom_d_i),
    .wren_a    (prom_c4_wr_i),
    .q_a       (prom_C4_qa_unused_s),

    .clock_b   (clk_20mhz_i),
    .address_b (ctrl_lu_a_s),
    .data_b    (8'd0),
    .wren_b    (1'b0),
    .q_b       (ctrl_lu_d_s)
  );

  // ---------------------------------------------------------------------------
  // Process ctrl_lu_seq
  //
  // Purpose:
  //   Registers output of Sprite Control Look-up PROM.
  //
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : ctrl_lu_seq
    if (!por_n_i) begin
      ctrl_lu_q <= '0;
    end
    else begin
      ctrl_lu_q <= ctrl_lu_q_d_s;
    end
  end

  // ---------------------------------------------------------------------------
  // Process ctrl_lu_comb
  //
  // Purpose:
  //   Combinational logic for the sprite control registers.
  //
  // NOTE(translation): the VHDL process reads ctrl_lu_q_d_s after assigning it
  // (signal semantics: converges to the new value via the sensitivity list).
  // The blocking assignments here read back the new value directly, which is the
  // same settled result.
  always_comb begin : ctrl_lu_comb
    // default assignments
    ctrl_lu_q_d_s = ctrl_lu_q;
    clk_en_eck_s  = 1'b0;
    clk_en_rd_s   = 1'b0;

    // register control
    if (clk_en_10mhz_i == 1'b1) begin
      ctrl_lu_q_d_s  = ctrl_lu_d_s[5:0];

      if (ctrl_lu_q[1] == 1'b0 && ctrl_lu_q_d_s[1] == 1'b1) begin
        // detect rising edge on ctrl_lu_q(1)
        clk_en_eck_s = 1'b1;
      end

      if (ctrl_lu_q[6] == 1'b0 && ctrl_lu_q_d_s[6] == 1'b1) begin
        // detect rising edge on ctrl_lu_q(6)
        clk_en_rd_s  = 1'b1;
      end
    end
  end
  //
  assign shift_oc_n_s = ~(ctrl_lu_q[1] & res_n_i);
  assign ck_inh_s     = ctrl_lu_q[2];
  assign cr_mux_sel_s = ctrl_lu_q[3];
  assign vram_we_n_s  = ctrl_lu_q[4];
  assign rs_enable_s  = ctrl_lu_q[5];

  // ---------------------------------------------------------------------------
  // Process ca_seq
  //
  // Purpose:
  //   Implements B5, the register that holds the CS flip-flops.
  //
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : ca_seq
    if (!por_n_i) begin
      ca_q <= '0;
    end
    else begin
      if (clk_en_7ck_n_s == 1'b1) begin
        ca_q <= c_s[8:6];
      end
    end
  end
  //
  assign ca6_s = ca_q[1];
  assign ca7_s = ca_q[2];
  assign ca8_s = ca_q[3];

  // ---------------------------------------------------------------------------
  // Process vram_mux
  //
  // Purpose:
  //   Generates the VRAM address CRx.
  //   It implements chips D5, C5 and B5.
  //
  always_comb begin : vram_mux
    if (cr_mux_sel_s == 1'b0) begin
      // D5
      cr_s[0] = h_i[2];
      cr_s[1] = h_i[3];
      cr_s[2] = h_t_i[0];
      cr_s[3] = h_t_i[1];
      // C5
      cr_s[4] = h_t_i[2];
      cr_s[5] = h_t_i[3];
      cr_s[6] = v_i[0];
      cr_s[7] = v_i[1];
      // B5
      cr_s[8] = v_i[2];
      cr_s[9] = v_i[3];
    end
    else begin
      // D5
      cr_s[0] = x_s[0];
      cr_s[1] = x_s[1];
      cr_s[2] = x_s[2];
      cr_s[3] = x_s[3];
      // C5
      cr_s[4] = x_s[4];
      cr_s[5] = x_s[5];
      cr_s[6] = ca6_s;
      cr_s[7] = ca7_s;
      // B5
      cr_s[8] = ca8_s;
      cr_s[9] = ~v_i[3];
    end
  end

  // ---------------------------------------------------------------------------
  // Shift Registers
  // ---------------------------------------------------------------------------
  // NOTE(translation): rs_int has no reset in the VHDL (only rd_shift_int is reset).
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : shifters_a7_a8_d7_d8_f8
    if (!por_n_i) begin
      rd_shift_int <= '1;
    end
    else begin
      if ((clk_en_10mhz_i & ~ck_inh_s) == 1'b1) begin
        rs_int       <= {(~(qh1_s | qh2_s)), rs_int[3:1]};
        rd_shift_int <=
          {lu_d_mux_s[0], rd_shift_int[15:13],
           lu_d_mux_s[1], rd_shift_int[11:9],
           lu_d_mux_s[2], rd_shift_int[7:5],
           lu_d_mux_s[3], rd_shift_int[3:1]};
      end
    end
  end

  assign rd_shift_s = (shift_oc_n_s == 1'b0) ? rd_shift_int : '1;
  assign rs_s       = (shift_oc_n_s == 1'b0) ? rs_int       : '1;
//assign rs_n_s[3] = ~rs_s[3] | ~rs_enable_s;
//assign rs_n_s[2] = ~rs_s[2] | ~rs_enable_s;
//assign rs_n_s[1] = ~rs_s[1] | ~rs_enable_s;
//assign rs_n_s[0] = ~rs_s[0] | ~rs_enable_s;
  assign rs_n_s[3] = rs_s[3] & rs_enable_s;
  assign rs_n_s[2] = rs_s[2] & rs_enable_s;
  assign rs_n_s[1] = rs_s[1] & rs_enable_s;
  assign rs_n_s[0] = rs_s[0] & rs_enable_s;

  // ---------------------------------------------------------------------------
  // Sprite VRAM
  // ---------------------------------------------------------------------------
  assign vram_a6_in_s[0] = rd_shift_s[ 0];
  assign vram_a6_in_s[1] = rd_shift_s[ 4];
  assign vram_a6_in_s[2] = rd_shift_s[ 8];
  assign vram_a6_in_s[3] = rd_shift_s[12];
  ladybug_sprite_vram vram_a6_b (
    .clk_i    (clk_20mhz_i),
    .clk_en_i (1'b1),
    .a_i      (cr_s),
    .cs_n_i   (rs_n_s[0]),
    .we_n_i   (vram_we_n_s),
    .d_i      (vram_a6_in_s),
    .d_o      (vram_a6_out_s)
  );
  //
  assign vram_b6_in_s[0] = rd_shift_s[ 1];
  assign vram_b6_in_s[1] = rd_shift_s[ 5];
  assign vram_b6_in_s[2] = rd_shift_s[ 9];
  assign vram_b6_in_s[3] = rd_shift_s[13];
  ladybug_sprite_vram vram_b6_b (
    .clk_i    (clk_20mhz_i),
    .clk_en_i (1'b1),
    .a_i      (cr_s),
    .cs_n_i   (rs_n_s[1]),
    .we_n_i   (vram_we_n_s),
    .d_i      (vram_b6_in_s),
    .d_o      (vram_b6_out_s)
  );
  //
  assign vram_c6_in_s[0] = rd_shift_s[ 2];
  assign vram_c6_in_s[1] = rd_shift_s[ 6];
  assign vram_c6_in_s[2] = rd_shift_s[10];
  assign vram_c6_in_s[3] = rd_shift_s[14];
  ladybug_sprite_vram vram_c6_b (
    .clk_i    (clk_20mhz_i),
    .clk_en_i (1'b1),
    .a_i      (cr_s),
    .cs_n_i   (rs_n_s[2]),
    .we_n_i   (vram_we_n_s),
    .d_i      (vram_c6_in_s),
    .d_o      (vram_c6_out_s)
  );
  //
  assign vram_d6_in_s[0] = rd_shift_s[ 3];
  assign vram_d6_in_s[1] = rd_shift_s[ 7];
  assign vram_d6_in_s[2] = rd_shift_s[11];
  assign vram_d6_in_s[3] = rd_shift_s[15];
  ladybug_sprite_vram vram_d6_b (
    .clk_i    (clk_20mhz_i),
    .clk_en_i (1'b1),
    .a_i      (cr_s),
    .cs_n_i   (rs_n_s[3]),
    .we_n_i   (vram_we_n_s),
    .d_i      (vram_d6_in_s),
    .d_o      (vram_d6_out_s)
  );
  // Remap VRAM data outputs to the complete bus ------------------------------
  assign rd_vram_s[15] = vram_d6_out_s[3] | rs_n_s[3];
  assign rd_vram_s[14] = vram_c6_out_s[3] | rs_n_s[2];
  assign rd_vram_s[13] = vram_b6_out_s[3] | rs_n_s[1];
  assign rd_vram_s[12] = vram_a6_out_s[3] | rs_n_s[0];
  //
  assign rd_vram_s[11] = vram_d6_out_s[2] | rs_n_s[3];
  assign rd_vram_s[10] = vram_c6_out_s[2] | rs_n_s[2];
  assign rd_vram_s[ 9] = vram_b6_out_s[2] | rs_n_s[1];
  assign rd_vram_s[ 8] = vram_a6_out_s[2] | rs_n_s[0];
  //
  assign rd_vram_s[ 7] = vram_d6_out_s[1] | rs_n_s[3];
  assign rd_vram_s[ 6] = vram_c6_out_s[1] | rs_n_s[2];
  assign rd_vram_s[ 5] = vram_b6_out_s[1] | rs_n_s[1];
  assign rd_vram_s[ 4] = vram_a6_out_s[1] | rs_n_s[0];
  //
  assign rd_vram_s[ 3] = vram_d6_out_s[0] | rs_n_s[3];
  assign rd_vram_s[ 2] = vram_c6_out_s[0] | rs_n_s[2];
  assign rd_vram_s[ 1] = vram_b6_out_s[0] | rs_n_s[1];
  assign rd_vram_s[ 0] = vram_a6_out_s[0] | rs_n_s[0];

  // ---------------------------------------------------------------------------
  // Process rd_seq
  //
  // Purpose:
  //   Implements the registers saving the RDx bus.
  //
  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : rd_seq
    if (!por_n_i) begin
      vram_q <= '0;
    end
    else begin
      if (blank_flont_i == 1'b0) begin
        // pseudo-asynchronous clear
        vram_q   <= '0;
      end
      else if (clk_en_rd_s == 1'b1) begin
        if (shift_oc_n_s == 1'b0) begin
          // take data from shift registers
          vram_q <= rd_shift_s;
        end
        else begin
          // take data from VRAM
          vram_q <= rd_vram_s;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Process sig_mux
  //
  // Purpose:
  //   Multiplexes the saved VRAM data to generate the four SIG outputs.
  //
  always_comb begin : sig_mux
    logic [1:0] vec_v;

    // default assignment
    sig_o = '0;

    vec_v = {h_i[1], h_i[0]};

    if (blank_i == 1'b0) begin
      case (vec_v)
        2'b00: begin
          sig_o[1] = vram_q[ 1];
          sig_o[2] = vram_q[ 5];
          sig_o[3] = vram_q[ 9];
          sig_o[4] = vram_q[13];
        end
        2'b01: begin
          sig_o[1] = vram_q[ 2];
          sig_o[2] = vram_q[ 6];
          sig_o[3] = vram_q[10];
          sig_o[4] = vram_q[14];
        end
        2'b10: begin
          sig_o[1] = vram_q[ 3];
          sig_o[2] = vram_q[ 7];
          sig_o[3] = vram_q[11];
          sig_o[4] = vram_q[15];
        end
        2'b11: begin
          sig_o[1] = vram_q[ 0];
          sig_o[2] = vram_q[ 4];
          sig_o[3] = vram_q[ 8];
          sig_o[4] = vram_q[12];
        end
        default: ;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Output Mapping
  // ---------------------------------------------------------------------------
  assign rom_sprite_a_o = ma_s;

endmodule
