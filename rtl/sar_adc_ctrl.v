`timescale 1ns/1ps

module sar_adc_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire       start,
    input  wire [1:0] ch_sel,
    input  wire [7:0] smp,
    input  wire [7:0] div,
    input  wire       cmp,
    output reg        sample,
    output reg  [7:0] dac,
    output reg  [1:0] ch,
    output wire       busy,
    output reg        eoc,
    output reg  [7:0] result
);
    localparam [1:0] IDLE = 2'd0, SAMPLE = 2'd1, CONVERT = 2'd2;

    reg [1:0] state;
    reg [7:0] cnt;
    reg [7:0] dcnt;
    reg [2:0] bitn;

    wire ce = (dcnt == div);

    assign busy = (state != IDLE);


    wire [7:0] kept = cmp ? dac : (dac & ~(8'd1 << bitn));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= IDLE;
            cnt    <= 8'd0;
            dcnt   <= 8'd0;
            bitn   <= 3'd0;
            sample <= 1'b0;
            dac    <= 8'd0;
            ch     <= 2'd0;
            eoc    <= 1'b0;
            result <= 8'd0;
        end else begin
            eoc <= 1'b0;
            if (!en) begin
                state  <= IDLE;
                sample <= 1'b0;
                dac    <= 8'd0;
                cnt    <= 8'd0;
                dcnt   <= 8'd0;
            end else begin
                case (state)
                    IDLE: begin
                        dcnt <= 8'd0;
                        cnt  <= 8'd0;
                        if (start) begin
                            sample <= 1'b1;
                            ch     <= ch_sel;
                            state  <= SAMPLE;
                        end
                    end

                    SAMPLE: begin
                        if (ce) begin
                            dcnt <= 8'd0;
                            if (cnt == smp) begin
                                sample <= 1'b0;
                                bitn   <= 3'd7;
                                dac    <= 8'h80;
                                state  <= CONVERT;
                            end else begin
                                cnt <= cnt + 8'd1;
                            end
                        end else begin
                            dcnt <= dcnt + 8'd1;
                        end
                    end

                    CONVERT: begin
                        if (ce) begin
                            dcnt <= 8'd0;
                            if (bitn == 3'd0) begin
                                result <= kept;
                                eoc    <= 1'b1;
                                dac    <= 8'd0;
                                state  <= IDLE;
                            end else begin
                                dac  <= kept | (8'd1 << (bitn - 3'd1));
                                bitn <= bitn - 3'd1;
                            end
                        end else begin
                            dcnt <= dcnt + 8'd1;
                        end
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
