# Diagnose why the cpu_clk generated clock was not created, and measure the
# TRUE CPU-domain slack by creating it manually on the implemented netlist.
open_project D:/vivado_project/project_2/project_2.xpr
open_run impl_1

puts "=== existing clocks ==="
foreach c [get_clocks] { puts "CLOCK: $c  period=[get_property PERIOD $c]" }

puts "=== BUFG cells matching cpu ==="
foreach c [get_cells -hier -quiet -filter {REF_NAME == BUFG || REF_NAME == BUFGCE}] {
    puts "BUFGCELL: $c"
}
puts "=== pin lookup cpu_clk_bufg/O ==="
set p [get_pins -quiet cpu_clk_bufg/O]
puts "PIN_RESULT: '$p'  (llength [llength $p])"
# try hierarchical
set p2 [get_pins -hier -quiet */cpu_clk_bufg/O]
puts "PIN_HIER: '$p2'"
set p3 [get_pins -hier -quiet -filter {NAME =~ *cpu_clk_bufg*}]
puts "PIN_ANY_BUFG: '$p3'"

# Manually create the generated clock on whatever BUFG feeds the CPU, then
# re-time to get the true worst CPU-domain setup slack.
if {[llength $p3]} {
    set opin [get_pins -hier -quiet -filter {NAME =~ *cpu_clk_bufg*O && DIRECTION == OUT}]
    puts "OPIN: '$opin'"
    if {[llength $opin]} {
        create_generated_clock -name cpu_clk_tmp -source [get_ports clk] -divide_by 2 $opin
        set_propagated_clock [get_clocks cpu_clk_tmp]
        update_timing
        puts "=== after creating cpu_clk_tmp ==="
        foreach c [get_clocks] { puts "CLOCK2: $c period=[get_property PERIOD $c]" }
        set paths [get_timing_paths -setup -to [get_clocks cpu_clk_tmp] -max_paths 1]
        if {[llength $paths]} {
            puts "CPU_SETUP_WNS: [get_property SLACK [lindex $paths 0]]"
        }
        set hpaths [get_timing_paths -hold -to [get_clocks cpu_clk_tmp] -max_paths 1]
        if {[llength $hpaths]} {
            puts "CPU_HOLD_WHS: [get_property SLACK [lindex $hpaths 0]]"
        }
    }
}
close_project
puts "DIAG_DONE"
