# Write the demo bitstream to the EGO1's SPI configuration flash (Micron N25Q32,
# 3.3V) so the FPGA auto-loads it on power-up and survives PROG / power-cycle.
#
# Two steps: (1) wrap the .bit into an .mcs with write_cfgmem, (2) program the
# flash over JTAG via the config-memory helper bitstream.
#
# Optional arg: path to the .bit (default demo_pipeline.bit).
set root D:/vivado_project/project_2
set bit  [expr {$argc >= 1 ? [lindex $argv 0] : "$root/demo_pipeline.bit"}]
set mcs  "$root/[file rootname [file tail $bit]].mcs"
set part n25q32-3.3v-spi-x1_x2_x4

# ---- 1) generate the .mcs (SPIx1, 4 MB device) -------------------------
write_cfgmem -force -format mcs -size 4 -interface SPIx1 \
    -loadbit "up 0x0 $bit" -file $mcs
puts "MCS_DONE: $mcs"

# ---- 2) connect to the board (Vivado 2018.3 uses open_hw, not open_hw_manager)
open_hw
connect_hw_server -quiet
open_hw_target
set dev [lindex [get_hw_devices xc7a35t_0] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
puts "DEVICE: $dev"

# ---- 3) attach the config memory and program it -----------------------
create_hw_cfgmem -hw_device $dev -mem_dev [lindex [get_cfgmem_parts $part] 0]
set cfg [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.FILES        [list $mcs]  $cfg
set_property PROGRAM.ADDRESS_RANGE {use_file}  $cfg
set_property PROGRAM.BLANK_CHECK   0           $cfg
set_property PROGRAM.ERASE         1           $cfg
set_property PROGRAM.CFG_PROGRAM   1           $cfg
set_property PROGRAM.VERIFY        1           $cfg
set_property PROGRAM.CHECKSUM      0           $cfg

# load the flash-programmer helper into the FPGA, then program the flash
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
refresh_hw_device $dev
program_hw_cfgmem -hw_cfgmem $cfg
puts "FLASH_PROGRAM_DONE"

close_hw_target
disconnect_hw_server
close_hw
puts "FLASH_ALL_DONE"
