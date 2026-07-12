# UART ↔ PC 验证方案（思路）

> 目标：把 UART 做成 SoC 内存映射外设，通过 EGO1 板载 USB-UART 口连到 PC；
> 在 CPU 上跑一个"串口监控固件（serial monitor）"，PC 端用 Python 脚本发命令、收回应，
> **自动化验证 CPU 的各项功能，尤其是新加的中断**。本文只讲思路与验证清单，不含代码。

> ## ✅ 实现状态（2026-07-12）
>
> 已实现并在 ModelSim 端到端验证通过（`sim/tb_rv32_uart.v`：真实串口波形驱动 → 固件解析 → 访存 → 中断回显）：
> - **固件** `programs/monitor.S`：命令主循环（P/R/W/C/T/E/Z/I）+ RX/定时器/异常 ISR，`mtvec` direct 模式。
>   注意：CPU 只实现字加载（无 `lbu`），所以固件里的字符串是**一字一字符**存储、`puts` 按字读。
> - **外设** `rtl/soc_uart.v`（包 `uart_rx/uart_tx`，组合读、寄存副作用）、`rtl/soc_clint.v`（`mtime/mtimecmp` 定时器）。
> - **PC 端** `tools/monitor.py`（pyserial 传输层，`!` 异步行单独入队）+ `tools/tests.py`（带超时的验证套件）。
>   跑真机前先 `pip install pyserial`，并**关掉 Vivado Hardware Manager**（USB-UART 与 JTAG 共用 FTDI）。
> - 仿真复现：`vsim -c -do sim/modelsim_uart.do`。已验证：boot 横幅、ping→PONG、W/R 内存往返(DEADBEEF)、
>   RX 中断回显(`!RX41`) 全部 PASS。
>
> 下面是完整的设计思路与验证清单（PC 真机验证仍待用户在板子上跑 `tools/tests.py`）。

---

## 1. 硬件/时钟前提

- 板载 USB-UART 走 FTDI，和 JTAG 复用同一 USB 口；PC 上是一个虚拟 COM。
- 引脚已在 `ego1_base.xdc`：`uart_tx = T4`、`uart_rx = N5`，LVCMOS33。**约束不用改**。
- UART 作为 SoC 外设，与 CPU 同处 **`cpu_clk = 50 MHz`** 域 → 波特率分频常数按 **50 MHz** 传参。
  - 起步波特率 **9600**（现有模块默认值，最稳）；链路稳定后可提到 115200 以加快批量测试。
- 现有 `project_3/uart_rx.v`、`uart_tx.v` 可直接复用为收发子模块，外面包一层 `soc_uart.v`
  （加 TX 数据寄存器 / RX 缓冲 + `rx_valid` 锁存 / 状态 / 控制 / 中断线），挂到 §7 的地址上。

---

## 2. 两种验证形态，都要有

1. **交互式手动**：PC 上用 PuTTY/`screen`/`miniterm` 直接敲，人肉看回显。用于 bring-up 和演示。
2. **自动化脚本**（主力）：Python + `pyserial` 写一个测试运行器，逐项跑、每项带**超时**（防 CPU 跑飞挂死），最后打印 PASS/FAIL 汇总表。

协议设计成**纯 ASCII 行式**，两种形态共用一套。

---

## 3. 串口监控协议（简单、可人读、可脚本）

固件在 CPU 上跑一个主循环：从 UART 读命令行 → 执行 → 回一行结果。命令 = 单字母 + 十六进制参数，`\n` 结尾。

| 命令 | 含义 | 回应 |
|---|---|---|
| `P`            | ping / 存活检测 | `PONG` |
| `R aaaaaaaa`   | 读一个字（addr 8 hex）| `=dddddddd` |
| `W aaaaaaaa dddddddd` | 写一个字 | `OK` |
| `C n`          | 读第 n 个性能计数器 | `=dddddddd` |
| `X aaaaaaaa`   | 从 addr 处调用/跳转执行一段子程序，回结果 | `=dddddddd` |
| `E`            | 触发一次 `ecall`（测同步异常）| `!TRAP cause=... epc=...` |
| `Z`            | 触发一条非法指令（测异常）| `!TRAP cause=2 epc=...` |
| `I e/d rx`     | 使能/禁用 UART RX 中断 | `OK` |
| `I e/d tmr N`  | 设定时器，N 拍后中断，使能定时器中断 | `OK` |

**约定**：ISR（中断服务程序）产生的**异步输出**一律以 `!` 前缀开头（如 `!RX41`、`!TICK`、`!TRAP...`），
命令的同步回应不带 `!`。这样 PC 脚本能明确区分"我问的答复"和"中断自己冒出来的消息"，是验证中断的关键抓手。

---

## 4. 要验证什么（完整清单）

### A. 链路与基础（先跑通这些，才谈中断）
1. **物理链路 / 波特率 / 8N1 framing**：先用 `project_3` 现成 echo（PC 发 → 原样收回）。确认 COM 号、波特率、TX/RX 极性对。
2. **CPU 启动横幅**：复位后固件打印 `RV32I OK\n`，PC 收到即证明 CPU 取指、跑到了 main、UART 通路正常。
3. **ping**：`P → PONG`，证明命令解析主循环活着。

### B. 数据通路 / 总线 / 存储器
4. **内存读写完整性（peek/poke）**：`W`/`R` 对一批 BRAM 地址写入再读回，PC 对比数据。覆盖 load/store、字节使能、总线握手 `mem_ready`。
5. **MMIO 外设**：`W` LED 寄存器 → 肉眼/回读确认；`R` 开关寄存器，PC 提示手拨开关再读，值对上 → 证明 GPIO 与地址译码正确。
6. **数据流冒险/前递**：`X` 调用一段小程序（如 `sum(1..100)=5050`、阶乘、斐波那契），PC 用自己算的结果比对 → 覆盖 ALU、分支、load-use stall + forwarding。

### C. ISA 正确性
7. **ISA 自测经 UART 输出**：把现有 `isa_selftest` 的结果（0xCAFE 通过 / 0xDEAD 失败）除了点 LED/数码管，再以 ASCII 打印出来；PC 断言收到 `CAFE`。等于把已验证过的自测搬到可脚本判定。

### D. 性能计数器（承接现有 demo）
8. **CPI 测量**：`C` 命令读 cycle / instret，PC 计算 CPI；跑一段基准，验证流水线 CPI≈1.2 量级。可与多周期核结果并列展示 ~3× 加速。

### E. 中断（本次新增的重头戏）
9. **UART RX 中断（抢占 + 恢复）**：
   - 让 CPU 主循环持续做一件可观测的事（如不断自增一个计数器、隔一会儿打印 `MAIN=nnnn`）。
   - PC 随时发一个字节 → **RX 中断必须抢占主循环**，ISR 把该字节做个可辨识变换后回传（如 +1 / 转大写 / ROT13），前缀 `!RX`。
   - **判定点**：(a) 变换后的字节确实回来了（ISR 跑了）；(b) `MAIN=nnnn` 计数**在中断前后连续不断裂**（证明 `mepc`/上下文保存正确、`mret` 回到断点续跑）。
10. **定时器中断（周期心跳）**：设 `mtimecmp`，ISR 每次递增 tick、每 N 次打印 `!TICK=k`。PC 验证心跳**按预期节奏**到达，且主循环仍在推进 → 证明定时器中断 + 抢占。
11. **使能/禁用 + 挂起语义**：`I d rx` 禁用 RX 中断 → PC 发字节，应**不立即回显**（`mip.MEIP` 挂起但不被响应）；随后 `I e rx` 重新使能 → 之前挂起的字节被处理回来。验证 `mie/mip/mstatus.MIE` 语义。
12. **中断屏蔽期不丢事件**：进 ISR 后 `MIE=0`；在 ISR 执行期间让另一个源（定时器）触发 → 它应**挂起等待**，`mret` 后再被响应，不丢失、不乱序。
13. **同步异常路径**：`Z`（非法指令）/`E`（ecall）→ CPU 精确陷入 `mtvec`，ISR 打印 `mcause`/`mepc`，然后按策略返回或优雅停机。验证异常与中断共用出口、`mcause` 编码正确、`mepc` = 出错指令自身 PC。
14. **（进阶）嵌套/优先级**：若实现了在 ISR 内重新开中断，制造"RX 中断中再来定时器中断"，验证处理次序与栈式保存/恢复。

### F. 鲁棒性
15. **超时/跑飞检测**：每条命令 PC 侧设超时；若 CPU 挂死（进了致命 trap），PC 判 FAIL 并可读 `0x1000_001c` trap 状态旁证。
16. **长时间回环压力**：连续发上万字节做 echo/变换，统计误码，验证 UART 在真实时钟域长期稳定。

---

## 5. PC 端工具

- **语言**：Python 3 + `pyserial`。
- **结构**：
  - `monitor.py`：底层——开串口（COMx, 9600/115200, 8N1）、`send_line()` / `read_line(timeout)`、区分 `!` 异步行（丢进一个队列供中断测试断言）。
  - `tests.py`：每个验证项一个函数，返回 (name, pass/fail, 详情)；`run_all()` 打印汇总表。
  - `repl.py`（可选）：透传交互模式，等价于自带的迷你终端，方便手动调试。
- **注意**：USB-UART 与 JTAG 复用同一 FTDI；**用 Vivado 烧写/连 hw_server 时可能占用串口**，跑串口测试前先关掉 Hardware Manager 或断开 hw_target。

---

## 6. 与仿真的关系（先仿真，后上板）

- 上板前先在 ModelSim 里验证：写一个 testbench 直接驱动 `rv32_soc_pipeline` 的 `uart_rx` 引脚（按位造 9600/50MHz 的串行波形），断言 `uart_tx` 上发出的字节。中断激励在仿真里最好造（定时器中断尤其），能把 §4-E 的大部分场景先在波形里跑通。
- 仿真通过后再上板，把"仿真能过、板子没反应"的调试面缩到最小（沿用历史上的 bisection 方法）。

---

## 7. 需要新增/改动的 RTL（清单，供后续实现）

1. `soc_uart.v`：包 `uart_rx`/`uart_tx` + TX 寄存器、RX `rx_valid` 锁存、状态/控制寄存器、`rx_ie/tx_ie`，输出 `irq` 汇入外部中断线。
2. `soc_clint.v`（或并进 SoC）：`mtime`/`mtimecmp` + `irq_timer`。
3. `rv32_soc_pipeline.v`：新增 `0x1000_0030+` 地址译码与读 mux；把 `irq_timer`/`irq_external` 接到 CPU。
4. `top_ego1_pipeline.v`：去掉 `assign uart_tx=1'b1;` 占位，把 `uart_tx/uart_rx` 接到 SoC。
5. 固件 `programs/monitor.S`（+ ISR）：主循环命令解析 + RX/定时器 ISR；依赖 §INTERRUPT_DESIGN 的 asm.py 扩展。
6. `sim/tb_rv32_uart.v` + `.do`：串口波形激励 + 中断激励的 testbench。

> 详细的中断硬件设计见 `INTERRUPT_DESIGN.md`；各模块职责见 `MODULE_OVERVIEW.md`。
