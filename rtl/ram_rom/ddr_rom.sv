//============================================================================
//
//  ddr_rom.sv - ROM data in DDR3 (MiSTer DDRAM port), sharing the port with screen_rotate
//  Copyright (C) 2026 Rodimus
//
//  Every index-0 byte of the MRA is mirrored to DDR3 at BASE_W + ioctl_addr / 8 during the download: one
//  byte-enabled single-beat write per byte, ioctl_wait while it is pending. Two read clients address that
//  image by index-0 byte address:
//    row port  - one 64-bit word per request (8-byte aligned; Indoor Soccer sprite rows)
//    byte port - a byte from an 8-byte cache, fetched when the address leaves the cached word (ADPCM)
//  screen_rotate's single-beat writes go through a one-deep buffer and win over everything else (it ignores
//  DDRAM_BUSY, so a write it makes while the buffer is still full replaces the older one, as before).
//  One read is outstanding at a time and every burst is 1 beat (f2sdram bursts above 16 words wedge).
//
//============================================================================

module ddr_rom #(parameter [28:0] BASE_W = 29'h07800000)  // DDR3 word address of index-0 byte 0 (byte 0x3C000000)
(
    input             clk,

    input             ioctl_download,
    input             ioctl_wr0,          // index-0 byte
    input      [24:0] ioctl_addr,
    input       [7:0] ioctl_dout,
    output            ioctl_wait,

    input             row_req,            // pulse; hold row_addr until row_rdy
    input      [24:0] row_addr,
    output reg [63:0] row_q = 64'd0,
    output reg        row_rdy = 1'b0,     // pulse

    input             byte_en,            // fetch for the byte port only while its board runs
    input      [24:0] byte_addr,
    output      [7:0] byte_q,
    output            byte_rdy,           // byte_q is the byte at byte_addr

    input             sr_we,              // screen_rotate, single-beat writes
    input      [28:0] sr_addr,
    input      [63:0] sr_din,
    input       [7:0] sr_be,

    output            DDRAM_CLK,
    input             DDRAM_BUSY,
    output      [7:0] DDRAM_BURSTCNT,
    output     [28:0] DDRAM_ADDR,
    input      [63:0] DDRAM_DOUT,
    input             DDRAM_DOUT_READY,
    output            DDRAM_RD,
    output     [63:0] DDRAM_DIN,
    output      [7:0] DDRAM_BE,
    output            DDRAM_WE
);

reg         cmd_we = 1'b0, cmd_rd = 1'b0;
reg  [28:0] cmd_addr = 29'd0;
reg  [63:0] cmd_din = 64'd0;
reg   [7:0] cmd_be = 8'hFF;

assign DDRAM_CLK      = clk;
assign DDRAM_BURSTCNT = 8'd1;
assign DDRAM_ADDR     = cmd_addr;
assign DDRAM_DIN      = cmd_din;
assign DDRAM_BE       = cmd_be;
assign DDRAM_WE       = cmd_we;
assign DDRAM_RD       = cmd_rd;

// a new command can be loaded when none is presented, or the presented one is accepted at this edge
wire cmd_free = !(cmd_we || cmd_rd) || !DDRAM_BUSY;

// screen_rotate write buffer
reg         sr_v = 1'b0;
reg  [28:0] sr_a;
reg  [63:0] sr_d;
reg   [7:0] sr_b;

// download write buffer
reg         dl_v = 1'b0;
reg  [28:0] dl_a;
reg  [63:0] dl_d;
reg   [7:0] dl_b;
assign ioctl_wait = dl_v;

// row request
reg         row_pend = 1'b0;
reg  [28:0] row_a;

// byte cache
reg  [63:0] bc_d = 64'd0;
reg  [28:0] bc_tag = 29'd0, bc_ftag = 29'd0;
reg         bc_v = 1'b0, bc_stale = 1'b0;
wire [28:0] byte_w = BASE_W + {7'd0, byte_addr[24:3]};
assign byte_rdy = bc_v && (bc_tag == byte_w);
assign byte_q   = bc_d[{byte_addr[2:0], 3'b000} +: 8];

reg         rd_out = 1'b0, rd_byte = 1'b0;

always @(posedge clk) begin
    row_rdy <= 1'b0;

    if (ioctl_wr0) begin
        dl_v <= 1'b1;
        dl_a <= BASE_W + {7'd0, ioctl_addr[24:3]};
        dl_d <= {8{ioctl_dout}};
        dl_b <= 8'd1 << ioctl_addr[2:0];
    end
    if (sr_we) begin
        sr_v <= 1'b1; sr_a <= sr_addr; sr_d <= sr_din; sr_b <= sr_be;
    end
    if (row_req) begin
        row_pend <= 1'b1;
        row_a    <= BASE_W + {7'd0, row_addr[24:3]};
    end
    if (ioctl_download) begin
        bc_v <= 1'b0;
        if (rd_out && rd_byte) bc_stale <= 1'b1;        // a fetch in flight returns pre-download data
    end

    if (cmd_free) begin
        cmd_we <= 1'b0;
        cmd_rd <= 1'b0;
        if (sr_v) begin
            cmd_we <= 1'b1; cmd_addr <= sr_a; cmd_din <= sr_d; cmd_be <= sr_b;
            if (!sr_we) sr_v <= 1'b0;
        end
        else if (dl_v) begin
            cmd_we <= 1'b1; cmd_addr <= dl_a; cmd_din <= dl_d; cmd_be <= dl_b;
            if (!ioctl_wr0) dl_v <= 1'b0;
        end
        else if (!rd_out && row_pend) begin
            cmd_rd <= 1'b1; cmd_addr <= row_a; cmd_be <= 8'hFF;
            rd_out <= 1'b1; rd_byte <= 1'b0;
            if (!row_req) row_pend <= 1'b0;
        end
        else if (!rd_out && byte_en && !ioctl_download && !byte_rdy) begin
            cmd_rd <= 1'b1; cmd_addr <= byte_w; cmd_be <= 8'hFF;
            rd_out <= 1'b1; rd_byte <= 1'b1;
            bc_ftag <= byte_w; bc_stale <= 1'b0;
        end
    end

    if (rd_out && DDRAM_DOUT_READY) begin
        rd_out <= 1'b0;
        if (rd_byte) begin
            bc_d   <= DDRAM_DOUT;
            bc_tag <= bc_ftag;
            bc_v   <= !bc_stale && !ioctl_download;
        end
        else begin
            row_q   <= DDRAM_DOUT;
            row_rdy <= 1'b1;
        end
    end
end

endmodule
