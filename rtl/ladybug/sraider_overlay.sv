//============================================================================
//
//  Space Raider starfield + grid, mixed under the Lady Bug video
//  Copyright (C) 2026 Rodimus
//
//  From MAME sraider.cpp / zerohour_stars.cpp (Frank Palazzolo):
//  - stars: 17-bit LFSR stepped once per slot of a 256x256 raster starting at
//    (offset & 0xFF, offset >> 8); a star where (state & 0xFF) == 0xFF and the
//    feedback bit is 0, on pixels with bit 4 of (x + 8) == bit 0 of y (no VA bit).
//    Two alternating fields: state 0 / 0x1FC71, offset += speed * 2 - 9 every
//    second frame. Clipped to x <= 0xD8 (flipped: x >= 0x27).
//  - grid: 1bpp gfx3 tilemap (bottom half = top half mirrored) plus a full-height
//    line at every x whose grid RAM byte is non-zero, both in the grid colour.
//  - priority: chars/sprites > grid > stars > background.
//
//  Output is a colour code (so the CRT Flip frame buffer stays 8 bits wide):
//    {2'b00, r[1:0], g[1:0], b[1:0]}  Lady Bug pixel (2-bit DAC levels)
//    {2'b01, 3'b000, r, g, b}         grid (full on / off per gun)
//    {2'b10, 1'b0, colour[4:0]}       star (MAME sraider_palette star colours)
//
//  The overlay runs one pixel behind the Lady Bug output and tracks MAME screen
//  coordinates (visible x 8-247, y 32-223) of the pixel it holds. The LFSR is
//  advanced to the first visible slot during vblank (up to 65535 steps, one per
//  clock) and by 16 extra steps in each hblank.
//
//============================================================================

module sraider_overlay
(
    input  logic        clk,
    input  logic        ce_pix,
    input  logic        enable,         // Space Raider (stars + grid present)
    input  logic  [7:0] ctrl,           // sub CPU LS273: [2:0] star speed, [3] star enable, [6:4] grid RGB, [7] flip

    input  logic  [1:0] in_r, in_g, in_b,
    input  logic        in_bg,
    input  logic        in_hbl, in_vbl,

    output logic [11:0] grid_rom_a,
    input  logic  [7:0] grid_rom_d,
    output logic  [7:0] grid_ram_a,
    input  logic  [7:0] grid_ram_d,

    output logic  [7:0] out_code,
    output logic        out_hbl, out_vbl
);

wire flip = ctrl[7];

// ---------------------------------------------------------------- pixel tracking
logic  [1:0] q_r, q_g, q_b;
logic        q_bg, q_hbl = 1'b1, q_vbl = 1'b1;
logic  [7:0] x_q, y_q;
logic        first_line = 1'b1;

always_ff @(posedge clk) begin
    if (ce_pix) begin
        q_r <= in_r; q_g <= in_g; q_b <= in_b; q_bg <= in_bg;
        q_hbl <= in_hbl; q_vbl <= in_vbl;
        if (in_vbl) first_line <= 1'b1;
        else if (!in_hbl) begin
            if (q_hbl) begin                            // first pixel of a line
                x_q        <= 8'd8;
                y_q        <= first_line ? 8'd32 : y_q + 8'd1;
                first_line <= 1'b0;
            end
            else x_q <= x_q + 8'd1;
        end
    end
end

// ---------------------------------------------------------------- stars
logic [16:0] st;
logic [16:0] pend;
logic [15:0] offset = 16'd0;
logic        field = 1'b0;
logic  [2:0] speed;
logic        en_d = 1'b0, first_px = 1'b1;
wire         star_en = ctrl[3];

assign speed = ctrl[2:0] - 3'd1;                         // MAME: set_speed((data & 7) - 1, 7)

wire tempbit  = ~st[16];
wire feedback = st[5] ? ~tempbit : tempbit;
wire [16:0] st_next = {st[15:0], feedback};

wire vbl_rise = ce_pix && in_vbl && !q_vbl;
wire hbl_rise = ce_pix && in_hbl && !q_hbl && !in_vbl;
wire px_new   = ce_pix && !in_vbl && !in_hbl;

wire [15:0] offset_next = offset + {11'd0, speed, 1'b0} - 16'd9;
wire [15:0] first_idx_a = 16'd8200 - offset;              // slot of (8, 32): 32 * 256 + 8 - offset
wire [15:0] first_idx_b = 16'd8200 - offset_next;

always_ff @(posedge clk) begin
    en_d <= star_en;
    if (star_en && !en_d) offset <= 16'd0;                // MAME set_enable: rising edge resets the offset

    if (vbl_rise) begin
        first_px <= 1'b1;
        if (star_en) begin
            field <= ~field;
            if (field) begin                              // count back to 0: field A, scroll
                offset <= offset_next;
                st     <= 17'd0;
                pend   <= {1'b0, first_idx_b};
            end
            else begin
                st     <= 17'h1FC71;
                pend   <= {1'b0, first_idx_a};
            end
        end
    end
    else begin : steps
        logic [16:0] add;
        add = 17'd0;
        if (hbl_rise) add = 17'd16;
        else if (px_new) begin
            if (first_px) first_px <= 1'b0;
            else          add = 17'd1;
        end
        if (pend != 17'd0) st <= st_next;
        pend <= pend - (pend != 17'd0 ? 17'd1 : 17'd0) + add;
    end
end

wire [7:0] xp8   = x_q + 8'd8;
wire       clip  = flip ? (x_q >= 8'h27) : (x_q <= 8'hD8);
wire       star  = enable && star_en && clip && (xp8[4] == y_q[0]) && (st[7:0] == 8'hFF) && !feedback;
wire [4:0] sc    = st[13:9];

// ---------------------------------------------------------------- grid
wire [7:0] tx  = flip ? ~x_q : x_q;
wire [7:0] ty  = flip ? ~y_q : y_q;
wire [7:0] tym = ty[7] ? ~ty : ty;                        // rows 16-31 mirror rows 15-0 (gridlayout2)

assign grid_rom_a = {tym[6:3], tx[7:3], tym[2:0]};
assign grid_ram_a = flip ? ~x_q : x_q;

wire [7:0] gbits = grid_rom_d;
wire       grid  = enable && (gbits[tx[2:0]] || grid_ram_d != 8'd0);

// ---------------------------------------------------------------- mix
always_ff @(posedge clk) begin
    if (ce_pix) begin
        out_hbl <= q_hbl;
        out_vbl <= q_vbl;
        if (!q_bg)     out_code <= {2'b00, q_r, q_g, q_b};
        else if (grid) out_code <= {2'b01, 3'b000, ctrl[6:4]};
        else if (star) out_code <= {2'b10, 1'b0, sc};
        else           out_code <= {2'b00, q_r, q_g, q_b};
    end
end

endmodule
