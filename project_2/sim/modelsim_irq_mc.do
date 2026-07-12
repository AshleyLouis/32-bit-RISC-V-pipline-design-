transcript on
if {[file exists work]} { catch {vdel -lib work -all} }
vlib work
vlog -work work +acc=rn rtl/rv32_alu.v rtl/rv32_regfile.v rtl/rv32_core_multicycle.v rtl/soc_bram.v rtl/soc_gpio.v rtl/uart_rx.v rtl/uart_tx.v rtl/soc_uart.v rtl/soc_clint.v rtl/rv32_soc.v sim/tb_rv32_irq_mc.v
vsim -voptargs=+acc work.tb_rv32_irq_mc
run -all
quit -f
