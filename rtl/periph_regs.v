`timescale 1ns/1ps

//  0x0 TMR_CTRL   RW  [0] EN  [1] ONESHOT
//  0x1 TMR_PRESC  RW
//  0x2 TMR_LOAD   RW  reset 0xFF
//  0x3 TMR_CMP    RW  reset 0x80
//  0x4 TMR_CNT    RO  current count
//  0x5 ADC_CTRL   RW  [0] EN [1] START (reads 0) [3:2] TRIG_SEL [5:4] CH
//                     TRIG_SEL: 0 software, 1 timer ovf, 2 timer cmp, 3 continuous
//  0x6 ADC_SMP    RW  reset 4
//  0x7 ADC_DIV    RW
//  0x8 ADC_THR_LO RW
//  0x9 ADC_THR_HI RW  reset 0xFF
//  0xA ADC_DATA   RO  oldest FIFO result, reading it POPS the FIFO
//  0xB ADC_RCH    RO  [7] VALID  [1:0] channel of the oldest result
//  0xC ADC_STAT   RO  [6] BUSY [5] FULL [4] EMPTY [3:0] LEVEL   reset 0x10
//  0xD IRQ_EN     RW
//  0xE IRQ_STAT   W1C [0] TMR_OVF [1] TMR_CMP [2] ADC_EOC [3] ADC_WD
//                     [4] FIFO_OVR [5] TRIG_MISS
//  0xF ID         RO  0xA8

module periph_regs (
    input  wire       clk,
    input  wire       rst_n,
    // CPU bus
    input  wire       cs,
    input  wire       we,
    input  wire [3:0] addr,
    input  wire [7:0] wdata,
    output reg  [7:0] rdata,
    output wire       irq,
    // timer side
    output wire       t_en,
    output wire       t_oneshot,
    output wire [7:0] t_presc,
    output wire [7:0] t_load,
    output wire [7:0] t_cmp,
    input  wire [7:0] t_cnt,
    input  wire       t_ovf,
    input  wire       t_cmp_p,
    input  wire       t_en_clr,
    // ADC side
    output wire       a_en,
    output wire       a_start,
    output wire [1:0] a_ch_sel,
    output wire [7:0] a_smp,
    output wire [7:0] a_div,
    input  wire       a_busy,
    input  wire       a_eoc,
    input  wire [7:0] a_result,
    // FIFO side
    output wire       f_pop,
    input  wire [9:0] f_rdata,
    input  wire [3:0] f_level,
    input  wire       f_empty,
    input  wire       f_full
);
    wire wr = cs &  we;
    wire rd = cs & ~we;

    reg       t_en_r, t_one_r;
    reg [7:0] presc_r, load_r, cmp_r;
    reg       a_en_r, sw_start;
    reg [1:0] trig_r, ch_r;
    reg [7:0] smp_r, div_r, lo_r, hi_r, irq_en_r;
    reg [5:0] irq_stat;

    assign t_en      = t_en_r;
    assign t_oneshot = t_one_r;
    assign t_presc   = presc_r;
    assign t_load    = load_r;
    assign t_cmp     = cmp_r;
    assign a_en      = a_en_r;
    assign a_ch_sel  = ch_r;
    assign a_smp     = smp_r;
    assign a_div     = div_r;

    //  ADC start logic 
    wire trig_event = sw_start
                    | ((trig_r == 2'd1) & t_ovf)
                    | ((trig_r == 2'd2) & t_cmp_p);
    assign a_start  = trig_event | ((trig_r == 2'd3) & ~a_busy);
    wire   trig_miss = trig_event & a_busy & a_en_r;

    //  FIFO pop
    assign f_pop = rd & (addr == 4'hA) & ~f_empty;

    //  interrupt events
    wire wd_hit = a_eoc & ((a_result < lo_r) | (a_result > hi_r));
    wire [5:0] irq_set = { trig_miss,
                           a_eoc & f_full,
                           wd_hit,
                           a_eoc,
                           t_cmp_p,
                           t_ovf };
    wire [5:0] irq_clr = (wr && addr == 4'hE) ? wdata[5:0] : 6'd0;

    assign irq = |(irq_stat & irq_en_r[5:0]);

    // register writes 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_en_r   <= 1'b0;
            t_one_r  <= 1'b0;
            presc_r  <= 8'd0;
            load_r   <= 8'hFF;
            cmp_r    <= 8'h80;
            a_en_r   <= 1'b0;
            sw_start <= 1'b0;
            trig_r   <= 2'd0;
            ch_r     <= 2'd0;
            smp_r    <= 8'd4;
            div_r    <= 8'd0;
            lo_r     <= 8'd0;
            hi_r     <= 8'hFF;
            irq_en_r <= 8'd0;
            irq_stat <= 6'd0;
        end else begin
            sw_start <= 1'b0;
            if (t_en_clr) t_en_r <= 1'b0; // one-shot finished

            if (wr) begin
                case (addr)
                    4'h0: begin t_en_r <= wdata[0]; t_one_r <= wdata[1]; end
                    4'h1: presc_r <= wdata;
                    4'h2: load_r  <= wdata;
                    4'h3: cmp_r   <= wdata;
                    4'h5: begin
                        a_en_r   <= wdata[0];
                        sw_start <= wdata[1];
                        trig_r   <= wdata[3:2];
                        ch_r     <= wdata[5:4];
                    end
                    4'h6: smp_r    <= wdata;
                    4'h7: div_r    <= wdata;
                    4'h8: lo_r     <= wdata;
                    4'h9: hi_r     <= wdata;
                    4'hD: irq_en_r <= wdata;
                    default: ;
                endcase
            end

            // write-1-to-clear, but a new event in the same clock wins
            irq_stat <= (irq_stat & ~irq_clr) | irq_set;
        end
    end

    // register reads (combinational)
    always @(*) begin
        rdata = 8'h00;
        if (cs) begin
            case (addr)
                4'h0: rdata = {6'd0, t_one_r, t_en_r};
                4'h1: rdata = presc_r;
                4'h2: rdata = load_r;
                4'h3: rdata = cmp_r;
                4'h4: rdata = t_cnt;
                4'h5: rdata = {2'd0, ch_r, trig_r, 1'b0, a_en_r};
                4'h6: rdata = smp_r;
                4'h7: rdata = div_r;
                4'h8: rdata = lo_r;
                4'h9: rdata = hi_r;
                4'hA: rdata = f_empty ? 8'h00 : f_rdata[7:0];
                4'hB: rdata = f_empty ? 8'h00 : {1'b1, 5'd0, f_rdata[9:8]};
                4'hC: rdata = {1'b0, a_busy, f_full, f_empty, f_level};
                4'hD: rdata = irq_en_r;
                4'hE: rdata = {2'd0, irq_stat};
                4'hF: rdata = 8'hA8;
                default: rdata = 8'h00;
            endcase
        end
    end
endmodule
