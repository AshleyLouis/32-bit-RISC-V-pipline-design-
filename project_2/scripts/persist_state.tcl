# Restore project_2.xpr to a clean, documented default state and PERMANENTLY
# register pipeline_50mhz.xdc (disabled) so pipeline/demo builds can just enable
# it instead of re-adding it each time. close_project persists to disk.
open_project D:/vivado_project/project_2/project_2.xpr
set root D:/vivado_project/project_2
if {[llength [get_files -quiet pipeline_50mhz.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $root/pipeline_50mhz.xdc
}
set_property is_enabled false [get_files pipeline_50mhz.xdc]
set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]
set_property source_mgmt_mode All [current_project]
set_property top top_ego1 [current_fileset]
set_property generic {} [get_filesets sources_1]
puts "XDC_REGISTERED: [llength [get_files -quiet pipeline_50mhz.xdc]]  enabled=[get_property is_enabled [get_files pipeline_50mhz.xdc]]"
puts "TOP: [get_property top [current_fileset]]  MGMT: [get_property source_mgmt_mode [current_project]]"
close_project
puts "PERSIST_DONE"
