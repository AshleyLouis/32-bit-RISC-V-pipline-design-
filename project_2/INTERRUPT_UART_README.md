# 中断 + UART 验证：怎么用（速查）

这是把中断功能和 UART↔PC 验证**跑起来**的操作清单。设计细节见 `INTERRUPT_DESIGN.md` /
`UART_VERIFICATION_PLAN.md` / `MODULE_OVERVIEW.md`。所有仿真已在 ModelSim 通过。

## 1. 仿真（已全部 PASS，随时可复现）

从 `project_2/` 运行（把 ModelSim 的 `win64` 加进 PATH）：

```bash
export PATH="/d/Mentor_Graphics_ModelSim_SE-64_10.6e/win64:$PATH"
vsim -c -do sim/modelsim_irq_pipe.do   # 流水线核：CSR/ecall/非法/定时器中断自测 -> CAFE
vsim -c -do sim/modelsim_irq_mc.do     # 多周期核：同一自测 -> CAFE
vsim -c -do sim/modelsim_uart.do       # UART 端到端：横幅/ping/内存往返/RX中断回显
```

回归（确认没破坏旧功能，也都 PASS）：`modelsim.do` `modelsim_isa.do`
`modelsim_pipe_soc.do` `modelsim_pipe_isa.do` `modelsim_demo.do`。

## 2. 重新汇编固件（改了 .S 之后）

```bash
cd programs
python asm.py monitor.S monitor.hex
python asm.py irq_selftest.S irq_selftest.hex
```

## 3. 上板（需要你在这台机器上跑 Vivado + 板子）

1. **把新源文件加进工程**（否则综合会报 `module 'soc_uart' not found`）：
   Vivado Tcl 里 `source scripts/add_irq_uart_sources.tcl`。
2. 用 `INIT_FILE=programs/monitor.hex` 构建 `top_ego1_pipeline`（50 MHz，推荐）
   或 `top_ego1`（多周期，100 MHz）。沿用现有构建脚本，只改 INIT_FILE 泛型。
3. 烧写（JTAG 易失：`scripts/program_ego1.tcl`；或 SPI flash 持久：`scripts/flash_ego1.tcl`）。

## 4. PC 端验证

```bash
pip install pyserial
python tools/tests.py --port COM5     # 换成你的串口号；波特率默认 9600
```

**务必先关掉 Vivado Hardware Manager**（板载 USB-UART 和 JTAG 共用同一 FTDI，
Hardware Manager 占着串口时 tests.py 打不开端口）。

`tests.py` 会逐项打印 PASS/FAIL：ping、内存读写、LED/开关 MMIO、性能计数器、
ecall/非法指令异常、UART RX 中断回显、定时器中断心跳、中断后主循环精确恢复。

单条命令调试可用：`python tools/monitor.py --port COM5 ping`（或 `read 0x10000010` 等）。

## 波特率提醒（不是"调到 50 MHz"）

波特率两个核都是 **9600**。50 MHz vs 100 MHz 是各自 SoC 的**时钟频率**，作为 UART 的
`CLK_FREQ` 参数传入（流水线 50M、多周期 100M），硬件里已按核设好；PC 端永远开 9600。
`CLK_FREQ` 传错会让实测波特率翻倍/减半 → PC 收乱码。
