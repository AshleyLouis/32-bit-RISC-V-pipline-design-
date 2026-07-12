# Adds the interrupt/UART sources (added after the baseline) to project_2.xpr.
# Run once from Vivado:  source scripts/add_irq_uart_sources.tcl
# Idempotent-ish: add_files warns (not errors) on files already present.
set origin_dir [file normalize [file join [file dirname [info script]] ..]]

add_files -norecurse [list \
    [file join $origin_dir rtl uart_rx.v] \
    [file join $origin_dir rtl uart_tx.v] \
    [file join $origin_dir rtl soc_uart.v] \
    [file join $origin_dir rtl soc_clint.v] \
]

add_files -fileset sources_1 -norecurse [file join $origin_dir programs monitor.hex]
add_files -fileset sources_1 -norecurse [file join $origin_dir programs irq_selftest.hex]
set_property file_type {Memory File} [get_files [file join $origin_dir programs monitor.hex]]
set_property file_type {Memory File} [get_files [file join $origin_dir programs irq_selftest.hex]]

add_files -fileset sim_1 -norecurse [list \
    [file join $origin_dir sim tb_rv32_irq_pipe.v] \
    [file join $origin_dir sim tb_rv32_irq_mc.v] \
    [file join $origin_dir sim tb_rv32_uart.v] \
]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Added UART/CLINT interrupt sources + monitor/irq firmware + IRQ/UART testbenches."
