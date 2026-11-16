; ---------------------------------------------------------------------------
; prog.asm : program for core8risc + Timer/ADC peripheral
;   LD rd,rs1 : rd = mem[rs1]     ST rd,rs1 : mem[rs1] = rd   (address in a reg)
;   Peripheral registers are at 0xF0..0xFF, GPIO_OUT = 0xE0, DONE_FLAG = 0xE1
;
;   Timer overflow triggers the ADC on channel 2 every 200 clocks.
;   The CPU polls ADC_STAT.EMPTY, pops each result (ADC_DATA), writes it to
;   GPIO_OUT and to RAM[0..15], then writes 0xA5 to DONE_FLAG and halts.
; ---------------------------------------------------------------------------
        LDI  r1, 0xF1        ; r1 = address of TMR_PRESC
        LDI  r2, 1
        ST   r2, r1          ; TMR_PRESC = 1
        ADDI r1, 1           ; 0xF2 TMR_LOAD
        LDI  r2, 99
        ST   r2, r1          ; TMR_LOAD = 99 -> period (1+1)*(99+1) = 200 clk
        ADDI r1, 4           ; 0xF6 ADC_SMP
        LDI  r2, 4
        ST   r2, r1          ; ADC_SMP = 4
        ADDI r1, 0xFF        ; 0xF5 ADC_CTRL  (r1 - 1)
        LDI  r2, 0x25        ; EN=1, TRIG_SEL=1 (timer ovf), CH=2
        ST   r2, r1          ; ADC_CTRL
        ADDI r1, 0xFB        ; 0xF0 TMR_CTRL  (r1 - 5)
        LDI  r2, 1
        ST   r2, r1          ; TMR_CTRL.EN = 1 -> timer starts counting

        LDI  r5, 0xFC        ; r5 = &ADC_STAT
        LDI  r6, 0x10        ; r6 = EMPTY mask
        LDI  r3, 0xFA        ; r3 = &ADC_DATA
        LDI  r4, 0xE0        ; r4 = &GPIO_OUT
        LDI  r7, 0           ; r7 = RAM write pointer
        LDI  r0, 16          ; r0 = samples still to take

wait_loop:
        LD   r2, r5          ; r2 = ADC_STAT
        AND  r2, r2, r6      ; Z = 1 when FIFO NOT empty
        BNEZ wait_loop       ; Z = 0 -> FIFO empty -> keep waiting

        LD   r1, r3          ; r1 = ADC_DATA (pops the FIFO)
        ST   r1, r4          ; GPIO_OUT = result (visible in waveform, checked by tb)
        ST   r1, r7          ; RAM[r7] = result
        ADDI r7, 1
        ADDI r0, 0xFF        ; r0 = r0 - 1, sets Z when it reaches 0
        BNEZ wait_loop

        LDI  r1, 0xA5
        LDI  r2, 0xE1
        ST   r1, r2          ; DONE_FLAG = 0xA5
        HALT
