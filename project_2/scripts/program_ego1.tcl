# Program the EGO1 (xc7a35t) with the built bitstream over JTAG.
# Volatile: configuration is lost on power cycle. Re-run to reprogram.
set bit [lindex $argv 0]
if {$bit eq ""} {
    set bit "D:/vivado_project/project_2/project_2.runs/impl_1/top_ego1.bit"
}
puts "PROGRAMMING_WITH: $bit"

open_hw
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAM_DONE: $dev"
close_hw_target
disconnect_hw_server
