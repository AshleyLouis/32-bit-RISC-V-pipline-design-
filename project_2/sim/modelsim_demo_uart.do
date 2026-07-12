transcript on
if {[file exists work]} { catch {vdel -lib work -all} }
vlib work
vlog -work work +acc=rn rtl/rv32_alu.v rtl/rv32_regfile.v rtl/rv32_core_pipeline.v rtl/soc_bram_dual.v rtl/uart_rx.v rtl/uart_tx.v rtl/soc_uart.v rtl/soc_clint.v rtl/rv32_soc_pipeline.v sim/tb_rv32_demo_uart.v
vsim -voptargs=+acc work.tb_rv32_demo_uart
run -all
quit -f
