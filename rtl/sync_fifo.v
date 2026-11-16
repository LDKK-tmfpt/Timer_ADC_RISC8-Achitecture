`timescale 1ns/1ps


module sync_fifo #(
    parameter W = 10
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         wr_en,
    input  wire [W-1:0] wdata,
    input  wire         rd_en,
    output wire [W-1:0] rdata,
    output wire         empty,
    output wire         full,
    output reg  [3:0]   level
);
    reg [W-1:0] mem [0:7];
    reg [2:0]   wptr, rptr;

    assign empty = (level == 4'd0);
    assign full  = (level == 4'd8);
    assign rdata = mem[rptr];

    wire do_wr = wr_en & ~full;
    wire do_rd = rd_en & ~empty;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr  <= 3'd0;
            rptr  <= 3'd0;
            level <= 4'd0;
            for (i = 0; i < 8; i = i + 1) mem[i] <= {W{1'b0}};
        end else begin
            if (do_wr) begin
                mem[wptr] <= wdata;
                wptr      <= wptr + 3'd1;
            end
            if (do_rd) rptr <= rptr + 3'd1;
            case ({do_wr, do_rd})
                2'b10:   level <= level + 4'd1;
                2'b01:   level <= level - 4'd1;
                default: level <= level;
            endcase
        end
    end
endmodule
