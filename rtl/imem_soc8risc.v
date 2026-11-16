`timescale 1ns / 1ps

module imem_soc8risc (
    input  wire [7:0]  addr,
    output reg  [15:0] instr
);
    always @(*) begin
        case (addr)
            8'h00: instr = 16'h82F1;   // LDI  r1, 0xF1
            8'h01: instr = 16'h8401;   // LDI  r2, 1
            8'h02: instr = 16'hB440;   // ST   r2, r1
            8'h03: instr = 16'h9201;   // ADDI r1, 1
            8'h04: instr = 16'h8463;   // LDI  r2, 99
            8'h05: instr = 16'hB440;   // ST   r2, r1
            8'h06: instr = 16'h9204;   // ADDI r1, 4
            8'h07: instr = 16'h8404;   // LDI  r2, 4
            8'h08: instr = 16'hB440;   // ST   r2, r1
            8'h09: instr = 16'h92FF;   // ADDI r1, 0xFF
            8'h0A: instr = 16'h8425;   // LDI  r2, 0x25
            8'h0B: instr = 16'hB440;   // ST   r2, r1
            8'h0C: instr = 16'h92FB;   // ADDI r1, 0xFB
            8'h0D: instr = 16'h8401;   // LDI  r2, 1
            8'h0E: instr = 16'hB440;   // ST   r2, r1
            8'h0F: instr = 16'h8AFC;   // LDI  r5, 0xFC
            8'h10: instr = 16'h8C10;   // LDI  r6, 0x10
            8'h11: instr = 16'h86FA;   // LDI  r3, 0xFA
            8'h12: instr = 16'h88E0;   // LDI  r4, 0xE0
            8'h13: instr = 16'h8E00;   // LDI  r7, 0
            8'h14: instr = 16'h8010;   // LDI  r0, 16
            8'h15: instr = 16'hA540;   // LD   r2, r5
            8'h16: instr = 16'h34B0;   // AND  r2, r2, r6
            8'h17: instr = 16'hE015;   // BNEZ wait_loop
            8'h18: instr = 16'hA2C0;   // LD   r1, r3
            8'h19: instr = 16'hB300;   // ST   r1, r4
            8'h1A: instr = 16'hB3C0;   // ST   r1, r7
            8'h1B: instr = 16'h9E01;   // ADDI r7, 1
            8'h1C: instr = 16'h90FF;   // ADDI r0, 0xFF
            8'h1D: instr = 16'hE015;   // BNEZ wait_loop
            8'h1E: instr = 16'h82A5;   // LDI  r1, 0xA5
            8'h1F: instr = 16'h84E1;   // LDI  r2, 0xE1
            8'h20: instr = 16'hB280;   // ST   r1, r2
            8'h21: instr = 16'hF000;   // HALT
            default: instr = 16'hF000;   // HALT
        endcase
    end
endmodule
