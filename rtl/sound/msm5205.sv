//============================================================================
//
//  OKI MSM5205 ADPCM decoder
//  Copyright (C) 2026 Rodimus
//
//  From MAME msm5205.cpp: 12-bit internal signal, 10-bit DAC, 49-step table
//  floor(16 * 1.1^step), index shift {-1,-1,-1,-1,2,4,6,8}. One nibble per
//  'step' pulse (the VCK edge at which MAME's update_adpcm runs); 'rst' is the
//  chip's RESET input as seen at that edge (signal and step cleared).
//
//============================================================================

module msm5205
(
    input  logic               clk,
    input  logic               step,
    input  logic               rst,
    input  logic         [3:0] data,
    output logic signed [11:0] signal
);

function automatic [10:0] stepval(input [5:0] s);
    case (s)
        6'd0:  stepval = 11'd16;   6'd1:  stepval = 11'd17;   6'd2:  stepval = 11'd19;   6'd3:  stepval = 11'd21;
        6'd4:  stepval = 11'd23;   6'd5:  stepval = 11'd25;   6'd6:  stepval = 11'd28;   6'd7:  stepval = 11'd31;
        6'd8:  stepval = 11'd34;   6'd9:  stepval = 11'd37;   6'd10: stepval = 11'd41;   6'd11: stepval = 11'd45;
        6'd12: stepval = 11'd50;   6'd13: stepval = 11'd55;   6'd14: stepval = 11'd60;   6'd15: stepval = 11'd66;
        6'd16: stepval = 11'd73;   6'd17: stepval = 11'd80;   6'd18: stepval = 11'd88;   6'd19: stepval = 11'd97;
        6'd20: stepval = 11'd107;  6'd21: stepval = 11'd118;  6'd22: stepval = 11'd130;  6'd23: stepval = 11'd143;
        6'd24: stepval = 11'd157;  6'd25: stepval = 11'd173;  6'd26: stepval = 11'd190;  6'd27: stepval = 11'd209;
        6'd28: stepval = 11'd230;  6'd29: stepval = 11'd253;  6'd30: stepval = 11'd279;  6'd31: stepval = 11'd307;
        6'd32: stepval = 11'd337;  6'd33: stepval = 11'd371;  6'd34: stepval = 11'd408;  6'd35: stepval = 11'd449;
        6'd36: stepval = 11'd494;  6'd37: stepval = 11'd544;  6'd38: stepval = 11'd598;  6'd39: stepval = 11'd658;
        6'd40: stepval = 11'd724;  6'd41: stepval = 11'd796;  6'd42: stepval = 11'd876;  6'd43: stepval = 11'd963;
        6'd44: stepval = 11'd1060; 6'd45: stepval = 11'd1166; 6'd46: stepval = 11'd1282; 6'd47: stepval = 11'd1411;
        default: stepval = 11'd1552;
    endcase
endfunction

logic signed [12:0] sig_q  = 13'sd0;
logic         [5:0] step_q = 6'd0;

wire [10:0] sv   = stepval(step_q);
wire [12:0] mag  = (data[2] ? {2'b00, sv} : 13'd0) + (data[1] ? {3'b000, sv[10:1]} : 13'd0) +
                   (data[0] ? {4'b0000, sv[10:2]} : 13'd0) + {5'b00000, sv[10:3]};
wire signed [13:0] nsig = data[3] ? ({sig_q[12], sig_q} - {1'b0, mag}) : ({sig_q[12], sig_q} + {1'b0, mag});
wire signed [13:0] nclp = (nsig > 14'sd2047) ? 14'sd2047 : (nsig < -14'sd2048) ? -14'sd2048 : nsig;

logic signed [6:0] shift;
always_comb begin
    case (data[2:0])
        3'd4: shift = 7'sd2;  3'd5: shift = 7'sd4;  3'd6: shift = 7'sd6;  3'd7: shift = 7'sd8;
        default: shift = -7'sd1;
    endcase
end
wire signed [7:0] nstep = $signed({2'b00, step_q}) + shift;

always_ff @(posedge clk) begin
    if (step) begin
        if (rst) begin
            sig_q  <= 13'sd0;
            step_q <= 6'd0;
        end
        else begin
            sig_q  <= nclp[12:0];
            step_q <= (nstep > 8'sd48) ? 6'd48 : (nstep < 8'sd0) ? 6'd0 : nstep[5:0];
        end
    end
end

assign signal = {sig_q[11:2], 2'b00};                         // 10-bit DAC

endmodule
