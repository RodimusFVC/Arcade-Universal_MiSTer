//  Copyright (C) 2026 Rodimus

module cosmicg_sound
(
    input  logic               clk,
    input  logic               reset,
    input  logic               we,
    input  logic         [3:0] wa,
    input  logic               wd,
    output logic signed [15:0] audio
);

logic [3:0] t16 = 4'd0;
always_ff @(posedge clk) t16 <= t16 + 4'd1;
wire tk = (t16 == 4'd0);
logic [8:0] t410 = 9'd0;
wire ts = (t410 == 9'd409);
always_ff @(posedge clk) t410 <= ts ? 9'd0 : t410 + 9'd1;

logic       en = 1'b0, dac = 1'b0, gds = 1'b0;
logic [2:0] msel = 3'd0;
logic       m_go, g_go, d_go, e_go, b_go;
logic       att_on = 1'b0;
logic [1:0] ch4 = 2'd0;
logic       b_end;
logic       gun_sel;
always_ff @(posedge clk) begin
    {m_go, g_go, d_go, e_go, b_go} <= 5'd0;
    if (reset) begin
        en <= 1'b0; dac <= 1'b0; gds <= 1'b0; msel <= 3'd0; att_on <= 1'b0; ch4 <= 2'd0; gun_sel <= 1'b0;
    end
    else begin
        if (b_end && ch4 == 2'd2) ch4 <= 2'd0;
        if (we) begin
            if (wa == 4'd12) begin
                en <= wd;
                if (!wd) begin att_on <= 1'b0; ch4 <= 2'd0; end
            end
            if (en || (wa == 4'd12 && wd)) case (wa)
                4'd1:  dac <= wd;
                4'd2:  if (wd) m_go <= 1'b1;
                4'd3:  msel[0] <= wd;
                4'd4:  msel[1] <= wd;
                4'd5:  msel[2] <= wd;
                4'd6:  att_on <= wd;
                4'd7:  if (wd) begin ch4 <= 2'd2; b_go <= 1'b1; end
                4'd8:  if (wd) begin if (ch4 == 2'd0) ch4 <= 2'd1; end else ch4 <= 2'd0;
                4'd9:  if (wd) d_go <= 1'b1;
                4'd13: if (wd) begin g_go <= 1'b1; gun_sel <= gds; end
                4'd14: gds <= wd;
                4'd15: if (wd) e_go <= 1'b1;
                default: ;
            endcase
        end
    end
end
wire stop_all = reset || (we && wa == 4'd12 && !wd);

function automatic [11:0] march_inc(input [2:0] s);
    case (s)
        3'd0: march_inc = 12'd1475; 3'd1: march_inc = 12'd1420; 3'd2: march_inc = 12'd1379; 3'd3: march_inc = 12'd1338;
        3'd4: march_inc = 12'd1297; 3'd5: march_inc = 12'd1256; 3'd6: march_inc = 12'd1215; 3'd7: march_inc = 12'd1161;
    endcase
endfunction
function automatic [7:0] march_low(input [2:0] s);
    case (s)
        3'd0: march_low = 8'd108; 3'd1: march_low = 8'd113; 3'd2: march_low = 8'd115; 3'd3: march_low = 8'd120;
        3'd4: march_low = 8'd123; 3'd5: march_low = 8'd128; 3'd6: march_low = 8'd133; 3'd7: march_low = 8'd136;
    endcase
endfunction
function automatic [12:0] chance_inc(input [3:0] s);
    case (s)
        4'd0: chance_inc = 13'd6405; 4'd1: chance_inc = 13'd6077; 4'd2: chance_inc = 13'd5790; 4'd3: chance_inc = 13'd5572;
        4'd4: chance_inc = 13'd5476; 4'd5: chance_inc = 13'd5381; 4'd6: chance_inc = 13'd5681; 4'd7: chance_inc = 13'd6077;
        4'd8: chance_inc = 13'd6268; 4'd9: chance_inc = 13'd6405; default: chance_inc = 13'd6541;
    endcase
endfunction

logic [23:0] m_ph;
logic [2:0]  m_sel;
logic [12:0] m_t = 13'd0;
always_ff @(posedge clk) begin
    if (stop_all) m_t <= 13'd0;
    else if (m_go) begin m_t <= 13'd4075; m_ph <= 24'd0; m_sel <= msel; end
    else begin
        if (tk && m_t != 13'd0) m_ph <= m_ph + {12'd0, march_inc(m_sel)};
        if (ts && m_t != 13'd0) m_t <= m_t - 13'd1;
    end
end
wire m_on  = m_t != 13'd0;
wire m_out = m_ph[23:16] >= march_low(m_sel);

logic [23:0] c_ph = 24'd0;
logic        c_wrap;
always_ff @(posedge clk) begin
    c_wrap <= 1'b0;
    if (tk) {c_wrap, c_ph} <= {1'b0, c_ph} + 25'd32967;
end
logic [16:0] lf_a = 17'h1ACE1;
always_ff @(posedge clk) if (c_wrap) lf_a <= {lf_a[15:0], lf_a[16] ^ lf_a[13]};

logic [14:0] e_t = 15'd0;
always_ff @(posedge clk) begin
    if (stop_all) e_t <= 15'd0;
    else if (e_go) e_t <= 15'd23826;
    else if (ts && e_t != 15'd0) e_t <= e_t - 15'd1;
end

logic [23:0] h_ph = 24'd0;
logic  [3:0] h_step = 4'd0;
logic  [8:0] h_t = 9'd0;
always_ff @(posedge clk) begin
    if (ch4 != 2'd1) begin h_step <= 4'd0; h_t <= 9'd0; end
    else begin
        if (tk) h_ph <= h_ph + {11'd0, chance_inc(h_step)};
        if (ts) begin
            h_t <= (h_t == 9'd503) ? 9'd0 : h_t + 9'd1;
            if (h_t == 9'd503) h_step <= (h_step == 4'd11) ? 4'd0 : h_step + 4'd1;
        end
    end
end

logic [23:0] g_ph;
logic [15:0] g_inc;
logic [13:0] g_t = 14'd0;
logic  [2:0] g_div;
always_ff @(posedge clk) begin
    if (stop_all) g_t <= 14'd0;
    else if (g_go) begin
        g_t <= gun_sel ? 14'd9444 : 14'd11649; g_ph <= 24'd0; g_inc <= gun_sel ? 16'd38034 : 16'd37597; g_div <= 3'd0;
    end
    else begin
        if (tk && g_t != 14'd0) g_ph <= g_ph + {8'd0, g_inc};
        if (ts && g_t != 14'd0) begin
            g_t <= g_t - 14'd1;
            g_div <= (g_div == 3'd5) ? 3'd0 : g_div + 3'd1;
            if (!gun_sel && g_div == 3'd5 && g_inc > 16'd35903) g_inc <= g_inc - 16'd1;
        end
    end
end
wire g_audible = gun_sel ? 1'b1 : (g_t > 14'd1104);

logic [23:0] d_ph = 24'd0;
logic        d_wrap;
logic [16:0] lf_d = 17'h0B5A3;
always_ff @(posedge clk) begin
    d_wrap <= 1'b0;
    if (tk) {d_wrap, d_ph} <= {1'b0, d_ph} + 25'd18710;
    if (d_wrap) lf_d <= {lf_d[15:0], lf_d[16] ^ lf_d[13]};
end
logic [17:0] d_t = 18'd0;
logic [13:0] d_env = 14'd0;
logic  [5:0] d_div = 6'd0;
always_ff @(posedge clk) begin
    if (stop_all) d_t <= 18'd0;
    else if (d_go) begin d_t <= 18'd182176; d_env <= 14'd7000; end
    else if (ts && d_t != 18'd0) begin
        d_t <= d_t - 18'd1;
        d_div <= d_div + 6'd1;
        if (d_div == 6'd0) d_env <= d_env - (d_env >> 10);
    end
end

logic [15:0] b_t = 16'd0;
logic [13:0] b_env = 14'd0;
logic  [5:0] b_div = 6'd0;
always_ff @(posedge clk) begin
    b_end <= 1'b0;
    if (stop_all || ch4 != 2'd2) b_t <= 16'd0;
    if (b_go) begin b_t <= 16'd37874; b_env <= 14'd12000; end
    else if (ts && b_t != 16'd0) begin
        b_t <= b_t - 16'd1;
        if (b_t == 16'd1) b_end <= 1'b1;
        b_div <= b_div + 6'd1;
        if (b_t < 16'd11506 && b_div == 6'd0) b_env <= b_env - (b_env >> 6);
    end
end

localparam signed [17:0] A = 18'sd6000;
wire signed [17:0] v_march = !m_on ? 18'sd0 : m_out ? A : -A;
wire signed [17:0] v_att   = !att_on ? 18'sd0 : lf_a[0] ? A : -A;
wire signed [17:0] v_chnc  = (ch4 != 2'd1) ? 18'sd0 : (h_ph[23:16] >= 8'd115) ? A : -A;
wire signed [17:0] v_gun   = (g_t == 14'd0 || !g_audible) ? 18'sd0 : (g_ph[23:16] >= 8'd113) ? A : -A;
wire signed [17:0] v_ext   = (e_t == 15'd0) ? 18'sd0 : c_ph[23] ? A : -A;
wire signed [17:0] v_dac   = dac ? 18'sd4000 : 18'sd0;
wire signed [17:0] d_src   = (d_t == 18'd0) ? 18'sd0 : lf_d[0] ? $signed({4'd0, d_env}) : -$signed({4'd0, d_env});
wire signed [17:0] b_src   = (b_t == 16'd0) ? 18'sd0 : lf_a[0] ? $signed({4'd0, b_env}) : -$signed({4'd0, b_env});

function automatic signed [20:0] sx(input signed [17:0] v);
    sx = {{3{v[17]}}, v};
endfunction
logic signed [17:0] d_lp = 18'sd0, b_lp = 18'sd0;
logic signed [20:0] mix;
logic signed [20:0] hp_lp = 21'sd0;
wire  signed [17:0] b_clip = (b_lp > 18'sd7000) ? 18'sd7000 : (b_lp < -18'sd7000) ? -18'sd7000 : b_lp;
always_ff @(posedge clk) begin
    if (ts) begin
        d_lp  <= d_lp + ((d_src - d_lp) >>> 4);
        b_lp  <= b_lp + ((b_src - b_lp) >>> 3);
        mix   <= sx(v_march) + sx(v_att) + sx(v_chnc) + sx(v_gun) + sx(v_ext) + sx(v_dac) + sx(d_lp) + sx(b_clip);
        hp_lp <= hp_lp + ((mix - hp_lp) >>> 11);
    end
end
wire signed [20:0] hp = mix - hp_lp;
assign audio = (hp > 21'sd32767) ? 16'sd32767 : (hp < -21'sd32768) ? -16'sd32768 : hp[15:0];

endmodule
