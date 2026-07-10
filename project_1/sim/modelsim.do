transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work

vlog -work work +acc=rn rtl/rv32_alu.v
vlog -work work +acc=rn rtl/rv32_regfile.v
vlog -work work +acc=rn rtl/rv32_core_multicycle.v
vlog -work work +acc=rn rtl/soc_bram.v
vlog -work work +acc=rn rtl/soc_gpio.v
vlog -work work +acc=rn rtl/rv32_soc.v
vlog -work work +acc=rn sim/tb_rv32_soc.v

vsim -voptargs=+acc work.tb_rv32_soc
run -all
quit -f
