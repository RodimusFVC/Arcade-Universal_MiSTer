//============================================================================
//
//  Universal Cosmic boards (Space Panic, Cosmic Alien, Magical Spot, Devil Zone, No Man's Land)
//  Copyright (C) 2026 Rodimus
//
//  From MAME cosmic.cpp / cosmic_v.cpp (Nicola Salmoria, Lee Taylor).
//
//  kind: 0 panic, 1 cosmica, 2 magspot, 3 devzone, 4 nomnlnd.
//  Video 10.816 MHz / 2 = 5.408 MHz (fractional enable from 19.656 MHz), 352 x 262, visible x 0-255, y 32-223.
//  Z80 10.816 MHz / 6 (panic, cosmica) or / 4 (magspot family).
//    panic / cosmica: 0000-3FFF ROM, 4000-5FFF video RAM, 6000-601F sprites, 6800-6803 inputs,
//                     7000-700B sound, 700C-700E colour registers, 700F flip, 7800-7801 sound (panic)
//    magspot family:  0000-2FFF ROM, 3800-3807 coinage DIP bits, 4000-401F sprites, 4800 DAC (nomnlnd 480A),
//                     4807 background enable, 480C-480D colour registers, 480F flip, 5000-5003 inputs,
//                     6000-7FFF video RAM
//  Interrupts: panic RST 08 at line 0 / RST 10 at line 224 (held to the acknowledge); cosmica coin = NMI;
//  magspot / devzone coin 1 = IRQ (RST 38), coin 2 = NMI; nomnlnd coin = NMI.
//  Picture (MAME): background (cosmica stars / devzone grid) < 1bpp bitmap coloured by the user1 map < 8
//  sprites (16x16 / 32x32, Y flip) < nomnlnd trees and river. Game flip mirrors bitmap, grid and trees, not
//  the sprites or stars; CRT Flip mirrors the logical raster (visible area symmetric).
//  Stars: the IC11 map latch is the PROM byte at the last x1 = 32n crossing (closed form, mirror-safe).
//  Grid: the RLE PROM is decoded once per frame in vblank into a frame RAM (read mirrored when flipped).
//
//============================================================================

module cosmic_board
(
    output logic        [13:0] z80_o,          // shared T80 (rtl/z80_socket.sv)
    input  logic        [29:0] z80_i,
    input  logic               clk,            // 19.656 MHz
    input  logic               reset,
    input  logic               pause,
    input  logic         [2:0] kind,
    input  logic               crt_flip,

    input  logic         [7:0] in0,            // panic / cosmica P1, magspot IN0
    input  logic         [7:0] in1,            // P2 / IN1
    input  logic         [7:0] in2,            // panic SYSTEM / IN2
    input  logic         [7:0] dsw0,           // panic / cosmica DSW / IN3
    input  logic         [7:0] dsw1,           // magspot DSW (coinage bits)
    input  logic         [7:0] coin,           // cosmica FAKE / magspot COINS / nomnlnd COIN, active high

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
    output logic        [13:0] snd_trig,       // 7000-700B (bit = data != 0), 7800-7801 (panic)

    output logic        [14:0] rom_cpu_a,
    input  logic         [7:0] rom_cpu_d,
    output logic        [11:0] rom_cmap_a,     // user1 colour map
    input  logic         [7:0] rom_cmap_d,
    output logic        [11:0] rom_u2_a,       // user2 (stars / grid / tree + river), port 1
    input  logic         [7:0] rom_u2_d,
    output logic        [11:0] rom_u2b_a,      // user2 port 2 (tree + river plane 2)
    input  logic         [7:0] rom_u2b_d,
    output logic        [11:0] rom_spr_a,      // gfx1: [7:0] first half (pen bit 1), [15:8] second half (pen bit 0)
    input  logic        [15:0] rom_spr_d,

    input  logic               prom_wr,        // 0x00-0x1F sprite colour PROM, 0x40-0x5F user3 (grid columns)
    input  logic         [6:0] prom_a,
    input  logic         [7:0] prom_d,

    output logic        [12:0] grid_wa,        // devzone grid frame (192 lines x 32 bytes) in a free RAM
    output logic         [7:0] grid_wd,
    output logic               grid_we,
    output logic        [12:0] grid_ra,
    input  logic         [7:0] grid_q
);

wire k_panic = (kind == 3'd0);
wire k_cosa  = (kind == 3'd1);
wire k_mag   = (kind >= 3'd2);
wire k_dev   = (kind == 3'd3);
wire k_nml   = (kind == 3'd4);

// ------------------------------------------------------------------ clocks
logic [14:0] pix_acc = 15'd0;
wire  [15:0] pix_sum = {1'b0, pix_acc} + 16'd5408;
wire  [15:0] pix_sub = pix_sum - 16'd19656;
always_ff @(posedge clk) begin
    ce_pix  <= pix_sum >= 16'd19656;
    pix_acc <= (pix_sum >= 16'd19656) ? pix_sub[14:0] : pix_sum[14:0];
end

// CPU edge stream: 10.816 MHz / 3 (1.8027 MHz CPU) or / 2 (2.704 MHz CPU), over 58968 = 3 * 19656
wire  [16:0] cpu_inc = k_mag ? 17'd16224 : 17'd10816;
logic [16:0] cpu_acc = 17'd0;
logic        cpu_ph = 1'b0, cen_p = 1'b0, cen_n = 1'b0;
wire  [17:0] cpu_sum  = {1'b0, cpu_acc} + {1'b0, cpu_inc};
wire         cpu_edge = cpu_sum >= 18'd58968;
wire  [17:0] cpu_sub  = cpu_sum - 18'd58968;
always_ff @(posedge clk) begin
    cpu_acc <= cpu_edge ? cpu_sub[16:0] : cpu_sum[16:0];
    cen_p   <= cpu_edge & ~cpu_ph;
    cen_n   <= cpu_edge &  cpu_ph;
    if (cpu_edge) cpu_ph <= ~cpu_ph;
end

// ------------------------------------------------------------------ video timing
logic [8:0] hcnt = 9'd0, vcnt = 9'd0;
always_ff @(posedge clk) begin
    if (ce_pix) begin
        if (hcnt == 9'd351) begin
            hcnt <= 9'd0;
            vcnt <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
        end
        else hcnt <= hcnt + 9'd1;
    end
end

wire [8:0] hs_start = 9'd288 + {{5{h_adj[3]}}, h_adj};
wire [8:0] vs_start = 9'd240 + {{5{v_adj[3]}}, v_adj};
wire hbl_s0 = hcnt[8];
wire vbl_s0 = (vcnt < 9'd32) || (vcnt >= 9'd224);
wire hs_s0  = (hcnt >= hs_start) && (hcnt < hs_start + 9'd32);
wire vs_s0  = (vcnt >= vs_start) && (vcnt < vs_start + 9'd3);
wire line0   = ce_pix && hcnt == 9'd351 && vcnt == 9'd261;          // next pixel: line 0
wire line224 = ce_pix && hcnt == 9'd351 && vcnt == 9'd223;          // next pixel: line 224 (vblank)

logic [7:0] frame = 8'd0;                                           // MAME screen frame number (stars, river)
always_ff @(posedge clk) if (line224) frame <= frame + 8'd1;

// ------------------------------------------------------------------ CPU
logic        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n;
logic [15:0] a;
logic  [7:0] din, dout;
logic        int_n = 1'b1;
logic  [7:0] int_vec = 8'hFF;
wire         nmi_n = k_panic ? 1'b1 : (k_cosa || k_nml) ? ~coin[0] : ~coin[1];

z80_socket cpu
(
    .RESET_n   (~reset),
    .CLK       (clk),
    .CEN_p     (cen_p & ~pause),
    .CEN_n     (cen_n & ~pause),
    .WAIT_n    (1'b1),
    .INT_n     (int_n),
    .NMI_n     (nmi_n),
    .BUSRQ_n   (1'b1),
    .M1_n      (m1_n),
    .MREQ_n    (mreq_n),
    .IORQ_n    (iorq_n),
    .RD_n      (rd_n),
    .WR_n      (wr_n),
    .RFSH_n    (rfsh_n),
    .HALT_n    (),
    .BUSAK_n   (),
    .OUT0      (1'b0),
    .A         (a),
    .DI        (din),
    .DO        (dout),
    .R800_mode (1'b0),
    .REG       (),
    .DIRSet    (1'b0),
    .DIR       (212'd0),
    .to_cpu    (z80_o),
    .from_cpu  (z80_i)
);

wire mem  = !mreq_n && rfsh_n;
wire inta = !m1_n && !iorq_n && mreq_n;                            // MREQ high: not an opcode fetch (T80 IORQ_n powers up low)
wire wr   = !wr_n;

// panic / cosmica map
wire pc_rom  = mem && !k_mag && a[15:14] == 2'b00;
wire pc_vid  = mem && !k_mag && a[15:13] == 3'b010;
wire pc_spr  = mem && !k_mag && a[15:5] == 11'b01100000000;
wire pc_in   = mem && !k_mag && a[15:11] == 5'b01101;
wire pc_snd  = mem && !k_mag && a[15:11] == 5'b01110 && a[3:0] < 4'd12;
wire pc_col  = mem && !k_mag && a[15:11] == 5'b01110 && a[3:0] >= 4'd12 && a[3:0] <= (k_panic ? 4'd14 : 4'd13);
wire pc_flip = mem && !k_mag && a[15:11] == 5'b01110 && a[3:0] == 4'd15;
wire pc_snd2 = mem && k_panic && a[15:11] == 5'b01111 && !a[1];
// magspot family map
wire mg_rom  = mem && k_mag && a < 16'h3000;
wire mg_dip  = mem && k_mag && a[15:11] == 5'b00111;
wire mg_spr  = mem && k_mag && a[15:5] == 11'b01000000000;
wire mg_io   = mem && k_mag && a[15:11] == 5'b01001;              // 4800-480F
wire mg_in   = mem && k_mag && a[15:11] == 5'b01010;
wire mg_vid  = mem && k_mag && a[15:13] == 3'b011;

wire vid_cs = pc_vid || mg_vid;
wire spr_cs = pc_spr || mg_spr;
assign rom_cpu_a = {1'b0, a[13:0]};

logic       flip = 1'b0, bg_en = 1'b0, dac = 1'b0;
logic [15:0] mg_snd = 16'd0;                                        // magspot family: LS259s latch D7 of 4800-480F
logic [2:0] creg = 3'd0;
always_ff @(posedge clk) begin
    if (reset) begin
        flip <= 1'b0; bg_en <= 1'b0; dac <= 1'b0; creg <= 3'd0; snd_trig <= 14'd0; mg_snd <= 16'd0;
    end
    else if (wr) begin
        if (pc_snd)  snd_trig[a[3:0]] <= (dout != 8'd0);
        if (pc_snd2) snd_trig[4'd12 + {3'd0, a[0]}] <= (dout != 8'd0);
        if (pc_snd && a[3:0] == 4'd10) dac <= dout[7];               // panic: bonus
        if (pc_col)  creg[a[1:0]] <= (dout != 8'd0);
        if (pc_flip) flip <= dout[7];
        if (mg_io) begin
            mg_snd[a[3:0]] <= dout[7];
            if (a[3:0] == (k_nml ? 4'd10 : 4'd0)) dac <= dout[7];
            if (a[3:0] == 4'd7 && (k_dev || k_nml)) bg_en <= dout != 8'd0;
            if (a[3:1] == 3'd6) creg[{1'b0, a[0]}] <= (dout != 8'd0);
            if (a[3:0] == 4'd15) flip <= dout[7];
        end
    end
end

// Space Panic: 8015 sound board (rtl/cosmic/panic_sound.sv)
logic signed [15:0] panic_snd;
panic_sound panic_snd_b
(
    .clk    (clk),
    .reset  (reset | ~k_panic),
    .trig   (snd_trig),
    .music  (dac),
    .coin_n (in2[6] & in2[7]),                                     // coin switches wired to the sound board
    .audio  (panic_snd)
);
// Cosmic Alien: 7910-S sound board (rtl/cosmic/cosmica_sound.sv)
logic signed [15:0] cosa_snd;
cosmica_sound cosa_snd_b
(
    .clk    (clk),
    .reset  (reset | ~k_cosa),
    .trig   (snd_trig[11:0]),
    .coin   (coin[0]),
    .audio  (cosa_snd)
);
// Magical Spot / Devil Zone: 8013 / 8022 sound board; No Man's Land: 8003 (rtl/cosmic/magspot_sound.sv, nomnlnd_sound.sv)
logic signed [15:0] ms_snd, nml_snd;
magspot_sound ms_snd_b
(
    .clk     (clk),
    .reset   (reset | ~(k_mag & ~k_nml)),
    .snd     (mg_snd),
    .coin_sw (coin[0] | coin[1]),
    .audio   (ms_snd)
);
nomnlnd_sound nml_snd_b
(
    .clk     (clk),
    .reset   (reset | ~k_nml),
    .snd     (mg_snd),
    .coin_sw (coin[0]),
    .audio   (nml_snd)
);
assign audio = k_panic ? panic_snd : k_cosa ? cosa_snd : k_nml ? nml_snd : ms_snd;

// interrupts
logic [1:0] coin_d = 2'b00;
always_ff @(posedge clk) begin
    coin_d <= coin[1:0];
    if (reset)                                    begin int_n <= 1'b1; int_vec <= 8'hFF; end
    else if (inta)                                int_n <= 1'b1;                       // HOLD_LINE: cleared on acknowledge
    else if (k_panic && line0)                    begin int_n <= 1'b0; int_vec <= 8'hCF; end   // RST 08
    else if (k_panic && line224)                  begin int_n <= 1'b0; int_vec <= 8'hD7; end   // RST 10
    else if ((kind == 3'd2 || k_dev) && coin[0] && !coin_d[0]) begin int_n <= 1'b0; int_vec <= 8'hFF; end
end

// video RAM (also the work RAM)
logic  [7:0] vram_q, vram_vq;
logic [12:0] vram_va;
dpram_dc #(.widthad_a(13)) video_ram
(
    .clock_a(clk), .address_a(a[12:0]), .data_a(dout), .wren_a(vid_cs && wr), .q_a(vram_q),
    .clock_b(clk), .address_b(vram_va), .q_b(vram_vq)
);

logic [7:0] spram[32];
always_ff @(posedge clk) if (spr_cs && wr) spram[a[4:0]] <= dout;

// inputs
wire  [7:0] in3 = {dsw0[7:1], k_dev ? ~vbl_s0 : vbl_s0};            // IN3 bit 0: vblank (devzone active low)
function automatic [7:0] nml_remap(input [7:0] ctl, input [7:0] fire);
    if ((fire & 8'hC0) == 8'd0)          nml_remap = 8'hFF;
    else if ((ctl & 8'h82) == 8'd0)      nml_remap = 8'hFE;
    else if ((ctl & 8'h0A) == 8'd0)      nml_remap = 8'hFB;
    else if ((ctl & 8'h28) == 8'd0)      nml_remap = 8'hEF;
    else if ((ctl & 8'hA0) == 8'd0)      nml_remap = 8'hBF;
    else                                 nml_remap = ctl;
endfunction

always_comb begin
    din = 8'hFF;
    if (inta)                     din = int_vec;
    else if (pc_rom || mg_rom)    din = rom_cpu_d;
    else if (vid_cs)              din = vram_q;
    else if (pc_in)
        case (a[1:0])
            2'd0: din = in0;
            2'd1: din = in1;
            2'd2: din = dsw0;
            2'd3: din = k_panic ? in2 : {2'b00, vcnt[7:2]};       // cosmica: (vpos >> 2) & 0x3F
        endcase
    else if (mg_dip)              din = k_nml ? 8'd1 : {7'd0, ~dsw1[3'd7 - a[2:0]]};
    else if (mg_in)
        case (a[1:0])
            2'd0: din = k_nml ? nml_remap(in0, in3) : in0;
            2'd1: din = k_nml ? nml_remap(in1, in3) : in1;
            2'd2: din = in2;
            2'd3: din = in3;
        endcase
end

// ------------------------------------------------------------------ PROMs
logic [7:0] prom[32], vprom[32];
always_ff @(posedge clk) begin
    if (prom_wr && prom_a[6:5] == 2'd0) prom[prom_a[4:0]]  <= prom_d;
    if (prom_wr && prom_a[6:5] == 2'd2) vprom[prom_a[4:0]] <= prom_d;
end

// ------------------------------------------------------------------ devzone grid (MAME devzone_draw_grid)
// Per 8-pixel group: if count == 0, count = PROM[addr++]; count++; if count == 0, horz = PROM[addr++];
// pixels = ~(vert & horz) (after a group horz has shifted in all ones = 0xFF).
typedef enum logic [2:0] {G_IDLE, G_GROUP, G_AW, G_A, G_BW, G_B, G_OUT} gstate_t;
gstate_t     gs = G_IDLE;
logic [10:0] g_addr;
logic  [7:0] g_count, g_horz;
logic [12:0] g_pos;
logic [10:0] g_rda;

always_ff @(posedge clk) begin
    grid_we <= 1'b0;
    case (gs)
        G_IDLE:  if (line224 && k_dev) begin g_addr <= 11'd0; g_count <= 8'd0; g_pos <= 13'd0; gs <= G_GROUP; end
        G_GROUP: begin
                     g_horz <= 8'hFF;
                     if (g_count == 8'd0) begin g_rda <= g_addr; g_addr <= g_addr + 11'd1; gs <= G_AW; end
                     else if (g_count == 8'hFF) begin g_count <= 8'd0; g_rda <= g_addr; g_addr <= g_addr + 11'd1; gs <= G_BW; end
                     else begin g_count <= g_count + 8'd1; gs <= G_OUT; end
                 end
        G_AW:    gs <= G_A;
        G_A:     if (rom_u2_d == 8'hFF) begin g_count <= 8'd0; g_rda <= g_addr; g_addr <= g_addr + 11'd1; gs <= G_BW; end
                 else begin g_count <= rom_u2_d + 8'd1; gs <= G_OUT; end
        G_BW:    gs <= G_B;
        G_B:     begin g_horz <= rom_u2_d; gs <= G_OUT; end
        G_OUT:   begin
                     grid_we <= 1'b1;
                     grid_wa <= g_pos;
                     grid_wd <= ~(vprom[g_pos[4:0]] & g_horz);
                     g_pos   <= g_pos + 13'd1;
                     gs      <= (g_pos == 13'd6143) ? G_IDLE : G_GROUP;
                 end
        default: gs <= G_IDLE;
    endcase
end

// ------------------------------------------------------------------ sprites: line buffer built a line ahead
logic [6:0] lb_q[2];
logic [7:0] lb_q_w[2];
logic [7:0] lb_wa, lb_ra;
logic [6:0] lb_wd;
logic       lb_we = 1'b0;
logic       lb_clr;
logic       build_buf = 1'b0;
wire        disp_buf;

genvar l;
generate
    for (l = 0; l < 2; l++) begin : lbuf
        dpram_dc #(.widthad_a(8), .width_a(8)) ram
        (
            .clock_a(clk), .address_a(lb_wa), .data_a({1'b0, lb_wd}), .wren_a(lb_we && build_buf == l),
            .clock_b(clk), .address_b(lb_ra), .data_b(8'd0), .wren_b(lb_clr && disp_buf == l), .q_b(lb_q_w[l])
        );
    end
endgenerate
assign lb_q[0] = lb_q_w[0][6:0];
assign lb_q[1] = lb_q_w[1][6:0];

typedef enum logic [2:0] {S_IDLE, S_SPR, S_COL, S_ROW_W, S_ROW_R, S_PIX, S_NEXT} sstate_t;
sstate_t    ss = S_IDLE;
wire  [8:0] tgt = (vcnt >= 9'd260) ? vcnt - 9'd260 : vcnt + 9'd2;
logic [7:0] sl_line;
logic [2:0] s_n;
logic [1:0] s_col;
logic [2:0] s_px;
logic [8:0] s_x;
logic [4:0] s_rr;
logic [3:0] s_color;
logic [6:0] s_code;
logic       s_big;
logic [15:0] s_d;

wire  [7:0] sb0 = spram[{s_n, 2'd0}], sb1 = spram[{s_n, 2'd1}], sb2 = spram[{s_n, 2'd2}], sb3 = spram[{s_n, 2'd3}];
wire        e_big = !sb0[7];
wire  [8:0] e_r   = {1'b0, sl_line} - {1'b0, sb1};
wire        e_vis = sb0 != 8'd0 && !e_r[8] && (e_big ? e_r[7:5] == 3'd0 : e_r[7:4] == 4'd0);
wire  [4:0] e_rr  = !sb0[6] ? ((e_big ? 5'd31 : 5'd15) - e_r[4:0]) : e_r[4:0];      // ~spr0 & 0x40: Y flip
wire  [3:0] cmask = k_cosa ? 4'hF : 4'h7;

wire  [2:0] pb    = 3'd7 - s_px;
wire  [1:0] s_pen = {s_d[{1'b0, pb}], s_d[{1'b1, pb}]};
wire  [8:0] wx    = s_x + {4'd0, s_col, s_px};

always_ff @(posedge clk) begin
    lb_we <= 1'b0;
    if (ce_pix && hcnt == 9'd351) begin                   // build line vcnt + 2 during line vcnt + 1
        sl_line   <= crt_flip ? ~tgt[7:0] : tgt[7:0];
        build_buf <= vcnt[0];
        s_n <= 3'd7;
        ss  <= S_SPR;
    end
    else case (ss)
        S_IDLE:  ;
        S_SPR:   if (e_vis) begin                                         // MAME order: offset 28 first, 0 last (wins)
                     s_code  <= {k_panic ? sb3[3] : 1'b0, ~sb0[5:0]};
                     s_color <= ~sb3[3:0] & cmask;
                     s_big   <= e_big;
                     s_rr    <= e_rr;
                     s_x     <= 9'd256 - {1'b0, sb2};
                     s_col   <= 2'd0;
                     ss      <= S_COL;
                 end
                 else ss <= S_NEXT;
        S_COL:   begin
                     rom_spr_a <= s_big ? {s_code[6:2], s_col, s_rr} : {s_code, s_col[0], s_rr[3:0]};
                     ss <= S_ROW_W;
                 end
        S_ROW_W: ss <= S_ROW_R;
        S_ROW_R: begin s_d <= rom_spr_d; s_px <= 3'd0; ss <= S_PIX; end
        S_PIX:   begin
                     if (s_pen != 2'd0 && !wx[8]) begin
                         lb_we <= 1'b1; lb_wa <= wx[7:0]; lb_wd <= {1'b1, s_color, s_pen};
                     end
                     s_px <= s_px + 3'd1;
                     if (s_px == 3'd7) begin
                         if (s_col == (s_big ? 2'd3 : 2'd1)) ss <= S_NEXT;
                         else begin s_col <= s_col + 2'd1; ss <= S_COL; end
                     end
                 end
        S_NEXT:  if (s_n == 3'd0) ss <= S_IDLE; else begin s_n <= s_n - 3'd1; ss <= S_SPR; end
        default: ss <= S_IDLE;
    endcase
end

// ------------------------------------------------------------------ picture pipeline
// S0: logical coordinates (CRT Flip), bitmap source (game flip), ROM / RAM addresses
wire [7:0] lx = crt_flip ? ~hcnt[7:0] : hcnt[7:0];
wire [7:0] ly = crt_flip ? ~vcnt[7:0] : vcnt[7:0];
wire [7:0] bx = flip ? ~lx : lx;
wire [7:0] by = flip ? ~ly : ly;

assign vram_va    = {by, bx[7:3]};
assign rom_cmap_a = k_panic ? {1'b0, creg[2], creg[0], bx[7:4], by[7:3]} :
                    k_cosa  ? {2'b00, creg[0], bx[7:4], by[7:3]} :
                              {2'b00, creg[0], bx[7:3], by[7:4]};
wire [7:0] gy = by - 8'd32;
assign grid_ra = {gy, bx[7:3]};

// stars (cosmica_draw_starfield): x1 = x +/- frame; map = PROM[(x1 >> 5) | (y >> 1 << 3)] latched at x1 = 32n
wire [7:0] x1   = flip ? lx - frame : lx + frame;
wire [7:0] x1e  = flip ? 8'd255 - frame : 8'd255 + frame;
wire [7:0] lym1 = ly - 8'd1;
wire       xcur = {3'b000, x1[4:0]} <= lx;
wire [9:0] st_a = xcur ? {ly[7:1], x1[7:5]} : {lym1[7:1], x1e[7:5]};

// tree + river (nomnlnd_draw_background), in bitmap coordinates
wire [7:0] water   = frame + by;
wire       t_rows  = ((!by[5] && by[6] && !by[7]) ^ (by[5] && !by[6] && by[7]));
wire       t_cols  = !bx[7] && bx[6] && !bx[5];
wire       w_cols  = bx[7] && !bx[6] && bx[5] && !bx[4];
wire [9:0] t_offs  = t_rows ? {2'b00, flip, by[4:0], bx[4:3]} : {1'b1, water, bx[3]};
wire [1:0] t_sel   = t_rows ? (t_cols ? 2'd1 : 2'd0) : (w_cols ? 2'd2 : 2'd0);

assign rom_u2_a  = k_nml ? {2'b00, t_offs} : k_cosa ? {2'b00, st_a} : {1'b0, g_rda};
assign rom_u2b_a = {1'b0, 1'b1, t_offs};                              // plane 2: offs | 0x400

// S1: memory data for the pixel, pipelined geometry
logic [7:0] s1_vq, s1_cm, s1_u2, s1_u2b, s1_gq;
logic [2:0] s1_b3;
logic [7:0] s1_x1, s1_lx;
logic [1:0] s1_ly, s1_tsel;
logic       s1_hd, s1_gvis, s1_ln, s1_clr;
// S2
logic [3:0] s2_c;                                                     // colour index
logic [1:0] s2_pal;                                                   // 0 black, 1 panic, 2 plain 3-bit, 3 magspot
logic [3:0] blk_d[2];

assign lb_ra    = s1_lx;
assign lb_clr   = ce_pix && s1_clr;
assign disp_buf = s1_ln;

wire        bm_on  = s1_vq[3'd7 - s1_b3];
wire  [3:0] cm_nib = creg[1] ? s1_cm[7:4] : s1_cm[3:0];
wire  [3:0] bm_pen = k_cosa ? {1'b0, cm_nib[2:0]} : cm_nib;
wire        star_on = k_cosa && !(s1_x1[2] && s1_ly[0]) && (s1_ly[1] ^ s1_lx[5]) &&
                      (((s1_x1 ^ s1_u2) & {3'b000, 4'hF, s1_x1[2]}) == 8'h1E);
wire  [2:0] star_c  = {s1_u2[5], s1_u2[6], s1_u2[7]};
wire        grid_on = k_dev && bg_en && s1_gvis && s1_gq[3'd7 - s1_b3];
wire        tp1 = s1_u2[3'd7 - s1_b3], tp2 = s1_u2b[3'd7 - s1_b3];
wire  [2:0] tree_c  = (s1_tsel == 2'd1) ? {tp1 & ~tp2, tp2, tp1 & tp2} :
                      (s1_tsel == 2'd2) ? {~tp1 & s1_hd, tp1 | tp2, tp1 & tp2} : 3'd0;
wire  [6:0] lbq     = lb_q[disp_buf];
wire  [5:0] sp_idx  = lbq[5:0];
wire  [7:0] sp_pr   = prom[sp_idx[4:0]];
wire  [3:0] sp_c    = k_cosa ? {1'b0, sp_idx[5] ? sp_pr[6:4] : sp_pr[2:0]} : k_panic ? {1'b0, sp_pr[2:0]} : sp_pr[3:0];
wire  [1:0] pal_k   = k_panic ? 2'd1 : k_cosa ? 2'd2 : 2'd3;

always_ff @(posedge clk) begin
    if (ce_pix) begin
        s1_vq <= vram_vq;  s1_cm <= rom_cmap_d;  s1_u2 <= rom_u2_d;  s1_u2b <= rom_u2b_d;  s1_gq <= grid_q;
        s1_b3 <= bx[2:0];  s1_x1 <= x1;  s1_lx <= lx;  s1_ly <= ly[1:0];  s1_tsel <= t_sel;  s1_hd <= bx[3];
        s1_gvis <= (by >= 8'd32) && (by < 8'd224);
        s1_ln <= vcnt[0];  s1_clr <= !hcnt[8];

        if (k_nml && bg_en && tree_c != 3'd0)  begin s2_c <= {1'b0, tree_c}; s2_pal <= 2'd3; end   // over everything
        else if (lbq[6])                       begin s2_c <= sp_c;            s2_pal <= pal_k; end
        else if (bm_on)                        begin s2_c <= bm_pen;          s2_pal <= pal_k; end   // pen 15 = colour 15 (MAME pen % indirect)
        else if (star_on)                      begin s2_c <= {1'b0, star_c};  s2_pal <= 2'd2; end
        else if (grid_on)                      begin s2_c <= 4'd4;            s2_pal <= 2'd3; end
        else                                   begin s2_c <= 4'd0;            s2_pal <= 2'd0; end

        blk_d[0] <= {hbl_s0, vbl_s0, hs_s0, vs_s0};
        blk_d[1] <= blk_d[0];
    end
end

// ------------------------------------------------------------------ palettes (MAME panic / cosmica / magspot)
wire [7:0] r_p = s2_c[0] ? 8'hFF : 8'h00;
wire [7:0] g_p = s2_c[1] ? 8'hFF : 8'h00;
wire [7:0] b_p = s2_c[2] ? 8'hFF : 8'h00;
always_ff @(posedge clk) begin
    if (ce_pix) begin
        case (s2_pal)
            2'd1:    begin video_r <= r_p; video_g <= g_p; video_b <= (s2_c[3:2] == 2'b10) ? 8'hAA : b_p; end
            2'd2:    begin video_r <= r_p; video_g <= g_p; video_b <= b_p; end
            2'd3:    begin video_r <= (s2_c[3] && !s2_c[0]) ? 8'hAA : r_p; video_g <= g_p; video_b <= b_p; end
            default: begin video_r <= 8'h00; video_g <= 8'h00; video_b <= 8'h00; end
        endcase
        {video_hblank, video_vblank, video_hs, video_vs} <= blk_d[1];      // same pixel as s2_c
    end
end

endmodule
