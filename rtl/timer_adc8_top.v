`timescale 1ns/1ps

module timer_adc8_top (
    input  wire       clk,
    input  wire       rst_n,
    // CPU bus
    input  wire       cs,
    input  wire       we,
    input  wire [3:0] addr,
    input  wire [7:0] wdata,
    output wire [7:0] rdata,
    output wire       irq,
    // PWM
    output wire       pwm_out,
    // analog front end
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp,
    // debug / waveform
    output wire [7:0] tmr_cnt_dbg,
    output wire       tmr_ovf_dbg
);
    wire       t_en, t_oneshot, t_ovf, t_cmp_p, t_en_clr;
    wire [7:0] t_presc, t_load, t_cmp, t_cnt;

    wire       a_en, a_start, a_busy, a_eoc;
    wire [1:0] a_ch_sel;
    wire [7:0] a_smp, a_div, a_result;

    wire       f_pop, f_empty, f_full;
    wire [9:0] f_rdata;
    wire [3:0] f_level;

    periph_regs u_regs (
        .clk(clk), .rst_n(rst_n),
        .cs(cs), .we(we), .addr(addr), .wdata(wdata), .rdata(rdata), .irq(irq),
        .t_en(t_en), .t_oneshot(t_oneshot), .t_presc(t_presc),
        .t_load(t_load), .t_cmp(t_cmp), .t_cnt(t_cnt),
        .t_ovf(t_ovf), .t_cmp_p(t_cmp_p), .t_en_clr(t_en_clr),
        .a_en(a_en), .a_start(a_start), .a_ch_sel(a_ch_sel),
        .a_smp(a_smp), .a_div(a_div),
        .a_busy(a_busy), .a_eoc(a_eoc), .a_result(a_result),
        .f_pop(f_pop), .f_rdata(f_rdata), .f_level(f_level),
        .f_empty(f_empty), .f_full(f_full)
    );

    timer8 u_timer (
        .clk(clk), .rst_n(rst_n),
        .en(t_en), .oneshot(t_oneshot),
        .presc(t_presc), .load(t_load), .cmp(t_cmp),
        .cnt(t_cnt), .ovf_pulse(t_ovf), .cmp_pulse(t_cmp_p),
        .en_clr(t_en_clr), .pwm(pwm_out)
    );

    sar_adc_ctrl u_adc (
        .clk(clk), .rst_n(rst_n),
        .en(a_en), .start(a_start), .ch_sel(a_ch_sel),
        .smp(a_smp), .div(a_div), .cmp(adc_cmp),
        .sample(adc_sample), .dac(adc_dac), .ch(adc_ch),
        .busy(a_busy), .eoc(a_eoc), .result(a_result)
    );

    sync_fifo #(.W(10)) u_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(a_eoc), .wdata({adc_ch, a_result}),
        .rd_en(f_pop), .rdata(f_rdata),
        .empty(f_empty), .full(f_full), .level(f_level)
    );

    // forward the timer count (and overflow pulse) for the final waveform
    assign tmr_cnt_dbg = t_cnt;
    assign tmr_ovf_dbg = t_ovf;
endmodule
