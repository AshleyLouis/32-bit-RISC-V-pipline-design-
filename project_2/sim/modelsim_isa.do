transcript on

if {[file exists work]} {
    catch {vdel -lib work -all}
}

vlib work

vlog -work work +acc=rn rtl/rv32_alu.v
vlog -work work +acc=rn rtl/rv32_regfile.v
vlog -work work +acc=rn rtl/rv32_core_multicycle.v
vlog -work work +acc=rn rtl/soc_bram.v
vlog -work work +acc=rn rtl/soc_gpio.v
vlog -work work +acc=rn rtl/uart_rx.v
vlog -work work +acc=rn rtl/uart_tx.v
vlog -work work +acc=rn rtl/soc_uart.v
vlog -work work +acc=rn rtl/soc_clint.v
vlog -work work +acc=rn rtl/rv32_soc.v
vlog -work work +acc=rn sim/tb_rv32_isa.v

vsim -voptargs=+acc work.tb_rv32_isa
run -all
quit -f
