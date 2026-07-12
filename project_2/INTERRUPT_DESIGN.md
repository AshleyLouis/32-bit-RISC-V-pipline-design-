# 中断设计文档（RV32I 五级流水线核 + RISC-V M-mode 中断）

> 目标：给 `rv32_core_pipeline` / `rv32_soc_pipeline` 加一套**标准 RISC-V 机器模式（M-mode）中断/异常**机制，
> 用于配合 UART 和 PC 做功能验证。本文只讲**设计思路与要点**，不含实现代码。
>
> 关键决策（已确认）：
> - **架构**：标准 RISC-V M-mode CSR（`mstatus/mie/mip/mtvec/mepc/mcause` + `csrrw/csrrs/csrrc` + `mret` + `ecall/ebreak`）。
> - **目标核**：流水线核为主，多周期核作为保底也一并实现。
> - **UART/定时器**：做成 SoC 内的**内存映射外设**，与 CPU 同处 `cpu_clk`（50 MHz）时钟域。
>
> ---
>
> ## ✅ 实现状态（2026-07-12，已完成并在 ModelSim 验证通过）
>
> 本文最初是设计思路；下面是**已按此实现并验证**的结果。两个核都实现了中断，
> 都通过了 `programs/irq_selftest.S`（CSR 往返 + ecall + 非法指令 + 定时器中断精确恢复，
> 通过写 `0xCAFE`）。既有 ISA 回归不变（流水线 63 拍 / 多周期 280 拍）。
> 完整 UART↔固件链路也在 `sim/tb_rv32_uart.v` 里端到端验证通过（见 `UART_VERIFICATION_PLAN.md` 的实现状态）。
>
> **与本文原设计的两处实现差异（都是调试中发现的必要修正）：**
> 1. **多周期核的异步中断在 `S_DECODE` 注入，不是 `S_FETCH`**。原因：`soc_bram.v` 是**同步**读
>    （`rdata`/`ready` 都寄存器化）。在 `S_FETCH`（`mem_valid` 当拍为高）取中断，会让下一拍 `ready`
>    虚假为高、且 `rdata` 是旧值 → ISR 第一条指令取成垃圾 → 连锁非法指令死循环。`S_DECODE` 当拍
>    `mem_valid=0`，保证干净重取，且 `pc` 仍指向已取未执行的指令，`mepc=pc` 依旧精确。
> 2. **CSR 读用显式 `always @*` 组合 mux，不能用"函数调用挂在连续赋值上"**（`wire x = csr_read(addr)`）。
>    后者只在**实参**变化时才重算，不随函数体内部读的 `mscratch` 等寄存器变化；于是"先 csrw 再 csrr
>    同一个 CSR"（addr 不变）会读到旧值。两个核都改成显式 mux。这是通用 Verilog 陷阱。
>
> ---

---

## 1. 为什么"流水线核加中断"比多周期难，难在哪

多周期核每个时刻**只有一条指令在执行**，`S_WB → S_FETCH` 的边界就是天然、干净的中断点：保存 PC、跳向量、清使能，一步到位。

流水线核里同时有 **IF/ID/EX/MEM/WB 多达 3~4 条指令在飞**。要做**精确中断（precise interrupt）**必须保证：

1. **原子性**：所有比"中断点"**更老**的指令必须**全部正常完成**（写回寄存器/存储器）；
2. **无副作用**：中断点及**更年轻**的指令必须**全部被压掉（squash）**，不能留下任何状态改动；
3. **可恢复**：`mepc` 必须精确等于"下一条本该执行、但被打断的指令"的 PC，`mret` 回来能无缝续跑。

因此整套设计的重点，就是**在流水线里选一个干净的注入点**，并处理它与已有的 **branch flush、load-use stall** 之间的优先级关系。

---

## 2. 复用现有流水线结构

现有 `rv32_core_pipeline.v` 的关键事实（决定了注入点的选择）：

| 事项 | 现状 |
|---|---|
| 取指 | `pc` → `instr_addr`，`instr_rdata` 在时钟沿锁进 `if_id_instr` |
| 分支解析 | 在 **EX 级**（`ex_branch_taken`），命中时把 `pc` 重定向，并压掉 `if_id`、`id_ex` 两级（`flush_counter++`） |
| load-use 冒险 | 在 ID 检测，**冻结** `pc`/`if_id`、往 `id_ex` 插气泡（`stall_counter++`） |
| 寄存器写回 | 统一在 `mem_wb`（WB 级）写 regfile |
| 现有 trap | `mem_wb_illegal` 置 `trap<=1` 后**死锁停机**（`S_TRAP`），不可恢复 |

现有 `trap` 是"撞墙即停"，我们要把它升级成**可向量、可恢复**的异常/中断出口。

---

## 3. 新增的 CSR（最小 M-mode 子集）

只实现中断/异常必需的位，其余位读 0、写忽略（符合 WARL 语义）。

| CSR | 地址 | 用到的位 | 含义 |
|---|---|---|---|
| `mstatus` | `0x300` | `MIE`(bit3)、`MPIE`(bit7) | 全局中断使能 / 进中断前的旧使能备份 |
| `mie`     | `0x304` | `MTIE`(bit7)、`MEIE`(bit11) | 定时器 / 外部中断的分项使能 |
| `mip`     | `0x344` | `MTIP`(bit7)、`MEIP`(bit11) | 定时器 / 外部中断挂起（**硬件置位**，只读） |
| `mtvec`   | `0x305` | base[31:2]，mode=0（direct） | 陷入向量基址（所有 trap 都跳这里） |
| `mepc`    | `0x341` | [31:2] | 陷入时保存的返回 PC |
| `mcause`  | `0x342` | Interrupt(bit31) + code | 陷入原因（区分中断/异常及具体号） |
| `mscratch`| `0x340` | 32 位通用 | ISR 暂存（保存 sp/上下文用，可选但强烈建议） |

> **精简**：`mtval`、`medeleg/mideleg`、多特权级都**不做**（本项目只有 M-mode）。
> `mtvec` 只支持 **direct 模式**（所有 trap 都进同一入口，ISR 里靠 `mcause` 分派），不做 vectored 模式，省一块逻辑。

### CSR 读写通路
- CSR 读是组合逻辑（一个对 6~7 个 CSR 的 mux）。
- CSR 指令（`csrrw/csrrs/csrrc`）语义：`rd ← 旧CSR值`，`CSR ← f(旧值, rs1)`，**读改写要原子**。
- 实现上把 CSR 指令当作**在单一提交级（建议 MEM/提交点）完成读-改-写**，`rd` 走正常 WB 通路写回。CSR 值**不参与前递（forwarding）**——CSR 极少被连续依赖，且 ISR 里通常紧跟隔离，遇到相邻依赖用**流水线串行化（在 CSR 指令处 stall 一两拍）**兜底即可，逻辑简单且不影响正确性。

---

## 4. 中断/异常的统一陷入序列（trap entry）

无论异步中断还是同步异常，硬件进入 trap 时执行同一套动作（一拍内完成）：

```
mepc     ← 陷入点 PC          // 精确：被打断/出错的那条指令地址
mcause   ← {中断?1:0, 原因号}
mstatus.MPIE ← mstatus.MIE    // 备份旧的全局使能
mstatus.MIE  ← 0              // 关中断，防止 ISR 一进来就被再次打断
pc       ← mtvec             // 跳向量（direct 模式）
（把陷入点及更年轻的在飞指令全部 squash）
```

`mret` 执行时对称地恢复：

```
mstatus.MIE  ← mstatus.MPIE   // 恢复全局使能
mstatus.MPIE ← 1
pc           ← mepc          // 回到断点续跑
```

**`mcause` 编码**（本项目用到的）：

| 类型 | Interrupt 位 | code | 来源 |
|---|---|---|---|
| 机器定时器中断 | 1 | 7  | CLINT-lite（`mtime ≥ mtimecmp`）|
| 机器外部中断   | 1 | 11 | UART / 按键（经 SoC 外部中断线）|
| 非法指令       | 0 | 2  | 译码 `dec_illegal` |
| 访存地址未对齐 | 0 | 4/6 | load/store 非对齐（现有对齐检查升级）|
| 环境调用 ecall | 0 | 11 | `ecall`（M-mode）|
| 断点 ebreak    | 0 | 3  | `ebreak` |

> **合并旧 trap**：把现有 `mem_wb_illegal` 死锁路径改成"非法指令异常 → 跳 `mtvec`"。仍保留一个**致命 trap**兜底：若 `mtvec` 未初始化（=0）或发生 double-fault，则回到旧的"点亮 trap 停机"，方便硬件上一眼看出跑飞。

---

## 5. 精确中断的注入点与优先级（本设计的核心）

### 5.1 异步中断（timer / external）——在 IF/ID 边界注入

**触发条件**：`mstatus.MIE && (mip & mie) != 0`，且当前拍走的是**正常推进路径**（既不是 branch flush，也不是 load-use stall）。

**为什么选 IF/ID 边界**：正常推进那一拍里，`if_id` 中的指令正被译码并进入 `id_ex`（它会**完成**），而 `pc` 指向的、正被取进 `if_id` 的那条指令**尚未产生任何状态**。于是：

```
mepc ← pc                 // pc 指向"下一条本该执行"的指令 = 精确断点
if_id_valid ← 0           // 压掉刚取进来的这条（唯一需要 squash 的）
id_ex ← 来自 if_id（照常）  // 更老的指令继续完成，不动
pc ← mtvec
（其余 mstatus/mcause 按 §4）
```

比 EX 级分支 flush 更省——**只需压 1 级**（IF），因为更深的 ID/EX/MEM/WB 都是更老指令，让它们自然流干（drain）即可。

### 5.2 优先级规则（避免与已有控制冒险打架）

同一拍里可能同时有多个重定向诉求，固定优先级：

```
branch/jump flush (EX, 最老指令的效果)   ← 最高
   > load-use stall (ID)                 ← 冻结，本拍不取中断
      > 异步中断注入 (IF)                 ← 正常推进时才取
         > 顺序推进 pc+4                  ← 最低
```

- **分支命中那一拍不取中断**：让分支重定向赢。下一拍从分支目标取指时若中断仍挂起，则以 `mepc = 分支目标` 取中断——依旧精确。
- **load-use stall 那一拍不取中断**：`pc` 被冻结，等 stall 解除、进入正常推进拍再取。中断只是稍晚一两拍到达，语义完全正确。
- 因此中断**只在"正常推进 else 分支"里判断**，天然与现有两种冒险互斥，改动局部、易验证。

### 5.3 同步异常——在检测级就地转 trap

同步异常（非法指令 / ecall / ebreak / 非对齐）要求 `mepc = 出错指令自身的 PC`，且它本身**不能产生副作用**：

| 异常 | 检测级 | 处理 |
|---|---|---|
| 非法指令 / ecall / ebreak | **ID**（`dec_illegal`、`ecall/ebreak` 译码可判） | 在 ID/EX 边界转 trap：`mepc ← if_id_pc`，压掉该指令**及更年轻的 IF**（类似 branch flush 压两级），跳 `mtvec` |
| load/store 地址未对齐 | **EX**（地址算出后） | 在 EX 转 trap：`mepc ← id_ex_pc`，按 branch-flush 方式压 IF/ID/EX，跳 `mtvec` |

关键点：**在指令写回 regfile/存储器之前**就把它拦下并 squash，才能保证"无副作用 + 精确"。当前设计里非法指令一路飘到 WB 才置 trap，需要**把检测前移到 ID**（译码信息 ID 就有），这是相对现有 RTL 最实质的一处改动。

### 5.4 CSR 指令与中断的原子性

进 ISR 后 `MIE=0`，ISR 内部读写 CSR 时天然不会被异步中断打断。真正要防的是**主程序里的 CSR 指令**在提交前被异步中断：只要坚持"异步中断在 IF 注入、CSR 读改写在更深的提交级原子完成"，被注入中断时 CSR 指令要么还没进入提交级（会被当作断点后重新执行，`mepc` 指向它），要么已提交（不受影响）——不会出现半更新。

---

## 6. 中断源与 SoC 侧接线

CPU 新增两根输入：`irq_timer`、`irq_external`（来自 SoC），分别驱动 `mip.MTIP`、`mip.MEIP`。

### 6.1 CLINT-lite 定时器（`mtime` / `mtimecmp`）
- SoC 内一个 64/32 位 `mtime` 计数器（按 `cpu_clk` 或分频 tick 递增）+ `mtimecmp` 比较寄存器。
- `irq_timer = (mtime >= mtimecmp)`。写 `mtimecmp` 即清挂起（标准 CLINT 行为）。
- 内存映射（见 §7）。用途：周期性"心跳"中断，演示定时器中断 + 抢占。

### 6.2 外部中断（UART / 按键）——用极简"中断汇聚"代替完整 PLIC
- 不做完整 PLIC。SoC 里把 `uart_rx_valid & rx_ie`、`uart_tx_ready & tx_ie`、（可选）按键去抖沿 OR 成一根 `irq_external`。
- ISR 进来后读 **UART 状态寄存器 / IRQ 状态寄存器**判断到底是谁触发（RX 有字节？TX 空？），再分派。够用且省逻辑。

---

## 7. 内存映射扩展（在现有基础上追加，不改旧地址）

现有映射保持不变（BRAM `0x0000_0000`，LED/开关/数码管 `0x1000_000x`，性能计数器 `0x1000_0010~0020`）。新增：

| 地址 | 名称 | R/W | 说明 |
|---|---|---|---|
| `0x1000_0030` | UART_TX   | W: 写字节即启动发送；R bit0: `tx_busy` |
| `0x1000_0034` | UART_RX   | R: 读取收到的字节；**读即清** `rx_valid` |
| `0x1000_0038` | UART_STATUS | R: bit0=`rx_valid`, bit1=`tx_busy` |
| `0x1000_003C` | UART_CTRL | RW: bit0=`rx_ie`, bit1=`tx_ie`（中断使能）|
| `0x1000_0040` | MTIME     | R（低32位）|
| `0x1000_0044` | MTIMECMP  | RW（写即清定时器挂起）|
| `0x1000_0048` | TIMER_CTRL| RW: bit0=enable |
| `0x1000_0050` | IRQ_STATUS| R: 外部中断源快照（rx/tx/按键各一位），供 ISR 分派 |

> `rv32_soc_pipeline` 里需要新增对应的地址译码 select 与读 mux；注意别和 `perf_sel`（`0x1000_001x/002x`）重叠——这类重叠曾经踩过坑（GPIO 影子掉性能计数器），新块从 `0x30` 起就避开了。

---

## 8. 工具链（asm.py）需要补的东西

现有 `asm.py` 不支持 CSR/系统指令，要让 ISR 能手写汇编，需补：

- **系统/CSR 指令**：`csrrw`、`csrrs`、`csrrc`（+ 立即数版 `csrrwi/csrrsi/csrrci` 可选）、`ecall`、`ebreak`、`mret`。
- **CSR 名字别名**：`mstatus=0x300, mie=0x304, mtvec=0x305, mscratch=0x340, mepc=0x341, mcause=0x342, mip=0x344`。
- **伪指令**：`csrr rd,csr` = `csrrs rd,csr,x0`；`csrw csr,rs` = `csrrw x0,csr,rs`；`csrs/csrc` 同理。
- **（建议）数据/定位指令**：`.word`、`.org`/`.align`，方便放中断向量表和常量（当前只能纯代码顺序排布）。
- 改完照旧用"**重新汇编 `sw_led.S` / `isa_selftest.S` 逐字节 diff**"回归，确认没破坏已有编码。

---

## 9. 交付分解 & 保底方案

**推荐实现顺序（每步都能单独在 ModelSim 里验证）：**
1. 加 CSR 文件 + `csrrw/csrrs/csrrc/mret/ecall/ebreak` 译码执行（先不接中断），写一段汇编读写 CSR 自测。
2. 把"非法指令"从 WB 死锁改成 ID 级精确异常，跳 `mtvec`；`ecall` 走同一出口。用故意的非法指令/`ecall` 自测。
3. 加异步中断注入（§5.1/5.2）+ CLINT-lite 定时器，先用**定时器中断**验证（无需 UART，最容易在仿真里造激励）。
4. 接 UART 外部中断，做完整的 PC↔板子交互验证（见 `UART_VERIFICATION_PLAN.md`）。

**保底（多周期核，可选）**：如果流水线精确中断一时没调通、但演示在即，可临时在 `rv32_core_multicycle` 上做同样的 CSR+中断——它在 `S_WB→S_FETCH` 边界注入，**只有一条指令在飞，无需处理 squash/优先级**，半天即可跑通，作为"中断能用"的兜底演示。两个核共用同一套 ISR 汇编和同一 SoC 外设，切换成本低。本项目主线仍是流水线核。

---

## 10. 需要注意的坑（结合本项目历史）

- **时钟域**：流水线 SoC 跑在 `cpu_clk = 50 MHz`（top 里 ÷2）。UART 做成 SoC 内外设后与 CPU 同域，**波特率分频常数必须按 50 MHz 传参**（`CLK_FREQ=50_000_000`），否则实测波特率翻倍、PC 收到乱码。ModelSim 的 `tb_rv32_pipe_*` 直接驱动 `rv32_soc_pipeline`、不含 top 的 ÷2，仿真里也要保持同一 `CLK_FREQ` 约定。
- **复位极性**：任何读 `reset_btn` 的新逻辑沿用 `resetn = reset_btn`（不取反），别再从手册通用按键段推极性。
- **XDC**：UART 引脚已在 `ego1_base.xdc`（`uart_tx=T4`、`uart_rx=N5`，LVCMOS33），不用改约束；只需把 top 里 `assign uart_tx=1'b1;` 的占位去掉，接到 SoC 的真实 TX。
- **时序**：中断逻辑加在 EX→PC 关键路径附近可能进一步吃紧（现有分支路径 100 MHz 差 0.143 ns，已靠 50 MHz 化解）。注入逻辑尽量做在 IF 边界、用已有的重定向多路器，避免再加长关键路径。
