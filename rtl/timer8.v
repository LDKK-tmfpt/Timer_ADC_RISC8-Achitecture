`timescale 1ns/1ps

module timer8 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire       oneshot,
    input  wire [7:0] presc,
    input  wire [7:0] load,
    input  wire [7:0] cmp,
    output reg  [7:0] cnt,
    output reg        ovf_pulse,
    output reg        cmp_pulse,
    output reg        en_clr,
    output wire       pwm
);
    reg [7:0] pre;

    wire       wrap     = (cnt >= load);
    wire [7:0] cnt_next = wrap ? 8'd0 : (cnt + 8'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pre       <= 8'd0;
            cnt       <= 8'd0;
            ovf_pulse <= 1'b0;
            cmp_pulse <= 1'b0;
            en_clr    <= 1'b0;
        end else begin
            ovf_pulse <= 1'b0;
            cmp_pulse <= 1'b0;
            en_clr    <= 1'b0;
            if (!en) begin
                pre <= 8'd0;
                cnt <= 8'd0;
            end else if (pre < presc) begin
                pre <= pre + 8'd1;
            end else begin
                pre <= 8'd0;
                cnt <= cnt_next;
                if (wrap) begin
                    ovf_pulse <= 1'b1;
                    if (oneshot) en_clr <= 1'b1;
                end
                if (cnt_next == cmp) cmp_pulse <= 1'b1;
            end
        end
    end

    assign pwm = en & (cnt < cmp);
endmodule
