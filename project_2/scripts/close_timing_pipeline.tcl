# Close timing on the pipelined core (top_ego1_pipeline, ISA self-test) without
# any RTL change: re-run implementation with the Performance_Explore strategy,
# which enables post-place and post-route phys_opt_design passes. The baseline
# Vivado-defaults run missed setup by only -0.143 ns, so this should close it.
open_project D:/vivado_project/project_2/project_2.xpr

set_property source_mgmt_mode DisplayOnly [current_project]
set_property top top_ego1_pipeline [current_fileset]
set_property generic {INIT_FILE=D:/vivado_project/project_2/programs/isa_selftest.hex} [get_filesets sources_1]

# Higher-effort implementation strategy (includes phys_opt_design steps).
set_property strategy Performance_Explore [get_runs impl_1]

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTH_FAILED"; close_project; return
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL_STATUS: [get_property STATUS [get_runs impl_1]]"
puts "IMPL_PROGRESS: [get_property PROGRESS [get_runs impl_1]]"

# Report post-route worst slack directly from the run.
open_run impl_1
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "CLOSED_WNS: $wns"
puts "CLOSED_WHS: $whs"
if {$wns >= 0} { puts "TIMING_MET: yes" } else { puts "TIMING_MET: no" }

# Restore documented project defaults for future work.
set_property top top_ego1 [current_fileset]
set_property generic {} [get_filesets sources_1]
set_property source_mgmt_mode All [current_project]
close_project
