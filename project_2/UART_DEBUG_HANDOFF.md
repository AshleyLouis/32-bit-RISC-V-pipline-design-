# UART 真机验证 —— 调试接续文档（2026-07-12 收尾）

> 下次接着做时，**从本文的"下一步"开始**。中断硬件本身已在真板验证通过（LED 显示
> CAFE）；当前卡在 **PC 端串口验证 `tools/tests.py`**，10 项里目前只过 1~2 项。

---

## 1. 当前状态一句话

板子在跑合并固件 `demo_uart.hex`（dip_sw=6 进串口监控），串口物理链路通（能收到回应），
但 `tools/tests.py` 大部分 FAIL。**根因已定位为"启动横幅串位"（Bug 1），修复代码已写入
`tools/monitor.py` 但尚未验证。** ecall 报错(Bug 2)是否为真 bug 尚无独立证据。

---

## 2. 最近一次真机跑的结果（改 monitor.py 之前）

```
[PASS] ping                             PONG        (第一次跑; 第二次连 ping 都 FAIL)
[FAIL] memory read/write   ERROR: invalid literal for int() with base 16: 'RV32I OK'
[FAIL] LED MMIO            ERROR: ... 'RV32I OK'
[FAIL] switch read         ERROR: ... 'RV32I OK'
[FAIL] perf counters       ERROR: ... 'RV32I OK'
[FAIL] ecall (cause 11)    !TRAP c=00000002 e=FFFDFFE4     <- 期望 c=0000000b
[PASS] illegal (cause 2)   !TRAP c=00000002 e=FFFDFFE8
[FAIL] RX interrupt echo   TIMEOUT
[FAIL] timer interrupt     TIMEOUT
[FAIL] main loop resumes   TIMEOUT
```

命令：`python tools/tests.py --port COM9`（串口号 COM9，波特率 9600）。

---

## 3. 问题诊断

### Bug 1（主因，已定位）：启动横幅 `RV32I OK` 串位整个回应流
- 固件进监控时会打印普通行 `RV32I OK`。它进了 `sync_q`，排在 `PONG` 前面。
- `ping` 有时拿到 `RV32I OK`、有时拿到 `PONG`，之后每个命令的回应都错位一格 →
  `read` 拿到 `RV32I OK` → `int('RV32I OK',16)` 抛异常。
- **为什么会反复出现**：怀疑打开串口时 pyserial 默认翻转 DTR/RTS，触发板子复位 →
  重新 boot → 因 dip_sw 仍=6 又进监控 → 又打印横幅。所以 drain 一次清不掉。

### Bug 2（未证实）：ecall 报 cause=2 而非 11
- 期望 ecall → mcause=0xb；实测两次都 c=00000002（非法指令），且 `e=FFFDFFE4` 这个
  mepc 是**垃圾地址**（不在监控代码 0x2xx 区）。
- **推断（未证实）**：可能是 Bug 1 串位后，`W`/`R` 命令把垃圾写进/跳进坏地址，CPU 早已
  跑飞，等发 `E` 时状态已乱 → 那两条 `!TRAP` 其实是跑飞后的产物，不是 ecall 本身的问题。
- **反证**：`programs/irq_selftest.S` 在 **ModelSim 仿真**里 ecall 明确得到 mcause=0xb
  （同一个 `rv32_core_pipeline`），说明核对 ecall 的译码**在仿真里是对的**。
- **关键：这个推断没有独立证据。** 三次想跑"进监控→发E→看!TRAP"的定向仿真都因为
  ModelSim 读不到 `/tmp/tb_ecall.v`（git-bash 的 /tmp 和 ModelSim 的 /tmp 映射不一致）
  而**根本没跑起来**。所以 ecall 是不是真 bug，下次必须先用能跑的仿真坐实。

---

## 4. 已做的修改（都在 `tools/monitor.py`，尚未在真机验证）

1. `drain_all()` 方法：清空 sync_q + async_q（`tests.py` 启动时调用，替换原 `drain_async`）。
2. **`_reader` 里直接过滤掉横幅行**：`BANNER_LINES=("RV32I OK",)`，命中就 `continue` 不入队
   —— 不管横幅何时到达都丢弃，比 drain 更可靠（这是主修复）。
3. **打开串口不翻转 DTR/RTS**：改成 `serial.Serial()` 后设 `dtr=False/rts=False` 再 `open()`，
   避免连接时复位板子导致横幅反复出现。

> `tools/tests.py` 也改了一行：启动 `m.drain_all()`（原为 `m.drain_async()`）。

⚠️ 这三处改完**还没跑过** `python -c "import ast..."` 语法检查（用户在检查前中断了），
下次先确认 monitor.py 语法 OK 再上真机。

---

## 5. 下一步（下次从这里开始）

1. **先语法检查**：`cd tools && python -c "import ast; ast.parse(open('monitor.py').read())"`。
2. **真机重跑**（不用重烧板子，只改了 PC 端 Python；确认板子 dip_sw=6、Hardware Manager 关闭）：
   `python tools/tests.py --port COM9`
3. **看 ecall 那行**：
   - 若变成 `c=0000000b` → Bug 1 是唯一根因，大概率全绿，收工。
   - 若仍 `c=00000002` → Bug 2 是真 bug。**这时先修仿真环境**再查：
     把定向 testbench 放到 `sim/`（不要放 `/tmp`，ModelSim 路径映射会失败），
     用 `.do` 文件跑（`vsim -c -do sim/xxx.do`，本机唯一可靠的 vsim 调用方式）。
     定向 tb：dip_sw=6 进监控 → send 'E' → 抓 tx 上的 `!TRAP` 行看 cause。
4. RX/timer 中断的 TIMEOUT 大概率也是被 Bug 1 连累；Bug 1 修好后重看，若仍超时再单独查
   （硬件中断逻辑本身已在 `tb_rv32_uart.v` / `tb_rv32_irq_*.v` 仿真验证过）。

---

## 6. 环境备忘（避免重复踩坑）

- **ModelSim**：安装目录被改名为 `D:\Mentor_Graphics_ModelSim_SE-64_10.6e`（空格→下划线），
  `modelsim106e` 符号链接已重建。vsim/vlog 在 `<dir>/win64/`。
- **本机唯一可靠的跑仿真方式**：在 `project_2/` 下建局部 `work` 库并用 `.do` 文件：
  `vsim -c -do sim/<name>.do`（`-work /tmp/xxx` 方式会因 cwd 的 modelsim.ini 里
  `work→./work` 映射而报 "Failed to access library 'work'"）。测试文件必须放 `sim/`，
  **不能放 `/tmp`**（ModelSim 读不到 git-bash 的 /tmp）。
- **Python**：用 `python`（`python3` / `py` 启动器坏的，heredoc 会失败）。
- 跑 `tests.py` 前**必须关掉 Vivado Hardware Manager**（USB-UART 与 JTAG 共用 FTDI）。
- 波特率两核都 9600；`CLK_FREQ` 参数：流水线 50M、多周期 100M（硬件里已按核设好）。

## 7. 已确认没问题的部分（不用再查）

- 中断硬件本身：两核 ModelSim 全绿（`tb_rv32_irq_pipe/mc` CAFE），**流水线核真板 CAFE 已确认**。
- UART 收发链路：`tb_rv32_uart.v` 端到端仿真 4/4 PASS（含 RX 中断回显 `!RX41`）。
- 合并固件 `demo_uart.hex`：`tb_rv32_demo_uart.v` 仿真 PASS（mode0=CAFE + mode6 进监控 + ping）。
- 8+1 个 ModelSim 回归全绿。asm.py CSR/系统指令 + li-label + .word/.org 扩展，旧程序逐字节一致。

## 8. 相关文件索引

- 设计：`INTERRUPT_DESIGN.md` `UART_VERIFICATION_PLAN.md` `MODULE_OVERVIEW.md` `INTERRUPT_UART_README.md`
- 固件：`programs/demo_uart.S/.hex`（合并版，板上在跑）、`programs/monitor.S/.hex`、`programs/irq_selftest.S/.hex`
- PC 端：`tools/monitor.py`（本次改过）、`tools/tests.py`
- 仿真：`sim/tb_rv32_{irq_pipe,irq_mc,uart,demo_uart}.v` + 对应 `.do`
- RTL：`rtl/{soc_uart,soc_clint,uart_rx,uart_tx}.v` + 改过的核/SoC/top
- 构建：`scripts/build_pipeline_irq.tcl`（改 INIT_FILE 即可复用给 demo_uart）、`scripts/flash_ego1.tcl`
