# NEXT STEPS — handoff & how-to for continuing this project

_Last updated 2026-07-11. Read this first if you're picking the project up again._

## Where things stand

A working RV32I CPU/SoC for the **EGO1 (Artix-7 `xc7a35tcsg324-1`)**, in two
flavours that share one memory map and one firmware format:

- **Multi-cycle** core — `top_ego1` → `rv32_soc`.
- **5-stage pipeline** core — `top_ego1_pipeline` → `rv32_soc_pipeline`
  (forwarding, load-use stall, branch/jump flush). Runs at **50 MHz** on the
  board (fabric ÷2 clock divider) so it closes timing cleanly.

Both pass the ISA self-test on real hardware, and an **interactive 6-mode demo**
(`programs/demo.S`) runs on both. The demo is written to **SPI flash and
auto-boots** — see `DEMO_GUIDE.md`. Current verified status is in
`HARDWARE_STATUS.md`; the architecture roadmap is `EGO1_RISCV_SOC_PLAN.md`.

## Tools on this machine (none are on PATH — use full paths)

| Tool | Location | Notes |
|------|----------|-------|
| Vivado 2018.3 | `D:\Xilinx\Vivado\2018.3\bin\vivado.bat` | project flow is the reliable one here |
| ModelSim SE-64 10.6e | `/d/Mentor_Graphics_ModelSim_SE-64_10.6e/win64/vsim.exe` | the `modelsim106e` symlink at repo root is broken; use the full path |
| Python 3 | `python` | NOT `py` / `D:\python\python.exe` (that launcher is broken) |

No RISC-V GCC is installed — firmware is written in assembly and built with the
in-repo assembler `programs/asm.py`.

## Common tasks (run from `project_2/`)

**Assemble firmware**
```bash
python programs/asm.py programs/demo.S programs/demo.hex
# sanity-check the assembler after editing it — must still reproduce these exactly:
python programs/asm.py programs/sw_led.S /tmp/a.hex && diff <(tr -d '\r' <programs/sw_led.hex) /tmp/a.hex
```

**Simulate (ModelSim)**
```bash
export PATH="/d/Mentor_Graphics_ModelSim_SE-64_10.6e/win64:$PATH"
vsim.exe -c -do sim/modelsim_demo.do      # dual-core demo; expect "PASS"
vsim.exe -c -do sim/modelsim_pipe_isa.do  # pipeline ISA self-test
```

**Build a bitstream**
```bash
V="/d/Xilinx/Vivado/2018.3/bin/vivado.bat -mode batch -notrace -source"
$V scripts/build_demo_pipeline.tcl   # pipeline demo -> demo_pipeline.bit
$V scripts/build_demo_both.tcl       # both cores' demo bitstreams
$V scripts/build_pipeline_50mhz.tcl  # pipeline ISA self-test @ 50 MHz
```

**Program the board — volatile (JTAG), lost on power-cycle/PROG**
```bash
$V scripts/program_ego1.tcl -tclargs D:/vivado_project/project_2/demo_pipeline.bit
```

**Program the board — permanent (SPI flash, auto-boots)**
```bash
$V scripts/flash_ego1.tcl -tclargs D:/vivado_project/project_2/demo_pipeline.bit
```

## HARDWARE instructions & gotchas (the non-obvious stuff)

These cost real debugging time; don't rediscover them.

1. **`FPGA_RESET` button (pin P15) is idle-HIGH, pressed-LOW** — the *opposite*
   of the 5 general-purpose buttons in the manual. The tops treat it directly
   as active-low `resetn` (`wire resetn = reset_btn;` — **no inversion**), with
   `PULLUP true` in `ego1_base.xdc`. If a new top reads `reset_btn`, copy this;
   do not re-derive polarity from the manual.

2. **The PROG button and power-cycle wipe a JTAG-loaded design.** JTAG config is
   volatile. If the board goes blank (LEDs off, 7-seg dark), it wasn't broken —
   just re-run `program_ego1.tcl`, or use flash (below) so it auto-boots.

3. **Auto-boot from flash** needs (a) the bitstream in flash via
   `flash_ego1.tcl`, and (b) the board's **boot-mode jumper in the QSPI/flash
   position**. Board LED **D24 lights** when the FPGA has configured from flash.
   Flash part is **Micron N25Q32, 3.3 V** → Vivado cfgmem part
   `n25q32-3.3v-spi-x1_x2_x4`.

4. **JTAG programming API is Vivado-2018.3-specific:** use `open_hw` /
   `close_hw` (NOT `open_hw_manager` / `close_hw_manager`, which are 2019.2+).
   The board enumerates as `xc7a35t_0`. To just probe it: `scripts/detect_hw.tcl`.

5. **Pipeline timing only closes at 50 MHz.** At 100 MHz the branch-resolution
   path misses setup (architectural, ~11 logic levels). The ÷2 divider lives in
   `top_ego1_pipeline.v`; the 50 MHz `cpu_clk` is constrained by
   `pipeline_50mhz.xdc`, which is **kept `is_enabled false`** and flipped `true`
   only by the pipeline build scripts. **Never** put a `create_generated_clock`
   guarded by `if {[get_pins ...]}` in the shared `ego1_base.xdc` — that guard
   runs before the netlist exists and silently leaves the CPU unconstrained.

6. **Two tops in one project.** With both `top_ego1` and `top_ego1_pipeline` as
   roots, set `source_mgmt_mode DisplayOnly` + explicit `top` to build the
   pipeline; `All` (default) auto-reselects `top_ego1`. Build scripts handle
   this and restore defaults on exit.

7. **Bitstream "failed" but the log says success?** The demo build scripts read
   a stale `impl_1` STATUS after `wait_on_run` and may print `*_FAILED` even
   though `write_bitstream completed successfully`. If so, the `.bit` is really
   in `project_2.runs/impl_1/` — `cp` it out.

## Memory map (both cores)

| Address | R/W | Function |
|---------|-----|----------|
| `0x1000_0000` | W/R | LED (low 16 bits) |
| `0x1000_0004` | R | `{dip_sw[7:0], sw[7:0]}` |
| `0x1000_0008` | W | seven-segment display value (hex per nibble) |
| `0x1000_0010` | R | cycle counter |
| `0x1000_0014` | R | instructions retired |
| `0x1000_0018` | R | memory-wait counter |
| `0x1000_001C` | R | pipeline: load-use stalls / multi-cycle: trap |
| `0x1000_0020` | R | pipeline: branch/jump flushes |

BRAM (instructions + data) lives at `0x0000_0000`. When adding a peripheral,
keep both SoCs' decoders in sync and update this table + the memory in
`EGO1_RISCV_SOC_PLAN.md`.

## Suggested next work (not started)

Roughly in order of value for the course:

1. **Post-implementation resource + Fmax table** — quick win. From a built
   design: `report_utilization`, `report_timing_summary`. Tabulate LUT/FF/BRAM
   and the max clock for each core. Good for the report.
2. **UART TX/RX** — add a memory-mapped UART peripheral (pins `uart_tx=T4`,
   `uart_rx=N5` are already in `ego1_base.xdc` and the tops). Lets you `printf`
   from firmware. Add a `to_bcd`-style routine or reuse it for output.
3. **External async SRAM controller** (`IS61WV12816BLL`) — pins are in the
   manual (`scratchpad_manual.txt`, "SRAM"/`MEM_*`). Bigger data memory.
4. **Direct-mapped I-cache** in front of BRAM/SRAM — the plan's stretch goal.

For each: add RTL in `rtl/`, a testbench in `sim/` + a `modelsim_*.do`, wire it
into both SoCs, extend the memory map above, sim-verify, then build/program.

## Repo conventions

- **Source is committed; build artifacts are not.** `.gitignore` excludes
  `*.runs/`, `*.cache/`, `.Xil/`, ModelSim `work/`, `*.vcd`, `*.bit/.mcs/.prm`,
  logs, the manual PDF, and the vendored `picorv32/` (its own git).
- The prebuilt demo bitstreams (`demo_pipeline.bit`, `demo_multicycle.bit`) are
  therefore not in git — rebuild from `scripts/build_demo_*.tcl`. Force-add them
  only if you want to archive a known-good binary.
- Firmware `.hex` files use LF line endings; if you edit `asm.py`, keep the
  `newline='\n'` on the output file (Windows text mode otherwise writes CRLF).
```
