# EGO1 RISC-V CPU/SoC Project Plan

## 1. Project Scope

Target board: EGO1, Xilinx Artix-7 XC7A35T-1CSG324C.

Goal: implement a self-written CPU using a RISC-V RV32I subset as reference, then integrate memory and memory-mapped I/O into a runnable FPGA system. PicoRV32 is used as an engineering reference for bus handshake, SoC memory map, UART style, and performance counters, not as a directly submitted CPU core.

Course target mapping:

| Level | Required result | Project implementation |
| --- | --- | --- |
| Basic | CPU supporting arithmetic, logic, memory access, branches/jumps, and test programs | RV32I-subset single-cycle or multi-cycle CPU |
| Advanced | CPU + memory subsystem + I/O, runnable small programs, bottleneck analysis | SoC with BRAM, optional external SRAM plan/cache, LEDs, switches, seven-segment/UART |
| Pipeline | Quantify clock frequency, CPI, throughput | 5-stage pipeline with counters for cycles, retired instructions, stalls |
| Extension | Deeper optimization | forwarding, load-use stall, branch flush, optional direct-mapped I-cache or MAC instruction |

## 2. Suggested ISA Subset

Start with a compact RV32I subset that can run hand-written assembly tests:

- R-type: `add`, `sub`, `and`, `or`, `xor`, `sll`, `srl`, `sra`, `slt`, `sltu`
- I-type ALU: `addi`, `andi`, `ori`, `xori`, `slti`, `sltiu`, `slli`, `srli`, `srai`
- Load/store: `lw`, `sw`; add `lb/lh/lbu/lhu/sb/sh` only after word access is stable
- Branch/jump: `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu`, `jal`, `jalr`
- Upper immediate: `lui`, `auipc`
- Optional debug: `ebreak`/illegal instruction trap flag

This subset is much easier to explain than a full RV32I implementation and still satisfies the course requirement for a RISC-V-referenced CPU.

## 3. CPU Architecture Roadmap

### Phase A: Multi-cycle CPU

Use a multi-cycle FSM first:

1. `FETCH`: read instruction from memory.
2. `DECODE`: decode opcode, read register file.
3. `EXECUTE`: ALU, branch decision, address calculation.
4. `MEMORY`: load/store transaction.
5. `WRITEBACK`: write destination register.

This version is easier to debug on FPGA and gives a correct baseline for CPI comparison.

### Phase B: 5-stage pipeline

After Phase A passes tests, split into:

- IF: program counter and instruction fetch
- ID: decode and register read
- EX: ALU, branch compare, target generation
- MEM: data memory/I/O access
- WB: register writeback

Required hazard handling:

- Register forwarding from EX/MEM and MEM/WB to EX.
- Load-use hazard stall for one cycle.
- Branch/jump flush after redirect.
- Optional static branch policy: always not taken.

## 4. SoC Bus And Memory Map

Use a simple valid/ready memory bus inspired by PicoRV32:

| Signal | Direction | Meaning |
| --- | --- | --- |
| `mem_valid` | CPU to bus | CPU requests memory/I/O access |
| `mem_ready` | bus to CPU | selected slave completed transaction |
| `mem_addr[31:0]` | CPU to bus | byte address |
| `mem_wdata[31:0]` | CPU to bus | write data |
| `mem_wstrb[3:0]` | CPU to bus | byte write enable; zero means read |
| `mem_rdata[31:0]` | bus to CPU | read data |

Recommended memory map:

| Address range | Device | Notes |
| --- | --- | --- |
| `0x0000_0000` - `0x0000_7fff` | BRAM instruction/data RAM | first runnable target |
| `0x1000_0000` | LED output | low 16 bits drive LEDs |
| `0x1000_0004` | switch input | low 16 bits read switches |
| `0x1000_0008` | seven-segment data | display debug value |
| `0x1000_000c` | UART data | optional serial TX/RX |
| `0x1000_0010` | performance cycle counter low | memory-mapped read |
| `0x1000_0014` | retired instruction counter low | memory-mapped read |
| `0x2000_0000` - | external SRAM | advanced memory backend |

## 5. Memory Subsystem Plan

Minimum advanced-layer plan:

- Use FPGA BRAM as low-latency instruction/data memory for the first complete system.
- Use a documented storage hierarchy: registers -> BRAM scratchpad -> external asynchronous SRAM.
- Add cycle counters and stall counters to quantify BRAM vs external SRAM latency.

Optional cache implementation:

- Direct-mapped I-cache or unified read cache.
- 16 or 32 cache lines, each line 16 bytes.
- Tag + valid + data arrays in BRAM.
- Miss path fetches from external SRAM through an SRAM controller.
- Replacement policy is trivial direct mapping, so hit rate analysis is easy to report.

## 6. EGO1 Board Resources

From `EGO1UserManualv210.120.pdf`:

- System clock: 100 MHz `SYS_CLK`, FPGA pin `P17`.
- FPGA: `XC7A35T-1CSG324C`.
- USB UART/JTAG:
  - `UART_RX` pin `T4`, described as FPGA serial transmit side.
  - `UART_TX` pin `N5`, described as FPGA serial receive side.
- LEDs are active high:
  - `LED0..LED15`: `F6 G4 G3 J4 H4 J3 J2 K2 K1 H6 H5 J5 K6 L1 M1 K3`.
- Switches:
  - `SW0..SW7`: `P5 P4 P3 P2 R2 M4 N4 R1`.
  - DIP switches: `U3 U2 V2 V5 V4 R3 T3 T5`.
- Seven-segment display is active high for both digit select and segment select.
- External SRAM: IS61WV12816BLL, 16-bit data bus, 19-bit address bus, async SRAM.

## 7. Verification Plan

Simulation tests:

1. Instruction unit tests: one small program per instruction group.
2. Register x0 test: writes to x0 must stay zero.
3. Branch/jump tests: taken, not taken, negative offset, `jalr`.
4. Load/store tests: aligned word access first.
5. I/O tests: write LED register, read switch register.
6. Pipeline tests: forwarding, load-use stall, branch flush.

FPGA tests:

1. Blink LED from software loop.
2. Mirror switches to LEDs by CPU program.
3. Show cycle/instruction counter or program state on seven-segment display.
4. Optional UART prints a short boot banner or hex counter.

## 8. Performance Evaluation

Measure these values for both baseline CPU and pipelined CPU:

- Vivado post-implementation maximum clock frequency.
- Total cycles: `mcycle` or memory-mapped cycle counter.
- Retired instructions: `minstret` or custom retire counter.
- CPI = cycles / retired instructions.
- Throughput = Fmax / CPI.
- Stall breakdown: load-use stalls, memory wait stalls, branch flushes.

Suggested report table:

| Design | Fmax | Program cycles | Retired instructions | CPI | Throughput | LUT/FF/BRAM |
| --- | --- | --- | --- | --- | --- | --- |
| Multi-cycle | TBD | TBD | TBD | TBD | TBD | TBD |
| 5-stage pipeline | TBD | TBD | TBD | TBD | TBD | TBD |
| Pipeline + cache/SRAM plan | TBD | TBD | TBD | TBD | TBD | TBD |

## 9. Division Of Work

Recommended roles:

- CPU datapath/control: decoder, ALU, register file, immediate generator, PC logic.
- Memory/I/O subsystem: BRAM, bus decoder, LED/switch/seven-segment/UART, SRAM controller.
- Verification: assembly tests, testbench, waveform review, regression checklist.
- FPGA integration/report: XDC, Vivado synthesis/implementation, performance and resource tables.

## 10. Immediate Next Steps

1. Create Verilog module skeletons: `rv32_core`, `regfile`, `alu`, `decoder`, `soc_bus`, `bram`, `gpio`, `top_ego1`.
2. Implement multi-cycle CPU and run simulation with a hand-coded instruction memory.
3. Add memory-mapped LED/switch registers and verify with testbench.
4. Add EGO1 XDC and synthesize the simplest LED-mirror program.
5. Convert CPU to 5-stage pipeline after the multi-cycle version is correct.
