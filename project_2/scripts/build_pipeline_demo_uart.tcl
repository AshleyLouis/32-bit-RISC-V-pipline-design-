# Build the 5-stage PIPELINED core (top_ego1_pipeline @ 50 MHz) running the
# interrupt self-test (programs/irq_selftest.hex): board shows CAFE on LEDs +
# seven-seg if CSR/exception/timer-interrupt logic all work on real silicon.
#
# Same mechanics as build_pipeline_50mhz.tcl (see its header for the XDC /
# two-top / DisplayOnly notes); only INIT_FILE differs and the .bit is copied
# out to top_ego1_pipeline_irq.bit for flashing.
open_project D:/vivado_project/project_2/project_2.xpr
set root D:/vivado_project/project_2

set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]

# register + ENABLE the pipeline-only generated-clock constraint
set pll_xdc $root/pipeline_50mhz.xdc
if {[lsearch -exact [get_files -quiet -of [get_filesets constrs_1]] $pll_xdc] < 0 &&
    [llength [get_files -quiet pipeline_50mhz.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $pll_xdc
}
set_property is_enabled true [get_files pipeline_50mhz.xdc]
puts "CPUCLK_XDC_ENABLED: [get_property is_enabled [get_files pipeline_50mhz.xdc]]"

set_property source_mgmt_mode DisplayOnly [current_project]

# Ensure all interrupt/UART sources are present in the fileset.
add_files -quiet -norecurse [list \
    $root/rtl/rv32_core_pipeline.v \
    $root/rtl/rv32_soc_pipeline.v \
    $root/rtl/soc_bram_dual.v \
    $root/rtl/uart_rx.v \
    $root/rtl/uart_tx.v \
    $root/rtl/soc_uart.v \
    $root/rtl/soc_clint.v \
    $root/rtl/top_ego1_pipeline.v ]
update_compile_order -fileset sources_1

set_property top top_ego1_pipeline [current_fileset]
set_property generic {INIT_FILE=D:/vivado_project/project_2/programs/demo_uart.hex} [get_filesets sources_1]
puts "FILESET_TOP: [get_property top [current_fileset]]"
puts "INIT_FILE: irq_selftest.hex"

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "SYNTH_STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTH_FAILED — aborting."
    close_project
    return
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL_STATUS: [get_property STATUS [get_runs impl_1]]"
puts "IMPL_PROGRESS: [get_property PROGRESS [get_runs impl_1]]"

# Copy the bit out under a stable name for flashing. (The STATUS field can read
# a stale "Running..." even on success — verify write_bitstream separately.)
set built $root/project_2.runs/impl_1/top_ego1_pipeline.bit
if {[file exists $built]} {
    file copy -force $built $root/top_ego1_pipeline_irq.bit
    puts "BIT_COPIED: $root/top_ego1_pipeline_irq.bit"
} else {
    puts "BIT_MISSING: $built (check impl log for write_bitstream completed)"
}

open_run impl_1
puts "OVERALL_WNS: [get_property STATS.WNS [get_runs impl_1]]"
puts "OVERALL_WHS: [get_property STATS.WHS [get_runs impl_1]]"
report_timing_summary -file $root/timing_irq.rpt

# Restore documented defaults so other builds are unaffected.
set_property top top_ego1 [current_fileset]
set_property generic {} [get_filesets sources_1]
set_property is_enabled false [get_files pipeline_50mhz.xdc]
set_property source_mgmt_mode All [current_project]
close_project
puts "BUILD_IRQ_DONE"
