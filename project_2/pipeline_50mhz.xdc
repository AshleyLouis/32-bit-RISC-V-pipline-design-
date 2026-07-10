## Generated clock for the PIPELINED top only (top_ego1_pipeline).
##
## top_ego1_pipeline divides the 100 MHz sys_clk by 2 (a toggle flop + BUFG,
## cpu_clk_bufg) to run the CPU/SoC at 50 MHz, which gives ~20 ns of setup
## budget for the branch-resolution path that just missed at 100 MHz.
##
## This file is UNGUARDED on purpose: create_generated_clock referencing a
## netlist pin is DEFERRED by Vivado until the synthesized netlist exists, so
## it applies correctly. A read-time `if {[llength [get_pins ...]]}` guard does
## NOT work — it runs before the netlist exists and silently skips the clock.
##
## Because it would ERROR on the multi-cycle top_ego1 build (no cpu_clk_bufg
## there), this file is kept DISABLED by default and enabled only by the
## pipeline build script:
##   set_property is_enabled true  [get_files pipeline_50mhz.xdc]   ;# pipeline
##   set_property is_enabled false [get_files pipeline_50mhz.xdc]   ;# multi-cycle
create_generated_clock -name cpu_clk -source [get_ports clk] -divide_by 2 \
    [get_pins cpu_clk_bufg/O]
