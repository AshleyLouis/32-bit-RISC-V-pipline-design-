# 模块设计说明（RV32I CPU / SoC）

> 对本项目每个 RTL 模块做一个简明的职责说明。分三部分：**CPU 内核**、**SoC / 外设**、**FPGA 顶层**，
> 最后列出为中断 + UART 验证**计划新增**的模块。现有部分对应 `rtl/` 下已存在的文件。

---

## 一、CPU 内核

### `rv32_alu.v` — 算术逻辑单元
- 纯组合逻辑。输入 4 位 `op` + 两个 32 位操作数 `a/b`，输出 `y`。
- 支持 ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU 共 10 种运算；移位量取 `b[4:0]`，算术右移用 `$signed >>>`。
- 被多周期核和流水线核共用。

### `rv32_regfile.v` — 通用寄存器堆
- 32 × 32 位寄存器，1 写口 + 2 读口。
- 写在时钟上升沿（`we && waddr!=0`）；`x0` 恒 0（读 0、写忽略）。
- 复位时清零全部寄存器（便于仿真观察）。读口为组合读出。

### `rv32_core_multicycle.v` — 多周期核（基线，本次不改）
- 状态机 `FETCH→DECODE→EXEC→MEM→WB`（+ `TRAP`）。每条指令按状态多拍完成，一次只有一条指令在飞。
- 通过统一的 `mem_valid/ready/addr/wdata/wstrb/rdata` 总线访存；取指和数据访问都走这条总线。
- 实测 CPI≈5.28。撞到非法指令/非对齐访问进 `S_TRAP` 死锁（`trap` 拉高）。
- 指令边界干净，是加中断"最容易正确"的核；本项目作保底方案（详见 `INTERRUPT_DESIGN.md` §9）。

### `rv32_core_pipeline.v` — 五级流水线核（**中断实现的主目标**）
- 经典 IF/ID/EX/MEM/WB，用 `if_id_* / id_ex_* / ex_mem_* / mem_wb_*` 四组流水寄存器分隔。
- **取指/数据分离**：`instr_addr/instr_rdata` 走指令口，`mem_*` 走数据口（配合双口 BRAM）。
- **前递**：EX 级从 `ex_mem`、`mem_wb` 前递 rs1/rs2，消除大部分数据冒险。
- **load-use 冒险**：ID 级检测，冻结 `pc/if_id` 并插气泡（`stall_counter`）。
- **分支/跳转**：EX 级解析（`ex_branch_taken`），命中即重定向 `pc` 并冲刷 IF/ID、ID/EX 两级（`flush_counter`）。
- 实测 CPI≈1.19。当前非法指令一路到 WB 才置 `trap` 死锁——中断改造会把它升级成 ID 级精确异常 + 可恢复陷入（见 `INTERRUPT_DESIGN.md`）。

---

## 二、SoC / 外设

### `soc_bram.v` — 单口 BRAM（配多周期 SoC）
- `$readmemh(INIT_FILE)` 初始化的片上 RAM，取指和数据共用一个口。
- 简单 valid/ready 握手，字节写使能 `wstrb`。

### `soc_bram_dual.v` — 双口 BRAM（配流水线 SoC）
- 一个只读**指令口**（给流水线取指）+ 一个读写**数据口**，让 IF 与 MEM 同拍互不阻塞。
- 同样由 `INIT_FILE` 初始化。

### `soc_gpio.v` — 内存映射 GPIO（多周期 SoC 用）
- 寄存器：LED（RW）、开关 `{dip_sw,sw}`（R）、32 位数码管显示值（RW）。
- 内含七段译码 `hex_to_seg` + 8 位数码管**扫描分频**（`scan_div` 轮流点亮各位）。
- valid/ready 握手，读写在同一拍完成。

### `rv32_soc.v` — 多周期 SoC 顶层
- 例化多周期核 + `soc_bram` + `soc_gpio` + 性能计数器，做地址译码与读数据 mux。
- 地址译码：BRAM `0x0000_0000`、GPIO `0x1000_000x`、性能计数器 `0x1000_001x`；未映射地址返回 `0xbad0add0`。
- 性能计数器：cycle / instret / mem_wait / trap 状态。

### `rv32_soc_pipeline.v` — 流水线 SoC 顶层（**中断/UART 集成点**）
- 例化流水线核 + `soc_bram_dual`，GPIO 与七段扫描逻辑内联在本模块，含性能计数器（cycle/instret/mem_wait/stall/flush）。
- 性能计数器地址已从 `0x1000_0010` 起排布，**与 GPIO 不重叠**（曾因重叠导致计数器被 GPIO 影子，已修）。
- **本次改造**：新增 UART / 定时器(CLINT-lite) / IRQ 状态寄存器的地址译码（`0x1000_0030+`），并把 `irq_timer`/`irq_external` 接进 CPU。

---

## 三、FPGA 顶层

### `top_ego1.v` — 多周期核顶层
- 绑定板级引脚（时钟、复位按钮、拨码/开关、LED、数码管、UART 引脚）。
- `resetn = reset_btn`（该按钮**空闲高、按下低**，本身即低有效复位，**不取反**）。
- 当前 `uart_tx` 是 `1'b1` 占位、`uart_rx` 未用。

### `top_ego1_pipeline.v` — 流水线核顶层
- 同上引脚绑定；额外含 **÷2 时钟分频**：100 MHz 输入经 `clk_div2` + `BUFG` 得 **50 MHz `cpu_clk`** 驱动 SoC，
  用来化解流水线分支路径在 100 MHz 下的时序缺口（生成时钟由 `pipeline_50mhz.xdc` 约束）。
- **本次改造**：去掉 `uart_tx=1'b1` 占位，把 UART 引脚接到 SoC；注意 UART 在 `cpu_clk=50 MHz` 域，波特率分频常数按 50 MHz 传。

---

## 四、UART 收发子模块（现于 `project_3/`，将复用）

### `uart_rx.v` — UART 接收
- 状态机 IDLE→START→DATA→STOP；检测起始位下降沿，在每位**中点采样**，LSB first，收满一字节 `rx_done` 打一拍脉冲。
- 参数化 `CLK_FREQ/BAUD_RATE` 决定分频 `BIT_PERIOD`。

### `uart_tx.v` — UART 发送
- 状态机 IDLE→START→DATA→STOP；`tx_start` 触发，`tx_busy` 期间不接受新数据，LSB first 逐位移出，空闲线高。

### `uart_top.v` — 独立 echo 验证顶层
- 只把 RX 收到的字节缓冲后原样发回（带 `rx_pending` 缓冲，避免 TX 忙时丢字节）。用于最早的物理链路 bring-up，不含 CPU。

---

## 五、中断 + UART 验证模块（✅ 已实现并在 ModelSim 验证）

| 模块 | 职责 |
|---|---|
| **CSR 单元**（两个核内） | `mstatus(MIE/MPIE)/mie(MTIE/MEIE)/mtvec/mepc/mcause/mscratch/mip` 读写；`csrrw/csrrs/csrrc[i]`；`mret`/陷入序列。CSR 读用显式 `always @*` mux（不能用函数调用挂连续赋值）。 |
| **陷入控制逻辑**（核内） | 流水线：异步中断 IF/ID 注入、同步异常/mret 在 EX 复用 flush 路径。多周期：中断在 **S_DECODE** 注入。`trap` 改为"无 mtvec 时致命停机"。 |
| `soc_uart.v` | 包 `uart_rx/uart_tx` + TX 寄存器、RX `rx_valid` 锁存、状态/控制寄存器、`rx_ie/tx_ie`，输出 `irq`。组合读 + 寄存副作用。 |
| `soc_clint.v` | `mtime`/`mtimecmp` 定时器，`irq_timer=enable&&mtime>=mtimecmp`，写 mtimecmp 清挂起。 |
| `uart_rx.v` / `uart_tx.v` | 字节级收发（从 `project_3` 复制进 `rtl/`，项目自包含）。 |
| `programs/monitor.S` | 串口监控主循环 + RX/定时器/异常 ISR。字符串一字一字符存（CPU 无 `lbu`）。 |
| `programs/irq_selftest.S` | CSR/异常/中断自测，通过写 `0xCAFE`，两个核都过。 |
| `tools/monitor.py` / `tools/tests.py` | PC 端 pyserial 传输层 + 自动化验证套件。 |
| `sim/tb_rv32_irq_pipe.v` / `tb_rv32_irq_mc.v` / `tb_rv32_uart.v` | 中断自测（两核）+ UART 端到端仿真台。 |

> 相关文档：中断硬件设计 → `INTERRUPT_DESIGN.md`；PC 验证方案 → `UART_VERIFICATION_PLAN.md`。
