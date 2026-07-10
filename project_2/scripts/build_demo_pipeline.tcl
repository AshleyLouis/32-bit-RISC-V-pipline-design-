# Build ONLY the pipeline demo bitstream (top_ego1_pipeline + demo.hex, 50 MHz)
# -> demo_pipeline.bit. The multi-cycle demo bit is built by build_demo_both.tcl.
# Registers pipeline_50mhz.xdc into constrs_1 if it is not already there (it is
# NOT stored in the .xpr by default), then enables it for this build only.
open_project D:/vivado_project/project_2/project_2.xpr
set root D:/vivado_project/project_2
set hex  $root/programs/demo.hex

# Make sure the generated-clock constraint file is in the project, then enable.
if {[llength [get_files -quiet pipeline_50mhz.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $root/pipeline_50mhz.xdc
}
set_property is_enabled true [get_files pipeline_50mhz.xdc]
puts "CPUCLK_XDC_ENABLED: [get_property is_enabled [get_files pipeline_50mhz.xdc]]"

set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]
set_property source_mgmt_mode DisplayOnly [current_project]
set_property top top_ego1_pipeline [current_fileset]
set_property generic "INIT_FILE=$hex" [get_filesets sources_1]

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "PIPE_SYNTH_FAILED"; close_project; return }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "PIPE_IMPL_STATUS: [get_property STATUS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { puts "PIPE_FAILED"; close_project; return }

open_run impl_1
puts "PIPE_OVERALL_WNS: [get_property STATS.WNS [get_runs impl_1]]"
foreach ck {sys_clk cpu_clk} {
    set cobj [get_clocks -quiet $ck]
    if {![llength $cobj]} { puts "CLK_MISSING: $ck"; continue }
    set sp [get_timing_paths -quiet -setup -to $cobj -max_paths 1]
    set hp [get_timing_paths -quiet -hold  -to $cobj -max_paths 1]
    puts "CLK_TIMING $ck  setupWNS=[get_property SLACK [lindex $sp 0]]  holdWHS=[get_property SLACK [lindex $hp 0]]"
}
file copy -force $root/project_2.runs/impl_1/top_ego1_pipeline.bit $root/demo_pipeline.bit
puts "PIPE_BIT_DONE: demo_pipeline.bit"

# Restore documented default project state (keep the xdc registered but disabled).
set_property top top_ego1 [current_fileset]
set_property generic {} [get_filesets sources_1]
set_property is_enabled false [get_files pipeline_50mhz.xdc]
set_property source_mgmt_mode All [current_project]
close_project
puts "BUILD_DEMO_PIPE_DONE"
