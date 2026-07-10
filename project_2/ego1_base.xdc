## EGO1 base constraints for the RISC-V CPU/SoC project.
## Board: EGO1, Xilinx Artix-7 XC7A35T-1CSG324C.

## 100 MHz system clock
set_property PACKAGE_PIN P17 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

## NOTE: the pipelined top (top_ego1_pipeline) divides this 100 MHz clock by 2
## to a 50 MHz cpu_clk. That generated clock lives in a SEPARATE, build-enabled
## constraint file (pipeline_50mhz.xdc), NOT here — a conditional guard in this
## shared file evaluates at XDC-read time before the netlist exists, so it never
## actually applies. See pipeline_50mhz.xdc and scripts/build_pipeline_50mhz.tcl.

## Dedicated reset button. Measured idle-high on hardware (opposite of the
## five general-purpose buttons): idle reads 1, pressed reads 0. The
## top-level treats reset_btn directly as an active-low reset (resetn).
## Pull-up reinforces the idle-high default when not pressed.
set_property PACKAGE_PIN P15 [get_ports reset_btn]
set_property IOSTANDARD LVCMOS33 [get_ports reset_btn]
set_property PULLUP true [get_ports reset_btn]

## Switches: sw[7:0] and dip_sw[7:0]
set_property PACKAGE_PIN P5 [get_ports {sw[0]}]
set_property PACKAGE_PIN P4 [get_ports {sw[1]}]
set_property PACKAGE_PIN P3 [get_ports {sw[2]}]
set_property PACKAGE_PIN P2 [get_ports {sw[3]}]
set_property PACKAGE_PIN R2 [get_ports {sw[4]}]
set_property PACKAGE_PIN M4 [get_ports {sw[5]}]
set_property PACKAGE_PIN N4 [get_ports {sw[6]}]
set_property PACKAGE_PIN R1 [get_ports {sw[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

set_property PACKAGE_PIN U3 [get_ports {dip_sw[0]}]
set_property PACKAGE_PIN U2 [get_ports {dip_sw[1]}]
set_property PACKAGE_PIN V2 [get_ports {dip_sw[2]}]
set_property PACKAGE_PIN V5 [get_ports {dip_sw[3]}]
set_property PACKAGE_PIN V4 [get_ports {dip_sw[4]}]
set_property PACKAGE_PIN R3 [get_ports {dip_sw[5]}]
set_property PACKAGE_PIN T3 [get_ports {dip_sw[6]}]
set_property PACKAGE_PIN T5 [get_ports {dip_sw[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dip_sw[*]}]

## LEDs: active high
set_property PACKAGE_PIN F6 [get_ports {led[0]}]
set_property PACKAGE_PIN G4 [get_ports {led[1]}]
set_property PACKAGE_PIN G3 [get_ports {led[2]}]
set_property PACKAGE_PIN J4 [get_ports {led[3]}]
set_property PACKAGE_PIN H4 [get_ports {led[4]}]
set_property PACKAGE_PIN J3 [get_ports {led[5]}]
set_property PACKAGE_PIN J2 [get_ports {led[6]}]
set_property PACKAGE_PIN K2 [get_ports {led[7]}]
set_property PACKAGE_PIN K1 [get_ports {led[8]}]
set_property PACKAGE_PIN H6 [get_ports {led[9]}]
set_property PACKAGE_PIN H5 [get_ports {led[10]}]
set_property PACKAGE_PIN J5 [get_ports {led[11]}]
set_property PACKAGE_PIN K6 [get_ports {led[12]}]
set_property PACKAGE_PIN L1 [get_ports {led[13]}]
set_property PACKAGE_PIN M1 [get_ports {led[14]}]
set_property PACKAGE_PIN K3 [get_ports {led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## Seven-segment display segments. Active high on EGO1.
set_property PACKAGE_PIN B4 [get_ports {seg0[0]}]
set_property PACKAGE_PIN A4 [get_ports {seg0[1]}]
set_property PACKAGE_PIN A3 [get_ports {seg0[2]}]
set_property PACKAGE_PIN B1 [get_ports {seg0[3]}]
set_property PACKAGE_PIN A1 [get_ports {seg0[4]}]
set_property PACKAGE_PIN B3 [get_ports {seg0[5]}]
set_property PACKAGE_PIN B2 [get_ports {seg0[6]}]
set_property PACKAGE_PIN D5 [get_ports {seg0[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg0[*]}]

set_property PACKAGE_PIN D4 [get_ports {seg1[0]}]
set_property PACKAGE_PIN E3 [get_ports {seg1[1]}]
set_property PACKAGE_PIN D3 [get_ports {seg1[2]}]
set_property PACKAGE_PIN F4 [get_ports {seg1[3]}]
set_property PACKAGE_PIN F3 [get_ports {seg1[4]}]
set_property PACKAGE_PIN E2 [get_ports {seg1[5]}]
set_property PACKAGE_PIN D2 [get_ports {seg1[6]}]
set_property PACKAGE_PIN H2 [get_ports {seg1[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg1[*]}]

set_property PACKAGE_PIN G2 [get_ports {seg_sel[0]}]
set_property PACKAGE_PIN C2 [get_ports {seg_sel[1]}]
set_property PACKAGE_PIN C1 [get_ports {seg_sel[2]}]
set_property PACKAGE_PIN H1 [get_ports {seg_sel[3]}]
set_property PACKAGE_PIN G1 [get_ports {seg_sel[4]}]
set_property PACKAGE_PIN F1 [get_ports {seg_sel[5]}]
set_property PACKAGE_PIN E1 [get_ports {seg_sel[6]}]
set_property PACKAGE_PIN G6 [get_ports {seg_sel[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg_sel[*]}]

## USB UART/JTAG.
## Manual wording:
## UART_RX / T4 is the FPGA serial transmit side.
## UART_TX / N5 is the FPGA serial receive side.
set_property PACKAGE_PIN T4 [get_ports uart_tx]
set_property PACKAGE_PIN N5 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
