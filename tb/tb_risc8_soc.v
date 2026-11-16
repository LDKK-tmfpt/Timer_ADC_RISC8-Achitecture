`timescale 1ns / 1ps

module tb_risc8_soc;
    reg        clk;
    reg        rst;
    wire       halted;
    wire [7:0] pc_out;
    wire [1:0] flags_out;
    wire       instr_done;

    wire       adc_sample, adc_cmp;
    wire [1:0] adc_ch;
    wire [7:0] adc_dac;
    wire       pwm_out, irq, gpio_wr;
    wire [7:0] gpio_out, done_flag;

    // timer8 cnt forwarded to the final test bench
    wire [7:0] tmr_cnt;
    wire       tmr_ovf;

    integer cycle_cnt;
    integer instr_cnt;
    integer err_cnt;
    integer smp_cnt;
    integer diff;
    integer i;
    reg [7:0] exp_code;

    risc8_soc dut (
        .clk         (clk),
        .rst         (rst),
        .adc_sample  (adc_sample),
        .adc_ch      (adc_ch),
        .adc_dac     (adc_dac),
        .adc_cmp     (adc_cmp),
        .pwm_out     (pwm_out),
        .irq         (irq),
        .gpio_out    (gpio_out),
        .gpio_wr     (gpio_wr),
        .done_flag   (done_flag),
        .tmr_cnt_dbg (tmr_cnt),
        .tmr_ovf_dbg (tmr_ovf),
        .halted      (halted),
        .pc_out      (pc_out),
        .flags_out   (flags_out),
        .instr_done  (instr_done)
    );

    // pretend analog part (sample&hold, DAC, comparator)
    analog_model u_analog (
        .sample (adc_sample),
        .ch     (adc_ch),
        .dac    (adc_dac),
        .cmp    (adc_cmp)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst       = 1'b1;
        cycle_cnt = 0;
        instr_cnt = 0;
        err_cnt   = 0;
        smp_cnt   = 0;

        #25;
        rst = 1'b0;
    end

    initial begin
        $dumpfile("tb_risc8_soc.vcd");
        $dumpvars(0, tb_risc8_soc);
    end

    // count cycles / instructions
    always @(posedge clk) begin
        if (!rst && !halted) begin
            cycle_cnt = cycle_cnt + 1;
            if (instr_done)
                instr_cnt = instr_cnt + 1;
        end
    end

    // one line for every ADC result the CPU writes to GPIO_OUT
    always @(posedge clk) begin
        if (!rst && gpio_wr) begin
            exp_code = u_analog.exp_mem[smp_cnt];
            diff = gpio_out - exp_code;
            if (diff < 0) diff = -diff;

            if (diff > 1) begin
                err_cnt = err_cnt + 1;
                $display("Sample %02d | t=%0d ns | PC=0x%02h | Timer cnt=%02d | ADC=%03d | EXP=%03d | FAIL",
                         smp_cnt, $time, pc_out, tmr_cnt, gpio_out, exp_code);
            end else begin
                $display("Sample %02d | t=%0d ns | PC=0x%02h | Timer cnt=%02d | ADC=%03d | EXP=%03d | OK",
                         smp_cnt, $time, pc_out, tmr_cnt, gpio_out, exp_code);
            end
            smp_cnt = smp_cnt + 1;
        end
    end

    // end of program
    always @(posedge clk) begin
        if (!rst && halted) begin
            $display("------------------------------------------------------------");
            $display("Program halted at cycle %0d, instructions completed: %0d", cycle_cnt, instr_cnt);

            if (smp_cnt !== 16)                 begin $display("FAIL samples: exp 16, got %0d", smp_cnt); err_cnt = err_cnt + 1; end
            if (done_flag !== 8'hA5)            begin $display("FAIL DONE_FLAG: exp 0xA5, got 0x%02h", done_flag); err_cnt = err_cnt + 1; end

            if (dut.u_core.u_regfile.regs[0] !== 8'h00) begin $display("FAIL R0: exp 0x00, got 0x%02h", dut.u_core.u_regfile.regs[0]); err_cnt = err_cnt + 1; end
            if (dut.u_core.u_regfile.regs[1] !== 8'hA5) begin $display("FAIL R1: exp 0xA5, got 0x%02h", dut.u_core.u_regfile.regs[1]); err_cnt = err_cnt + 1; end
            if (dut.u_core.u_regfile.regs[2] !== 8'hE1) begin $display("FAIL R2: exp 0xE1, got 0x%02h", dut.u_core.u_regfile.regs[2]); err_cnt = err_cnt + 1; end
            if (dut.u_core.u_regfile.regs[3] !== 8'hFA) begin $display("FAIL R3: exp 0xFA, got 0x%02h", dut.u_core.u_regfile.regs[3]); err_cnt = err_cnt + 1; end
            if (dut.u_core.u_regfile.regs[4] !== 8'hE0) begin $display("FAIL R4: exp 0xE0, got 0x%02h", dut.u_core.u_regfile.regs[4]); err_cnt = err_cnt + 1; end
            if (dut.u_core.u_regfile.regs[5] !== 8'hFC) begin $display("FAIL R5: exp 0xFC, got 0x%02h", dut.u_core.u_regfile.regs[5]); err_cnt = err_cnt + 1; end
            if (dut.u_core.u_regfile.regs[6] !== 8'h10) begin $display("FAIL R6: exp 0x10, got 0x%02h", dut.u_core.u_regfile.regs[6]); err_cnt = err_cnt + 1; end
            if (dut.u_core.u_regfile.regs[7] !== 8'h10) begin $display("FAIL R7: exp 0x10, got 0x%02h", dut.u_core.u_regfile.regs[7]); err_cnt = err_cnt + 1; end
            if (flags_out !== 2'b11)                    begin $display("FAIL Flags Z,C: exp 11, got %b", flags_out); err_cnt = err_cnt + 1; end

            // RAM[0..15] must hold the results sent to GPIO_OUT
            for (i = 0; i < 16; i = i + 1) begin
                if (dut.u_dmem.ram[i] !== u_analog.exp_mem[i] &&
                    ((dut.u_dmem.ram[i] > u_analog.exp_mem[i] ? dut.u_dmem.ram[i] - u_analog.exp_mem[i]
                                                              : u_analog.exp_mem[i] - dut.u_dmem.ram[i]) > 1)) begin
                    $display("FAIL MEM[0x%02h]: exp 0x%02h, got 0x%02h", i, u_analog.exp_mem[i], dut.u_dmem.ram[i]);
                    err_cnt = err_cnt + 1;
                end
            end

            if (err_cnt == 0)
                $display("*** ALL TESTS PASSED ***");
            else
                $display("*** TEST FAILED WITH %0d ERRORS ***", err_cnt);
            $display("------------------------------------------------------------");
            $finish;
        end
    end

    // watchdog
    initial begin
        #200000;
        $display("*** TEST FAILED: TIMEOUT (PC=0x%02h, samples=%0d) ***", pc_out, smp_cnt);
        $finish;
    end
endmodule