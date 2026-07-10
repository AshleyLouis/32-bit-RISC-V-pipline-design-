# Rebuild top_ego1 with the switch-mirror program (sw_led.hex) baked into BRAM,
# overriding the INIT_FILE parameter via a synthesis generic so the RTL default
# (isa_selftest.hex) stays untouched. Produces impl_1/top_ego1.bit.
open_project D:/vivado_project/project_2/project_2.xpr

set_property generic {INIT_FILE=D:/vivado_project/project_2/programs/sw_led.hex} [get_filesets sources_1]

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "IMPL_STATUS: [get_property STATUS [get_runs impl_1]]"
puts "IMPL_PROGRESS: [get_property PROGRESS [get_runs impl_1]]"

# Leave the project's stored generic clean so future builds use the RTL default.
set_property generic {} [get_filesets sources_1]
close_project
