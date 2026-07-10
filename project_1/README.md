# EGO1 RV32I SoC

This directory contains the first runnable baseline for the course project:

- multi-cycle RV32I-subset CPU
- unified BRAM instruction/data memory
- memory-mapped LED, switch, and seven-segment GPIO
- cycle, retired-instruction, and memory-wait counters
- EGO1 top wrapper and base XDC constraints

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

This has been checked with ModelSim SE-64 10.6e. The expected result is:

```text
PASS: RV32 SoC switch-to-LED smoke test
```

### Vivado With ModelSim

Create/open the Vivado project, then make sure ModelSim is configured:

```text
Tools -> Settings -> Simulation -> Target simulator -> ModelSim Simulator
Tools -> Settings -> Simulation -> ModelSim install path
```

The project script adds `sim/tb_rv32_soc.v` to `sim_1` and sets it as the
simulation top. Then run:

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
