#!/usr/bin/env python3
"""Instruction-set check of prog.asm for the user's core8risc ISA.

Runs the assembled program on a Python functional model of the ISA (flags Z/C,
branch on Z) with a crude Timer/ADC stub (timer overflow every 200 clk ->
ADC result 86 pushed 14 clk later). It checks encoding + program flow only;
it does NOT model the pipeline and is NOT a replacement for the Verilog sim.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from asm import assemble  # noqa: E402

here = os.path.dirname(os.path.abspath(__file__))
words = assemble(open(os.path.join(here, "prog.asm")).read())
rom = {pc: w for pc, w, _ in words}

regs = [0] * 8
ram = [0] * 256
fz = fc = 0
pc, clk, halted = 0, 0, False
per, fifo, pending = {}, [], []
timer_start = None
gpio_log, done = [], 0


def mem_read(a):
    if a < 0xE0:
        return ram[a]
    if a == 0xFC:                       # ADC_STAT: bit4 = empty
        return (0x10 if not fifo else 0) | len(fifo)
    if a == 0xFA:                       # ADC_DATA pop
        return fifo.pop(0) if fifo else 0
    return per.get(a, 0)


def mem_write(a, v):
    global timer_start, done
    if a < 0xE0:
        ram[a] = v
    elif a == 0xE0:
        gpio_log.append(v)
    elif a == 0xE1:
        done = v
    else:
        per[a] = v
        if a == 0xF0 and (v & 1) and timer_start is None:
            timer_start = clk


def tick():
    if timer_start is None:
        return
    period = (per.get(0xF1, 0) + 1) * (per.get(0xF2, 255) + 1)
    if clk > timer_start and (clk - timer_start) % period == 0:
        pending.append(clk + 14)
    while pending and pending[0] <= clk:
        pending.pop(0)
        if len(fifo) < 8:
            fifo.append(86)


def advance(n):
    global clk
    for _ in range(n):
        clk += 1
        tick()


def setflags(res9):
    global fz, fc
    fz = 1 if (res9 & 255) == 0 else 0
    fc = (res9 >> 8) & 1


while not halted and clk < 200000:
    ir = rom.get(pc, 0xF000)
    op, rd, rs1, rs2, imm = ir >> 12, (ir >> 9) & 7, (ir >> 6) & 7, (ir >> 3) & 7, ir & 255
    advance(1)
    npc = (pc + 1) & 255
    a, b = regs[rs1], regs[rs2]
    if op == 1:   r = a + b;  regs[rd] = r & 255; setflags(r)
    elif op == 2: r = a - b;  regs[rd] = r & 255; setflags(r); fc = 1 if a < b else 0
    elif op == 3: r = a & b;  regs[rd] = r; setflags(r); fc = 0
    elif op == 4: r = a | b;  regs[rd] = r; setflags(r); fc = 0
    elif op == 5: r = a ^ b;  regs[rd] = r; setflags(r); fc = 0
    elif op == 6: r = (a << 1) & 255; fc = a >> 7; regs[rd] = r; fz = 1 if r == 0 else 0
    elif op == 7: r = a >> 1;         fc = a & 1;  regs[rd] = r; fz = 1 if r == 0 else 0
    elif op == 8: regs[rd] = imm
    elif op == 9: r = regs[rd] + imm; regs[rd] = r & 255; setflags(r)
    elif op == 10: regs[rd] = mem_read(a)
    elif op == 11: mem_write(a, regs[rd])
    elif op == 12 or (op == 13 and fz) or (op == 14 and not fz):
        npc = imm; advance(2)                   # 2 flushed pipeline slots
    elif op == 15: halted = True; npc = pc
    pc = npc

print("halted:", halted, " clocks:", clk, " done flag: 0x%02X" % done)
print("gpio writes:", len(gpio_log), " values:", sorted(set(gpio_log)))
print("RAM[0:16]:", ram[:16])
ok = halted and done == 0xA5 and len(gpio_log) == 16 and all(v == 86 for v in gpio_log)
print("ISS CHECK:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
