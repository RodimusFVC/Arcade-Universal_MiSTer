//-----------------------------------------------------------------------------
//
// FPGA Lady Bug
//
// $Id: ladybug_sprite_ctrl.vhd,v 1.8 2005/10/10 22:02:14 arnim Exp $
//
// Control logic of the Sprite module.
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

module ladybug_sprite_ctrl (
  input  logic        clk_20mhz_i,
  input  logic        clk_en_5mhz_i,
  input  logic        clk_en_5mhz_n_i,
  input  logic        por_n_i,
  input  logic        vbl_n_i,
  input  logic        vbl_d_n_i,
  input  logic        vc_i,
  input  logic        vc_d_i,
  input  logic        ha_i,
  input  logic        ha_d_i,
  input  logic        rb6_i,
  input  logic        rb7_i,
  input  logic        rc3_i,
  input  logic        rc4_i,
  input  logic        rc5_i,
  input  logic        j7_b_i,
  input  logic        j7_c_i,
  input  logic        clk_en_eck_i,
  output logic [10:0] c_o,
  output logic        clk_en_5ck_n_o,
  output logic        clk_en_6ck_n_o,
  output logic        clk_en_7ck_n_o,
  output logic        s6ck_n_o,
  output logic        s7ck_n_o,
  output logic        clk_en_b7_p3_o,
  output logic        e5_p8_o,
  output logic        clk_en_e7_3_o,
  output logic        a8_p5_n_o
);

  logic clk_5mhz_q;

  logic a7_p5_s, a7_p5_q;
  logic a7_p9_q;

  logic a8_p5_q;

  logic n4_p5_s, n4_p5_q;

  logic [2:1] f7_ck_en_s,
              f7_cl_s,
              f7_qa_s, f7_qb_s, f7_qc_s, f7_qd_s,
              f7_da_s, f7_db_s, f7_dc_s, f7_dd_s;

  logic [2:1] j5_ck_en_s,
              j5_cl_s,
              j5_qa_s, j5_qb_s, j5_qc_s, j5_qd_s,
              j5_da_s, j5_db_s, j5_dc_s, j5_dd_s;

  logic       e7_ck_en_s,
              e7_cl_n_s;
  logic [4:1] e7_d_s,
              e7_q_s, e7_q_n_s,
              e7_d_out_s, e7_d_out_n_s;

  logic [7:0] h5_n_s;

  function automatic logic [7:0] ttl_45_f(input logic a, input logic b,
                                          input logic c, input logic d);
    logic [3:0]  idx_v;
    logic [15:0] vec_v;
    begin
      vec_v = '1;

      idx_v = {d, c, b, a};
      vec_v[idx_v] = 1'b0;

      ttl_45_f = vec_v[7:0];
    end
  endfunction

  always_ff @(posedge clk_20mhz_i or negedge por_n_i) begin : seq
    if (!por_n_i) begin
      clk_5mhz_q <= 1'b0;
      a7_p5_q    <= 1'b0;
      a7_p9_q    <= 1'b0;
      a8_p5_q    <= 1'b0;
      n4_p5_q    <= 1'b0;
    end
    else begin
      if (clk_en_5mhz_i == 1'b1) begin
        clk_5mhz_q <= 1'b1;
      end
      else if (clk_en_5mhz_n_i == 1'b1) begin
        clk_5mhz_q <= 1'b0;
      end

      a7_p5_q   <= a7_p5_s;
      if (clk_en_5mhz_n_i == 1'b1) begin
        a7_p9_q <= j5_qd_s[2];
      end

      if (clk_en_eck_i == 1'b1) begin
        a8_p5_q <= ~(j7_b_i & j7_c_i);
      end

      n4_p5_q <= n4_p5_s;
    end
  end

  always_comb begin : comb
    if (a7_p5_q == 1'b0) begin
      n4_p5_s = 1'b0;
    end
    else if ((vc_i & ~vc_d_i) == 1'b1) begin
      n4_p5_s = 1'b1;
    end
    else begin
      n4_p5_s = n4_p5_q;
    end

    if ((ha_i & ~ha_d_i) == 1'b1) begin
      a7_p5_s = f7_qd_s[2];
    end
    else begin
      a7_p5_s = a7_p5_q;
    end
  end

  assign f7_cl_s[1] = n4_p5_q & ha_i & vbl_n_i;
  assign f7_cl_s[2] = f7_cl_s[1];
  ttl_393 f7_b (
    .ck_i    (clk_20mhz_i),
    .ck_en_i (f7_ck_en_s),
    .por_n_i (por_n_i),
    .cl_i    (f7_cl_s),
    .qa_o    (f7_qa_s),
    .qb_o    (f7_qb_s),
    .qc_o    (f7_qc_s),
    .qd_o    (f7_qd_s),
    .da_o    (f7_da_s),
    .db_o    (f7_db_s),
    .dc_o    (f7_dc_s),
    .dd_o    (f7_dd_s)
  );

  always_comb begin : f7_ck_en
    logic ff_q_v, ff_d_v;

    ff_q_v = j5_qd_s[2] | ( ~( ~( vbl_n_i   & ha_i   & n4_p5_q ) ) | ~( ~( ~f7_qd_s[2] & ~e7_q_n_s[1] ) ) );

    ff_d_v = j5_dd_s[2] | ( ~( ~( vbl_d_n_i & ha_d_i & n4_p5_s ) ) | ~( ~( ~f7_qd_s[2] & ~e7_d_out_n_s[1] ) ) );
    f7_ck_en_s[1] = ~ff_q_v & ff_d_v;

    f7_ck_en_s[2] = f7_qb_s[1] & ~f7_db_s[1];
  end

  assign j5_cl_s[1] = ~vbl_n_i
                      |
                      ~(
                        ~( ~clk_5mhz_q
                           &
                           ~h5_n_s[0] )
                       )
                      |
                      n4_p5_q;
  assign j5_cl_s[2] = a7_p9_q
                      |
                      (
                       ~(
                         ~(
                           n4_p5_q
                           &
                           ha_i
                           &
                           vbl_n_i
                          )
                        )
                       |
                       ~(
                         ~(
                           ~f7_qd_s[2]
                           &
                           ~e7_q_n_s[1]
                          )
                        )
                      );
  ttl_393 j5_b (
    .ck_i    (clk_20mhz_i),
    .ck_en_i (j5_ck_en_s),
    .por_n_i (por_n_i),
    .cl_i    (j5_cl_s),
    .qa_o    (j5_qa_s),
    .qb_o    (j5_qb_s),
    .qc_o    (j5_qc_s),
    .qd_o    (j5_qd_s),
    .da_o    (j5_da_s),
    .db_o    (j5_db_s),
    .dc_o    (j5_dc_s),
    .dd_o    (j5_dd_s)
  );

  always_comb begin : j5_ck_en
    j5_ck_en_s[1] =
                    ~(
                      ~ha_i
                      &
                      e7_q_s[3]
                     )
                    & ~(
                    ~(
                      ~ha_d_i
                      &
                      e7_d_out_s[3]
                     ));

    j5_ck_en_s[2] =
                    ~(
                      j5_qc_s[1]
                      |
                      e7_q_s[2]
                     )
                    & ~(
                    ~(
                      j5_dc_s[1]
                      |
                      e7_d_out_s[2]
                     ));
  end

  assign e7_d_s[1] = ~rb7_i;
  assign e7_d_s[2] = ~(
                      rb7_i
                      &
                      rc5_i
                      &
                      (
                       ~rc4_i
                       &
                       ~(
                         ~(
                           ~rc3_i
                           |
                           rb6_i
                          )
                        )
                      )
                     );
  assign e7_d_s[3] = ~e7_d_s[2]
                     &
                     ~a8_p5_q;
  assign e7_d_s[4] = 1'b0;

  assign e7_ck_en_s = clk_en_5mhz_i & ~h5_n_s[4];

  assign e7_cl_n_s  = f7_qd_s[2]
                      |
                      (
                       ~( ~clk_5mhz_q
                          &
                          ~h5_n_s[0] )
                      );

  ttl_175 e7_b (
    .ck_i    (clk_20mhz_i),
    .ck_en_i (e7_ck_en_s),
    .por_n_i (por_n_i),
    .cl_n_i  (e7_cl_n_s),
    .d_i     (e7_d_s),
    .q_o     (e7_q_s),
    .q_n_o   (e7_q_n_s),
    .d_o     (e7_d_out_s),
    .d_n_o   (e7_d_out_n_s)
  );

  assign clk_en_e7_3_o = ~e7_q_s[3] & e7_d_out_s[3];

  always_comb begin : h5
    logic [7:0] ff_q_v, ff_d_v;
    logic       f5_p3_q_v, f5_p3_d_v;

    f5_p3_q_v = ~( ~a7_p5_q & vbl_n_i );
    ff_q_v    = ttl_45_f(j5_qa_s[1],
                         j5_qb_s[1],
                         ha_i,
                         f5_p3_q_v);
    f5_p3_d_v = ~( ~a7_p5_s & vbl_d_n_i );
    ff_d_v    = ttl_45_f(j5_da_s[1],
                         j5_db_s[1],
                         ha_d_i,
                         f5_p3_d_v);

    h5_n_s         = ff_q_v;

    clk_en_5ck_n_o = ~ff_q_v[5] & ff_d_v[5];
    clk_en_6ck_n_o = ~ff_q_v[6] & ff_d_v[6];
    clk_en_7ck_n_o = ~ff_q_v[7] & ff_d_v[7];

    s6ck_n_o       = ff_q_v[6];
    s7ck_n_o       = ff_q_v[7];
  end

  assign clk_en_b7_p3_o = f7_ck_en_s[1];
  assign e5_p8_o        = ~( n4_p5_q
                             |
                             ~(
                               ~(
                                 f7_qa_s[1]
                                 &
                                 f7_qb_s[1]
                                )
                              ) );
  assign a8_p5_n_o      = ~a8_p5_q;

  assign c_o[ 0] = j5_qa_s[1];
  assign c_o[ 1] = j5_qb_s[1];
  assign c_o[ 2] = j5_qa_s[2];
  assign c_o[ 3] = j5_qb_s[2];
  assign c_o[ 4] = j5_qc_s[2];
  assign c_o[ 5] = j5_qd_s[2];
  assign c_o[ 6] = f7_qa_s[2];
  assign c_o[ 7] = f7_qb_s[2];
  assign c_o[ 8] = f7_qc_s[2];
  assign c_o[ 9] = f7_qa_s[1];
  assign c_o[10] = f7_qb_s[1];

endmodule
