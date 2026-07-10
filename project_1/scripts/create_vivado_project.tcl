set origin_dir [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $origin_dir vivado_rv32_ego1]

create_project rv32_ego1 $proj_dir -part xc7a35tcsg324-1 -force

add_files -norecurse [list \
    [file join $origin_dir rtl rv32_alu.v] \
    [file join $origin_dir rtl rv32_regfile.v] \
    [file join $origin_dir rtl rv32_core_multicycle.v] \
    [file join $origin_dir rtl soc_bram.v] \
    [file join $origin_dir rtl soc_gpio.v] \
    [file join $origin_dir rtl rv32_soc.v] \
    [file join $origin_dir rtl top_ego1.v] \
]

add_files -fileset constrs_1 -norecurse [file join $origin_dir ego1_base.xdc]
add_files -fileset sources_1 -norecurse [file join $origin_dir programs sw_led.hex]
add_files -fileset sim_1 -norecurse [file join $origin_dir sim tb_rv32_soc.v]

set_property top top_ego1 [current_fileset]
set_property top tb_rv32_soc [get_filesets sim_1]
set_property file_type {Memory File} [get_files [file join $origin_dir programs sw_led.hex]]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Created Vivado project at $proj_dir"
