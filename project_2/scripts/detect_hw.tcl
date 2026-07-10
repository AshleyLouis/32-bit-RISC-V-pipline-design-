# Detect the EGO1 board over JTAG. Read-only: does not program anything.
open_hw
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
puts "DETECTED_DEVICE: $dev"
puts "PART: [get_property PART $dev]"
close_hw_target
disconnect_hw_server
