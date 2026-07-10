# Build the 5-stage PIPELINED core (top_ego1_pipeline) running the ISA self-test.
#
# Root cause of earlier failures: the four pipeline RTL files were never added
# to the project's sources_1 fileset (only the 7 multi-cycle files were present),
# so top_ego1_pipeline literally did not exist in the project -> "module not
# found", and automatic top selection fell back to top_ego1. Fix: add the
# missing files (as add_sources_to_project_2.tcl always intended), then build.
open_project D:/vivado_project/project_2/project_2.xpr
set root D:/vivado_project/project_2

# DisplayOnly = automatic hierarchy update (new files get parsed) + manual top
# (our top_ego1_pipeline selection is not auto-overridden by the other root).
set_property source_mgmt_mode DisplayOnly [current_project]

add_files -norecurse [list \
    $root/rtl/rv32_core_pipeline.v \
    $root/rtl/rv32_soc_pipeline.v \
    $root/rtl/soc_bram_dual.v \
    $root/rtl/top_ego1_pipeline.v ]
update_compile_order -fileset sources_1

set_property top top_ego1_pipeline [current_fileset]
set_property generic {INIT_FILE=D:/vivado_project/project_2/programs/isa_selftest.hex} [get_filesets sources_1]
puts "FILESET_TOP: [get_property top [current_fileset]]"
puts "NVERILOG: [llength [get_files -of [current_fileset] *.v]]"

# Two-stage launch: synthesize and WAIT before implementation.
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "SYNTH_STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTH_FAILED — aborting before implementation."
    close_project
    return
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL_STATUS: [get_property STATUS [get_runs impl_1]]"
puts "IMPL_PROGRESS: [get_property PROGRESS [get_runs impl_1]]"

# Restore documented default top (multi-cycle) and generic; keep the pipeline
# files in the project (they belong there) and restore automatic mgmt mode.
set_property top top_ego1 [current_fileset]
set_property generic {} [get_filesets sources_1]
set_property source_mgmt_mode All [current_project]
close_project
