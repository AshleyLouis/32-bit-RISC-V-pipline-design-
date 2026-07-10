# EGO1 RV32I SoC

**Docs:** [`NEXT_STEPS.md`](NEXT_STEPS.md) — how to build/sim/program/flash and
extend the project (start here to continue work) · [`DEMO_GUIDE.md`](DEMO_GUIDE.md)
— the in-class demo · [`HARDWARE_STATUS.md`](HARDWARE_STATUS.md) — verified state ·
[`EGO1_RISCV_SOC_PLAN.md`](EGO1_RISCV_SOC_PLAN.md) — architecture roadmap.

This directory contains the first runnable baseline for the course project:

- multi-cycle RV32I-subset CPU
- unified BRAM instruction/data memory
- memory-mapped LED, switch, and seven-segment GPIO
- cycle, retired-instruction, and memory-wait counters
- EGO1 top wrapper and base XDC constraints

It also contains the advanced variant used for the second-stage requirements:

- five-stage pipelined RV32I-subset CPU
- forwarding, load-use stall detection, branch/jump flush handling
- Harvard-style instruction/data BRAM access through `soc_bram_dual`
- pipeline stall and flush performance counters
- pipelined EGO1 top wrapper `top_ego1_pipeline`

## Memory Map

| Address | Access | Description |
| --- | --- | --- |
| `0x0000_0000` | R/W | BRAM program/data memory |
| `0x1000_0000` | R/W | LED register, low 16 bits |
| `0x1000_0004` | R | switch input, `{dip_sw, sw}` |
| `0x1000_0008` | R/W | seven-segment display value |
| `0x1000_0010` | R | cycle counter low 32 bits |
| `0x1000_0014` | R | retired instruction counter low 32 bits |
| `0x1000_0018` | R | memory wait counter |
| `0x1000_001c` | R | trap status |

In the pipelined SoC, the advanced performance counter block uses:

| Address | Access | Description |
| --- | --- | --- |
| `0x1000_0010` | R | cycle counter low 32 bits |
| `0x1000_0014` | R | retired instruction counter low 32 bits |
| `0x1000_0018` | R | memory wait counter |
| `0x1000_001c` | R | load-use stall counter |
| `0x1000_0020` | R | pipeline flush counter |

## Smoke Test Program

`programs/sw_led.hex` loads this loop into BRAM:

```asm
lui  x1, 0x10000
loop:
lw   x2, 4(x1)
sw   x2, 0(x1)
sw   x2, 8(x1)
jal  x0, loop
```

On the board, LEDs should mirror `{dip_sw, sw}` and the seven-segment display
scans the same 32-bit debug value.

## Vivado Project

From this directory, run in Vivado Tcl mode:

```tcl
source scripts/create_vivado_project.tcl
```

The script creates a project for `xc7a35tcsg324-1`, sets `top_ego1` as top, and
adds `ego1_base.xdc`.

## Simulation

The testbench is `sim/tb_rv32_soc.v`.

### ModelSim

From this directory:

```powershell
vsim -c -do sim/modelsim.do
```

This smoke test checks program fetch, `lw`, `sw`, GPIO switch input, LED output,
and the main SoC bus. It has been checked with ModelSim SE-64 10.6e. The expected
result is:

```text
PASS: RV32 SoC switch-to-LED smoke test
```

For a broader CPU/SoC self-test:

```powershell
vsim -c -do sim/modelsim_isa.do
```

This checks ALU operations, shifts, signed/unsigned comparisons, branches,
`jal`, BRAM load/store, GPIO, and the performance counters. The expected result
is:

```text
PASS: RV32 ISA/GPIO self-test
```

The measured baseline result on the ISA/GPIO self-test is:

```text
PASS: RV32 ISA/GPIO self-test, cycles=280 instret=53 mem_wait=60
```

So the multi-cycle baseline CPI is `280 / 53 = 5.28`.

For the pipelined CPU smoke test:

```powershell
vsim -c -do sim/modelsim_pipe_soc.do
```

Expected result:

```text
PASS: pipelined RV32 SoC switch-to-LED smoke test
```

For the pipelined CPU ISA/GPIO self-test:

```powershell
vsim -c -do sim/modelsim_pipe_isa.do
```

Expected result:

```text
PASS: pipelined RV32 ISA/GPIO self-test, cycles=63 instret=53 load_stalls=2 flushes=2
```

So the pipelined CPI is `63 / 53 = 1.19`.

### Vivado With ModelSim

Create/open the Vivado project, then make sure ModelSim is configured:

```text
Tools -> Settings -> Simulation -> Target simulator -> ModelSim Simulator
Tools -> Settings -> Simulation -> ModelSim install path
```

The project script adds all four testbenches to `sim_1` and sets
`tb_rv32_soc` as the default simulation top. To run other tests, set the
simulation top to `tb_rv32_isa`, `tb_rv32_pipe_soc`, or `tb_rv32_pipe_isa`.
Then run:

```text
Flow Navigator -> Simulation -> Run Simulation -> Run Behavioral Simulation
```

### Icarus Verilog

If Icarus Verilog is installed, one command line from this directory is:

```powershell
iverilog -g2012 -o sim/tb_rv32_soc.vvp rtl/rv32_alu.v rtl/rv32_regfile.v rtl/rv32_core_multicycle.v rtl/soc_bram.v rtl/soc_gpio.v rtl/rv32_soc.v sim/tb_rv32_soc.v
vvp sim/tb_rv32_soc.vvp
```

The expected result is:

```text
PASS: RV32 SoC switch-to-LED smoke test
```
