//============================================================================
//
//  Universal 8302 board (Mr. Do's Castle, Do! Run Run, Wild Ride, Jumping Jack, Kick Rider)
//  Copyright (C) 2026 Rodimus
//
//  From MAME docastle.cpp (Brad Oliver) and the Mr. Do's Castle service manual schematics.
//
//  Clocks: 4.000 MHz for both Z80s, 9.828 MHz video crystal / 2 = pixel clock (here 19.656 / 4),
//  HD6845S CRTC at pixel / 8 (one character = 8 pixels). The game programs the CRTC.
//
//  map_mode 0 (MAME docastle_state):   main 0000-7FFF ROM, 8000-97FF RAM, 9800-99FF sprites,
//      A000-A7FF latch, B000/B800 video RAM, B400/BC00 colour RAM, E000 sub NMI;
//      sub 0000-3FFF ROM, 8000-87FF RAM, A000-A7FF latch, C000-C007(+C080) inputs / flip,
//      E000/E400/E800/EC00 SN76489A.
//  map_mode 1 (MAME dorunrun_state):   main 0000-1FFF ROM, 2000-37FF RAM, 3800-39FF sprites,
//      4000-9FFF ROM, A000-A7FF latch, B000 video RAM, B400 colour RAM, B800 sub NMI;
//      sub 0000-3FFF ROM, 8000-87FF RAM, A000/A400/A800/AC00 SN76489A, C000 inputs / flip,
//      E000-E7FF latch.
//  idsoccer (MAME idsoccer_state): main 0000-3FFF / 6000-9FFF ROM, 4000-57FF RAM, 5800-59FF sprites,
//      A000 latch, B000/B800 video RAM, B400/BC00 colour RAM, C000 ADPCM status / control, E000 sub NMI;
//      sub as docastle; sprite layout with tile bits 8-9 and no Y flip; MSM5205 at 384 kHz / 48;
//      second joystick on TMS1025 port 4; sprite graphics byte-wide (8 reads per row).
//  pri_low: tile pens 0-7 drawn over sprites (dorunrun_state), else pens 8-15 (docastle_state).
//
//  Main <-> sub: one bidirectional latch; a main access holds main WAIT until the sub CPU
//  accesses the latch (MAME main_from_sub_r / main_to_sub_w).
//  IRQs (as MAME): main IRQ = CRTC VSYNC; sub IRQ on HSYNC when MA6 rises, held until acknowledged;
//  sub WAIT = any SN76489A not READY. Inputs through two TMS1025 multiplexers (read returns the
//  port selected by the previous access). The sprite CPU (pass-through to the CF37201 sprite chip)
//  is not modelled: as in MAME, the main CPU's sprite writes go straight to sprite RAM.
//
//============================================================================

module docastle_board
(
    output logic        [13:0] z80m_o,         // shared T80s (rtl/z80_socket.sv): main
    input  logic        [29:0] z80m_i,
    output logic        [13:0] z80s_o,         // sub
    input  logic        [29:0] z80s_i,
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic               pause,
    input  logic               map_mode,
    input  logic               idsoccer,
    input  logic               pri_low,
    input  logic               crt_flip,

    input  logic         [7:0] joys,
    input  logic         [7:0] buttons,
    input  logic         [7:0] system,
    input  logic         [7:0] dsw1,
    input  logic         [7:0] dsw2,
    input  logic         [7:0] joys2,

    input  logic         [3:0] h_adj,
    input  logic         [3:0] v_adj,

    output logic               ce_pix,
    output logic         [7:0] video_r,
    output logic         [7:0] video_g,
    output logic         [7:0] video_b,
    output logic               video_hs,
    output logic               video_vs,
    output logic               video_hblank,
    output logic               video_vblank,
    output logic signed [15:0] audio,

    output logic        [15:0] rom_main_a,     // 0000-9FFF
    input  logic         [7:0] rom_main_d,
    output logic        [13:0] rom_sub_a,
    input  logic         [7:0] rom_sub_d,
    output logic        [11:0] rom_tile_a,     // gfx1 row: 4 byte lanes
    input  logic        [31:0] rom_tile_d,
    output logic        [11:0] rom_spr_a,      // gfx2 row: 8 byte lanes
    input  logic        [63:0] rom_spr_d,
    output logic        [16:0] rom_spr8_a,     // idsoccer gfx2 (128K, byte-wide)
    input  logic         [7:0] rom_spr8_d,
    output logic        [15:0] rom_adpcm_a,
    input  logic         [7:0] rom_adpcm_d,

    input  logic               prom_wr,
    input  logic         [7:0] prom_a,
    input  logic         [7:0] prom_d,

    input  logic        [12:0] hs_address,
    output logic         [7:0] hs_data_out,
    input  logic         [7:0] hs_data_in,
    input  logic               hs_write
);

// ------------------------------------------------------------------ clocks
logic [1:0] ph = 2'd0;
always_ff @(posedge clk) ph <= ph + 2'd1;
assign ce_pix = (ph == 2'd3);

logic [2:0] chr = 3'd0;                         // pixel within character
always_ff @(posedge clk) if (ce_pix) chr <= chr + 3'd1;
wire crtc_ce = ce_pix && chr == 3'd7;

// both Z80s: 4.000 MHz = 19.656 MHz * 1000 / 4914, rising / falling edges alternate
logic [11:0] frac_q = 12'd0;
logic        frac_ph = 1'b0, cen_p = 1'b0, cen_n = 1'b0;
wire  [12:0] frac_sum  = {1'b0, frac_q} + 13'd1000;
wire         frac_edge = frac_sum >= 13'd2457;
wire  [12:0] frac_sub  = frac_sum - 13'd2457;
always_ff @(posedge clk) begin
    frac_q <= frac_edge ? frac_sub[11:0] : frac_sum[11:0];
    cen_p  <= frac_edge & ~frac_ph;
    cen_n  <= frac_edge &  frac_ph;
    if (frac_edge) frac_ph <= ~frac_ph;
end
wire cpu_p = cen_p & ~pause;
wire cpu_n = cen_n & ~pause;

// ------------------------------------------------------------------ main CPU
logic        m_mreq_n, m_iorq_n, m_rd_n, m_wr_n, m_m1_n, m_rfsh_n;
logic [15:0] m_a;
logic  [7:0] m_di, m_do;
logic        m_wait_n, m_int_n;

z80_socket main_cpu
(
    .RESET_n (~reset), .CLK(clk), .CEN_p(cpu_p), .CEN_n(cpu_n),
    .WAIT_n  (m_wait_n), .INT_n(m_int_n), .NMI_n(1'b1), .BUSRQ_n(1'b1),
    .M1_n(m_m1_n), .MREQ_n(m_mreq_n), .IORQ_n(m_iorq_n), .RD_n(m_rd_n), .WR_n(m_wr_n), .RFSH_n(m_rfsh_n),
    .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(m_a), .DI(m_di), .DO(m_do),
    .R800_mode(1'b0), .REG(), .DIRSet(1'b0), .DIR(212'd0),
    .to_cpu(z80m_o), .from_cpu(z80m_i)
);

wire m_mem = !m_mreq_n && m_rfsh_n;
wire m_io  = !m_iorq_n && m_m1_n;

// address decode per board
wire m_rom  = m_mem && (idsoccer ? (m_a < 16'h4000 || (m_a >= 16'h6000 && m_a < 16'hA000)) :
                        map_mode ? (m_a < 16'h2000 || (m_a >= 16'h4000 && m_a < 16'hA000)) : !m_a[15]);
wire m_ram  = m_mem && (idsoccer ? (m_a >= 16'h4000 && m_a < 16'h5800) :
                        map_mode ? (m_a >= 16'h2000 && m_a < 16'h3800) : (m_a >= 16'h8000 && m_a < 16'h9800));
wire m_spr  = m_mem && (idsoccer ? (m_a[15:9] == 7'b0101100) :
                        map_mode ? (m_a[15:9] == 7'b0011100) : (m_a[15:9] == 7'b1001100));        // 5800 / 3800 / 9800
wire m_lat  = m_mem && m_a[15:11] == 5'b10100;                                                     // A000-A7FF
wire m_vid  = m_mem && (map_mode ? (m_a[15:11] == 5'b10110) : (m_a[15:12] == 4'hB));                // docastle / idsoccer: mirrored at B800
wire m_vram = m_vid && !m_a[10];
wire m_cram = m_vid &&  m_a[10];
wire m_nmi  = m_mem && !m_wr_n && (map_mode ? (m_a[15:11] == 5'b10111) : (m_a[15:12] == 4'hE));  // B800 / E000
wire m_adp  = m_mem && idsoccer && m_a[15:12] == 4'hC;                                             // C000
wire m_crtc = m_io && !m_wr_n && m_a[7:2] == 6'd0 && !m_a[0];                                       // 00 address, 02 data

wire [12:0] m_ram_a = m_a[12:0];                         // 2000-37FF / 8000-97FF -> 0000-17FF
assign rom_main_a   = m_a;

logic [7:0] m_ram_q, vram_q, cram_q;

dpram_dc #(.widthad_a(13)) main_ram
(
    .clock_a(clk), .address_a(m_ram_a), .data_a(m_do), .wren_a(m_ram && !m_wr_n), .q_a(m_ram_q),
    .clock_b(clk), .address_b(hs_address), .data_b(hs_data_in), .wren_b(hs_write), .q_b(hs_data_out)
);

// ------------------------------------------------------------------ sub CPU
logic        s_mreq_n, s_iorq_n, s_rd_n, s_wr_n, s_m1_n, s_rfsh_n;
logic [15:0] s_a;
logic  [7:0] s_di, s_do;
logic        s_int_n = 1'b1, s_nmi_n = 1'b1;
logic  [3:0] sn_ready;

z80_socket sub_cpu
(
    .RESET_n (~reset), .CLK(clk), .CEN_p(cpu_p), .CEN_n(cpu_n),
    .WAIT_n  (&sn_ready), .INT_n(s_int_n), .NMI_n(s_nmi_n), .BUSRQ_n(1'b1),
    .M1_n(s_m1_n), .MREQ_n(s_mreq_n), .IORQ_n(s_iorq_n), .RD_n(s_rd_n), .WR_n(s_wr_n), .RFSH_n(s_rfsh_n),
    .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(s_a), .DI(s_di), .DO(s_do),
    .R800_mode(1'b0), .REG(), .DIRSet(1'b0), .DIR(212'd0),
    .to_cpu(z80s_o), .from_cpu(z80s_i)
);

wire s_mem = !s_mreq_n && s_rfsh_n;
wire s_rom = s_mem && s_a[15:14] == 2'b00;
wire s_ram = s_mem && s_a[15:11] == 5'b10000;
wire s_lat = s_mem && (map_mode ? s_a[15:11] == 5'b11100 : s_a[15:11] == 5'b10100);
wire s_inp = s_mem && s_a[15:12] == 4'hC && s_a[11:8] == 4'h0 && s_a[6:3] == 4'd0;               // C000-C007 / C080-C087
wire s_snb = s_mem && (map_mode ? s_a[15:12] == 4'hA : s_a[15:12] == 4'hE);                        // A000-AFFF / E000-EFFF
wire [1:0] s_sn_n = s_a[11:10];

assign rom_sub_a = s_a[13:0];

logic [7:0] s_ram_q;
dpram_dc #(.widthad_a(11)) sub_ram
(
    .clock_a(clk), .address_a(s_a[10:0]), .data_a(s_do), .wren_a(s_ram && !s_wr_n), .q_a(s_ram_q),
    .clock_b(clk)
);

// ------------------------------------------------------------------ main <-> sub latch with main WAIT
logic [7:0] latch = 8'h00;
logic       busy = 1'b0, m_lat_d = 1'b0, s_lat_d = 1'b0;
always_ff @(posedge clk) begin
    m_lat_d <= m_lat;
    s_lat_d <= s_lat;
    if (reset) busy <= 1'b0;
    else if (s_lat && !s_lat_d) busy <= 1'b0;                 // sub access releases the main CPU
    else if (m_lat && !m_lat_d) busy <= 1'b1;                 // main access waits for it
    if (m_lat && !m_wr_n) latch <= m_do;
    if (s_lat && !s_wr_n) latch <= s_do;
end
assign m_wait_n = ~(busy && m_lat);

// sub NMI: main write to E000 / B800
logic m_nmi_d = 1'b0;
always_ff @(posedge clk) begin
    m_nmi_d <= m_nmi;
    if (reset) s_nmi_n <= 1'b1;
    else if (m_nmi && !m_nmi_d) s_nmi_n <= 1'b0;
    else if (cpu_p) s_nmi_n <= 1'b1;                           // pulse: long enough for the edge-triggered NMI
end

// ------------------------------------------------------------------ TMS1025 inputs, flip latch
logic [2:0] tms_s = 3'd0;
logic [7:0] tms_h = 8'h00;
logic       flip  = 1'b0;
logic       s_inp_d = 1'b0;

function automatic [7:0] tms_port(input [2:0] s, input [7:0] j, input [7:0] b, input [7:0] sy, input [7:0] d1, input [7:0] d2, input [7:0] j2);
    case (s)
        3'd1: tms_port = d2;
        3'd2: tms_port = d1;
        3'd3: tms_port = j;
        3'd4: tms_port = j2;
        3'd5: tms_port = b;
        3'd7: tms_port = sy;
        default: tms_port = 8'h00;                             // unconnected port inputs read 0 (MAME default)
    endcase
endfunction

wire [7:0] tms_now = (tms_s != 3'd0) ? tms_port(tms_s, joys, buttons, system, dsw1, dsw2, idsoccer ? joys2 : 8'h00) : tms_h;

always_ff @(posedge clk) begin
    s_inp_d <= s_inp;
    if (reset) begin
        tms_s <= 3'd0; flip <= 1'b0;
    end
    else if (s_inp && !s_inp_d) begin
        flip <= s_a[7];                                        // LS273 latches A7 on every access
        if (!s_rd_n) begin
            tms_h <= tms_now;                                  // value returned by this read
            tms_s <= s_a[2:0];                                 // selects the port for the next one
        end
    end
end

// ------------------------------------------------------------------ sound: 4x SN76489A, READY -> sub WAIT
logic signed [10:0] sn_out[4];
genvar i;
generate
    for (i = 0; i < 4; i++) begin : sn
        jt89 psg
        (
            .rst(reset), .clk(clk), .clk_en(cpu_p),
            .wr_n(s_wr_n), .cs_n(~(s_snb && s_sn_n == i)), .din(s_do), .sound(sn_out[i]), .ready(sn_ready[i])
        );
    end
endgenerate
wire signed [12:0] snd_sum = sn_out[0] + sn_out[1] + sn_out[2] + sn_out[3];

// ------------------------------------------------------------------ Indoor Soccer ADPCM (MAME idsoccer_state)
// 384 kHz / 48 = 8 kHz VCK = 19.656 MHz / 2457. Control write: D7 falling = stop, D6 falling = start the
// 16K-byte block (D1-D0); status read: D7 = playing. Each VCK: next nibble (high first) or stop at the block end.
logic [11:0] vck_div = 12'd0;
wire         vck = (vck_div == 12'd2456);
always_ff @(posedge clk) vck_div <= vck ? 12'd0 : vck_div + 12'd1;

logic [16:0] adp_pos = 17'd0, adp_end = 17'd0;              // nibble address (64K bytes)
logic        adp_idle = 1'b1, adp_rst = 1'b1, adp_wr_d = 1'b0;
logic  [7:0] adp_ctl = 8'h00;
logic  [3:0] adp_nib = 4'd0;
logic        adp_step = 1'b0;
wire         adp_wr = m_adp && !m_wr_n;

assign rom_adpcm_a = adp_pos[16:1];

always_ff @(posedge clk) begin
    adp_wr_d <= adp_wr;
    adp_step <= 1'b0;
    if (reset) begin
        adp_idle <= 1'b1; adp_rst <= 1'b1; adp_ctl <= 8'h00;
    end
    else begin
        if (adp_wr && !adp_wr_d) begin
            if (adp_ctl[7] && !m_do[7]) begin adp_idle <= 1'b1; adp_rst <= 1'b1; end
            if (adp_ctl[6] && !m_do[6]) begin
                adp_pos  <= {m_do[1:0], 15'd0};                                // (data & 3) * 0x8000 nibbles
                adp_end  <= {m_do[1:0], 15'd0} + 17'h08000;
                adp_idle <= 1'b0; adp_rst <= 1'b0;
            end
            adp_ctl <= m_do;
        end
        if (vck && !pause) begin
            if (adp_pos >= adp_end || adp_idle) begin
                adp_idle <= 1'b1; adp_rst <= 1'b1;
            end
            else begin
                adp_nib <= adp_pos[0] ? rom_adpcm_d[3:0] : rom_adpcm_d[7:4];
                adp_pos <= adp_pos + 17'd1;
            end
            adp_step <= 1'b1;                                   // decoder runs after the callback, as in MAME
        end
    end
end

logic signed [11:0] adp_sig;
msm5205 adpcm
(
    .clk(clk), .step(adp_step), .rst(adp_rst), .data(adp_nib), .signal(adp_sig)
);

// mix: 4x SN76489A at 0.25, MSM5205 at 0.40 (MAME routes)
// SN: jt89 channel +/-255 x4 = MAME 0x7fff/4 x 0.25 per channel; MSM: MAME 2047/4096 x 0.40 of full scale = x3.2
// every operand explicitly signed: with an unsigned concatenation in the sum, the LRM makes 'adp_w >>> 2' a logical shift
wire signed [16:0] adp_w = $signed({{5{adp_sig[11]}}, adp_sig}) * 17'sd13;
wire signed [16:0] adp_s = adp_w >>> 2;
wire signed [16:0] sn_w  = $signed({{4{snd_sum[12]}}, snd_sum}) * 17'sd4;
wire signed [16:0] mix   = sn_w + (idsoccer ? adp_s : 17'sd0);
assign audio = (mix > 17'sd32767) ? 16'sd32767 : (mix < -17'sd32768) ? -16'sd32768 : mix[15:0];

// ------------------------------------------------------------------ CRTC
logic        crtc_vs, crtc_hs, crtc_vbl, crtc_hbl, crtc_de;
logic [13:0] crtc_ma;
logic  [4:0] crtc_ra;

mc6845 crtc
(
    .CLOCK(clk), .CLKEN(crtc_ce), .nRESET(~reset),
    .ENABLE(m_crtc), .R_nW(1'b0), .RS(m_a[1]), .DI(m_do), .DO(),
    .VSYNC(crtc_vs), .HSYNC(crtc_hs), .VBLANK(crtc_vbl), .HBLANK(crtc_hbl), .DE(crtc_de),
    .CURSOR(), .LPSTB(1'b0), .MA(crtc_ma), .RA(crtc_ra)
);

// main IRQ follows VSYNC (MAME set_inputline); sub IRQ on HSYNC when MA6 rises (MAME docastle_tint)
assign m_int_n = ~crtc_vs;
logic hs_d = 1'b0, ma6_prev = 1'b0;
always_ff @(posedge clk) begin
    hs_d <= crtc_hs;
    if (reset) s_int_n <= 1'b1;
    else if (!s_m1_n && !s_iorq_n) s_int_n <= 1'b1;
    else if (crtc_hs && !hs_d) begin
        if (crtc_ma[6] && !ma6_prev) s_int_n <= 1'b0;
        ma6_prev <= crtc_ma[6];
    end
end

// ------------------------------------------------------------------ video RAM, sprite RAM
logic [9:0] v_tile_a;
logic [7:0] v_code, v_attr;

dpram_dc #(.widthad_a(10)) video_ram
(
    .clock_a(clk), .address_a(m_a[9:0]), .data_a(m_do), .wren_a(m_vram && !m_wr_n), .q_a(vram_q),
    .clock_b(clk), .address_b(v_tile_a), .q_b(v_code)
);
dpram_dc #(.widthad_a(10)) color_ram
(
    .clock_a(clk), .address_a(m_a[9:0]), .data_a(m_do), .wren_a(m_cram && !m_wr_n), .q_a(cram_q),
    .clock_b(clk), .address_b(v_tile_a), .q_b(v_attr)
);

logic [6:0] spr_e;
logic [7:0] spr_q[4];                                         // y, x, attr, code
genvar l;
generate
    for (l = 0; l < 4; l++) begin : spr_lane
        dpram_dc #(.widthad_a(7)) ram
        (
            .clock_a(clk), .address_a(m_a[8:2]), .data_a(m_do), .wren_a(m_spr && !m_wr_n && m_a[1:0] == l),
            .clock_b(clk), .address_b(spr_e), .q_b(spr_q[l])
        );
    end
endgenerate

// ------------------------------------------------------------------ main CPU data in
always_comb begin
    m_di = 8'hFF;
    if (m_rom)       m_di = rom_main_d;
    else if (m_ram)  m_di = m_ram_q;
    else if (m_lat)  m_di = latch;
    else if (m_vram) m_di = vram_q;
    else if (m_cram) m_di = cram_q;
    else if (m_adp)  m_di = adp_idle ? 8'h00 : 8'h80;
end

always_comb begin
    s_di = 8'hFF;
    if (s_rom)       s_di = rom_sub_d;
    else if (s_ram)  s_di = s_ram_q;
    else if (s_lat)  s_di = latch;
    else if (s_inp)  s_di = (s_inp_d ? tms_h : tms_now);
end

// ------------------------------------------------------------------ raster position from the CRTC
// x = pixel within the 256-pixel horizontal display window (every line), y = display line (0-191).
// MAME visible area: x 8-247 of that window, y 0-191.
logic       hd_q = 1'b0, de_q = 1'b0;
logic [7:0] px = 8'd0, py = 8'd0;
logic       first_de = 1'b1, vbl_q = 1'b1;
wire        hd_pix = !crtc_hbl;                                // horizontal display, CRTC changes on character edges
wire        de_pix = crtc_de;
always_ff @(posedge clk) begin
    if (ce_pix) begin
        hd_q  <= hd_pix;
        de_q  <= de_pix;
        vbl_q <= crtc_vbl;
        if (crtc_vbl) first_de <= 1'b1;
        if (hd_pix) begin
            if (!hd_q) begin
                px <= 8'd0;
                if (de_pix) begin
                    py <= first_de ? 8'd0 : py + 8'd1;
                    first_de <= 1'b0;
                end
            end
            else px <= px + 8'd1;
        end
    end
end

// logical (MAME) coordinates of the pixel at stage 0
wire [7:0] lx = crt_flip ? ~px : px;                           // CRT Flip mirrors the whole picture
wire [7:0] ly = crt_flip ? (8'd191 - py) : py;
wire [7:0] tx = flip ? ~lx : lx;                               // tilemap flip (MAME flip_screen_set: X and Y)
wire [7:0] ty = flip ? (8'd191 - ly) : ly;
wire [7:0] tmy = ty + 8'd32;                                   // MAME set_scrolldy(-32)

assign v_tile_a = {tmy[7:3], tx[7:3]};

// ------------------------------------------------------------------ sprite line buffer (built one line ahead)
// MAME draw_sprites: offs 0x1FC down to 0; the first sprite to cover a pixel wins (priority 31);
// pens 8-14 draw, pen 15 draws nothing but blocks later sprites, pens 0-7 are transparent.
// Buffer b holds physical line n with n[0] == b; colour index in BRAM, visible / taken flags in registers.
logic [7:0]   lb_q[2];
logic [7:0]   lb_wa, lb_wd, lb_ra;
logic         lb_we;
logic         build_buf = 1'b0;
// flags as plain 256-bit registers per buffer: a bit-select write into an unpacked array of vectors
// crashes Quartus 17 elaboration (VRFX AssignRam "other_index")
logic [255:0] lb_taken0 = '0, lb_taken1 = '0;
logic [255:0] lb_vis0   = '0, lb_vis1   = '0;
wire  [255:0] lb_taken_b = build_buf ? lb_taken1 : lb_taken0;

generate
    for (l = 0; l < 2; l++) begin : lbuf
        dpram_dc #(.widthad_a(8)) ram
        (
            .clock_a(clk), .address_a(lb_wa), .data_a(lb_wd), .wren_a(lb_we && build_buf == l),
            .clock_b(clk), .address_b(lb_ra), .q_b(lb_q[l])
        );
    end
endgenerate

typedef enum logic [2:0] {SP_IDLE, SP_ADDR, SP_CHK, SP_FETCH, SP_PIX} sp_state_t;
sp_state_t   sp_st = SP_IDLE;
logic  [6:0] sp_e7;
logic  [7:0] sp_line;                                          // logical (MAME) line being built
logic  [3:0] sp_px;
logic  [8:0] sp_x;
logic        sp_fx;
logic  [4:0] sp_color;
logic        sp_rom_ok;
logic [11:0] sp_rom_a;

assign spr_e     = sp_e7;
assign rom_spr_a = sp_rom_a;

// MAME sprite position (non-Indoor-Soccer layout), flip screen applied as in draw_sprites
wire  [7:0] sxp8 = spr_q[1] + 8'd8;
wire  [8:0] sx0  = {1'b0, sxp8} - 9'd8;                        // ((x + 8) & 0xFF) - 8
wire  [8:0] sy0  = {1'b0, spr_q[0]} - 9'd32;
wire  [8:0] sx   = flip ? 9'd240 - sx0 : sx0;
wire  [8:0] sy   = flip ? 9'd176 - sy0 : sy0;
wire        fx   = spr_q[2][6] ^ flip;
wire        fy   = (idsoccer ? 1'b0 : spr_q[2][7]) ^ flip;     // Indoor Soccer: no Y flip bit
wire  [9:0] sp_code10 = {spr_q[2][7], spr_q[2][4], spr_q[3]};  // Indoor Soccer: tile bits 9 (attr 7) and 8 (attr 4)

// Indoor Soccer row fetch: 8 bytes from the byte-wide sprite ROM
logic [16:0] sp_rom8_a;
logic  [3:0] sp_k;
logic [63:0] sp_row8;
assign rom_spr8_a = sp_rom8_a;
wire  [8:0] sr   = {1'b0, sp_line} - sy;
wire        on_line = !sr[8] && sr[7:4] == 4'd0;

wire  [3:0] sp_c    = sp_fx ? ~sp_px : sp_px;
wire [63:0] sp_rowd = idsoccer ? sp_row8 : rom_spr_d;
wire  [7:0] sp_byte = sp_rowd[{sp_c[3:1], 3'b000} +: 8];
wire  [3:0] sp_pen  = sp_c[0] ? sp_byte[3:0] : sp_byte[7:4];  // packed MSB first: even pixel in the high nibble
wire  [8:0] sp_xp   = sp_x + {5'd0, sp_px};

// Build two lines ahead so each build gets a full line: at the end of display line n build line n+2
// into buffer n[0] (just displayed); at vblank build lines 0 and 1.
logic       pend1 = 1'b0;
wire        go_vbl  = ce_pix && crtc_vbl && !vbl_q;
wire        go_line = ce_pix && de_q && !de_pix && py < 8'd190;

always_ff @(posedge clk) begin
    lb_we <= 1'b0;
    case (sp_st)
        SP_IDLE: if (go_vbl || go_line || pend1) begin : start_line
                     logic [7:0] phys;
                     phys  = go_vbl ? 8'd0 : go_line ? py + 8'd2 : 8'd1;
                     pend1 <= go_vbl;
                     sp_line   <= crt_flip ? 8'd191 - phys : phys;
                     build_buf <= phys[0];
                     if (phys[0]) begin lb_taken1 <= '0; lb_vis1 <= '0; end
                     else         begin lb_taken0 <= '0; lb_vis0 <= '0; end
                     sp_e7     <= 7'd127;
                     sp_st     <= SP_ADDR;
                 end
        SP_ADDR: sp_st <= SP_CHK;                              // sprite RAM read
        SP_CHK:  begin
                     if (on_line) begin
                         sp_rom_a  <= {spr_q[3], fy ? ~sr[3:0] : sr[3:0]};
                         sp_rom8_a <= {sp_code10, fy ? ~sr[3:0] : sr[3:0], 3'd0};
                         sp_k      <= 4'd0;
                         sp_x      <= sx;
                         sp_fx     <= fx;
                         sp_color  <= idsoccer ? {1'b0, spr_q[2][3:0]} : spr_q[2][4:0];
                         sp_px     <= 4'd0;
                         sp_rom_ok <= 1'b0;
                         sp_st     <= idsoccer ? SP_FETCH : SP_PIX;
                     end
                     else if (sp_e7 == 7'd0) sp_st <= SP_IDLE;
                     else begin sp_e7 <= sp_e7 - 7'd1; sp_st <= SP_ADDR; end
                 end
        SP_FETCH: begin                                        // address k on the bus, byte k-1 arrives
                     if (sp_k != 4'd0) sp_row8[{sp_k[2:0] - 3'd1, 3'b000} +: 8] <= rom_spr8_d;
                     sp_rom8_a[2:0] <= sp_rom8_a[2:0] + 3'd1;
                     sp_k <= sp_k + 4'd1;
                     if (sp_k == 4'd8) sp_st <= SP_PIX;
                 end
        SP_PIX:  begin
                     if (!sp_rom_ok) sp_rom_ok <= 1'b1;        // ROM read cycle
                     else begin
                         if (sp_pen[3] && !sp_xp[8] && !lb_taken_b[sp_xp[7:0]]) begin
                             if (build_buf) lb_taken1[sp_xp[7:0]] <= 1'b1;
                             else           lb_taken0[sp_xp[7:0]] <= 1'b1;
                             if (sp_pen != 4'hF) begin
                                 if (build_buf) lb_vis1[sp_xp[7:0]] <= 1'b1;
                                 else           lb_vis0[sp_xp[7:0]] <= 1'b1;
                                 lb_we <= 1'b1;
                                 lb_wa <= sp_xp[7:0];
                                 lb_wd <= {sp_color, sp_pen[2:0]};
                             end
                         end
                         sp_px <= sp_px + 4'd1;
                         if (sp_px == 4'd15) begin
                             if (sp_e7 == 7'd0) sp_st <= SP_IDLE;
                             else begin sp_e7 <= sp_e7 - 7'd1; sp_st <= SP_ADDR; end
                         end
                     end
                 end
    endcase
end

// ------------------------------------------------------------------ tile pipeline + priority + colour PROM
// stage 0: video RAM read (tile index from the logical position); 1: gfx1 row read; 2: line buffer read;
// 3: palette index; 4: colour PROM read -> RGB. Blanking and sync ride the same pipeline.
logic [7:0]  s1_code, s1_attr;
logic [2:0]  s1_tx, s1_ty;
logic [7:0]  s1_lx;
logic        s1_ln;
logic [31:0] s2_row;
logic [4:0]  s2_color;
logic [2:0]  s2_tx;
logic [7:0]  s2_lx;
logic        s2_ln;
logic [7:0]  s3_idx;
logic [3:0]  blk[3];                                           // {visible, hs, vs, vbl}

assign rom_tile_a = {s1_attr[5], s1_code, s1_ty};              // code + 8 * (colour & 0x20); 32 bytes per tile
assign lb_ra      = s2_lx;

wire [7:0] t_byte = s2_row[{s2_tx[2:1], 3'b000} +: 8];
wire [3:0] t_pen  = s2_tx[0] ? t_byte[3:0] : t_byte[7:4];
wire       t_front = pri_low ? !t_pen[3] : t_pen[3];          // MAME set_transmask: layer-0 pens drawn over sprites
wire       s_vis   = s2_ln ? lb_vis1[s2_lx] : lb_vis0[s2_lx];

wire vis_s0 = hd_pix && px >= 8'd8 && px < 8'd248;           // MAME visarea 8..247 of the 256-pixel window (horizontal)

always_ff @(posedge clk) begin
    if (ce_pix) begin
        s1_code <= v_code; s1_attr <= v_attr; s1_tx <= tx[2:0]; s1_ty <= tmy[2:0]; s1_lx <= lx; s1_ln <= py[0];
        s2_row  <= rom_tile_d; s2_color <= s1_attr[4:0]; s2_tx <= s1_tx; s2_lx <= s1_lx; s2_ln <= s1_ln;

        if (t_front)    s3_idx <= {s2_color, t_pen[2:0]};
        else if (s_vis) s3_idx <= lb_q[s2_ln];
        else            s3_idx <= {s2_color, t_pen[2:0]};

        blk[0] <= {vis_s0, crtc_hs, crtc_vs, crtc_vbl};
        for (int k = 1; k < 3; k++) blk[k] <= blk[k-1];
    end
end

logic [7:0] pal_q;
dpram_dc #(.widthad_a(8)) color_prom
(
    .clock_a(clk), .address_a(prom_a), .data_a(prom_d), .wren_a(prom_wr),
    .clock_b(clk), .address_b(s3_idx), .q_b(pal_q)
);

// MAME palette: R 0x23/0x4b/0x91 on bits 5-7, G on bits 2-4, B 0x52/0xad on bits 0-1
wire [7:0] c_r = (pal_q[5] ? 8'h23 : 8'h00) + (pal_q[6] ? 8'h4B : 8'h00) + (pal_q[7] ? 8'h91 : 8'h00);
wire [7:0] c_g = (pal_q[2] ? 8'h23 : 8'h00) + (pal_q[3] ? 8'h4B : 8'h00) + (pal_q[4] ? 8'h91 : 8'h00);
wire [7:0] c_b = (pal_q[0] ? 8'h52 : 8'h00) + (pal_q[1] ? 8'hAD : 8'h00);

logic out_vis = 1'b0, out_hs = 1'b0, out_vs = 1'b0, out_vbl = 1'b1;
always_ff @(posedge clk) begin
    if (ce_pix) begin
        video_r <= c_r; video_g <= c_g; video_b <= c_b;
        {out_vis, out_hs, out_vs, out_vbl} <= blk[2];          // same pixel as the colour PROM output
    end
end
assign video_hblank = !out_vis;
assign video_vblank = out_vbl;

// ------------------------------------------------------------------ CRT H/V position: the CRTC's own sync,
// re-timed from the blanking (self-calibrated each frame), so setting 0 is the native timing
logic       hb_q = 1'b1, vb_q = 1'b1, chs_q = 1'b0, cvs_q = 1'b0;
logic [8:0] hc = 9'd0, ln = 9'd0;
logic [8:0] hs_pos = 9'd0, hs_len = 9'd16, vs_pos = 9'd0, vs_len = 9'd3;
logic [8:0] hs_t = 9'd0, vs_t = 9'd0;
wire        hbl_now = !out_vis;
wire  [8:0] hc_cur  = (hbl_now && !hb_q) ? 9'd0 : hc + 9'd1;
wire  [8:0] ln_cur  = (out_vbl && !vb_q) ? 9'd0 : (hbl_now && !hb_q) ? ln + 9'd1 : ln;
wire  [8:0] hs_beg  = hs_pos + {{5{h_adj[3]}}, h_adj};
wire  [8:0] vs_beg  = vs_pos + {{5{v_adj[3]}}, v_adj};
always_ff @(posedge clk) begin
    if (ce_pix) begin
        hb_q <= hbl_now; vb_q <= out_vbl; chs_q <= out_hs; cvs_q <= out_vs;
        hc <= hc_cur; ln <= ln_cur;
        if (out_hs && !chs_q) begin hs_pos <= hc_cur; hs_t <= 9'd0; end
        else if (out_hs) hs_t <= hs_t + 9'd1;
        if (!out_hs && chs_q) hs_len <= hs_t + 9'd1;
        if (out_vs && !cvs_q) begin vs_pos <= ln_cur; vs_t <= 9'd0; end
        if (out_vs && (hbl_now && !hb_q)) vs_t <= vs_t + 9'd1;
        if (!out_vs && cvs_q) vs_len <= vs_t + 9'd1;
    end
end
wire [8:0] hs_end = hs_beg + hs_len;
wire [8:0] vs_end = vs_beg + vs_len;
assign video_hs = (hc_cur >= hs_beg) && (hc_cur < hs_end);
assign video_vs = (ln_cur >= vs_beg) && (ln_cur < vs_end);

endmodule
