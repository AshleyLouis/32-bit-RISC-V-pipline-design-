# EGO1 Hardware Bring-Up — Status & Handoff

_Last updated: 2026-07-10 (pipeline timing closed at 50 MHz, board reprogrammed). Board: EGO1, Xilinx Artix-7 `xc7a35tcsg324-1` (speed grade −1). Vivado 2018.3 at `D:\Xilinx\Vivado\2018.3` (not on PATH — call by full path)._

This file is the running status of getting the RV32I CPU/SoC onto the physical
EGO1 board. Simulation status is in `README.md`; architecture/roadmap is in
`EGO1_RISCV_SOC_PLAN.md`.

---

## ✅ Completed (verified on the physical board)

| # | What | Bitstream / build | On-board result |
|---|------|-------------------|-----------------|
| 1 | **Multi-cycle CPU, ISA self-test** | `top_ego1` + `isa_selftest.hex` | LEDs + 7-seg show **`CAFE`** (PASS). Confirmed. |
| 2 | **Multi-cycle CPU, switch-mirror demo** | `top_ego1` + `sw_led.hex` (INIT_FILE overridden via synth generic) | LEDs / 7-seg mirror `{dip_sw, sw}` live. Confirmed. |
| 3 | **Pipelined CPU, ISA self-test** | `top_ego1_pipeline` + `isa_selftest.hex` | LEDs + 7-seg show **`CAFE`** (PASS) → forwarding, load-use stall, branch-flush logic all correct on silicon. Confirmed. |
| 4 | **Pipelined CPU @ 50 MHz, timing-closed, ISA self-test** | `top_ego1_pipeline` + `isa_selftest.hex`, ÷2 CPU clock, `Vivado Implementation Defaults` | Programmed 2026-07-10 17:28 build (`End of startup status: HIGH`, `PROGRAM_DONE`). Shows **`CAFE`** — confirmed by user (noted big-endian digit order is expected). |
| 5 | **Interactive 6-mode demo firmware** (both cores) | `demo_pipeline.bit` / `demo_multicycle.bit` + `programs/demo.hex` | Board programmed with `demo_pipeline.bit` 2026-07-10 (`PROGRAM_DONE`). `dip_sw[2:0]` pages through CAFE / live I/O / 5050 / cycles / instret / CPI. Sim-verified on both cores (pipe CPI 1.64 vs multi-cycle 5.01, same 305 instrs). See `DEMO_GUIDE.md`. |

Supporting fixes done this session:
- **Added 4 missing pipeline RTL files to the Vivado project.** `project_2.xpr`'s
  `sources_1` fileset previously held only the 7 multi-cycle files; the pipeline
  files (`rv32_core_pipeline.v`, `rv32_soc_pipeline.v`, `soc_bram_dual.v`,
  `top_ego1_pipeline.v`) were never added, which is why the pipeline top could not
  be built. They are now permanently in the project (`get_files` shows 11 `.v`).
- **Reusable TCL scripts** created in `scripts/` (see below).
- **`isa_selftest` pass/fail convention:** PASS writes `0xCAFE`, FAIL writes
  `0xDEAD`, to both LED (`0x1000_0000`) and 7-seg (`0x1000_0008`).

---

## ✅ Timing closure for the pipelined core — DONE (2026-07-10, via 50 MHz CPU clock)

The pipeline missed at 100 MHz (root cause architectural: branch-resolution path
`soc/cpu/id_ex_rs1_reg → soc/cpu/pc_reg`, 11 logic levels, ~77% route — P&R
sweeping could not fix it). Historical 100 MHz numbers, for reference:

| Build (100 MHz) | WNS (setup) | TNS | Failing eps | Hold (WHS) | Met? |
|-----------------|-------------|-----|-------------|------------|------|
| Vivado defaults | −0.143 ns | −3.472 ns | 41 | +0.042 ns | ❌ |
| `Performance_Explore` | −0.199 ns | −1.809 ns | 25 | +0.058 ns | ❌ |

**Fix applied: CPU clock halved to 50 MHz via a fabric ÷2 divider.** Now closes
cleanly with **Vivado Implementation Defaults** (no strategy tricks):

| Clock | Freq | Period | Setup WNS | Hold WHS | Failing eps |
|-------|------|--------|-----------|----------|-------------|
| `sys_clk` | 100 MHz | 10 ns | **+8.892 ns** | +0.280 ns | 0 |
| `cpu_clk` (÷2) | 50 MHz | 20 ns | **+5.619 ns** | +0.030 ns | 0 |

Overall WNS +5.619, WHS +0.030, **TNS 0.000** (zero violations). CPU hold is thin
(+0.030 ns) but positive. Throughput is unaffected — the self-test is nowhere near
clock-bound.

**Edits that landed (all applied):**
1. `rtl/top_ego1_pipeline.v`: `(* keep *)` ÷2 toggle flop `clk_div2` on `clk` →
   `BUFG cpu_clk_bufg` → `cpu_clk`; `rv32_soc_pipeline` is clocked by `cpu_clk`.
   Divider lives only in this FPGA top, so the `tb_rv32_pipe_*` ModelSim benches
   (which drive `rv32_soc_pipeline` directly) are unaffected.
2. `pipeline_50mhz.xdc` (NEW, separate constraint file):
   `create_generated_clock -name cpu_clk -source [get_ports clk] -divide_by 2 [get_pins cpu_clk_bufg/O]`
   — **unguarded on purpose.** Kept `is_enabled false` by default; the pipeline
   build script flips it `true`. `ego1_base.xdc` only carries a pointer note now.
3. `scripts/build_pipeline_50mhz.tcl`: enables `pipeline_50mhz.xdc`, resets impl
   strategy to defaults, builds, reports per-clock WNS/WHS, then disables the file
   and restores multi-cycle defaults.

⚠️ **Gotcha that cost a rebuild (do not repeat):** the first attempt put the
generated clock in the *shared* `ego1_base.xdc` wrapped in
`if {[llength [get_pins -quiet cpu_clk_bufg/O]]}`. That guard is **pure Tcl that
runs at XDC-read time during synthesis, before the netlist exists** → returns
empty → clock silently never created → the whole CPU domain built
**UNCONSTRAINED** (timing report showed only `sys_clk`, 1 endpoint; a fake
+8.66 ns WNS). Diagnosed with `scripts/diag_cpuclk.tcl` (opens the routed design,
finds `cpu_clk_bufg/O` exists, manually creates the clock → true unconstrained
slack was −49.99 ns). **Rule: never gate a `create_generated_clock` on a
`get_pins`/`get_cells` query in a shared XDC — use a separate, unconditional,
build-`is_enabled` file so Vivado can defer evaluation to when the netlist exists.**

## ⏳ Longer-term stretch items (from `EGO1_RISCV_SOC_PLAN.md`, not started)
External async SRAM controller (`IS61WV12816BLL`); optional direct-mapped I-cache;
UART TX/RX bring-up; post-implementation Fmax + LUT/FF/BRAM resource table.

---

## Current repository / project state (as left for next task)

- **The 6-mode demo is written to SPI flash (N25Q32); auto-boot CONFIRMED on
  hardware** (as of 2026-07-10 ~19:04, `demo_pipeline.bit`, pipeline core).
  Survives PROG / power-cycle — no laptop needed for the demo. `demo_multicycle.bit`
  also built.
  Flash flow: `scripts/flash_ego1.tcl` (write_cfgmem → `.mcs` → `program_hw_cfgmem`).
  For volatile JTAG loads (e.g. to switch cores quickly) use `program_ego1.tcl`.
- **`pipeline_50mhz.xdc` is now permanently registered** in `constrs_1`
  (`is_enabled false` by default). Pipeline/demo build scripts just flip it to
  `true`; no more per-build `add_files`.
- `project_2.xpr` restored to documented defaults: **top = `top_ego1`**,
  no generic override, `source_mgmt_mode = All`, 11 Verilog sources,
  `impl_1` strategy reset to **Vivado Implementation Defaults**,
  `pipeline_50mhz.xdc` present in `constrs_1` but **`is_enabled false`** (so a
  default multi-cycle build is unaffected).
- **RTL: the 50 MHz divider IS now applied** in `rtl/top_ego1_pipeline.v`.

## Reusable scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| `detect_hw.tcl` | Read-only JTAG probe; prints `DETECTED_DEVICE:` / `PART:`. Board enumerates as `xc7a35t_0`. |
| `program_ego1.tcl` | Program a `.bit` over JTAG. Pass the bit path with **`-tclargs <path>`** (defaults to `impl_1/top_ego1.bit`). Success prints `End of startup status: HIGH` + `PROGRAM_DONE:`. |
| `build_sw_led.tcl` | Rebuild multi-cycle `top_ego1` with `sw_led.hex` via INIT_FILE synth generic. |
| `build_pipeline_isa.tcl` | Build `top_ego1_pipeline` + `isa_selftest.hex` at 100 MHz (no divider; does NOT meet timing). Superseded by `build_pipeline_50mhz.tcl`. |
| `build_pipeline_50mhz.tcl` | **Preferred pipeline build.** Enables `pipeline_50mhz.xdc`, resets impl strategy to defaults, builds `top_ego1_pipeline` + `isa_selftest.hex` at 50 MHz CPU clock, reports per-clock WNS/WHS, then disables the XDC + restores multi-cycle defaults. |
| `close_timing_pipeline.tcl` | Re-run pipeline impl with `Performance_Explore` and report post-route WNS/WHS. (Historical — 50 MHz closes on defaults now.) |
| `diag_cpuclk.tcl` | Open routed `impl_1`, list clocks, find `cpu_clk_bufg`, manually create the ÷2 generated clock and report true CPU-domain setup/hold. Use to check whether `cpu_clk` actually applied. |
| `diag.tcl` | Dump `source_mgmt_mode`, fileset top, per-file `used_in_synthesis`, and `find_top`. |
| `build_demo_both.tcl` | Build multi-cycle demo (`demo_multicycle.bit`) then pipeline demo, both with `demo.hex`. |
| `build_demo_pipeline.tcl` | Build only the pipeline demo (`demo_pipeline.bit`). |
| `persist_state.tcl` | Restore clean default project state; permanently register `pipeline_50mhz.xdc` (disabled). |

⚠️ **Demo build scripts have a false-negative STATUS check:** after `wait_on_run
impl_1`, `get_property STATUS`/`PROGRESS` can return a stale
`"Running Design Initialization..."` even though the bitstream wrote fine
(`write_bitstream completed successfully` in the log). The script then prints
`PIPE_FAILED` and skips the `.bit` copy. If this happens, the bit really is in
`project_2.runs/impl_1/` — just `cp` it out and check
`*_timing_summary_routed.rpt`. (Grep the log for `write_bitstream completed`.)

## Firmware toolchain (`programs/`)

- **`asm.py`** — minimal two-pass RV32I assembler (Python 3). `python asm.py in.S out.hex`.
  Validated: reproduces `sw_led.hex` and `isa_selftest.hex` byte-for-byte.
- **`demo.S` / `demo.hex`** — the interactive demo firmware (85 instrs).
- Sim: `sim/modelsim_demo.do` + `sim/tb_rv32_demo.v` run demo.hex on BOTH cores
  and print CPI. `vsim` lives at
  `/d/Mentor_Graphics_ModelSim_SE-64_10.6e/win64/vsim.exe` (the `modelsim106e`
  symlink at the repo root is broken).

Typical program command (from `project_2/`):
```bash
/d/Xilinx/Vivado/2018.3/bin/vivado.bat -mode batch -notrace \
  -source scripts/program_ego1.tcl -tclargs D:/vivado_project/project_2/project_2.runs/impl_1/top_ego1_pipeline.bit
```

## Vivado gotchas learned this session (save the next person hours)

- **Conditional XDC on netlist objects silently no-ops.** A
  `create_generated_clock`/etc. wrapped in `if {[llength [get_pins ...]]}` inside a
  shared XDC evaluates at XDC-**read** time (synthesis start), before the netlist
  exists → the query is empty → the constraint is skipped and the domain builds
  UNCONSTRAINED. Symptom: only `sys_clk` in the timing report, tiny endpoint count,
  fake-huge WNS. Fix: put such constraints in a **separate, unconditional** XDC and
  toggle `is_enabled` per build so Vivado defers evaluation to netlist time.
- **"module not found" → check the fileset first.** Before touching
  `source_mgmt_mode`, confirm the module's file is actually in `sources_1`
  (`get_files -of [current_fileset] *.v`; `find_top`). The real bug was a missing
  file, not a mode issue.
- **Two top wrappers in one project:** with both `top_ego1` and
  `top_ego1_pipeline` as roots, `source_mgmt_mode All` auto-reselects `top_ego1`
  and ignores an explicit top override; `None` freezes a stale compile order that
  drops files; **`DisplayOnly`** (auto hierarchy update + manual top) is the
  correct mode to force a specific top.
- **`launch_runs impl_1 -to_step write_bitstream` can race `synth_1`** and stall at
  `Scripts Generated` / 0%. Launch and `wait_on_run synth_1` first, then impl.
- **Bare non-project `synth_design` batch flow** failed here with a misleading
  `couldn't read .../retarget/retarget_vhdl.tcl: No error` (the file exists — red
  herring). The **project run flow is the reliable path** on this machine.
- **`FPGA_RESET` (P15) is idle-HIGH / pressed-LOW** — treat `reset_btn` directly as
  active-low `resetn` (no inversion); XDC has `PULLUP true`. (See project memory.)
