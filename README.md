# Timer + ADC + UVM + CPU core8risc (Vivado)

This SoC integrates your **5-stage pipelined CPU core `core8risc**`, RAM (`dmem8risc`), GPIO, and a **Timer + 8-bit SAR ADC + FIFO + 16 memory-mapped registers** peripheral block.
The final testbench is `tb/tb_risc8_soc.v`, with the `timer8` counter `cnt` forwarded to the final waveform.

> **Verification Status:** The assembler and program have been verified using `asm/iss_check.py` (Python ISA model, non-pipelined).
> **RTL, Verilog testbenches, and UVM environments have not yet been run on a physical simulator** (the generation environment lacks Vivado/iverilog).
> Please run this project in Vivado and report any compilation errors or simulation mismatches.

---

## 1. Directory Structure

| File / Directory | Description |
| --- | --- |
| `rtl/alu8risc.v`, `ctrlu8risc.v`, `hazardu8risc.v`, `regfile8risc.v`, `dmem8risc.v` | **Your original RTL files (unmodified)** |
| `rtl/core8risc_io.v` | Modified copy of `core8risc.v` with 3 key interface adaptations |
| `rtl/imem_soc8risc.v` | SoC program ROM (**auto-generated** from `asm/prog.asm`, matching `imem8risc` port interface) |
| `rtl/risc8_soc.v` | Top-level SoC integrating Core + RAM + GPIO + peripherals and address decoding |
| `rtl/timer8.v`, `sar_adc_ctrl.v`, `sync_fifo.v`, `periph_regs.v`, `timer_adc8_top.v` | Timer and SAR ADC peripheral hardware modules |
| `tb/analog_model.v` | Analog front-end behavioral model (mux, sample & hold, DAC, comparator) & expected ADC code memory |
| `tb/tb_risc8_soc.v` | **Final SoC testbench** (includes `tmr_cnt` monitoring) |
| `uvm/` | UVM verification environment for the Timer+ADC block (`reg_test`, `adc_sw_test`, `timer_trig_test`) |
| `asm/` | `asm.py` (custom ISA assembler), `prog.asm`, `iss_check.py` |
| `cpu_original/` | Original `core8risc.v`, `imem8risc.v`, `tb_core8risc.v` (for reference only, do not include in project) |
| `scripts/create_project.tcl` | Vivado automatic project creation Tcl script |
| `sim/run_xsim.sh`, `.bat` | Command-line xsim execution scripts |

---

## 2. Core Integration: Required Modifications

Since your original core encapsulated `dmem8risc` internally without external data bus access, peripherals could not be attached. `core8risc_io.v` introduces three modifications to `core8risc.v`:

1. Added 5 external data bus ports: `dm_we`, `dm_re`, `dm_addr`, `dm_wdata` (outputs) and `dm_rdata` (input).
2. Removed internal `dmem8risc u_dmem` and tied bus signals directly to the MEM stage:
* `dm_we = exmem_valid && exmem_mem_we`
* `dm_re = exmem_valid && exmem_mem_to_reg`
* `dm_addr = exmem_addr`
* `dm_wdata = exmem_st_data`
* `mem_rdata = dm_rdata`


3. Replaced `imem8risc` with `imem_soc8risc` (SoC program ROM).

`risc8_soc.v` instantiates `dmem8risc` externally and performs address decoding. Each `LD`/`ST` instruction asserts for exactly 1 clock cycle in the MEM stage, ensuring peripheral `cs` signals pulse for 1 cycle (required for `ADC_DATA` where a read pops the FIFO). System reset is **active-high `rst**`, matching your core convention.

### Data Memory Map

* `0x00 – 0xDF`: System Data RAM
* `0xE0`: `GPIO_OUT` (Data write)
* `0xE1`: `DONE_FLAG`
* `0xF0 – 0xFF`: Peripheral Control Registers

---

## 3. Forwarding Timer `cnt` to the Final Testbench

```
timer8.cnt -> timer_adc8_top.tmr_cnt_dbg -> risc8_soc.tmr_cnt_dbg -> tb_risc8_soc.tmr_cnt

```

* In `tb_risc8_soc.v`: `wire [7:0] tmr_cnt;` connects to `.tmr_cnt_dbg(tmr_cnt)` of `risc8_soc`.
* `scripts/wave_tb_risc8_soc.tcl` automatically adds `tmr_cnt` (yellow, unsigned format) and `tmr_ovf` to the waveform viewer.
* The testbench prints `tmr_cnt` whenever the CPU reads an ADC sample. *(Alternative hierarchical reference: `wire [7:0] tmr_cnt = dut.u_periph.u_timer.cnt;`)*

---

## 4. How to Run in Vivado

* **Quick Method:** Go to `Tools → Run Tcl Script...` and select `scripts/create_project.tcl`. This script creates the project, adds all sources, sets `tb_risc8_soc` as the top module for `sim_1`, and configures the `sim_uvm` fileset (with `-L uvm` enabled). Then click **Run Simulation → Run Behavioral Simulation**.
* **Manual Method:** Add the 13 files in `rtl/` (Top = `risc8_soc`; **exclude** `cpu_original/`), add `tb/analog_model.v` and `tb/tb_risc8_soc.v` to Simulation Sources (Top = `tb_risc8_soc`), and run simulation for approximately $60\,\mu\text{s}$.

**Expected Output:** 16 printed lines in the console (`sample N : ADC=... (expected ...) tmr_cnt=...`), followed by timer overflow logs, and finally `*** ALL TESTS PASSED ***`.

---

## 5. Program (`asm/prog.asm`) & ISA Overview

Supported ISA instructions (per `ctrlu8risc.v`):
`NOP, ADD, SUB, AND, OR, XOR (rd,rs1,rs2), SHL, SHR (rd,rs1), LDI rd,imm, ADDI rd,imm (rd=rd+imm), LD rd,rs1 (rd=mem[rs1]), ST rd,rs1 (mem[rs1]=rd), JMP, BEQZ, BNEZ, HALT`.

Branching relies on the **Z** flag set by the most recent ALU instruction (`LDI`/`LD`/`ST` do not modify flags). Since `LD`/`ST` addresses must reside in registers, memory addresses are loaded using `LDI`/`ADDI`.

### Program Logic

1. Configures `TMR_PRESC = 1`, `TMR_LOAD = 99` ($200$-clock period).
2. Configures `ADC_SMP = 4`, `ADC_CTRL = 0x25` (Enables ADC, sets trigger source to timer overflow, selects channel 2), and enables the timer.
3. Enters a polling loop checking `ADC_STAT`. If the FIFO is not empty, it reads `ADC_DATA`, writes the result to `GPIO_OUT` and RAM `[0..15]`.
4. After 16 samples, writes `0xA5` to `DONE_FLAG` and executes `HALT`.

*Channel 2 input is modeled as a $50\,\text{kHz}$ sine wave ($1.65\text{V} \pm 1.4\text{V}$); the testbench compares each result against expected values with a tolerance of $\pm 1$ LSB.*

### Modifying the Program

Edit `asm/prog.asm`, then run:

```bash
python3 asm/asm.py asm/prog.asm rtl/imem_soc8risc.v
python3 asm/iss_check.py

```

---

## 6. Peripheral Register Map (Offset from `0xF0`)

| Offset | Register Name | Description |
| --- | --- | --- |
| `0x0` | `TMR_CTRL` | [0] Enable (`EN`), [1] One-shot mode (`ONESHOT`) |
| `0x1` | `TMR_PRESC` | Clock prescaler divider value |
| `0x2` | `TMR_LOAD` | Timer reload / maximum count value |
| `0x3` | `TMR_CMP` | Timer compare threshold |
| `0x4` | `TMR_CNT` | Live timer counter value (Read-Only) |
| `0x5` | `ADC_CTRL` | [0] EN, [1] START, [3:2] TRIG_SEL (0: SW, 1: Timer OVF, 2: Timer CMP, 3: Continuous), [5:4] CH |
| `0x6` | `ADC_SMP` | Sample phase duration |
| `0x7` | `ADC_DIV` | ADC clock prescaler divider |
| `0x8` | `ADC_THR_LO` | Watchdog lower threshold |
| `0x9` | `ADC_THR_HI` | Watchdog upper threshold |
| `0xA` | `ADC_DATA` | Oldest ADC FIFO result (Reading pops FIFO) |
| `0xB` | `ADC_RCH` | [7] Valid, [1:0] Popped sample channel ID |
| `0xC` | `ADC_STAT` | [6] Busy, [5] Full, [4] Empty, [3:0] FIFO Level |
| `0xD` | `IRQ_EN` | Interrupt Enable mask |
| `0xE` | `IRQ_STAT` | Interrupt Status (Write-1-to-Clear) |
| `0xF` | `ID` | Peripheral ID (`0xA8`) |

---

## 7. UVM Verification

* Use the `sim_uvm` simulation set (XSIM supports UVM 1.2 via `-L uvm`).
* Verifies `timer_adc8_top` directly without CPU involvement.
* Switch tests in Vivado via `xsim.simulate.xsim.more_options`:
`-testplusarg UVM_TESTNAME=reg_test` | `adc_sw_test` | `timer_trig_test`.

## 8. Author
HOANG NGOC LONG - SE204586