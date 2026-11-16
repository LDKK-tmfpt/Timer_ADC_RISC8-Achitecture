`timescale 1ns/1ps
// Bus + analog wires of the Timer/ADC block, shared by DUT, UVM and the
// SystemVerilog analog model.
interface timer_adc_if (input logic clk);
    logic       rst_n;
    // CPU bus
    logic       cs;
    logic       we;
    logic [3:0] addr;
    logic [7:0] wdata;
    logic [7:0] rdata;
    logic       irq;
    logic       pwm_out;
    // analog side
    logic       adc_sample;
    logic [1:0] adc_ch;
    logic [7:0] adc_dac;
    logic       adc_cmp;
    // debug
    logic [7:0] tmr_cnt;
    logic       tmr_ovf;
    // input voltages driven by the UVM test (volts)
    real        vin [4];
endinterface
