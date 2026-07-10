set origin_dir [file normalize [file join [file dirname [info script]] ..]]

add_files -norecurse [list \
    [file join $origin_dir rtl rv32_alu.v] \
    [file join $origin_dir rtl rv32_regfile.v] \
    [file join $origin_dir rtl rv32_core_multicycle.v] \
    [file join $origin_dir rtl rv32_core_pipeline.v] \
    [file join $origin_dir rtl soc_bram.v] \
    [file join $origin_dir rtl soc_bram_dual.v] \
    [file join $origin_dir rtl soc_gpio.v] \
    [file join $origin_dir rtl rv32_soc.v] \
    [file join $origin_dir rtl rv32_soc_pipeline.v] \
    [file join $origin_dir rtl top_ego1.v] \
    [file join $origin_dir rtl top_ego1_pipeline.v] \
]

add_files -fileset constrs_1 -norecurse [file join $origin_dir ego1_base.xdc]
add_files -fileset sources_1 -norecurse [file join $origin_dir programs sw_led.hex]
add_files -fileset sources_1 -norecurse [file join $origin_dir programs isa_selftest.hex]
add_files -fileset sim_1 -norecurse [list \
    [file join $origin_dir sim tb_rv32_soc.v] \
    [file join $origin_dir sim tb_rv32_isa.v] \
    [file join $origin_dir sim tb_rv32_pipe_soc.v] \
    [file join $origin_dir sim tb_rv32_pipe_isa.v] \
]

set_property top top_ego1 [current_fileset]
set_property top tb_rv32_soc [get_filesets sim_1]
set_property file_type {Memory File} [get_files [file join $origin_dir programs sw_led.hex]]
set_property file_type {Memory File} [get_files [file join $origin_dir programs isa_selftest.hex]]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Added RV32 SoC baseline and pipelined sources to project_2."
