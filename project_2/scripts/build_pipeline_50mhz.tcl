# Build the 5-stage PIPELINED core (top_ego1_pipeline) running the ISA self-test,
# with the top-level ÷2 clock divider (cpu_clk = 50 MHz on cpu_clk_bufg).
#
# The CPU/SoC is constrained at 20 ns via a SEPARATE constraint file
# (pipeline_50mhz.xdc) that we enable only for this build. It must NOT be
# guarded/conditional (see that file's header) and it must NOT live in the
# shared ego1_base.xdc, or it either never applies (guarded) or breaks the
# multi-cycle build (unguarded in the shared file).
open_project D:/vivado_project/project_2/project_2.xpr
set root D:/vivado_project/project_2

# Reset impl strategy to defaults (a prior timing-closure run left it on
# Performance_Explore). With the halved clock, defaults should close easily.
set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]

# --- register + ENABLE the pipeline-only generated-clock constraint ---------
set pll_xdc $root/pipeline_50mhz.xdc
if {[lsearch -exact [get_files -quiet -of [get_filesets constrs_1]] $pll_xdc] < 0 &&
    [llength [get_files -quiet pipeline_50mhz.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $pll_xdc
}
set_property is_enabled true [get_files pipeline_50mhz.xdc]
puts "CPUCLK_XDC_ENABLED: [get_property is_enabled [get_files pipeline_50mhz.xdc]]"

# DisplayOnly = automatic hierarchy update (new files parsed) + manual top
# (top_ego1_pipeline not auto-overridden by the other root, top_ego1).
set_property source_mgmt_mode DisplayOnly [current_project]

add_files -norecurse [list \
    $root/rtl/rv32_core_pipeline.v \
    $root/rtl/rv32_soc_pipeline.v \
    $root/rtl/soc_bram_dual.v \
    $root/rtl/top_ego1_pipeline.v ]
update_compile_order -fileset sources_1

set_property top top_ego1_pipeline [current_fileset]
set_property generic {INIT_FILE=D:/vivado_project/project_2/programs/isa_selftest.hex} [get_filesets sources_1]
puts "FILESET_TOP: [get_property top [current_fileset]]"
puts "NVERILOG: [llength [get_files -of [current_fileset] *.v]]"

# Two-stage launch: synthesize and WAIT before implementation.
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "SYNTH_STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTH_FAILED — aborting before implementation."
    close_project
    return
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL_STATUS: [get_property STATUS [get_runs impl_1]]"
puts "IMPL_PROGRESS: [get_property PROGRESS [get_runs impl_1]]"

# Post-route timing: overall + per-clock worst setup/hold from the timing engine.
open_run impl_1
puts "OVERALL_WNS: [get_property STATS.WNS [get_runs impl_1]]"
puts "OVERALL_WHS: [get_property STATS.WHS [get_runs impl_1]]"
puts "OVERALL_TNS: [get_property STATS.TNS [get_runs impl_1]]"
report_timing_summary -file $root/timing_50mhz.rpt
puts "CLOCKS_IN_DESIGN: [get_clocks]"
foreach ck {sys_clk cpu_clk} {
    set cobj [get_clocks -quiet $ck]
    if {![llength $cobj]} { puts "CLK_MISSING: $ck"; continue }
    set sp [get_timing_paths -quiet -setup -to $cobj -max_paths 1]
    set hp [get_timing_paths -quiet -hold  -to $cobj -max_paths 1]
    set sslack "n/a"; set hslack "n/a"
    if {[llength $sp]} { set sslack [get_property SLACK [lindex $sp 0]] }
    if {[llength $hp]} { set hslack [get_property SLACK [lindex $hp 0]] }
    puts "CLK_TIMING $ck  setupWNS=$sslack  holdWHS=$hslack"
}

# Restore documented default top (multi-cycle) and generic; DISABLE the
# pipeline-only clock constraint so the default multi-cycle build is unaffected.
set_property top top_ego1 [current_fileset]
set_property generic {} [get_filesets sources_1]
set_property is_enabled false [get_files pipeline_50mhz.xdc]
set_property source_mgmt_mode All [current_project]
close_project
puts "BUILD_50MHZ_DONE"
