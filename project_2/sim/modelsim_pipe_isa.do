transcript on

if {[file exists work]} {
    catch {vdel -lib work -all}
}

vlib work

vlog -work work +acc=rn rtl/rv32_alu.v
vlog -work work +acc=rn rtl/rv32_regfile.v
vlog -work work +acc=rn rtl/rv32_core_pipeline.v
vlog -work work +acc=rn rtl/soc_bram_dual.v
vlog -work work +acc=rn rtl/rv32_soc_pipeline.v
vlog -work work +acc=rn sim/tb_rv32_pipe_isa.v

vsim -voptargs=+acc work.tb_rv32_pipe_isa
run -all
quit -f
