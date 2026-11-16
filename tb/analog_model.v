`timescale 1ns/1ps

module analog_model #(
    parameter real VREF    = 3.3,
    parameter real SINE_HZ = 50.0e3
) (
    input  wire       sample,
    input  wire [1:0] ch,
    input  wire [7:0] dac,
    output reg        cmp
);
    localparam real LSB = VREF / 256.0;

    real    vhold;
    real    vdac;
    integer n_hold;
    integer code;
    reg [7:0] exp_mem [0:255];   // code the ADC should produce for each hold
    integer   hold_t  [0:255];   // time of each hold (ns)
    integer   hold_mv [0:255];   // held voltage (millivolts)
    reg [1:0] hold_ch [0:255];   // channel that was held

    function real vin_at;
        input [1:0] c;
        input real  t_ns;
        begin
            case (c)
                2'd0:    vin_at = 0.50;
                2'd1:    vin_at = 2.00;
                2'd2:    vin_at = 1.65 + 1.40 * $sin(6.283185307179586 * SINE_HZ * t_ns * 1.0e-9);
                default: vin_at = 3.00;
            endcase
        end
    endfunction

    reg hold_tog;      // toggles on every hold, wakes up the comparator
    reg was_tracking;  // 1 after 'sample' has really been 1 (ignores X->0 at reset)

    initial begin
        vhold        = 0.0;
        vdac         = 0.0;
        n_hold       = 0;
        cmp          = 1'b0;
        hold_tog     = 1'b0;
        was_tracking = 1'b0;
    end

    always @(posedge sample) was_tracking = 1'b1;

    always @(negedge sample) begin
        if (was_tracking) begin
            vhold = vin_at(ch, $realtime);
            code  = $rtoi(vhold / LSB);
            if (code > 255) code = 255;
            if (n_hold < 256) begin
                exp_mem[n_hold]  = code[7:0];
                hold_t[n_hold]   = $rtoi($realtime);
                hold_mv[n_hold]  = $rtoi(vhold * 1000.0);
                hold_ch[n_hold]  = ch;
            end
            n_hold   = n_hold + 1;
            hold_tog = ~hold_tog;
        end
        was_tracking = 1'b0;
    end

    // DAC + comparator: cmp = 1 when held input >= DAC voltage
    always @(dac or hold_tog) begin
        vdac = dac * LSB;
        cmp  = (vhold >= vdac);
    end
endmodule