# EGO1 RISC-V SoC — In-Class Demo Guide

One firmware (`programs/demo.S` → `programs/demo.hex`) shows off the whole
project on the physical board. It runs **unchanged on both CPUs** (multi-cycle
and 5-stage pipeline), so you can demonstrate correctness, interactive I/O, real
program execution, the hardware performance counters, **and** the pipeline
speedup — all from the switches, no PC needed.

> **Board status:** the pipeline demo (`demo_pipeline.bit`, 50 MHz, timing-closed)
> is written to the **SPI flash (N25Q32)** as of 2026-07-10 and **auto-boot is
> confirmed** on real hardware — it survives PROG / power-cycle with no laptop.
> Just power the board, set `dip_sw[2:0]`, and observe. (D24 lights on config.)

## Driving the demo — `dip_sw[2:0]` selects the view

Flip the three right-most DIP switches to choose what the LEDs + seven-segment
show. It updates live.

| `dip_sw[2:0]` | Shows | What it proves |
|:---:|---|---|
| `000` (0) | `CAFE` | ISA self-test magic word — datapath correctness |
| `001` (1) | live `{dip_sw, sw}` | Memory-mapped GPIO — flip `sw`, LEDs/7-seg follow instantly |
| `010` (2) | `5050` | Runs a real program: sum 1..100 in a loop |
| `011` (3) | benchmark **cycles** (decimal) | Hardware cycle counter |
| `100` (4) | benchmark **instructions** (decimal) | Hardware instret counter |
| `101` (5) | **CPI × 100** (decimal) | The headline result (see below) |
| `110/111` | `FFFF` | unused |

Numbers in modes 2–5 are shown in **decimal** (the firmware converts to BCD),
so `0528` literally means CPI = 5.28.

## The headline: multi-cycle vs. pipeline (verified in simulation)

The **same 305 instructions** run on both cores. Measured with the on-chip
counters:

| | Multi-cycle (`top_ego1`) | Pipeline (`top_ego1_pipeline`) |
|---|:---:|:---:|
| instructions (mode 4) | `0305` | `0305` |
| cycles (mode 3) | `1529` | `0503` |
| **CPI ×100 (mode 5)** | **`0501`** (5.01) | **`0164`** (1.64) |

Same work, **~3× fewer cycles** on the pipeline — forwarding + hazard handling
paying off, quantified live on the board.

> Note: these CPI numbers are for the sum-1..100 benchmark and differ from the
> project's ISA-self-test CPI (5.28 / 1.19) in the README — different workload.
> The sum loop is branch-heavy (a taken branch every 3 instructions), so the
> pipeline's per-instruction cost is a bit above its best case.

## Suggested 2-minute script for the professor

1. `dip_sw=000` → **CAFE**: "the CPU passes its full RV32I self-test on silicon."
2. `dip_sw=001` → flip `sw`: "memory-mapped GPIO, live."
3. `dip_sw=010` → **5050**: "it runs real programs — this is sum 1..100."
4. `dip_sw=011/100` → cycles & instrs: "hardware performance counters."
5. `dip_sw=101` → **CPI**: "1.64 on the pipeline…"
6. Re-flash the multi-cycle bitstream, `dip_sw=101` again → "…vs 5.01 multi-cycle.
   Same program, 3× faster."

## Programming the board

Two prebuilt bitstreams (both baked with `demo.hex`):

```bash
# from project_2/  — pipeline demo (50 MHz, timing-closed)
/d/Xilinx/Vivado/2018.3/bin/vivado.bat -mode batch -notrace \
  -source scripts/program_ego1.tcl -tclargs D:/vivado_project/project_2/demo_pipeline.bit

# multi-cycle demo (for the head-to-head)
/d/Xilinx/Vivado/2018.3/bin/vivado.bat -mode batch -notrace \
  -source scripts/program_ego1.tcl -tclargs D:/vivado_project/project_2/demo_multicycle.bit
```

JTAG programming is volatile (lost on power-cycle / PROG) — just re-run to switch
cores. To make a bitstream **permanent** (auto-boot from flash), write it to the
N25Q32 SPI flash instead:

```bash
# writes demo_pipeline.bit to flash (pass a different .bit as -tclargs to change)
/d/Xilinx/Vivado/2018.3/bin/vivado.bat -mode batch -notrace \
  -source scripts/flash_ego1.tcl -tclargs D:/vivado_project/project_2/demo_pipeline.bit
```

The pipeline demo is already in flash. To put the **multi-cycle** demo in flash
instead (e.g. for the head-to-head without a laptop), re-run the above with
`demo_multicycle.bit`.

## Rebuilding from source

```bash
# assemble firmware (validated: reproduces sw_led.hex + isa_selftest.hex exactly)
python programs/asm.py programs/demo.S programs/demo.hex

# simulate on BOTH cores (checks CAFE / mirror / 5050, prints CPI)
<modelsim>/win64/vsim.exe -c -do sim/modelsim_demo.do   # expect "PASS"

# build both bitstreams
/d/Xilinx/Vivado/2018.3/bin/vivado.bat -mode batch -notrace -source scripts/build_demo_both.tcl
```
