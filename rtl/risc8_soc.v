`timescale 1ns / 1ps

module risc8_soc (
    input  wire       clk,
    input  wire       rst,// active high
    // analog front end
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp,
    // pins
    output wire       pwm_out,
    output wire       irq,
    output wire [7:0] gpio_out,
    output reg        gpio_wr,
    output wire [7:0] done_flag,
    // debug / waveform
    output wire [7:0] tmr_cnt_dbg,
    output wire       tmr_ovf_dbg,
    output wire       halted,
    output wire [7:0] pc_out,
    output wire [1:0] flags_out,
    output wire       instr_done
);
    wire rst_n = ~rst;

    //  CPU core 
    wire       dm_we, dm_re;
    wire [7:0] dm_addr, dm_wdata, dm_rdata;

    core8risc_io u_core (
        .clk(clk), .rst(rst),
        .halted(halted), .pc_out(pc_out),
        .flags_out(flags_out), .instr_done(instr_done),
        .dm_we(dm_we), .dm_re(dm_re),
        .dm_addr(dm_addr), .dm_wdata(dm_wdata), .dm_rdata(dm_rdata)
    );

    //  address decode 
    wire io_sel   = (dm_addr[7:5] == 3'b111);          // 0xE0 - 0xFF
    wire gpio_sel = (dm_addr[7:4] == 4'hE);
    wire per_sel  = (dm_addr[7:4] == 4'hF);

    //  RAM (your dmem8risc) 
    wire [7:0] ram_rdata;
    dmem8risc u_dmem (
        .clk(clk), .rst(rst),
        .we(dm_we & ~io_sel),
        .addr(dm_addr), .wdata(dm_wdata),
        .rdata(ram_rdata)
    );
    wire [7:0] ram_rd = io_sel ? 8'h00 : ram_rdata;

    //  GPIO 
    reg [7:0] gpio_r, done_r;
    always @(posedge clk) begin
        if (rst) begin
            gpio_r  <= 8'd0;
            done_r  <= 8'd0;
            gpio_wr <= 1'b0;
        end else begin
            gpio_wr <= 1'b0;
            if (dm_we & gpio_sel) begin
                case (dm_addr[3:0])
                    4'h0: begin gpio_r <= dm_wdata; gpio_wr <= 1'b1; end
                    4'h1: done_r <= dm_wdata;
                    default: ;
                endcase
            end
        end
    end
    assign gpio_out  = gpio_r;
    assign done_flag = done_r;
    wire [7:0] gpio_rd = !(dm_re & gpio_sel) ? 8'h00 :
                         (dm_addr[3:0] == 4'h0) ? gpio_r :
                         (dm_addr[3:0] == 4'h1) ? done_r : 8'h00;

    // Timer + ADC peripheral 
    // cs is high for exactly one clock per LD/ST (MEM stage never repeats
    wire [7:0] per_rd;
    timer_adc8_top u_periph (
        .clk(clk), .rst_n(rst_n),
        .cs((dm_we | dm_re) & per_sel), .we(dm_we), .addr(dm_addr[3:0]),
        .wdata(dm_wdata), .rdata(per_rd), .irq(irq),
        .pwm_out(pwm_out),
        .adc_sample(adc_sample), .adc_ch(adc_ch),
        .adc_dac(adc_dac), .adc_cmp(adc_cmp),
        .tmr_cnt_dbg(tmr_cnt_dbg), .tmr_ovf_dbg(tmr_ovf_dbg)
    );

    // read-data mux 
    assign dm_rdata = ram_rd | gpio_rd | per_rd;
endmodule
