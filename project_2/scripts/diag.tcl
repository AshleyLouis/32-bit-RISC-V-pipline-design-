open_project D:/vivado_project/project_2/project_2.xpr
puts "SMM: [get_property source_mgmt_mode [current_project]]"
puts "FILESET_TOP: [get_property top [current_fileset]]"
puts "--- per-file used_in_synthesis ---"
foreach f [get_files -of [current_fileset] *.v] {
    puts "  [get_property used_in_synthesis $f] | [get_property IS_ENABLED $f] | $f"
}
puts "--- can Vivado see the module? ---"
puts "MODULES: [find_top -fileset [current_fileset] -return_file_paths]"
close_project
