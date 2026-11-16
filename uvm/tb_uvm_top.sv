`timescale 1ns/1ps

module tb_uvm_top;
    import uvm_pkg::*;
    import timer_adc_pkg::*;
    `include "uvm_macros.svh"

    logic clk = 1'b0;
    always #5 clk = ~clk;

    timer_adc_if tif (clk);

    timer_adc8_top dut (
        .clk(clk), .rst_n(tif.rst_n),
        .cs(tif.cs), .we(tif.we), .addr(tif.addr), .wdata(tif.wdata),
        .rdata(tif.rdata), .irq(tif.irq), .pwm_out(tif.pwm_out),
        .adc_sample(tif.adc_sample), .adc_ch(tif.adc_ch),
        .adc_dac(tif.adc_dac), .adc_cmp(tif.adc_cmp),
        .tmr_cnt_dbg(tif.tmr_cnt), .tmr_ovf_dbg(tif.tmr_ovf)
    );

    // ---- analog model: mux -> sample&hold -> DAC -> comparator
    real vhold = 0.0;
    always @(negedge tif.adc_sample) vhold = tif.vin[tif.adc_ch];
    always_comb tif.adc_cmp = (vhold >= real'(tif.adc_dac) * (3.3 / 256.0));

    initial begin
        for (int i = 0; i < 4; i++) tif.vin[i] = 0.0;
        tif.rst_n = 1'b0;
        #100 tif.rst_n = 1'b1;
    end

    initial begin
        uvm_config_db#(virtual timer_adc_if)::set(null, "*", "vif", tif);
        run_test();
    end

    initial begin
        #2000000;
        `uvm_fatal("TIMEOUT", "simulation timeout")
    end
endmodule
