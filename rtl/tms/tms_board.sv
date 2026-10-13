//============================================================================
//
//  Universal TMS99xx boards (Cosmic Guerilla, Get A Way)
//  Copyright (C) 2026 Rodimus
//
//  From MAME cosmicg.cpp (Nicola Salmoria, Lee Taylor) and getaway.cpp (hap, Angelo Salese).
//  CPU: Erik Piehl's TMS9900 VHDL (rtl/tms/tms9900.vhd), one instance for both boards.
//
//  Cosmic Guerilla (getaway = 0): TMS9980A 9.828 MHz / 4 (8-bit bus: +2 cycles per word access).
//    0000-1FFF ROM (data lines scrambled, decoded on read), 2000-3FFF video RAM with the CRTC in a hole
//    (3FF1 address, 3FF5 register write, 3FF7 register read). CRU bits 00-03 CRTC MA8-11, 04-07 IN0, 08-0F IN1;
//    writes 01-0F sound / flip (0A) / sound enable (0C), 16-17 colour registers. Coin = level 4 (held).
//    (CRU bit = MAME CRU map address / 2.)
//    MC6845 at 9.828 / 16; 1bpp bitmap coloured by a 1K map; pixel 4.914 MHz.
//  Get A Way (getaway = 1): TMS9900 3 MHz (cycle model 24 / 19.656 per clock). 0000-2FFF ROM (16-bit,
//    stored as high / low byte planes), 3800-3FFF RAM. CRU bits 00-04 pedal, 05-0C wheel, 0D-17 DSW, 19 coin,
//    1A start, 1B blitter busy (0); writes 00-7F = 16 registers driving a blitter (gfx ROM -> two 3-plane
//    bitmaps). Vblank = level 2.
//    MAME blits instantly; here the CPU is held at its next opcode fetch while the blitter runs.
//
//============================================================================

module tms_board
(
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic               pause,
    input  logic               getaway,
    input  logic               crt_flip,

    input  logic         [7:0] in0,            // cosmicg IN0 / getaway IN.0 (coin, start)
    input  logic         [7:0] in1,            // cosmicg IN1 / getaway controls: [0] accelerate, [1] left, [2] right (low)
    input  logic         [7:0] in2,            // cosmicg IN2: [0] coin (high), [1] cocktail
    input  logic         [7:0] dsw0,           // getaway DSW bits 0-7
    input  logic         [7:0] dsw1,           // getaway DSW bits 8-10

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
    output logic        [15:0] snd_out,        // cosmicg CRU output bits 0-15

    output logic        [14:0] rom_cpu_a,
    input  logic         [7:0] rom_cpu_d,
    output logic        [11:0] rom_chr_a,      // cosmicg colour map / getaway gfx (bit 12 of the gfx address = [15:8])
    input  logic        [15:0] rom_chr_d
);

// ------------------------------------------------------------------ clocks
logic [1:0] ph = 2'd0;
always_ff @(posedge clk) ph <= ph + 2'd1;
wire ce_cg = (ph == 2'd3);                                          // 4.914 MHz

logic [14:0] pix_acc = 15'd0;
wire  [15:0] pix_sum = {1'b0, pix_acc} + 16'd5408;
wire  [15:0] pix_sub = pix_sum - 16'd19656;
logic        ce_ga = 1'b0;
always_ff @(posedge clk) begin
    ce_ga   <= pix_sum >= 16'd19656;                                // 5.408 MHz (10.816 MHz XTAL / 2)
    pix_acc <= (pix_sum >= 16'd19656) ? pix_sub[14:0] : pix_sum[14:0];
end
assign ce_pix = getaway ? ce_ga : ce_cg;

// TMS9900 cycle model counts 8 per CPU cycle: 2.457 MHz at 1 per clock (cosmicg); 3 MHz adds 4344/19656 (getaway)
logic [14:0] st_acc = 15'd0;
logic        step2 = 1'b0;
wire  [15:0] st_sum = {1'b0, st_acc} + 16'd4344;
always_ff @(posedge clk) begin
    step2  <= getaway && st_sum >= 16'd19656;
    st_acc <= (st_sum >= 16'd19656) ? st_sum[14:0] - 15'd19656 : st_sum[14:0];
end

// ------------------------------------------------------------------ CPU
logic [15:0] cpu_a, cpu_do;
logic        cpu_rd, cpu_wr, cpu_as, cpu_cruin, cpu_cruout, cpu_cruclk, cpu_int_ack;
logic        cpu_ready = 1'b1;
logic        int_req;
logic  [7:0] bhi, blo;
logic        blit_busy;

tms9900 cpu                                                         // cycle_clks_g = 8 (VHDL default)
(
    .clk            (clk),
    .reset          (reset),
    .addr_out       (cpu_a),
    .data_in        ({bhi, blo}),
    .data_out       (cpu_do),
    .rd             (cpu_rd),
    .wr             (cpu_wr),
    .ready          (cpu_ready),
    .iaq            (),
    .as             (cpu_as),
    .alu_debug_arg1 (),
    .alu_debug_arg2 (),
    .cpu_debug_out  (),
    .mult_debug_out (),
    .int_req        (int_req),
    .ic03           (getaway ? 4'd2 : 4'd4),
    .int_ack        (cpu_int_ack),
    .cruin          (cpu_cruin),
    .cruout         (cpu_cruout),
    .cruclk         (cpu_cruclk),
    .hold           (pause | blit_busy),
    .holda          (),
    .waits          (8'd0),
    .scratch_en     (1'b0),
    .stuck          (),
    .turbo          (1'b0),
    .byte_bus       (~getaway),
    .ir_step2       (step2)
);

// ------------------------------------------------------------------ byte sequencer: every word = high byte
// (even address) then low byte, on 8-bit memories; READY holds the CPU until both are done
logic [1:0]  bs = 2'd0;
wire         bph = (bs == 2'd2);
wire  [15:0] ba  = {cpu_a[15:1], bph};
logic [15:0] ba_q;
logic  [7:0] byte_q;
wire         b_wr = cpu_wr && (bs == 2'd1 || bs == 2'd2);
wire  [7:0]  b_do = bph ? cpu_do[7:0] : cpu_do[15:8];

always_ff @(posedge clk) begin
    ba_q <= ba;
    if (reset) begin bs <= 2'd0; cpu_ready <= 1'b1; end
    else case (bs)
        2'd0: if (cpu_as) begin bs <= 2'd1; cpu_ready <= 1'b0; end
        2'd1: bs <= 2'd2;
        2'd2: begin bhi <= byte_q; bs <= 2'd3; end
        2'd3: begin blo <= byte_q; bs <= 2'd0; cpu_ready <= 1'b1; end
    endcase
end

// cosmicg map (14-bit bus)
wire cg_rom  = !ba[13];
wire cg_hole = ba[13:3] == 11'h7FE;                                 // 3FF0-3FF7
wire cg_vram = ba[13] && !cg_hole;
wire crtc_en = !getaway && cg_hole && (bs == 2'd2) && ((cpu_wr && (ba[2:0] == 3'd1 || ba[2:0] == 3'd5)) ||
                                                      (cpu_rd && ba[2:0] == 3'd7));
// getaway map
wire ga_rom = ba < 16'h3000;
wire ga_ram = ba[15:11] == 5'b00111;

assign rom_cpu_a = getaway ? {1'b0, ba[0], ba[13:1]} : {2'b00, ba[12:0]};

// cosmicg program ROM: two bytes have a bit flipped (MAME init_cosmicg), then the data lines are swapped
wire [7:0] cg_s = rom_cpu_d ^ ((ba_q[13:0] == 14'h1E9B || ba_q[13:0] == 14'h1E9F) ? 8'h20 : 8'h00);
wire [7:0] cg_rom_d = {cg_s[4], cg_s[5], cg_s[6], cg_s[7], cg_s[0], cg_s[1], cg_s[2], cg_s[3]};
// (s >> 3 & 0x11) | (s >> 1 & 0x22) | (s << 1 & 0x44) | (s << 3 & 0x88): 7<-4, 6<-5, 5<-6, 4<-7, 3<-0, 2<-1, 1<-2, 0<-3

logic [7:0] pl_qa[3], ram_q, crtc_do;
always_comb begin
    byte_q = 8'h00;
    if (!getaway) begin
        if (!ba_q[13])                          byte_q = cg_rom_d;
        else if (ba_q[13:3] == 11'h7FE)         byte_q = (ba_q[2:0] == 3'd7) ? crtc_do : 8'h00;
        else                                    byte_q = pl_qa[0];
    end
    else begin
        if (ba_q < 16'h3000)                    byte_q = rom_cpu_d;
        else if (ba_q[15:11] == 5'b00111)       byte_q = ram_q;
    end
end

dpram_dc #(.widthad_a(11)) work_ram
(
    .clock_a(clk), .address_a(ba[10:0]), .data_a(b_do), .wren_a(getaway && ga_ram && b_wr), .q_a(ram_q),
    .clock_b(clk), .address_b(11'd0), .q_b()
);

// ------------------------------------------------------------------ CRU
// CRU bit = address / 2 (MAME's CRU maps are in address units: map(0x10, 0x1f) = bits 8-15)
wire [10:0] cb = getaway ? {4'd0, cpu_a[7:1]} : cpu_a[11:1];       // getaway io_map global_mask(0xff)
logic [4:0] pedal = 5'd0;
logic [7:0] wheel = 8'd0;
wire [10:0] dsw   = {dsw1[2:0], dsw0};
logic [13:0] crtc_ma;
logic  [4:0] crtc_ra;
wire  [4:0] cb_w = cb[4:0] - 5'd5;                                  // wheel bit
wire  [4:0] cb_d = cb[4:0] - 5'd13;                                 // DSW bit

always_comb begin
    cpu_cruin = 1'b0;
    if (!getaway) begin
        if (cb[10:2] == 9'd0)                   cpu_cruin = crtc_ma[{2'b10, cb[1:0]}];   // MA8-11
        else if (cb[10:2] == 9'd1)              cpu_cruin = in0[cb[2:0]];                // IN0 bits 4-7
        else if (cb[10:3] == 8'd1)              cpu_cruin = in1[cb[2:0]];                // IN1 (DIPs 4-7)
    end
    else begin
        if (cb < 11'h005)                       cpu_cruin = pedal[cb[2:0]];              // 00-04 pedal
        else if (cb < 11'h00D)                  cpu_cruin = wheel[cb_w[2:0]];            // 05-0C wheel
        else if (cb < 11'h018)                  cpu_cruin = dsw[cb_d[3:0]];              // 0D-17 DSW
        else if (cb == 11'h019)                 cpu_cruin = in0[0];                      // coin
        else if (cb == 11'h01A)                 cpu_cruin = in0[1];                      // start
                                                                                         // 1B busy = 0
    end
end

logic       cruclk_d = 1'b0;
wire        cru_wr = cpu_cruclk && !cruclk_d && cpu_a[15:13] == 3'd0;   // external instructions use A0-A2
logic [1:0] creg = 2'd0;
logic [7:0] regs[16];
logic       blit_go;

always_ff @(posedge clk) begin
    cruclk_d <= cpu_cruclk;
    blit_go  <= 1'b0;
    if (reset) begin
        snd_out <= 16'd0; creg <= 2'd0;
        for (int i = 0; i < 16; i++) regs[i] <= 8'd0;
    end
    else if (cru_wr) begin
        if (!getaway) begin
            if (cb < 11'd16)                    snd_out[cb[3:0]] <= cpu_cruout;
            if (cb == 11'h016 || cb == 11'h017) creg[cb[0]] <= cpu_cruout;
        end
        else if (!cb[7]) begin
            regs[cb[6:3]][cb[2:0]] <= cpu_cruout;
            if (cb == 11'h00F && cpu_cruout && !regs[1][7]) blit_go <= 1'b1;    // reg 1 bit 7: 0 -> 1
        end
    end
end

// interrupts: cosmicg coin held on level 4; getaway vblank on level 2, held until acknowledged (max 2 lines)
logic       ga_irq = 1'b0;
logic [9:0] ga_irq_t = 10'd0;
logic       ga_vbl_d = 1'b0;
logic       ga_vbl;
always_ff @(posedge clk) begin
    ga_vbl_d <= ga_vbl;
    if (reset || cpu_int_ack)                     ga_irq <= 1'b0;
    else if (ga_vbl && !ga_vbl_d)                 begin ga_irq <= 1'b1; ga_irq_t <= 10'd0; end
    else if (ga_irq && ce_ga) begin
        ga_irq_t <= ga_irq_t + 10'd1;
        if (ga_irq_t == 10'd687) ga_irq <= 1'b0;
    end
end
assign int_req = getaway ? ga_irq : in2[0];

// getaway pedal / wheel from digital controls, once per frame (MAME PEDAL 0-1F, PADDLE -8..8)
always_ff @(posedge clk) begin
    if (reset) begin pedal <= 5'd0; wheel <= 8'd0; end
    else if (ga_vbl && !ga_vbl_d) begin
        if (!in1[0]) pedal <= (pedal >= 5'd29) ? 5'd31 : pedal + 5'd2;
        else         pedal <= (pedal <= 5'd2)  ? 5'd0  : pedal - 5'd2;
        if (!in1[1] && in1[2])       begin if ($signed(wheel) > -8'sd8) wheel <= wheel - 8'd1; end
        else if (!in1[2] && in1[1])  begin if ($signed(wheel) <  8'sd8) wheel <= wheel + 8'd1; end
        else if ($signed(wheel) > 0) wheel <= wheel - 8'd1;
        else if ($signed(wheel) < 0) wheel <= wheel + 8'd1;
    end
end

// ------------------------------------------------------------------ getaway blitter (MAME io_w, reg 1 bit 7)
typedef enum logic [2:0] {B_IDLE, B_GFX, B_GFXW, B_RD0, B_WR0, B_RD1, B_WR1, B_NEXT} bstate_t;
bstate_t     bst = B_IDLE;
logic [12:0] b_src;
logic  [2:0] b_cmask;
logic  [7:0] b_x, b_y, b_h, b_yi;
logic  [4:0] b_w, b_c;
logic        b_fill, b_main;
logic  [7:0] b_g;
assign blit_busy = (bst != B_IDLE) || blit_go;

wire  [7:0] b_dy   = b_y + b_yi;
wire  [4:0] b_col0 = b_x[7:3];
wire  [4:0] b_col1 = b_x[7:3] + 5'd1;
wire  [7:0] b_v8   = b_fill ? 8'hFF : {b_g[0], b_g[1], b_g[2], b_g[3], b_g[4], b_g[5], b_g[6], b_g[7]};
wire [15:0] b_v16  = {8'd0, b_v8} << b_x[2:0];
wire [15:0] b_m16  = 16'h00FF << b_x[2:0];
wire        b_hi   = (bst == B_RD1 || bst == B_WR1);
wire  [4:0] b_col  = b_hi ? b_col1 : b_col0;
wire  [7:0] b_m    = b_hi ? b_m16[15:8] : b_m16[7:0];
wire  [7:0] b_v    = b_hi ? b_v16[15:8] : b_v16[7:0];
wire        bl_wr  = (bst == B_WR0 || bst == B_WR1);

wire [7:0] gfx_d = b_src[12] ? rom_chr_d[15:8] : rom_chr_d[7:0];

always_ff @(posedge clk) begin
    if (reset) bst <= B_IDLE;
    else case (bst)
        B_IDLE: if (blit_go) begin
                    b_src   <= {regs[6][4:0], regs[5]};
                    b_cmask <= regs[6][7:5] ^ 3'd7;                 // drawn with colour 0 = white: xor-ed
                    b_x     <= regs[4];
                    b_y     <= regs[3];
                    b_h     <= regs[8];
                    b_w     <= regs[7][4:0];
                    b_fill  <= regs[1][6];
                    b_main  <= regs[1][3];
                    b_yi    <= 8'd0;
                    b_c     <= 5'd0;
                    bst     <= (regs[7][4:0] == 5'd0 || regs[8] == 8'd0) ? B_IDLE : B_GFX;
                end
        B_GFX:  bst <= B_GFXW;
        B_GFXW: begin b_g <= gfx_d; bst <= B_RD0; end
        B_RD0:  bst <= B_WR0;
        B_WR0:  bst <= (b_x[2:0] != 3'd0) ? B_RD1 : B_NEXT;
        B_RD1:  bst <= B_WR1;
        B_WR1:  bst <= B_NEXT;
        B_NEXT: begin
                    b_src <= b_src + 13'd1;
                    if (b_yi == b_h - 8'd1) begin
                        b_yi <= 8'd0;
                        b_x  <= b_x - 8'd8;
                        b_c  <= b_c + 5'd1;
                        bst  <= (b_c == b_w - 5'd1) ? B_IDLE : B_GFX;
                    end
                    else begin
                        b_yi <= b_yi + 8'd1;
                        bst  <= B_GFX;
                    end
                end
        default: bst <= B_IDLE;
    endcase
end

// ------------------------------------------------------------------ bitmaps
// planes 0-2: getaway main bitmap {column, y}; plane 0 is also the cosmicg video RAM.
// score planes: getaway score bitmap, columns 28-31 only (MAME shows it from x = 231)
logic [12:0] pl_ab;
logic  [7:0] pl_qb[3], sc_qa[3], sc_qb[3];
logic  [9:0] sc_ab;
wire  [12:0] pl_aa = getaway ? {b_col, b_dy} : ba[12:0];

genvar p;
generate
    for (p = 0; p < 3; p++) begin : planes
        // fill: every plane, main bitmap cleared / score bitmap set to the colour; copy: colour planes only
        wire       sel   = b_fill || b_cmask[p];
        wire [7:0] val   = b_fill ? ((!b_main && b_cmask[p]) ? 8'hFF : 8'h00) : b_v;
        wire [7:0] new_p = sel ? ((pl_qa[p] & ~b_m) | (val & b_m)) : pl_qa[p];
        wire [7:0] new_s = sel ? ((sc_qa[p] & ~b_m) | (val & b_m)) : sc_qa[p];

        dpram_dc #(.widthad_a(13)) pl
        (
            .clock_a(clk), .address_a(pl_aa),
            .data_a(getaway ? new_p : b_do),
            .wren_a(getaway ? (bl_wr && b_main) : (p == 0 && cg_vram && b_wr)),
            .q_a(pl_qa[p]),
            .clock_b(clk), .address_b(pl_ab), .q_b(pl_qb[p])
        );
        dpram_dc #(.widthad_a(10)) sc
        (
            .clock_a(clk), .address_a({b_col[1:0], b_dy}), .data_a(new_s),
            .wren_a(getaway && bl_wr && !b_main && b_col[4:2] == 3'b111), .q_a(sc_qa[p]),
            .clock_b(clk), .address_b(sc_ab), .q_b(sc_qb[p])
        );
    end
endgenerate

// ------------------------------------------------------------------ cosmicg video: MC6845, bitmap + colour map
logic [2:0] chr = 3'd0;
always_ff @(posedge clk) if (ce_cg) chr <= chr + 3'd1;
wire crtc_ce = ce_cg && chr == 3'd7;
logic crtc_hs, crtc_vs, crtc_vbl, crtc_hbl, crtc_de;

mc6845 crtc
(
    .CLOCK(clk), .CLKEN(crtc_ce), .nRESET(~reset),
    .ENABLE(crtc_en), .R_nW(cpu_rd), .RS(ba[2]), .DI(b_do), .DO(crtc_do),
    .VSYNC(crtc_vs), .HSYNC(crtc_hs), .VBLANK(crtc_vbl), .HBLANK(crtc_hbl), .DE(crtc_de),
    .CURSOR(), .LPSTB(1'b0), .MA(crtc_ma), .RA(crtc_ra)
);

// CRT Flip: mirrored MA / RA from the previous frame's first / last displayed character and last row line
logic [13:0] ma_first_c, ma_last_c, ma_sum = 14'd0;
logic  [4:0] ra_max_c = 5'd0, ra_max = 5'd0;
logic        first_de = 1'b1, cvbl_q = 1'b0;
always_ff @(posedge clk) begin
    if (crtc_ce) begin
        cvbl_q <= crtc_vbl;
        if (crtc_vbl && !cvbl_q) begin
            ma_sum <= ma_first_c + ma_last_c; ra_max <= ra_max_c;
            first_de <= 1'b1; ra_max_c <= 5'd0;
        end
        else if (crtc_de) begin
            if (first_de) ma_first_c <= crtc_ma;
            first_de  <= 1'b0;
            ma_last_c <= crtc_ma;
            if (crtc_ra > ra_max_c) ra_max_c <= crtc_ra;
        end
    end
end

wire        cg_flip = snd_out[10] && in2[1];                        // game flip only with the cocktail DIP
wire [13:0] ma_l = crt_flip ? ma_sum - crtc_ma : crtc_ma;
wire  [4:0] ra_l = crt_flip ? ra_max - crtc_ra : crtc_ra;
// MA7-MA12 on the schematic are MA6-MA11, with RA0 as MA6
wire [12:0] offs_n = {ma_l[11:5], ra_l[0], ma_l[4:0]};
wire [11:0] cg_cmap_a = {2'b00, creg[1], creg[0], offs_n[12:9], offs_n[4:1]};
assign rom_chr_a = getaway ? b_src[11:0] : cg_cmap_a;

// getaway video coordinates (stage 0)
logic [8:0] hcnt = 9'd0, vcnt = 9'd0;
wire  [7:0] gx = crt_flip ? 8'd255 - hcnt[7:0] : hcnt[7:0] + 8'd8;   // MAME visible x 8-255
wire  [7:0] gy = crt_flip ? 8'd239 - vcnt[7:0] : vcnt[7:0];          // y 0-239

assign pl_ab = getaway ? {gx[7:3], gy} : (cg_flip ? ~offs_n : offs_n);
assign sc_ab = {gx[4:3], gy};

// cosmicg pixel stream: a character's data is latched at its end and shown during the next (all signals
// delayed by the same 8 pixels)
logic [7:0] cd_lat, cc_lat;
logic       cde1 = 1'b0, chs1 = 1'b0, cvs1 = 1'b0, cvbl1 = 1'b1, crev = 1'b0, cfl1 = 1'b0;
always_ff @(posedge clk) begin
    if (ce_cg && chr == 3'd7) begin
        cd_lat <= pl_qb[0]; cc_lat <= rom_chr_d[7:0];
        cde1 <= crtc_de; chs1 <= crtc_hs; cvs1 <= crtc_vs; cvbl1 <= crtc_vbl;
        crev <= cg_flip ^ crt_flip; cfl1 <= cg_flip;
    end
end
wire [3:0] cg_col = cfl1 ? cc_lat[7:4] : cc_lat[3:0];
wire       cg_bit = crev ? cd_lat[chr] : cd_lat[3'd7 - chr];
wire [3:0] cg_pen = cg_bit ? cg_col : {cg_col[3], 3'd0};

// getaway timing: 344 x 262 at 5.408 MHz (60.0 Hz), visible 248 x 240
always_ff @(posedge clk) begin
    if (ce_ga) begin
        if (hcnt == 9'd343) begin
            hcnt <= 9'd0;
            vcnt <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
        end
        else hcnt <= hcnt + 9'd1;
    end
end
assign ga_vbl = vcnt >= 9'd240;
wire [8:0] g_hs0 = 9'd280 + {{5{h_adj[3]}}, h_adj};
wire [8:0] g_vs0 = 9'd244 + {{5{v_adj[3]}}, v_adj};

logic [2:0] g_bits;
logic [3:0] g1_blk;
always_ff @(posedge clk) begin
    if (ce_ga) begin                                                // RAM data of the pixel at stage 0
        g_bits <= (gx >= 8'd231) ? {sc_qb[2][gx[2:0]], sc_qb[1][gx[2:0]], sc_qb[0][gx[2:0]]}
                                 : {pl_qb[2][gx[2:0]], pl_qb[1][gx[2:0]], pl_qb[0][gx[2:0]]};
        g1_blk <= {hcnt >= 9'd248, ga_vbl, hcnt >= g_hs0 && hcnt < g_hs0 + 9'd32, vcnt >= g_vs0 && vcnt < g_vs0 + 9'd3};
    end
end
logic [2:0] g_pen;
always_comb case (g_bits)                                           // MAME clut { 0, 1, 6, 5, 4, 3, 2, 7 }
    3'd0: g_pen = 3'd0; 3'd1: g_pen = 3'd1; 3'd2: g_pen = 3'd6; 3'd3: g_pen = 3'd5;
    3'd4: g_pen = 3'd4; 3'd5: g_pen = 3'd3; 3'd6: g_pen = 3'd2; 3'd7: g_pen = 3'd7;
endcase

logic c_vis = 1'b0, c_hs = 1'b0, c_vs = 1'b0, c_vbl = 1'b1;

// cosmicg CRT H/V position: the CRTC's own sync re-timed from the blanking (Castle board pattern)
logic       hb_q = 1'b1, vb_q = 1'b1, chs_q = 1'b0, cvs_q = 1'b0;
logic [8:0] hc = 9'd0, ln = 9'd0;
logic [8:0] hs_pos = 9'd0, hs_len = 9'd16, vs_pos = 9'd0, vs_len = 9'd3;
logic [8:0] hs_t = 9'd0, vs_t = 9'd0;
wire        hbl_now = !c_vis;
wire  [8:0] hc_cur  = (hbl_now && !hb_q) ? 9'd0 : hc + 9'd1;
wire  [8:0] ln_cur  = (c_vbl && !vb_q) ? 9'd0 : (hbl_now && !hb_q) ? ln + 9'd1 : ln;
wire  [8:0] hs_beg  = hs_pos + {{5{h_adj[3]}}, h_adj};
wire  [8:0] vs_beg  = vs_pos + {{5{v_adj[3]}}, v_adj};
always_ff @(posedge clk) begin
    if (ce_cg) begin
        hb_q <= hbl_now; vb_q <= c_vbl; chs_q <= c_hs; cvs_q <= c_vs;
        hc <= hc_cur; ln <= ln_cur;
        if (c_hs && !chs_q) begin hs_pos <= hc_cur; hs_t <= 9'd0; end
        else if (c_hs) hs_t <= hs_t + 9'd1;
        if (!c_hs && chs_q) hs_len <= hs_t + 9'd1;
        if (c_vs && !cvs_q) begin vs_pos <= ln_cur; vs_t <= 9'd0; end
        if (c_vs && (hbl_now && !hb_q)) vs_t <= vs_t + 9'd1;
        if (!c_vs && cvs_q) vs_len <= vs_t + 9'd1;
    end
end
wire cg_hs = (hc_cur >= hs_beg) && (hc_cur < hs_beg + hs_len);
wire cg_vs = (ln_cur >= vs_beg) && (ln_cur < vs_beg + vs_len);

// ------------------------------------------------------------------ output
always_ff @(posedge clk) begin
    if (getaway ? ce_ga : ce_cg) begin
        if (getaway) begin                                          // BRG_3BIT: R = bit 1, G = bit 2, B = bit 0
            video_r <= {8{g_pen[1]}}; video_g <= {8{g_pen[2]}}; video_b <= {8{g_pen[0]}};
            video_hblank <= g1_blk[3]; video_vblank <= g1_blk[2];
            video_hs <= g1_blk[1]; video_vs <= g1_blk[0];
        end
        else begin                                                  // MAME cosmicg_palette
            video_r <= (cg_pen > 4'd8) ? 8'hFF : cg_pen[0] ? 8'hAA : 8'h00;
            video_g <= cg_pen[1] ? 8'hAA : 8'h00;
            video_b <= cg_pen[2] ? 8'hAA : 8'h00;
            c_vis <= cde1; c_hs <= chs1; c_vs <= cvs1; c_vbl <= cvbl1;
            video_hblank <= !cde1; video_vblank <= cvbl1;
            video_hs <= cg_hs; video_vs <= cg_vs;
        end
    end
end

// cosmicg sound (rtl/tms/cosmicg_sound.sv); Get A Way: discrete, no schematic or recording (MAME: no sound)
logic signed [15:0] cg_snd;
cosmicg_sound cg_sound
(
    .clk   (clk),
    .reset (reset | getaway),
    .we    (cru_wr && !getaway && cb < 11'd16),
    .wa    (cb[3:0]),
    .wd    (cpu_cruout),
    .audio (cg_snd)
);
assign audio = getaway ? 16'sd0 : cg_snd;

endmodule
