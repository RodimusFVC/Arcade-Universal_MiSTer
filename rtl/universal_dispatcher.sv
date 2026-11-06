// Based on MAME ladybug.cpp, sraider.cpp (Nicola Salmoria, Frank Palazzolo, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module universal_dispatcher
(
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,
    input  logic  [7:0] variant,
    input  logic  [3:0] rom_dec,
    input  logic  [7:0] game_flags2,
    output logic        ce_pix,

    input  logic  [7:0] in0,
    input  logic  [7:0] in1,
    input  logic  [7:0] in2,
    input  logic  [7:0] dsw0,
    input  logic  [7:0] dsw1,
    input  logic  [7:0] coin,           // [0] coin 1, [1] coin 2 (active high)

    input  logic [24:0] ioctl_addr,
    input  logic  [7:0] ioctl_dout,
    input  logic        ioctl_wr0,

    input  logic        crt_flip,
    input  logic  [3:0] h_adj,
    input  logic  [3:0] v_adj,

    output logic  [7:0] video_r,
    output logic  [7:0] video_g,
    output logic  [7:0] video_b,
    output logic        video_hs,
    output logic        video_vs,
    output logic        video_hblank,
    output logic        video_vblank,

    output logic signed [15:0] audio,

    output logic        ddr_row_req,
    output logic [24:0] ddr_row_addr,
    input  logic        ddr_row_rdy,
    input  logic [63:0] ddr_row_q,
    output logic        ddr_byte_en,
    output logic [24:0] ddr_byte_addr,
    input  logic  [7:0] ddr_byte_q,
    input  logic        ddr_byte_rdy,

    input  logic [15:0] hs_address,
    input  logic  [7:0] hs_data_in,
    output logic  [7:0] hs_data_out,
    input  logic        hs_write
);

/////////////////////////////  Shared ROM blocks  /////////////////////////////

wire load_cpu  = ioctl_wr0 && ioctl_addr < 25'h08000;
wire load_chl  = ioctl_wr0 && ioctl_addr[24:12] == 13'h0008;
wire load_chh  = ioctl_wr0 && ioctl_addr[24:12] == 13'h0009;
wire load_spl  = ioctl_wr0 && ioctl_addr[24:12] == 13'h000A;
wire load_sph  = ioctl_wr0 && ioctl_addr[24:12] == 13'h000B;
wire load_prom = ioctl_wr0 && ioctl_addr[24:7]  == 18'h00180;
wire load_dech = ioctl_wr0 && ioctl_addr[24:8]  == 17'h000C1;
wire load_decl = ioctl_wr0 && ioctl_addr[24:8]  == 17'h000C2;
wire load_sub  = ioctl_wr0 && ioctl_addr[24:15] == 10'h002;

wire board_8203  = (variant == 8'd1) || (variant == 8'd2);
wire sraider_ovl = (variant == 8'd1);
wire mrdo        = (variant >= 8'd3) && (variant <= 8'd6);
wire dcastle     = (variant == 8'd7) || (variant == 8'd8) || (variant == 8'd9);
wire idsoc       = (variant == 8'd9);
wire zhour       = (variant == 8'd10) || (variant == 8'd11);
wire cheeky      = (variant == 8'd12);
wire cosmic      = (variant >= 8'd13) && (variant <= 8'd17);
wire cs_grid     = (variant == 8'd16);
wire tms         = (variant == 8'd18) || (variant == 8'd19);
logic [15:0] dc_adpcm_a;
logic [16:0] dc_spr8_a;
logic  [7:0] dc_spr8_d;
logic        dc_spr8_req;

assign ddr_row_req   = dc_spr8_req;
assign ddr_row_addr  = 25'h40000 + {8'd0, dc_spr8_a};
assign ddr_byte_en   = idsoc;
assign ddr_byte_addr = 25'h60000 + {9'd0, dc_adpcm_a};

logic [15:0] dc_main_a;
logic  [7:0] dc_main_lo_d, dc_main_hi_d;
logic [13:0] dc_sub_a;
logic  [7:0] dc_sub_d;
logic [11:0] dc_tile_a, dc_spr_a;
logic [31:0] dc_tile_d;
logic [63:0] dc_spr_d;
wire win_dc_mhi   = ioctl_addr[24:13] == 12'h014;
wire win_dc_sub   = ioctl_addr[24:14] == 11'h00C;
wire win_dc_tile  = ioctl_addr[24:14] == 11'h00D;
wire load_dc_mlo  = ioctl_wr0 && ioctl_addr[24:15] == 10'h004;
wire load_dc_mhi  = ioctl_wr0 && win_dc_mhi;
wire load_dc_sub  = ioctl_wr0 && win_dc_sub;
wire load_dc_tile = ioctl_wr0 && win_dc_tile;
wire load_dc_prom = ioctl_wr0 && ioctl_addr[24:8]  == 17'h003C0;
wire load_dc_spr  = ioctl_wr0 && ioctl_addr[24:15] == 10'h008;

logic [14:0] rom_cpu_a, lb_cpu_a, md_cpu_a, zh_cpu_a, cm_cpu_a, cs_cpu_a, tm_cpu_a;
logic [11:0] tm_chr_a;
logic [11:0] lb_char_a, lb_sprite_a, md_fg_a, md_bg_a, zh_chr_a, zh_spr_a, cm_chr_a, cm_spr_a;
logic [11:0] cs_cmap_a, cs_u2_a, cs_u2b_a, cs_spr_a;
logic  [7:0] cs_u2_d, cs_u2b_d;
logic  [7:0] rom_cpu_d;
logic  [7:0] dec_a;
logic  [7:0] dec_h, dec_l;
logic [11:0] rom_char_a, rom_sprite_a;

//                       cosmic ? cs_cpu_a : tms ? tm_cpu_a : lb_cpu_a;
assign rom_cpu_a    = mrdo ? md_cpu_a : zhour ? zh_cpu_a : cheeky ? cm_cpu_a :
                      cosmic ? cs_cpu_a : tms ? tm_cpu_a : lb_cpu_a;
assign rom_char_a   = mrdo ? md_fg_a  : zhour ? zh_chr_a : cheeky ? cm_chr_a : cosmic ? cs_cmap_a : tms ? tm_chr_a : lb_char_a;
assign rom_sprite_a = mrdo ? md_bg_a  : cheeky ? cm_spr_a : cosmic ? cs_spr_a : lb_sprite_a;
logic [15:0] rom_char_d, rom_sprite_d;

dpram_dc #(.widthad_a(15)) rom_cpu
(
    .clock_a(clk), .address_a(ioctl_addr[14:0]), .data_a(ioctl_dout), .wren_a(load_cpu || load_dc_mlo),
    .clock_b(clk), .address_b(dcastle ? dc_main_a[14:0] : rom_cpu_a), .q_b(rom_cpu_d)
);
assign dc_main_lo_d = rom_cpu_d;

wire [11:0] chsp_wa = win_dc_tile ? ioctl_addr[13:2] : ioctl_addr[11:0];

dpram_dc #(.widthad_a(12)) rom_char_l
(
    .clock_a(clk), .address_a(chsp_wa), .data_a(ioctl_dout), .wren_a(load_chl || (load_dc_tile && ioctl_addr[1:0] == 2'd0)),
    .clock_b(clk), .address_b(dcastle ? dc_tile_a : rom_char_a), .q_b(rom_char_d[7:0])
);

dpram_dc #(.widthad_a(12)) rom_char_h
(
    .clock_a(clk), .address_a(reset ? chsp_wa : cs_u2b_a), .data_a(ioctl_dout),
    .wren_a(load_chh || (load_dc_tile && ioctl_addr[1:0] == 2'd1)), .q_a(cs_u2b_d),
    .clock_b(clk), .address_b(cosmic ? cs_u2_a : dcastle ? dc_tile_a : rom_char_a), .q_b(rom_char_d[15:8])
);
assign cs_u2_d = rom_char_d[15:8];

dpram_dc #(.widthad_a(12)) rom_sprite_l
(
    .clock_a(clk), .address_a(chsp_wa), .data_a(ioctl_dout), .wren_a(load_spl || (load_dc_tile && ioctl_addr[1:0] == 2'd2)),
    .clock_b(clk), .address_b(dcastle ? dc_tile_a : rom_sprite_a), .q_b(rom_sprite_d[7:0])
);

dpram_dc #(.widthad_a(12)) rom_sprite_h
(
    .clock_a(clk), .address_a(chsp_wa), .data_a(ioctl_dout), .wren_a(load_sph || (load_dc_tile && ioctl_addr[1:0] == 2'd3)),
    .clock_b(clk), .address_b(dcastle ? dc_tile_a : rom_sprite_a), .q_b(rom_sprite_d[15:8])
);
assign dc_tile_d = {rom_sprite_d[15:8], rom_sprite_d[7:0], rom_char_d[15:8], rom_char_d[7:0]};

dpram_dc #(.widthad_a(8)) rom_dec_h
(
    .clock_a(clk), .address_a(ioctl_addr[7:0]), .data_a(ioctl_dout), .wren_a(load_dech),
    .clock_b(clk), .address_b(dec_a), .q_b(dec_h)
);

dpram_dc #(.widthad_a(8)) rom_dec_l
(
    .clock_a(clk), .address_a(ioctl_addr[7:0]), .data_a(ioctl_dout), .wren_a(load_decl),
    .clock_b(clk), .address_b(dec_a), .q_b(dec_l)
);

logic [14:0] rom_sub_a, lb_sub_a;
assign rom_sub_a = lb_sub_a;
logic  [7:0] rom_sub_d;
logic [11:0] grid_rom_a;
logic  [7:0] grid_rom_d, grid_ram_a, grid_ram_d;
logic        grid_wr;
logic  [7:0] grid_a, grid_d;

wire [14:0] sub_wa = win_dc_sub ? {1'b0, ioctl_addr[13:0]} : win_dc_mhi ? {2'b10, ioctl_addr[12:0]} : ioctl_addr[14:0];

dpram_dc #(.widthad_a(15)) rom_sub
(
    .clock_a(clk), .address_a(reset ? sub_wa : {2'b10, dc_main_a[12:0]}), .data_a(ioctl_dout),
    .wren_a(load_sub || load_dc_sub || load_dc_mhi), .q_a(dc_main_hi_d),
    .clock_b(clk), .address_b(dcastle ? {1'b0, dc_sub_a} : rom_sub_a), .q_b(rom_sub_d)
);
assign dc_sub_d = rom_sub_d;

logic [10:0] md_spr_a;
logic [31:0] md_spr_d;
logic  [1:0] grid_lane = 2'd0;
always_ff @(posedge clk) grid_lane <= grid_rom_a[1:0];
assign grid_rom_d = md_spr_d[grid_lane*8 +: 8];
wire         load_mdspr = ioctl_wr0 && ioctl_addr[24:13] == 12'h00C;
//     for (ln = 0; ln < 4; ln++) begin : mdspr
//         dpram_dc #(.widthad_a(11)) rom
//         (
//         );
//     for (ln = 0; ln < 4; ln++) begin : dctile
//         dpram_dc #(.widthad_a(12)) rom
//         (
//         );
//     for (ln = 0; ln < 8; ln++) begin : dcspr
//         dpram_dc #(.widthad_a(12)) rom
//         (
//         );

genvar ln;

wire load_zhspr = ioctl_wr0 && ioctl_addr[24:13] == 12'h00E;
generate
    for (ln = 0; ln < 8; ln++) begin : dcspr
        dpram_dc #(.widthad_a(12)) rom
        (
            .clock_a(clk),
            .address_a(load_mdspr ? {1'b0, ioctl_addr[12:2]} : load_zhspr ? {2'b10, ioctl_addr[12:3]} : ioctl_addr[14:3]),
            .data_a(ioctl_dout),
            .wren_a(((load_dc_spr || load_zhspr) && ioctl_addr[2:0] == ln) ||
                    (ln < 4 && load_mdspr && {30'd0, ioctl_addr[1:0]} == ln)),
            .clock_b(clk),
            .address_b(board_8203 ? {2'b00, grid_rom_a[11:2]} : mrdo ? {1'b0, md_spr_a} :
                       zhour ? {1'b1, zh_spr_a[10:0]} : dc_spr_a),
            .q_b(dc_spr_d[ln*8 +: 8])
        );
    end
endgenerate
assign md_spr_d = dc_spr_d[31:0];

wire prom_k1_wr = load_prom && ioctl_addr[6:5] == 2'd0;
wire prom_f4_wr = load_prom && ioctl_addr[6:5] == 2'd1;
wire prom_c4_wr = load_prom && ioctl_addr[6:5] == 2'd2;
logic [4:0] lb_k1_a, lb_f4_a, lb_c4_a;
logic [7:0] lb_k1_d, lb_f4_d, lb_c4_d;

dpram_dc #(.widthad_a(5)) rom_k1
(
    .clock_a(clk), .address_a(ioctl_addr[4:0]), .data_a(ioctl_dout), .wren_a(prom_k1_wr),
    .clock_b(clk), .address_b(lb_k1_a), .q_b(lb_k1_d)
);
dpram_dc #(.widthad_a(5)) rom_f4
(
    .clock_a(clk), .address_a(ioctl_addr[4:0]), .data_a(ioctl_dout), .wren_a(prom_f4_wr),
    .clock_b(clk), .address_b(lb_f4_a), .q_b(lb_f4_d)
);
dpram_dc #(.widthad_a(5)) rom_c4
(
    .clock_a(clk), .address_a(ioctl_addr[4:0]), .data_a(ioctl_dout), .wren_a(prom_c4_wr),
    .clock_b(clk), .address_b(lb_c4_a), .q_b(lb_c4_d)
);

logic [7:0] dc_prom_a, dc_prom_d;
dpram_dc #(.widthad_a(8)) rom_dcprom
(
    .clock_a(clk), .address_a(ioctl_addr[7:0]), .data_a(ioctl_dout), .wren_a(load_dc_prom),
    .clock_b(clk), .address_b(dc_prom_a), .q_b(dc_prom_d)
);

localparam RAM_BLOCKS = 13;
ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] lb_pr_i, md_pr_i, dc_pr_i, zh_pr_i, cm_pr_i, cs_pr_i, cs_pr_b_i, tm_pr_i, pool_i;
ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pool_o;
ram_pool_pkg::pram_i_t [2:0] fb_pr_i;
ram_pool_pkg::pram_i_t [8:0] lb_ram_i;
logic        cs_grid_we;
logic  [7:0] cs_grid_wd;
logic [12:0] cs_grid_wa, cs_grid_ra;

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

// z80pa_0: Lady Bug / Space Raider / Mrs. Dynamite main, Mr. Do!, Castle main, Zero Hour / Red Clash, Cheeky Mouse, Cosmic boards
chip_pool_pkg::z80pa_i_t lb_z80pa_0_i, md_z80pa_0_i, dc_z80pa_0_i, zh_z80pa_0_i, cm_z80pa_0_i, cs_z80pa_0_i, z80pa_0_i;
chip_pool_pkg::z80pa_o_t z80pa_0_o;
assign z80pa_0_i = mrdo ? md_z80pa_0_i : dcastle ? dc_z80pa_0_i : zhour ? zh_z80pa_0_i : cheeky ? cm_z80pa_0_i :
                   cosmic ? cs_z80pa_0_i : lb_z80pa_0_i;

wire [15:0] z80pa_0_a;
wire  [7:0] z80pa_0_do;
wire        z80pa_0_m1_n, z80pa_0_mreq_n, z80pa_0_iorq_n, z80pa_0_rd_n, z80pa_0_wr_n, z80pa_0_rfsh_n;

t80sv_T80pa #(.Mode(0)) z80pa_0
(
    .RESET_n (z80pa_0_i.reset_n), .CLK(clk), .CEN_p(z80pa_0_i.cen_p), .CEN_n(z80pa_0_i.cen_n),
    .WAIT_n  (z80pa_0_i.wait_n), .INT_n(z80pa_0_i.int_n), .NMI_n(z80pa_0_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80pa_0_m1_n), .MREQ_n(z80pa_0_mreq_n), .IORQ_n(z80pa_0_iorq_n), .RD_n(z80pa_0_rd_n), .WR_n(z80pa_0_wr_n),
    .RFSH_n(z80pa_0_rfsh_n), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(z80pa_0_a), .DI(z80pa_0_i.di), .DO(z80pa_0_do),
    .R800_mode(1'b0), .REG(), .DIRSet(1'b0), .DIR(212'd0)
);

assign z80pa_0_o.a = z80pa_0_a;           assign z80pa_0_o.dout = z80pa_0_do;
assign z80pa_0_o.m1_n = z80pa_0_m1_n;     assign z80pa_0_o.mreq_n = z80pa_0_mreq_n; assign z80pa_0_o.iorq_n = z80pa_0_iorq_n;
assign z80pa_0_o.rd_n = z80pa_0_rd_n;     assign z80pa_0_o.wr_n = z80pa_0_wr_n;     assign z80pa_0_o.rfsh_n = z80pa_0_rfsh_n;

// z80pa_1: Space Raider / Mrs. Dynamite 8203 sub, Castle sub
chip_pool_pkg::z80pa_i_t lb_z80pa_1_i, dc_z80pa_1_i, z80pa_1_i;
chip_pool_pkg::z80pa_o_t z80pa_1_o;
assign z80pa_1_i = dcastle ? dc_z80pa_1_i : lb_z80pa_1_i;

wire [15:0] z80pa_1_a;
wire  [7:0] z80pa_1_do;
wire        z80pa_1_m1_n, z80pa_1_mreq_n, z80pa_1_iorq_n, z80pa_1_rd_n, z80pa_1_wr_n, z80pa_1_rfsh_n;

t80sv_T80pa #(.Mode(0)) z80pa_1
(
    .RESET_n (z80pa_1_i.reset_n), .CLK(clk), .CEN_p(z80pa_1_i.cen_p), .CEN_n(z80pa_1_i.cen_n),
    .WAIT_n  (z80pa_1_i.wait_n), .INT_n(z80pa_1_i.int_n), .NMI_n(z80pa_1_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80pa_1_m1_n), .MREQ_n(z80pa_1_mreq_n), .IORQ_n(z80pa_1_iorq_n), .RD_n(z80pa_1_rd_n), .WR_n(z80pa_1_wr_n),
    .RFSH_n(z80pa_1_rfsh_n), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(z80pa_1_a), .DI(z80pa_1_i.di), .DO(z80pa_1_do),
    .R800_mode(1'b0), .REG(), .DIRSet(1'b0), .DIR(212'd0)
);

assign z80pa_1_o.a = z80pa_1_a;           assign z80pa_1_o.dout = z80pa_1_do;
assign z80pa_1_o.m1_n = z80pa_1_m1_n;     assign z80pa_1_o.mreq_n = z80pa_1_mreq_n; assign z80pa_1_o.iorq_n = z80pa_1_iorq_n;
assign z80pa_1_o.rd_n = z80pa_1_rd_n;     assign z80pa_1_o.wr_n = z80pa_1_wr_n;     assign z80pa_1_o.rfsh_n = z80pa_1_rfsh_n;

chip_pool_pkg::sn76489_i_t [6:0] lb_sn76489_i;
chip_pool_pkg::sn76489_i_t [1:0] md_sn76489_i;
chip_pool_pkg::sn76489_i_t [3:0] dc_sn76489_i;
chip_pool_pkg::sn76489_o_t [6:0] sn76489_o;

// sn76489 pool: Lady Bug (2), Space Raider / Mrs. Dynamite (5), Mr. Do! (2), Mr. Do's Castle family (4, SN76489A).
// Own sn76489sv (Rodimus), no jt89. sound is the real chip's unipolar 0..1020 (not jt89's signed): boards scale for it.
genvar si;
generate
    for (si = 0; si < 7; si = si + 1) begin : g_sn76489
        chip_pool_pkg::sn76489_i_t i;
        if (si < 2)      begin : g0 assign i = mrdo ? md_sn76489_i[si] : dcastle ? dc_sn76489_i[si] : lb_sn76489_i[si]; end
        else if (si < 4) begin : g1 assign i = dcastle ? dc_sn76489_i[si] : lb_sn76489_i[si]; end
        else             begin : gn assign i = lb_sn76489_i[si]; end
        wire [10:0] sound;
        wire        ready;
        if (si < 4) begin : gdc
            // slots 0-3 serve both chip types at runtime: Lady Bug / Space Raider / Mr. Do! = SN76489 (VARIANT 0),
            // Mr. Do's Castle family (docastle.cpp) = SN76489A (VARIANT 1); same inputs, output picked by dcastle
            wire [10:0] sound_a, sound_b;
            wire        ready_a, ready_b;
            sn76489sv #(.VARIANT(0)) sn76489
            (
                .rst(i.rst), .clk(clk), .ce(i.ce), .wr_n(i.wr_n), .cs_n(i.cs_n), .din(i.din), .sound(sound_a), .ready(ready_a)
            );
            sn76489sv #(.VARIANT(1)) sn76489a
            (
                .rst(i.rst), .clk(clk), .ce(i.ce), .wr_n(i.wr_n), .cs_n(i.cs_n), .din(i.din), .sound(sound_b), .ready(ready_b)
            );
            assign sound = dcastle ? sound_b : sound_a;
            assign ready = dcastle ? ready_b : ready_a;
        end else begin : gl
            sn76489sv #(.VARIANT(0)) sn76489
            (
                .rst(i.rst), .clk(clk), .ce(i.ce), .wr_n(i.wr_n), .cs_n(i.cs_n), .din(i.din), .sound(sound), .ready(ready)
            );
        end
        assign sn76489_o[si].sound = sound; assign sn76489_o[si].ready = ready;
    end
endgenerate

// mc6845_0: Mr. Do's Castle CRTC, Cosmic Guerilla / Get A Way CRTC (never run together; same module, no generics)
chip_pool_pkg::mc6845_i_t dc_mc6845_0_i, tm_mc6845_0_i, mc6845_0_i;
chip_pool_pkg::mc6845_o_t mc6845_0_o;
assign mc6845_0_i = tms ? tm_mc6845_0_i : dc_mc6845_0_i;

wire [7:0] mc6845_0_do;
wire       mc6845_0_vs, mc6845_0_hs, mc6845_0_vbl, mc6845_0_hbl, mc6845_0_de;
wire [13:0] mc6845_0_ma;
wire  [4:0] mc6845_0_ra;

crtc6845sv_mc6845 mc6845_0
(
    .CLOCK(clk), .CLKEN(mc6845_0_i.clken), .nRESET(mc6845_0_i.reset_n),
    .ENABLE(mc6845_0_i.enable), .R_nW(mc6845_0_i.r_nw), .RS(mc6845_0_i.rs), .DI(mc6845_0_i.di), .DO(mc6845_0_do),
    .VSYNC(mc6845_0_vs), .HSYNC(mc6845_0_hs), .VBLANK(mc6845_0_vbl), .HBLANK(mc6845_0_hbl), .DE(mc6845_0_de),
    .CURSOR(), .LPSTB(1'b0), .MA(mc6845_0_ma), .RA(mc6845_0_ra)
);

assign mc6845_0_o.dout = mc6845_0_do;      assign mc6845_0_o.vsync = mc6845_0_vs;   assign mc6845_0_o.hsync = mc6845_0_hs;
assign mc6845_0_o.vblank = mc6845_0_vbl;   assign mc6845_0_o.hblank = mc6845_0_hbl; assign mc6845_0_o.de = mc6845_0_de;
assign mc6845_0_o.ma = mc6845_0_ma;        assign mc6845_0_o.ra = mc6845_0_ra;

// jt5205_0: Mr. Do's Castle (Indoor Soccer MSM5205, S = 2); jotego's jt5205 unmodified
chip_pool_pkg::jt5205_i_t dc_jt5205_0_i, jt5205_0_i;
chip_pool_pkg::jt5205_o_t jt5205_0_o;
assign jt5205_0_i = dc_jt5205_0_i;

wire signed [11:0] jt5205_0_sound;
wire               jt5205_0_irq, jt5205_0_vclk;

jt5205 jt5205_0
(
    .rst(jt5205_0_i.rst), .clk(clk), .cen(jt5205_0_i.cen), .sel(jt5205_0_i.sel), .din(jt5205_0_i.din),
    .sound(jt5205_0_sound), .sample(), .irq(jt5205_0_irq), .vclk_o(jt5205_0_vclk)
);

assign jt5205_0_o.sound = jt5205_0_sound;  assign jt5205_0_o.irq = jt5205_0_irq;  assign jt5205_0_o.vclk = jt5205_0_vclk;

// tms9900_0: Cosmic Guerilla (TMS9980A) and Get A Way (TMS9900); cycle_clks_g stays at the VHDL default 8
chip_pool_pkg::tms9900_i_t tm_tms9900_0_i, tms9900_0_i;
chip_pool_pkg::tms9900_o_t tms9900_0_o;
assign tms9900_0_i = tm_tms9900_0_i;

wire [15:0] tms9900_0_addr, tms9900_0_dout;
wire        tms9900_0_rd, tms9900_0_wr, tms9900_0_iaq, tms9900_0_as, tms9900_0_int_ack, tms9900_0_cruout, tms9900_0_cruclk, tms9900_0_holda;

tms9900 tms9900_0
(
    .clk            (clk),
    .reset          (tms9900_0_i.reset),
    .addr_out       (tms9900_0_addr),
    .data_in        (tms9900_0_i.data_in),
    .data_out       (tms9900_0_dout),
    .rd             (tms9900_0_rd),
    .wr             (tms9900_0_wr),
    .ready          (tms9900_0_i.ready),
    .iaq            (tms9900_0_iaq),
    .as             (tms9900_0_as),
    .alu_debug_arg1 (),
    .alu_debug_arg2 (),
    .cpu_debug_out  (),
    .mult_debug_out (),
    .int_req        (tms9900_0_i.int_req),
    .ic03           (tms9900_0_i.ic03),
    .int_ack        (tms9900_0_int_ack),
    .cruin          (tms9900_0_i.cruin),
    .cruout         (tms9900_0_cruout),
    .cruclk         (tms9900_0_cruclk),
    .hold           (tms9900_0_i.hold),
    .holda          (tms9900_0_holda),
    .waits          (8'd0),
    .scratch_en     (1'b0),
    .stuck          (),
    .turbo          (1'b0),
    .byte_bus       (tms9900_0_i.byte_bus),
    .ir_step2       (tms9900_0_i.ir_step2)
);

assign tms9900_0_o.addr_out = tms9900_0_addr;  assign tms9900_0_o.data_out = tms9900_0_dout;
assign tms9900_0_o.rd = tms9900_0_rd;          assign tms9900_0_o.wr = tms9900_0_wr;
assign tms9900_0_o.iaq = tms9900_0_iaq;        assign tms9900_0_o.as = tms9900_0_as;
assign tms9900_0_o.int_ack = tms9900_0_int_ack; assign tms9900_0_o.cruout = tms9900_0_cruout;
assign tms9900_0_o.cruclk = tms9900_0_cruclk;  assign tms9900_0_o.holda = tms9900_0_holda;

/////////////////////////////  Lady Bug  /////////////////////////////

logic [1:0] lb_r, lb_g, lb_b;
logic       lb_hs_n, lb_vs_n, lb_hbl, lb_vbl, lb_bg;
logic [7:0] sub_ctrl;
logic       lb_ce;
logic signed [15:0] lb_audio;
logic [7:0] lb_hs_data;
logic [7:0] ov_code, fb_code;
logic       ov_hbl, ov_vbl, fb_hbl, fb_vbl;

ladybug_machine ladybug
(
    .z80pa_0_i       (lb_z80pa_0_i),
    .z80pa_0_o       (z80pa_0_o),
    .z80pa_1_i       (lb_z80pa_1_i),
    .z80pa_1_o       (z80pa_1_o),
    .sn76489_i       (lb_sn76489_i),
    .sn76489_o       (sn76489_o),
    .pr_i            (lb_ram_i),
    .pr_o            (pool_o[11:3]),
    .clk_20mhz_i     (clk),
    .ext_res_n_i     (~reset & ~mrdo & ~dcastle & ~zhour & ~cheeky & ~cosmic & ~tms),
    .pause_i         (pause),
    .decrypt_en_i    (rom_dec == 4'd1),
    .p2_follows_p1_i (game_flags2[0]),
    .board_8203_i    (board_8203),

    .in0_i           (in0),
    .in1_i           (in1),
    .in2_i           (in2),
    .dsw0_i          (dsw0),
    .dsw1_i          (dsw1),
    .coin1_i         (coin[0]),
    .coin2_i         (coin[1]),

    .clk_en_5mhz_o   (lb_ce),
    .rgb_r_o         (lb_r),
    .rgb_g_o         (lb_g),
    .rgb_b_o         (lb_b),
    .bg_o            (lb_bg),
    .ctrl_o          (sub_ctrl),
    .grid_wr_o       (grid_wr),
    .grid_a_o        (grid_a),
    .grid_d_o        (grid_d),
    .hsync_n_o       (lb_hs_n),
    .vsync_n_o       (lb_vs_n),
    .hblank_o        (lb_hbl),
    .vblank_o        (lb_vbl),
    .audio_o         (lb_audio),

    .rom_cpu_a_o     (lb_cpu_a),
    .rom_cpu_d_i     (rom_cpu_d),
    .dec_a_o         (dec_a),
    .dec_d_i         ({dec_h[3:0], dec_l[3:0]}),
    .rom_char_a_o    (lb_char_a),
    .rom_char_d_i    (rom_char_d),
    .rom_sprite_a_o  (lb_sprite_a),
    .rom_sprite_d_i  (rom_sprite_d),
    .rom_sub_a_o     (lb_sub_a),
    .rom_sub_d_i     (rom_sub_d),

    .prom_k1_a_o     (lb_k1_a),
    .prom_k1_d_i     (lb_k1_d),
    .prom_f4_a_o     (lb_f4_a),
    .prom_f4_d_i     (lb_f4_d),
    .prom_c4_a_o     (lb_c4_a),
    .prom_c4_d_i     (lb_c4_d),

    .hs_address      (hs_address),
    .hs_data_out     (lb_hs_data),
    .hs_data_in      (hs_data_in),
    .hs_write        (hs_write)
);

function automatic [7:0] dac2(input [1:0] v);
    case (v)
        2'd0: dac2 = 8'd0;
        2'd1: dac2 = 8'd81;
        2'd2: dac2 = 8'd174;
        2'd3: dac2 = 8'd255;
    endcase
endfunction

sraider_overlay overlay
(
    .clk        (clk),
    .ce_pix     (lb_ce),
    .enable     (sraider_ovl),
    .ctrl       (sub_ctrl),
    .in_r       (lb_r),
    .in_g       (lb_g),
    .in_b       (lb_b),
    .in_bg      (lb_bg),
    .in_hbl     (lb_hbl),
    .in_vbl     (lb_vbl),
    .grid_rom_a (grid_rom_a),
    .grid_rom_d (grid_rom_d),
    .grid_ram_a (grid_ram_a),
    .grid_ram_d (grid_ram_d),
    .out_code   (ov_code),
    .out_hbl    (ov_hbl),
    .out_vbl    (ov_vbl)
);

/////////////////////////////  Board RAM pool  /////////////////////////////
//   block 0: flip buffer 00000-07FFF | Mr. Do! work RAM | Castle main RAM | Zero Hour / Cheeky Mouse work RAM |
//            Cosmic video RAM | TMS plane 0
//   block 1: flip buffer 08000-0FFFF | Mr. Do! fg code | Castle sub RAM | Zero Hour / Cheeky Mouse video RAM |
//            Devil Zone grid | TMS plane 1
//   block 2: flip buffer 10000-167FF | Mr. Do! fg attr | Castle video RAM | TMS plane 2
//                 tms ? tm_pr_i : lb_pr_i;
//     for (ln = 0; ln < 3; ln++) begin : rpool
//         dpram_dc #(.widthad_a(15)) ram
//         (
//         );
//   block  3 (4K): Lady Bug cpu RAM | Cosmic Guerilla / Get A Way work RAM (2K)
//   block  4 (1K): LB char RAM | Mr. Do! bg attr | Castle colour RAM | Zero Hour sprite lane 0 | Cheeky Mouse lbuf 0 | Cosmic lbuf 0 | TMS score plane 0
//   block  5 (1K): LB char colour RAM | Mr. Do! bg code | Castle sprite lane 0 | ZH lane 1 | Cheeky lbuf 1 | Cosmic lbuf 1 | TMS score plane 1
//   block  6 (1K): LB sprite RAM | Mr. Do! lbuf 0 | Castle sprite lane 1 | ZH lane 2 | TMS score plane 2
//   block  7 (1K): LB sprite VRAM A6 | Mr. Do! lbuf 1 | Castle lane 2 | ZH lane 3
//   block  8 (1K): LB sprite VRAM B6 | Mr. Do! sprite lane 0 | Castle lane 3 | ZH lbuf 0
//   block  9 (1K): LB sprite VRAM C6 | Mr. Do! sprite lane 1 | Castle lbuf 0 | ZH lbuf 1
//   block 10 (1K): LB sprite VRAM D6 | Mr. Do! sprite lane 2 | Castle lbuf 1
//   block 11 (1K): Space Raider / Mrs. Dynamite sub RAM | Mr. Do! sprite lane 3
//   block 12 (1K): Space Raider / Mrs. Dynamite grid RAM (256 bytes used)
assign pool_i = mrdo ? md_pr_i : dcastle ? dc_pr_i : zhour ? zh_pr_i : cheeky ? cm_pr_i : cosmic ? cs_pr_i :
                tms ? tm_pr_i : lb_pr_i;
assign lb_pr_i[2:0]  = fb_pr_i;
assign lb_pr_i[11:3] = lb_ram_i;
generate
    for (ln = 0; ln < RAM_BLOCKS; ln++) begin : rpool
        localparam int AW = (ln < 3) ? 15 : (ln == 3) ? 12 : 10;
        dpram_dc #(.widthad_a(AW)) ram
        (
            .clock_a(clk), .address_a(pool_i[ln].a_addr[AW-1:0]), .data_a(pool_i[ln].a_d), .wren_a(pool_i[ln].a_we),
            .q_a(pool_o[ln].a_q),
            .clock_b(clk), .address_b(pool_i[ln].b_addr[AW-1:0]), .data_b(pool_i[ln].b_d), .wren_b(pool_i[ln].b_we),
            .q_b(pool_o[ln].b_q)
        );
    end
endgenerate
assign cs_pr_i[0]    = cs_pr_b_i[0];
assign cs_pr_i[1].a_addr = {3'd0, cs_grid_wa};  assign cs_pr_i[1].a_d = cs_grid_wd;  assign cs_pr_i[1].a_we = cs_grid && cs_grid_we;
assign cs_pr_i[1].b_addr = {3'd0, cs_grid_ra};  assign cs_pr_i[1].b_d = 8'd0;        assign cs_pr_i[1].b_we = 1'b0;
assign cs_pr_i[RAM_BLOCKS-1:2] = cs_pr_b_i[RAM_BLOCKS-1:2];
assign lb_pr_i[12].a_addr = {8'd0, grid_a};      assign lb_pr_i[12].a_d = grid_d;  assign lb_pr_i[12].a_we = grid_wr;
assign lb_pr_i[12].b_addr = {8'd0, grid_ram_a};  assign lb_pr_i[12].b_d = 8'd0;    assign lb_pr_i[12].b_we = 1'b0;
assign grid_ram_d = pool_o[12].b_q;

crt_flip_fb flip_fb
(
    .clk     (clk),
    .reset   (reset),
    .ce_pix  (lb_ce),
    .en      (crt_flip),
    .din     (ov_code),
    .in_hbl  (ov_hbl),
    .in_vbl  (ov_vbl),
    .dout    (fb_code),
    .out_hbl (fb_hbl),
    .out_vbl (fb_vbl),
    .alt_en  (1'b0),
    .alt_wa  (17'd0),
    .alt_wd  (8'd0),
    .alt_we  (1'b0),
    .alt_ra  (17'd0),
    .alt_q   (),
    .pr_i    (fb_pr_i),
    .pr_o    (pool_o[2:0])
);

function automatic [23:0] decode(input [7:0] c);
    case (c[7:6])
        2'b01:   decode = {{8{c[2]}}, {8{c[1]}}, {8{c[0]}}};
        2'b10:   decode = {c[0] ? 8'h97 : 8'h00,
                           (c[2] ? 8'h47 : 8'h00) + (c[1] ? 8'h97 : 8'h00),
                           (c[4] ? 8'h47 : 8'h00) + (c[3] ? 8'h97 : 8'h00)};
        default: decode = {dac2(c[5:4]), dac2(c[3:2]), dac2(c[1:0])};
    endcase
endfunction

wire [23:0] lb_rgb = decode(fb_code);

logic       hb_q = 1'b0, vb_q = 1'b0;
logic [8:0] hc_q = 9'd0;
logic [8:0] ln_q = 9'd0;
wire  [8:0] hc_cur = (fb_hbl && !hb_q) ? 9'd0 : hc_q + 9'd1;
wire  [8:0] ln_cur = (fb_vbl && !vb_q) ? 9'd0 : (fb_hbl && !hb_q) ? ln_q + 9'd1 : ln_q;
wire  [8:0] hs_beg = 9'd14 + {{5{h_adj[3]}}, h_adj};
wire  [8:0] vs_beg = 9'd27 + {{5{v_adj[3]}}, v_adj};
wire [17:0] vkey   = {ln_cur, hc_cur};
wire        lb_hs  = (hc_cur >= hs_beg) && (hc_cur < hs_beg + 9'd16);
wire  [8:0] vs_end = vs_beg + 9'd6;
wire        lb_vs  = (vkey >= {vs_beg, 9'd310}) && (vkey < {vs_end, 9'd310});
always_ff @(posedge clk) begin
    if (lb_ce) begin
        hb_q <= fb_hbl; vb_q <= fb_vbl;
        hc_q <= hc_cur; ln_q <= ln_cur;
    end
end

/////////////////////////////  Mr. Do!  /////////////////////////////

logic        md_ce, md_hs, md_vs, md_hbl, md_vbl;
logic  [7:0] md_r, md_g, md_b, md_hs_data;
logic signed [15:0] md_audio;

mrdo_board mrdo_b
(
    .z80pa_0_i    (md_z80pa_0_i),
    .z80pa_0_o    (z80pa_0_o),
    .sn76489_i    (md_sn76489_i),
    .sn76489_o    (sn76489_o[1:0]),
    .clk          (clk),
    .reset        (reset | ~mrdo),
    .pause        (pause),
    .prot_mode    (variant == 8'd4 ? 2'd1 : variant == 8'd5 ? 2'd2 : 2'd0),
    .cpu_4m0      (variant == 8'd6),
    .crt_flip     (crt_flip),
    .p1           (in0),
    .p2           (in1),
    .dsw1         (dsw0),
    .dsw2         (dsw1),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (md_ce),
    .video_r      (md_r),
    .video_g      (md_g),
    .video_b      (md_b),
    .video_hs     (md_hs),
    .video_vs     (md_vs),
    .video_hblank (md_hbl),
    .video_vblank (md_vbl),
    .audio        (md_audio),
    .rom_cpu_a    (md_cpu_a),
    .rom_cpu_d    (rom_cpu_d),
    .rom_fg_a     (md_fg_a),
    .rom_fg_d     (rom_char_d),
    .rom_bg_a     (md_bg_a),
    .rom_bg_d     (rom_sprite_d),
    .rom_spr_a    (md_spr_a),
    .rom_spr_d    (md_spr_d),
    .prom_wr      (load_prom),
    .prom_a       (ioctl_addr[6:0]),
    .prom_d       (ioctl_dout),
    .hs_address   (hs_address[11:0]),
    .hs_data_out  (md_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & mrdo),
    .pr_i         (md_pr_i),
    .pr_o         (pool_o)
);

/////////////////////////////  Mr. Do's Castle  /////////////////////////////

logic        dc_ce, dc_hs, dc_vs, dc_hbl, dc_vbl;
logic  [7:0] dc_r, dc_g, dc_b, dc_hs_data;
logic signed [15:0] dc_audio;

docastle_board docastle_b
(
    .z80pa_0_i    (dc_z80pa_0_i),
    .z80pa_0_o    (z80pa_0_o),
    .z80pa_1_i    (dc_z80pa_1_i),
    .z80pa_1_o    (z80pa_1_o),
    .sn76489_i    (dc_sn76489_i),
    .sn76489_o    (sn76489_o[3:0]),
    .jt5205_0_i   (dc_jt5205_0_i),
    .jt5205_0_o   (jt5205_0_o),
    .mc6845_0_i   (dc_mc6845_0_i),
    .mc6845_0_o   (mc6845_0_o),
    .clk          (clk),
    .reset        (reset | ~dcastle),
    .pause        (pause),
    .map_mode     (variant == 8'd8),
    .idsoccer     (idsoc),
    .pri_low      (variant == 8'd8 || idsoc),
    .crt_flip     (crt_flip),
    .joys         (in0),
    .buttons      (in1),
    .system       (in2),
    .dsw1         (dsw0),
    .dsw2         (dsw1),
    .joys2        (coin),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (dc_ce),
    .video_r      (dc_r),
    .video_g      (dc_g),
    .video_b      (dc_b),
    .video_hs     (dc_hs),
    .video_vs     (dc_vs),
    .video_hblank (dc_hbl),
    .video_vblank (dc_vbl),
    .audio        (dc_audio),
    .rom_main_a   (dc_main_a),
    .rom_main_d   (dc_main_a[15] ? dc_main_hi_d : dc_main_lo_d),
    .rom_sub_a    (dc_sub_a),
    .rom_sub_d    (dc_sub_d),
    .rom_tile_a   (dc_tile_a),
    .rom_tile_d   (dc_tile_d),
    .rom_spr_a    (dc_spr_a),
    .rom_spr_d    (dc_spr_d),
    .rom_spr8_a   (dc_spr8_a),
    .rom_spr8_req (dc_spr8_req),
    .rom_spr8_rdy (ddr_row_rdy),
    .rom_spr8_q   (ddr_row_q),
    .rom_adpcm_a  (dc_adpcm_a),
    .rom_adpcm_d  (ddr_byte_q),
    .rom_adpcm_rdy(ddr_byte_rdy),
    .prom_a_o     (dc_prom_a),
    .prom_d_i     (dc_prom_d),
    .hs_address   (hs_address[12:0]),
    .hs_data_out  (dc_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & dcastle),
    .pr_i         (dc_pr_i),
    .pr_o         (pool_o)
);

/////////////////////////////  Zero Hour / Red Clash  /////////////////////////////

logic        zh_ce, zh_hs, zh_vs, zh_hbl, zh_vbl;
logic  [7:0] zh_r, zh_g, zh_b, zh_hs_data;
logic signed [15:0] zh_audio;

zerohour_board zerohour_b
(
    .z80pa_0_i    (zh_z80pa_0_i),
    .z80pa_0_o    (z80pa_0_o),
    .clk          (clk),
    .reset        (reset | ~zhour),
    .pause        (pause),
    .redclash     (variant == 8'd11),
    .crt_flip     (crt_flip),
    .in0          (in0),
    .in1          (in1),
    .dsw1         (dsw0),
    .dsw2         (dsw1),
    .coin         (coin),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (zh_ce),
    .video_r      (zh_r),
    .video_g      (zh_g),
    .video_b      (zh_b),
    .video_hs     (zh_hs),
    .video_vs     (zh_vs),
    .video_hblank (zh_hbl),
    .video_vblank (zh_vbl),
    .audio        (zh_audio),
    .rom_cpu_a    (zh_cpu_a),
    .rom_cpu_d    (rom_cpu_d),
    .rom_chr_a    (zh_chr_a),
    .rom_chr_d    (rom_char_d[7:0]),
    .rom_spr_a    (zh_spr_a),
    .rom_spr_d    (dc_spr_d),
    .prom_wr      (load_prom),
    .prom_a       (ioctl_addr[6:0]),
    .prom_d       (ioctl_dout),
    .hs_address   (hs_address),
    .hs_data_out  (zh_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & zhour),
    .pr_i         (zh_pr_i),
    .pr_o         (pool_o)
);

/////////////////////////////  Cheeky Mouse  /////////////////////////////

logic        cm_ce, cm_hs, cm_vs, cm_hbl, cm_vbl;
logic  [7:0] cm_r, cm_g, cm_b, cm_hs_data, cm_p40;
logic  [1:0] cm_p80;
logic signed [15:0] cm_audio;

cheekyms_board cheekyms_b
(
    .z80pa_0_i    (cm_z80pa_0_i),
    .z80pa_0_o    (z80pa_0_o),
    .clk          (clk),
    .reset        (reset | ~cheeky),
    .pause        (pause),
    .crt_flip     (crt_flip),
    .inputs       (in0),
    .dsw          (dsw0),
    .coin         (coin),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (cm_ce),
    .video_r      (cm_r),
    .video_g      (cm_g),
    .video_b      (cm_b),
    .video_hs     (cm_hs),
    .video_vs     (cm_vs),
    .video_hblank (cm_hbl),
    .video_vblank (cm_vbl),
    .port40       (cm_p40),
    .port80_snd   (cm_p80),
    .rom_cpu_a    (cm_cpu_a),
    .rom_cpu_d    (rom_cpu_d),
    .rom_chr_a    (cm_chr_a),
    .rom_chr_d    (rom_char_d),
    .rom_spr_a    (cm_spr_a),
    .rom_spr_d    (rom_sprite_d),
    .prom_wr      (load_prom),
    .prom_a       (ioctl_addr[6:0]),
    .prom_d       (ioctl_dout),
    .hs_address   (hs_address[9:0]),
    .hs_data_out  (cm_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & cheeky),
    .pr_i         (cm_pr_i),
    .pr_o         (pool_o)
);

cheekyms_sound cheekyms_snd
(
    .clk    (clk),
    .reset  (reset | ~cheeky),
    .port40 (cm_p40),
    .port80 (cm_p80),
    .audio  (cm_audio)
);

/////////////////////////////  Cosmic boards  /////////////////////////////

logic        cs_ce, cs_hs, cs_vs, cs_hbl, cs_vbl;
logic  [7:0] cs_r, cs_g, cs_b, cs_hs_data;
logic [13:0] cs_snd;
logic signed [15:0] cs_audio;
wire   [7:0] cs_kind = variant - 8'd13;

cosmic_board cosmic_b
(
    .z80pa_0_i    (cs_z80pa_0_i),
    .z80pa_0_o    (z80pa_0_o),
    .clk          (clk),
    .reset        (reset | ~cosmic),
    .pause        (pause),
    .kind         (cs_kind[2:0]),
    .crt_flip     (crt_flip),
    .in0          (in0),
    .in1          (in1),
    .in2          (in2),
    .dsw0         (dsw0),
    .dsw1         (dsw1),
    .coin         (coin),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (cs_ce),
    .video_r      (cs_r),
    .video_g      (cs_g),
    .video_b      (cs_b),
    .video_hs     (cs_hs),
    .video_vs     (cs_vs),
    .video_hblank (cs_hbl),
    .video_vblank (cs_vbl),
    .audio        (cs_audio),
    .snd_trig     (cs_snd),
    .rom_cpu_a    (cs_cpu_a),
    .rom_cpu_d    (rom_cpu_d),
    .rom_cmap_a   (cs_cmap_a),
    .rom_cmap_d   (rom_char_d[7:0]),
    .rom_u2_a     (cs_u2_a),
    .rom_u2_d     (cs_u2_d),
    .rom_u2b_a    (cs_u2b_a),
    .rom_u2b_d    (cs_u2b_d),
    .rom_spr_a    (cs_spr_a),
    .rom_spr_d    (rom_sprite_d),
    .prom_wr      (load_prom),
    .prom_a       (ioctl_addr[6:0]),
    .prom_d       (ioctl_dout),
    .grid_wa      (cs_grid_wa),
    .grid_wd      (cs_grid_wd),
    .grid_we      (cs_grid_we),
    .grid_ra      (cs_grid_ra),
    .grid_q       (pool_o[1].b_q),
    .pr_i         (cs_pr_b_i),
    .pr_o         (pool_o),
    .hs_address   (hs_address),
    .hs_data_out  (cs_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & cosmic)
);

/////////////////////////////  TMS99xx boards  /////////////////////////////

logic        tm_ce, tm_hs, tm_vs, tm_hbl, tm_vbl;
logic  [7:0] tm_r, tm_g, tm_b, tm_hs_data;
logic [15:0] tm_snd;
logic signed [15:0] tm_audio;

tms_board tms_b
(
    .tms9900_0_i  (tm_tms9900_0_i),
    .tms9900_0_o  (tms9900_0_o),
    .mc6845_0_i   (tm_mc6845_0_i),
    .mc6845_0_o   (mc6845_0_o),
    .clk          (clk),
    .reset        (reset | ~tms),
    .pause        (pause),
    .getaway      (variant == 8'd19),
    .crt_flip     (crt_flip),
    .in0          (in0),
    .in1          (in1),
    .in2          (in2),
    .dsw0         (dsw0),
    .dsw1         (dsw1),
    .h_adj        (h_adj),
    .v_adj        (v_adj),
    .ce_pix       (tm_ce),
    .video_r      (tm_r),
    .video_g      (tm_g),
    .video_b      (tm_b),
    .video_hs     (tm_hs),
    .video_vs     (tm_vs),
    .video_hblank (tm_hbl),
    .video_vblank (tm_vbl),
    .audio        (tm_audio),
    .snd_out      (tm_snd),
    .rom_cpu_a    (tm_cpu_a),
    .rom_cpu_d    (rom_cpu_d),
    .rom_chr_a    (tm_chr_a),
    .rom_chr_d    (rom_char_d),
    .pr_i         (tm_pr_i),
    .pr_o         (pool_o),
    .hs_address   (hs_address),
    .hs_data_out  (tm_hs_data),
    .hs_data_in   (hs_data_in),
    .hs_write     (hs_write & tms)
);

/////////////////////////////  output select  /////////////////////////////

assign ce_pix       = tms ? tm_ce    : cosmic ? cs_ce    : cheeky ? cm_ce    : zhour ? zh_ce    : dcastle ? dc_ce    : mrdo ? md_ce    : lb_ce;
assign video_r      = tms ? tm_r     : cosmic ? cs_r     : cheeky ? cm_r     : zhour ? zh_r     : dcastle ? dc_r     : mrdo ? md_r     : lb_rgb[23:16];
assign video_g      = tms ? tm_g     : cosmic ? cs_g     : cheeky ? cm_g     : zhour ? zh_g     : dcastle ? dc_g     : mrdo ? md_g     : lb_rgb[15:8];
assign video_b      = tms ? tm_b     : cosmic ? cs_b     : cheeky ? cm_b     : zhour ? zh_b     : dcastle ? dc_b     : mrdo ? md_b     : lb_rgb[7:0];
assign video_hblank = tms ? tm_hbl   : cosmic ? cs_hbl   : cheeky ? cm_hbl   : zhour ? zh_hbl   : dcastle ? dc_hbl   : mrdo ? md_hbl   : fb_hbl;
assign video_vblank = tms ? tm_vbl   : cosmic ? cs_vbl   : cheeky ? cm_vbl   : zhour ? zh_vbl   : dcastle ? dc_vbl   : mrdo ? md_vbl   : fb_vbl;
assign video_hs     = tms ? tm_hs    : cosmic ? cs_hs    : cheeky ? cm_hs    : zhour ? zh_hs    : dcastle ? dc_hs    : mrdo ? md_hs    : lb_hs;
assign video_vs     = tms ? tm_vs    : cosmic ? cs_vs    : cheeky ? cm_vs    : zhour ? zh_vs    : dcastle ? dc_vs    : mrdo ? md_vs    : lb_vs;
assign audio        = tms ? tm_audio : cosmic ? cs_audio : cheeky ? cm_audio : zhour ? zh_audio : dcastle ? dc_audio : mrdo ? md_audio : lb_audio;
assign hs_data_out  = tms ? tm_hs_data : cosmic ? cs_hs_data : cheeky ? cm_hs_data : zhour ? zh_hs_data :
                      dcastle ? dc_hs_data : mrdo ? md_hs_data : lb_hs_data;

endmodule
