//============================================================================
//
//  Universal 8-bit arcade hardware for MiSTer
//  Copyright (C) 2026 Rodimus
//
//  Top level carried over from the Rodimus Pac-Man core (MikeJ / Sorgelig lineage)
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

wire        CLK_SYS;
wire        locked;
wire [127:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [10:0] ps2_key;
wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_din;
wire        ioctl_wr;
wire        ddr_ioctl_wait;     // ddr_rom: index-0 byte being mirrored to DDR3
wire  [7:0] ioctl_index;
// ART-2026-10-24: original
// wire [24:0] ioctl_addr;
wire [26:0] ioctl_addr27;                     // hps_io's full address: the artwork download can pass 32 MB
wire [24:0] ioctl_addr = ioctl_addr27[24:0];  // every other ioctl user
wire  [7:0] ioctl_dout;
wire [15:0] joystick_0, joystick_1;
wire [15:0] joystick_r_analog_0, joystick_r_analog_1;   // right analog sticks: [15:8] Y, [7:0] X, signed
wire [21:0] gamma_bus;
wire        direct_video;
wire        video_rotated;
wire        pause_cpu;
wire        hblank, vblank;

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire signed [15:0] audio;
assign AUDIO_L = pause_cpu ? 16'd0 : audio;
assign AUDIO_R = pause_cpu ? 16'd0 : audio;
assign AUDIO_S = 1;   // signed
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS = 0;

///////////////////////////////////////////////////

// MRA index 1:
//   byte 0      board variant (see rtl/universal_board.sv)
//   byte 1      flags: [0] 4-way joystick, [2] coins are 2-frame pulses, [4] vertical, [7] vertical is ROT90
//   byte 2      CPU ROM decode (see rtl/universal_board.sv)
//   byte 3      board flags (see rtl/universal_board.sv)
//   bytes 4-9   idle level of every bit of the 6 ports (board order)
//   bytes 10-15 per port: DIP switch byte that supplies it (bit 7 set = none, use the idle byte)
//   bytes 16-63 input map, one byte per port bit (bit 0 first): control id, 0 = none; a pressed control inverts its bit
// Only DIP ports go in the MRA switch bytes: Main_MiSTer builds the default as int shifts, so a byte >= 0x80 at
// position 3 sign-extends over bytes 4-7, and bytes 4+ are shifted by 32+ (mra_loader.cpp: binary[i] << (i * 8))
reg [7:0] game_var    = 8'd0;
reg [7:0] game_flags  = 8'h11;
reg [3:0] rom_dec     = 4'd0;
reg [7:0] game_flags2 = 8'd0;
reg [5:0] in_map[48];
reg [7:0] port_idle[6] = '{8'hFF,8'hFF,8'hFF,8'hFF,8'hFF,8'h00};
reg [7:0] port_dip[6]  = '{8'h80,8'h80,8'h80,8'h80,8'h80,8'h80};
wire [5:0] map_idx  = ioctl_addr[5:0] - 6'd16;
wire [2:0] idle_idx = ioctl_addr[2:0] - 3'd4;      // bytes 4-9  -> 0-5
wire [3:0] dip_idx4 = ioctl_addr[3:0] - 4'd10;     // bytes 10-15 -> 0-5
wire [2:0] dip_idx  = dip_idx4[2:0];

always @(posedge CLK_SYS) begin
    if (ioctl_wr && ioctl_index == 8'd1) begin
        if (ioctl_addr == 25'd0) game_var   <= ioctl_dout;
        if (ioctl_addr == 25'd1) game_flags  <= ioctl_dout;
        if (ioctl_addr == 25'd2) rom_dec     <= ioctl_dout[3:0];
        if (ioctl_addr == 25'd3) game_flags2 <= ioctl_dout;
        if (ioctl_addr >= 25'd4  && ioctl_addr < 25'd10) port_idle[idle_idx] <= ioctl_dout;
        if (ioctl_addr >= 25'd10 && ioctl_addr < 25'd16) port_dip[dip_idx]   <= ioctl_dout;
        if (ioctl_addr >= 25'd16 && ioctl_addr < 25'd64) in_map[map_idx] <= ioctl_dout[5:0];
    end
end

wire game_vert = game_flags[4];
wire vert_view = game_vert & ~status[12];

wire [1:0] ar = status[9:8];

wire        art_fb;                // artwork framebuffer on HDMI: square canvas pixels
wire        art_ioctl_wait, art_avail;
wire [11:0] art_cw, art_ch;
// ART-2026-10-24: original
// assign VIDEO_ARX = (!ar) ? (vert_view ? 12'd3 : 12'd4) : (ar - 1'd1);
// assign VIDEO_ARY = (!ar) ? (vert_view ? 12'd4 : 12'd3) : 12'd0;
assign VIDEO_ARX = (!ar) ? (art_fb ? art_cw : vert_view ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (art_fb ? art_ch : vert_view ? 12'd4 : 12'd3) : 12'd0;

// Status bit layout kept the same as the Pac-Man core
`include "build_id.v"
localparam CONF_STR = {
	"UNIVERSAL;;",
	"P1,Video Options;",
	"P1O89,Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	"P1OC,Orientation,Vert,Horz;",
	"P1OB,HDMI Flip,Off,On;",
	"P1OM,CRT Flip,Off,On;",
	"P1O[40:37],H Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[44:41],V Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1OGI,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"H1P2,Game Options;",
	"H1P2-,Artwork (MAME layout views);",
	"H1P2O[48:45],View,Off,View 1,View 2,View 3,View 4,View 5,View 6,View 7,View 8,View 9,View 10,View 11,View 12,View 13,View 14,View 15;",
	"H1P2O[49],Backdrop,On,Off;",
	"H1P2O[50],Overlay,On,Off;",
	"H1P2O[51],Bezel,On,Off;",
	"H1P2O[54],Control Panel,On,Off;",
	"H1P2O[52],Side Art,On,Off;",
	"H1P2O[53],Zoom to Screen,Off,On;",
	"H1-;",
	"P3,Pause Options;",
	"P3OJ,Pause when OSD is open,On,Off;",
	"P3OK,Dim video after 10s,On,Off;",
	"-;",
	"P4,High Score Options;",
	"P4OL,Autosave Hiscores,Off,On;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Btn 1,Btn 2,Btn 3,Btn 4,Coin,Start 1P,Start 2P,Pause,Btn 5,Btn 6,Rack Test;",
	"jn,A,B,X,Y,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_SYS),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	// ART-2026-10-24: original
	// .status_menumask({direct_video}),
	.status_menumask({~art_avail, direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	// ART-2026-10-24: original
	// .ioctl_addr(ioctl_addr),
	.ioctl_addr(ioctl_addr27),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),
	// DDR3-2026-10-23: original
	// .ioctl_wait(1'b0),
	// ART-2026-10-24: was .ioctl_wait(ddr_ioctl_wait),
	.ioctl_wait(ddr_ioctl_wait | art_ioctl_wait),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_r_analog_0(joystick_r_analog_0),
	.joystick_r_analog_1(joystick_r_analog_1),
	.ps2_key(ps2_key)
);

////////////////////   CLOCKS   ///////////////////

wire        CLK_2X;         // 39.312 MHz = 2 x CLK_SYS, same VCO (phase-locked 2:1): artwork + video back end + DDRAM

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_SYS),
	.outclk_1(CLK_2X),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(0),
	.mgmt_address(0),
	.mgmt_writedata(0),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

// Hold the board in reset until the PLL is locked and the ROM download has finished
wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked;

///////////////////         Keyboard           //////////////////

// CTL-2026-10-24: keyboard -> ctl_keyboard (rtl/mister_custom/controllers.sv); keys now act on press. Original commented out below.
// reg kb_up = 0, kb_down = 0, kb_left = 0, kb_right = 0;
// reg kb_b1 = 0, kb_b2 = 0;
// reg kb_coin1 = 0, kb_coin2 = 0, kb_start1 = 0, kb_start2 = 0, kb_pause = 0, kb_service = 0, kb_tilt = 0;
//
// wire       pressed = ~ps2_key[9];
// wire [7:0] code    = ps2_key[7:0];
//
// always @(posedge CLK_SYS) begin
// 	reg old_state;
// 	old_state <= ps2_key[10];
// 	if (old_state != ps2_key[10]) begin
// 		case (code)
// 			'h16: kb_start1  <= pressed; // 1
// 			'h1E: kb_start2  <= pressed; // 2
// 			'h2E: kb_coin1   <= pressed; // 5
// 			'h36: kb_coin2   <= pressed; // 6
// 			'h46: kb_service <= pressed; // 9
// 			'h2C: kb_tilt    <= pressed; // T
// 			'h4D: kb_pause   <= pressed; // P
//
// 			'h75: kb_up      <= pressed; // up
// 			'h72: kb_down    <= pressed; // down
// 			'h6B: kb_left    <= pressed; // left
// 			'h74: kb_right   <= pressed; // right
// 			'h14: kb_b1      <= pressed; // ctrl
// 			'h11: kb_b2      <= pressed; // alt
// 		endcase
// 	end
// end
// kb: [0] up [1] down [2] left [3] right [4] Btn 1 (Ctrl) [5] Btn 2 (Alt) [6] Start 1 [7] Start 2 [8] Coin 1 [9] Coin 2 [10] Service [11] Tilt [12] Pause
wire [12:0] kb;
// CTL2-2026-10-25: controllers.sv v2: ctl_keyboard pause wired (no toggle keys here, so no behaviour change). v1 commented out below.
// ctl_keyboard keyboard(.clk(CLK_SYS), .ps2_key(ps2_key), .kb(kb));
/* verilator lint_off PINCONNECTEMPTY */
ctl_keyboard keyboard(.clk(CLK_SYS), .ps2_key(ps2_key), .pause(pause_cpu), .kb(kb), .kbx());
/* verilator lint_on PINCONNECTEMPTY */

//////////////////  Arcade Buttons/Interfaces   ///////////////////////////

// Joystick bits: 0 R, 1 L, 2 D, 3 U, 4-7 Btn 1-4, 8 Coin, 9 Start 1P, 10 Start 2P, 11 Pause, 12-13 Btn 5-6, 14 Rack Test (unmapped)
// CTL-2026-10-24: keyboard arrows from ctl_keyboard. Original commented out below.
// wire [3:0] dir1_raw = {joystick_0[3] | kb_up, joystick_0[2] | kb_down, joystick_0[1] | kb_left, joystick_0[0] | kb_right};
wire [3:0] dir1_raw = {joystick_0[3] | kb[0], joystick_0[2] | kb[1], joystick_0[1] | kb[2], joystick_0[0] | kb[3]};
wire [3:0] dir2_raw = joystick_1[3:0];
wire [3:0] dir1, dir2;   // {U, D, L, R}

// CTL-2026-10-24: 4-way restriction -> ctl_joy4way. Original commented out below.
// joy4way joy4way_1(.clk(CLK_SYS), .en(game_flags[0]), .in(dir1_raw), .out(dir1));
// joy4way joy4way_2(.clk(CLK_SYS), .en(game_flags[0]), .in(dir2_raw), .out(dir2));
ctl_joy4way joy4way_1(.clk(CLK_SYS), .en(game_flags[0]), .in(dir1_raw), .out(dir1));
ctl_joy4way joy4way_2(.clk(CLK_SYS), .en(game_flags[0]), .in(dir2_raw), .out(dir2));

// CTL-2026-10-24: keyboard P from ctl_keyboard. Original commented out below.
// wire m_pause = joystick_0[11] | kb_pause;
wire m_pause = joystick_0[11] | kb[12];

// CTL-2026-10-24: coin PORT_IMPULSE(2) -> ctl_coin_impulse. Original commented out below.
// // MAME PORT_IMPULSE(2): a coin press is latched, then held for exactly two frames from the next vblank
// wire       coin1_raw = joystick_0[8] | kb_coin1;
// wire       coin2_raw = joystick_1[8] | kb_coin2;
// reg        coin1_d = 1'b0, coin2_d = 1'b0, coin1_pend = 1'b0, coin2_pend = 1'b0, imp_vbl = 1'b0;
// reg  [1:0] coin1_frames = 2'd0, coin2_frames = 2'd0;
// always @(posedge CLK_SYS) begin
// 	coin1_d <= coin1_raw;
// 	coin2_d <= coin2_raw;
// 	imp_vbl <= vblank;
// 	if (coin1_raw & ~coin1_d) coin1_pend <= 1'b1;
// 	if (coin2_raw & ~coin2_d) coin2_pend <= 1'b1;
// 	if (vblank & ~imp_vbl) begin
// 		if (coin1_pend)                begin coin1_frames <= 2'd2; coin1_pend <= 1'b0; end
// 		else if (coin1_frames != 2'd0) coin1_frames <= coin1_frames - 2'd1;
// 		if (coin2_pend)                begin coin2_frames <= 2'd2; coin2_pend <= 1'b0; end
// 		else if (coin2_frames != 2'd0) coin2_frames <= coin2_frames - 2'd1;
// 	end
// end
// wire coin1 = game_flags[2] ? |coin1_frames : coin1_raw;
// wire coin2 = game_flags[2] ? |coin2_frames : coin2_raw;
// MAME PORT_IMPULSE(2) when game_flags[2]: a coin press is held for exactly two frames from the next vblank.
// CTL2-2026-10-25: coin impulse paused with the CPU (PAUSE_MODE 1: frame count holds, a press while paused is discarded). v1 commented out below.
// // pause tied 0: the original block keeps counting vblanks while paused (bit-identical).
// wire coin1, coin2;
// ctl_coin_impulse coin_imp1(.clk(CLK_SYS), .pause(1'b0), .vblank(vblank), .en(game_flags[2]),
//                            .coin_raw(joystick_0[8] | kb[8]), .coin(coin1));
// ctl_coin_impulse coin_imp2(.clk(CLK_SYS), .pause(1'b0), .vblank(vblank), .en(game_flags[2]),
//                            .coin_raw(joystick_1[8] | kb[9]), .coin(coin2));
wire coin1, coin2;
ctl_coin_impulse #(.PAUSE_MODE(1)) coin_imp1(.clk(CLK_SYS), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
                           .coin_raw(joystick_0[8] | kb[8]), .coin(coin1));
ctl_coin_impulse #(.PAUSE_MODE(1)) coin_imp2(.clk(CLK_SYS), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
                           .coin_raw(joystick_1[8] | kb[9]), .coin(coin2));

// Rack Test cheat: held (MAME DIP with a key), or flipped on each press (MAME PORT_TOGGLE)
wire rack_btn = joystick_0[14] | joystick_1[14];
// CTL-2026-10-24: Rack Test PORT_TOGGLE -> ctl_toggle. Original commented out below.
// reg  rack_d = 1'b0, rack_tog = 1'b0;
// always @(posedge CLK_SYS) begin
// 	rack_d <= rack_btn;
// 	if (ioctl_download)          rack_tog <= 1'b0;
// 	else if (rack_btn & ~rack_d) rack_tog <= ~rack_tog;
// end
wire rack_tog;
// CTL2-2026-10-25: Rack Test toggle ignores presses while paused. v1 commented out below.
// ctl_toggle rack_toggle(.clk(CLK_SYS), .clear(ioctl_download), .btn(rack_btn), .q(rack_tog));
ctl_toggle rack_toggle(.clk(CLK_SYS), .clear(ioctl_download), .btn(rack_btn), .pause(pause_cpu), .q(rack_tog));

// Twin stick (Crazy Climber pattern): right-hand stick = right analog stick, or Btn 3-6 = R Right / Left / Down / Up
// CTL-2026-10-24: right-stick directions -> ctl_stick_dirs (+-48 per axis). Original commented out below.
// wire signed [7:0] rx0 = joystick_r_analog_0[7:0], ry0 = joystick_r_analog_0[15:8];
// wire signed [7:0] rx1 = joystick_r_analog_1[7:0], ry1 = joystick_r_analog_1[15:8];
// wire [3:0] rstick0 = {ry0 < -8'sd48, ry0 > 8'sd48, rx0 < -8'sd48, rx0 > 8'sd48};   // {U, D, L, R}
// wire [3:0] rstick1 = {ry1 < -8'sd48, ry1 > 8'sd48, rx1 < -8'sd48, rx1 > 8'sd48};
wire [3:0] rstick0, rstick1;   // {U, D, L, R}
ctl_stick_dirs #(.MODE(0), .THRESH(7'd48)) rstick_0(.stick(joystick_r_analog_0), .dir(rstick0));
ctl_stick_dirs #(.MODE(0), .THRESH(7'd48)) rstick_1(.stick(joystick_r_analog_1), .dir(rstick1));

// CTL-2026-10-24: control ids 0-35 -> ctl_ids (pad 2's Start = Start 2 only); ids 36-45 stay core-local. Original commented out below.
// // control ids used by the MRA input map (same numbering as the Pac-Man core; 24-31 reserved for analog)
// wire [63:0] ctl =
// {
// 	18'd0,
// 	joystick_1[13] | rstick1[3],                    // 45 P2 R Up    (Btn 6)
// 	joystick_1[12] | rstick1[2],                    // 44 P2 R Down  (Btn 5)
// 	joystick_1[7]  | rstick1[1],                    // 43 P2 R Left  (Btn 4)
// 	joystick_1[6]  | rstick1[0],                    // 42 P2 R Right (Btn 3)
// 	joystick_0[13] | rstick0[3],                    // 41 P1 R Up    (Btn 6)
// 	joystick_0[12] | rstick0[2],                    // 40 P1 R Down  (Btn 5)
// 	joystick_0[7]  | rstick0[1],                    // 39 P1 R Left  (Btn 4)
// 	joystick_0[6]  | rstick0[0],                    // 38 P1 R Right (Btn 3)
// 	rack_tog,                                       // 37 rack test (toggle)
// 	rack_btn,                                       // 36 rack test (held)
// 	joystick_1[13:12],                              // 35-34 P2 Btn 6-5
// 	joystick_0[13:12],                              // 33-32 P1 Btn 6-5
// 	8'd0,                                           // 31-24 reserved
// 	1'b0,                                           // 23 coin 3
// 	kb_service,                                     // 22 service
// 	kb_tilt,                                        // 21 tilt
// 	joystick_0[10] | joystick_1[10] | kb_start2,    // 20 start 2
// 	joystick_0[9]  | joystick_1[9]  | kb_start1,    // 19 start 1
// 	coin2,                                          // 18 coin 2
// 	coin1,                                          // 17 coin 1
// 	joystick_1[7:4],                                // 16-13 P2 Btn 4-1
// 	dir2[0], dir2[1], dir2[2], dir2[3],             // 12 R, 11 L, 10 D, 9 U
// 	joystick_0[7:6], joystick_0[5] | kb_b2, joystick_0[4] | kb_b1,   // 8-5 P1 Btn 4-1
// 	dir1[0], dir1[1], dir1[2], dir1[3],             // 4 R, 3 L, 2 D, 1 U
// 	1'b0                                            // 0 none
// };
wire [35:0] ctl36;
ctl_ids ids(.joy0(joystick_0), .joy1(joystick_1), .kb(kb), .dir1(dir1), .dir2(dir2),
            .coin1(coin1), .coin2(coin2), .coin3(1'b0), .ctl(ctl36));
wire [63:0] ctl =
{
	18'd0,
	joystick_1[13] | rstick1[3],                    // 45 P2 R Up    (Btn 6)
	joystick_1[12] | rstick1[2],                    // 44 P2 R Down  (Btn 5)
	joystick_1[7]  | rstick1[1],                    // 43 P2 R Left  (Btn 4)
	joystick_1[6]  | rstick1[0],                    // 42 P2 R Right (Btn 3)
	joystick_0[13] | rstick0[3],                    // 41 P1 R Up    (Btn 6)
	joystick_0[12] | rstick0[2],                    // 40 P1 R Down  (Btn 5)
	joystick_0[7]  | rstick0[1],                    // 39 P1 R Left  (Btn 4)
	joystick_0[6]  | rstick0[0],                    // 38 P1 R Right (Btn 3)
	rack_tog,                                       // 37 rack test (toggle)
	rack_btn,                                       // 36 rack test (held)
	ctl36                                           // 35-0 shared ids
};

// DIP switches arrive from the OSD via ioctl index 254
reg [7:0] dip_sw[8] = '{8'hFF,8'hFF,8'hFF,8'hFF,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_SYS) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

// CTL-2026-10-24: input port builder -> ctl_port_map (idle = port_idle or the selected DIP byte, per port). Original commented out below.
// reg [7:0] in_port[6];
// always @(posedge CLK_SYS) begin
// 	for (int p = 0; p < 6; p++)
// 		for (int b = 0; b < 8; b++)
// 			in_port[p][b] <= (port_dip[p][7] ? port_idle[p][b] : dip_sw[port_dip[p][2:0]][b]) ^ ctl[in_map[p*8 + b]];
// end
// CTL2-2026-10-25: per-port DIP byte select (port_dip) absorbed into ctl_port_map BASE_MODE 1. v1 commented out below.
// wire [7:0]   in_port[6];
// wire [47:0]  port_idle_flat, in_ports;
// wire [383:0] in_map_flat;
// genvar gi;
// generate
// 	for (gi = 0; gi < 6; gi = gi + 1) begin : g_port
// 		assign port_idle_flat[gi*8 +: 8] = port_dip[gi][7] ? port_idle[gi] : dip_sw[port_dip[gi][2:0]];
// 		assign in_port[gi] = in_ports[gi*8 +: 8];
// 	end
// 	for (gi = 0; gi < 48; gi = gi + 1) begin : g_map
// 		assign in_map_flat[gi*8 +: 8] = {2'b00, in_map[gi]};
// 	end
// endgenerate
// ctl_port_map #(.NP(6), .IDW(6)) port_map
// (
// 	.clk(CLK_SYS), .idle(port_idle_flat), .in_map(in_map_flat), .dips(32'd0), .ctl(ctl),
// 	.ovr_mask(48'd0), .ovr_val(48'd0), .ports(in_ports)
// );
wire [7:0]   in_port[6];
wire [47:0]  port_idle_flat, port_sel_flat, in_ports;
wire [63:0]  dip_bytes_flat;
wire [383:0] in_map_flat;
genvar gi;
generate
	for (gi = 0; gi < 6; gi = gi + 1) begin : g_port
		assign port_idle_flat[gi*8 +: 8] = port_idle[gi];
		assign port_sel_flat[gi*8 +: 8]  = port_dip[gi];   // [7] = 1: idle byte, else DIP byte [2:0]
		assign in_port[gi] = in_ports[gi*8 +: 8];
	end
	for (gi = 0; gi < 8; gi = gi + 1) begin : g_dip
		assign dip_bytes_flat[gi*8 +: 8] = dip_sw[gi];
	end
	for (gi = 0; gi < 48; gi = gi + 1) begin : g_map
		assign in_map_flat[gi*8 +: 8] = {2'b00, in_map[gi]};
	end
endgenerate
ctl_port_map #(.NP(6), .IDW(6), .BASE_MODE(1)) port_map
(
	.clk(CLK_SYS), .idle(port_idle_flat), .in_map(in_map_flat), .dips(32'd0), .port_sel(port_sel_flat),
	.dip_bytes(dip_bytes_flat), .dip_bit(144'd0), .ctl(ctl), .ovr_mask(48'd0), .ovr_val(48'd0), .ports(in_ports)
);

// PAUSE SYSTEM
// ART-2026-10-24: stays on CLK_SYS ahead of the artwork (board pause / hiscore handshake unchanged); its rgb_out is the
// game picture the artwork composites (pause dim darkens the game, not the artwork)
wire [23:0] rgb_out;
pause #(8,8,8,20) pause
(
	.*,
	.clk_sys(CLK_SYS),
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[20:19])
);

///////////////                 Video                  ////////////////

wire hs, vs;
wire [7:0] r, g, b;
wire ce_pix;                       // ART-2026-10-24: CLK_2X pixel enable (art_xclk); the board's is bd_ce
wire bd_ce;                        // board pixel enable (CLK_SYS)

wire rotate_ccw = ~game_flags[7];  // ROT270 sets rotate CCW, ROT90 sets CW
wire no_rotate  = ~game_vert | status[12] | direct_video;
wire flip       = status[11];

// ART-2026-10-24: video back end on CLK_2X (art_xclk -> artwork -> arcade_video / screen_rotate, CLK_VIDEO = CLK_2X,
// DDRAM_CLK = CLK_2X); the board, pause, hiscore and ddr_rom stay on CLK_SYS. art_xclk moves the pixels and the
// artwork download across (related clocks: plain timed register paths). ddr_arb shares the DDRAM port: screen_rotate,
// ddr_rom (bridged from CLK_SYS) and the artwork (bursts split, lowest priority).
wire  [7:0] av_r, av_g, av_b;      // artwork output (CLK_2X): the board picture one pixel late, artwork applied
wire        av_hs, av_vs, av_hbl, av_vbl;
wire [27:0] v_px;
wire        a_wr;
wire [26:0] a_addr;
wire  [7:0] a_dout;
wire        art_wait;
art_xclk #(.IDX(8'd5), .VW(28)) art_xclk
(
	.clk_sys(CLK_SYS), .clk_art(CLK_2X),
	.bd_ce(bd_ce), .bd_px({hs, vs, hblank, vblank, rgb_out}), .ce_art(ce_pix), .px(v_px),
	.ioctl_wr(ioctl_wr), .ioctl_index(ioctl_index), .ioctl_addr(ioctl_addr27), .ioctl_dout(ioctl_dout),
	.ioctl_wait(art_ioctl_wait), .a_wr(a_wr), .a_addr(a_addr), .a_dout(a_dout), .art_wait(art_wait)
);

// MAME artwork (OSD Game Options page): native composite on the core video (one pixel late), full view through the
// DDR3 framebuffer on HDMI. CRT Flip: every board turns its picture exactly 180 degrees (board sim 2026-10-24).
wire        art_run;
wire [31:0] art_fb_base;
wire  [7:0] art_burstcnt, art_be;
wire [28:0] art_addr;
wire [63:0] art_din, art_dout;
wire        art_rd, art_we, art_busy, art_dout_ready;
artwork #(.IDX(8'd5)) artwork
(
	.clk(CLK_2X),
	.sel(status[48:45]), .layer_off({status[54], status[51:49]}), .side_off(status[52]), .zoom(status[53]),
	.crt_flip(status[22]), .hdmi_flip(status[11]), .turn(status[12]), .avail(art_avail),
	.hdmi_w(HDMI_WIDTH), .hdmi_h(HDMI_HEIGHT),
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(a_wr),
	.ioctl_addr(a_addr), .ioctl_dout(a_dout), .ioctl_wait(art_wait),
	.ce_pix(ce_pix),
	.hs_in(v_px[27]), .vs_in(v_px[26]), .hblank_in(v_px[25]), .vblank_in(v_px[24]), .rgb_in(v_px[23:0]),
	.hs_out(av_hs), .vs_out(av_vs), .hblank_out(av_hbl), .vblank_out(av_vbl), .rgb_out({av_r, av_g, av_b}),
	.running(art_run), .ddr_owner(), .canvas_w(art_cw), .canvas_h(art_ch),
	.fb_base(art_fb_base), .fb_vbl(FB_VBL),
	.DDRAM_CLK(), .DDRAM_BUSY(art_busy), .DDRAM_BURSTCNT(art_burstcnt), .DDRAM_ADDR(art_addr),
	.DDRAM_DOUT(art_dout), .DDRAM_DOUT_READY(art_dout_ready), .DDRAM_RD(art_rd),
	.DDRAM_DIN(art_din), .DDRAM_BE(art_be), .DDRAM_WE(art_we)
);
assign art_fb = art_run & ~direct_video;

// DDR3-2026-10-23: screen_rotate's DDR3 writes go through ddr_rom (shared port). Original:
// screen_rotate screen_rotate(.*);
// ART-2026-10-24: they now go to ddr_arb (S port, CLK_2X); the framebuffer is the artwork's while it draws
wire        sr_fb_en;
wire  [4:0] sr_fb_format;
wire [11:0] sr_fb_w, sr_fb_h;
wire [31:0] sr_fb_base;
wire [13:0] sr_fb_stride;
wire        sr_we;
wire [28:0] sr_addr;
wire [63:0] sr_din;
wire  [7:0] sr_be;
wire        ddr_row_req, ddr_row_rdy, ddr_byte_en, ddr_byte_rdy;
wire [24:0] ddr_row_addr, ddr_byte_addr;
wire [63:0] ddr_row_q;
wire  [7:0] ddr_byte_q;

screen_rotate screen_rotate
(
	.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE),
	.rotate_ccw(rotate_ccw), .no_rotate(no_rotate), .flip(flip), .video_rotated(video_rotated),
	// ART-2026-10-24: original
	// .FB_EN(FB_EN), .FB_FORMAT(FB_FORMAT), .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT), .FB_BASE(FB_BASE),
	// .FB_STRIDE(FB_STRIDE), .FB_VBL(FB_VBL), .FB_LL(FB_LL),
	.FB_EN(sr_fb_en), .FB_FORMAT(sr_fb_format), .FB_WIDTH(sr_fb_w), .FB_HEIGHT(sr_fb_h), .FB_BASE(sr_fb_base),
	.FB_STRIDE(sr_fb_stride), .FB_VBL(FB_VBL), .FB_LL(FB_LL),
	.DDRAM_CLK(), .DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(), .DDRAM_ADDR(sr_addr), .DDRAM_DIN(sr_din),
	.DDRAM_BE(sr_be), .DDRAM_WE(sr_we), .DDRAM_RD()
);

assign FB_EN     = art_fb | sr_fb_en;
assign FB_FORMAT = art_fb ? 5'b00110    : sr_fb_format;
assign FB_WIDTH  = art_fb ? art_cw      : sr_fb_w;
assign FB_HEIGHT = art_fb ? art_ch      : sr_fb_h;
assign FB_BASE   = art_fb ? art_fb_base : sr_fb_base;
assign FB_STRIDE = art_fb ? 14'd8192    : sr_fb_stride;

// Every index-0 byte mirrored to DDR3 at 0x3C000000; Indoor Soccer reads its sprite rows and ADPCM from there
// ART-2026-10-24: ddr_rom's DDRAM port goes to ddr_arb's G port (bridged CLK_SYS -> CLK_2X); screen_rotate no longer
// passes through it. Original port list:
//	.sr_we(sr_we), .sr_addr(sr_addr), .sr_din(sr_din), .sr_be(sr_be),
//	.DDRAM_CLK(DDRAM_CLK), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
//	.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(DDRAM_DIN),
//	.DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE)
wire        g_busy, g_dout_ready, g_rd, g_we;
wire [63:0] g_dout, g_din;
wire [28:0] g_addr;
wire  [7:0] g_be;
ddr_rom ddr_rom
(
	.clk(CLK_SYS),
	.ioctl_download(ioctl_download),
	.ioctl_wr0(ioctl_wr & (ioctl_index == 8'd0)),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ddr_ioctl_wait),
	.row_req(ddr_row_req), .row_addr(ddr_row_addr), .row_q(ddr_row_q), .row_rdy(ddr_row_rdy),
	.byte_en(ddr_byte_en), .byte_addr(ddr_byte_addr), .byte_q(ddr_byte_q), .byte_rdy(ddr_byte_rdy),
	.sr_we(1'b0), .sr_addr(29'd0), .sr_din(64'd0), .sr_be(8'd0),
	.DDRAM_CLK(), .DDRAM_BUSY(g_busy), .DDRAM_BURSTCNT(), .DDRAM_ADDR(g_addr),
	.DDRAM_DOUT(g_dout), .DDRAM_DOUT_READY(g_dout_ready), .DDRAM_RD(g_rd), .DDRAM_DIN(g_din),
	.DDRAM_BE(g_be), .DDRAM_WE(g_we)
);

// DDRAM port: screen_rotate > ddr_rom > artwork at every command slot; artwork bursts split into 8-beat pieces,
// at most 64 artwork read beats in flight (32 while the game reads ROM data from DDR3: sim, 16 starves the
// compositor at long DDR latency)
ddr_arb #(.CHUNK(8), .RWIN(64), .RWIN_G(32), .G_HOLD(4096), .SDEPTH(8)) ddr_arb
(
	.clk(CLK_2X), .clk_sys(CLK_SYS),
	// screen_rotate's picture is not shown while the artwork framebuffer is (its writes would only take bandwidth)
	.sr_we(sr_we & ~art_fb), .sr_addr(sr_addr), .sr_din(sr_din), .sr_be(sr_be),
	.g_rd(g_rd), .g_we(g_we), .g_addr(g_addr), .g_din(g_din), .g_be(g_be),
	.g_busy(g_busy), .g_dout(g_dout), .g_dout_ready(g_dout_ready),
	.a_rd(art_rd), .a_we(art_we), .a_burstcnt(art_burstcnt), .a_addr(art_addr), .a_din(art_din), .a_be(art_be),
	.a_busy(art_busy), .a_dout(art_dout), .a_dout_ready(art_dout_ready),
	.DDRAM_CLK(DDRAM_CLK), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE)
);

arcade_video #(256,24) arcade_video
(
	.*,

	// ART-2026-10-24: original
	// .clk_video(CLK_SYS),
	// .RGB_in(rgb_out),
	// .HBlank(hblank),
	// .VBlank(vblank),
	// .HSync(hs),
	// .VSync(vs),
	.clk_video(CLK_2X),

	.RGB_in({av_r, av_g, av_b}),
	.HBlank(av_hbl),
	.VBlank(av_vbl),
	.HSync(av_hs),
	.VSync(av_vs),

	.fx(status[18:16])
);

///////////////                 Board                  ////////////////

universal_board board
(
	.clk(CLK_SYS),
	.reset(reset),
	.pause(pause_cpu),
	.variant(game_var),
	.rom_dec(rom_dec),
	.game_flags2(game_flags2),
	// ART-2026-10-24: was .ce_pix(ce_pix),
	.ce_pix(bd_ce),

	.in0(in_port[0]),
	.in1(in_port[1]),
	.in2(in_port[2]),
	.dsw0(in_port[3]),
	.dsw1(in_port[4]),
	.coin(in_port[5]),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr0(ioctl_wr & (ioctl_index == 8'd0)),

	.crt_flip(status[22]),
	.h_adj(status[40:37]),
	.v_adj(status[44:41]),

	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_hs(hs),
	.video_vs(vs),
	.video_hblank(hblank),
	.video_vblank(vblank),

	.audio(audio),

	.ddr_row_req(ddr_row_req),
	.ddr_row_addr(ddr_row_addr),
	.ddr_row_rdy(ddr_row_rdy),
	.ddr_row_q(ddr_row_q),
	.ddr_byte_en(ddr_byte_en),
	.ddr_byte_addr(ddr_byte_addr),
	.ddr_byte_q(ddr_byte_q),
	.ddr_byte_rdy(ddr_byte_rdy),

	.hs_address(hs_address),
	.hs_data_in(hs_data_in),
	.hs_data_out(hs_data_out),
	.hs_write(hs_write_enable)
);

// Hiscore: config = MRA index 3, dump = index 4; RAM via the board's second port while the CPU is paused
wire [15:0] hs_address;
wire  [7:0] hs_data_in;
wire  [7:0] hs_data_out;
wire        hs_write_enable;
wire        hs_access_read;
wire        hs_access_write;
wire        hs_pause;
wire        hs_configured;

// HSCORE-2026-10-23: was CFG_ADDRESSWIDTH(4), HS_SCOREWIDTH default 8 (256 B). Largest tables: nomnlnd 1731 B,
// cosmicg 32 entries.
hiscore #(
	.HS_ADDRESSWIDTH(16),
	.HS_SCOREWIDTH(11),
	.CFG_ADDRESSWIDTH(5),
	.CFG_LENGTHWIDTH(2)
) hi (
	.*,
	.clk(CLK_SYS),
	.paused(pause_cpu),
	.autosave(status[21]),
	.ram_address(hs_address),
	.data_from_ram(hs_data_out),
	.data_to_ram(hs_data_in),
	.data_from_hps(ioctl_dout),
	.data_to_hps(ioctl_din),
	.ram_write(hs_write_enable),
	.ram_intent_read(hs_access_read),
	.ram_intent_write(hs_access_write),
	.pause_cpu(hs_pause),
	.configured(hs_configured)
);

endmodule

// CTL-2026-10-24: local joy4way replaced by ctl_joy4way (rtl/mister_custom/controllers.sv). Original commented out below.
// // 4-way joystick: the most recently pressed direction wins (from the MiSTer Pac-Man port)
// module joy4way
// (
// 	input        clk,
// 	input        en,
// 	input  [3:0] in,
// 	output [3:0] out
// );
//
// reg  [3:0] mask = 4'hF;
// reg  [3:0] in1 = 0, in2 = 0;
// wire [3:0] innew = in1 & ~in2;
//
// assign out = in1 & mask;
//
// always @(posedge clk) begin
// 	in1 <= in;
// 	in2 <= in1;
//
// 	if (innew[0]) mask <= 4'b0001;
// 	if (innew[1]) mask <= 4'b0010;
// 	if (innew[2]) mask <= 4'b0100;
// 	if (innew[3]) mask <= 4'b1000;
//
// 	if (!(in & mask) || !en) mask <= 4'hF;
// end
//
// endmodule
