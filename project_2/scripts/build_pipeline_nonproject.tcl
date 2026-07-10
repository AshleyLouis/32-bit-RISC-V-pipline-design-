# Non-project batch build of the 5-stage PIPELINED core running the ISA
# self-test. Bypasses the .xpr auto-hierarchy entirely: read RTL, set top
# explicitly, run the full implementation flow, write a distinctly-named
# bitstream. Reading extra modules (the multi-cycle wrappers) is harmless
# because synth_design -top elaborates only the pipeline hierarchy.
set root D:/vivado_project/project_2
set part xc7a35tcsg324-1
set init_file $root/programs/isa_selftest.hex
set outbit $root/project_2.runs/impl_1/top_ego1_pipeline.bit

read_verilog [glob $root/rtl/*.v]
read_xdc $root/ego1_base.xdc

synth_design -top top_ego1_pipeline -part $part -generic INIT_FILE=$init_file
opt_design
place_design
route_design

report_timing_summary -file $root/pipeline_timing_summary.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "PIPELINE_WNS: $wns"
puts "TOP_CHECK: [llength [get_cells -hier -filter {REF_NAME =~ *core_pipeline*}]] pipeline-core cells"

write_bitstream -force $outbit
puts "BITSTREAM_WRITTEN: $outbit"
