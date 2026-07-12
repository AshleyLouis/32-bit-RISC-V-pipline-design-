`timescale 1ns / 1ps

module top_ego1 #(
    parameter INIT_FILE = "D:/vivado_project/project_2/programs/isa_selftest.hex"
) (
    input  wire        clk,
    input  wire        reset_btn,
    input  wire [7:0]  sw,
    input  wire [7:0]  dip_sw,
    output wire [15:0] led,
    output wire [7:0]  seg0,
    output wire [7:0]  seg1,
    output wire [7:0]  seg_sel,
    output wire        uart_tx,
    input  wire        uart_rx
);
    // reset_btn is idle-high on hardware (pressed = 0), so it is already an
    // active-low reset signal; do not invert it.
    wire resetn = reset_btn;
    wire trap;

    rv32_soc #(
        .BRAM_WORDS(8192),
        .INIT_FILE(INIT_FILE),
        .CLK_FREQ(100_000_000),   // multi-cycle SoC runs at the full 100 MHz
        .BAUD_RATE(9600)
    ) soc (
        .clk(clk),
        .resetn(resetn),
        .sw(sw),
        .dip_sw(dip_sw),
        .led(led),
        .seg0(seg0),
        .seg1(seg1),
        .seg_sel(seg_sel),
        .uart_rx_pin(uart_rx),
        .uart_tx_pin(uart_tx),
        .trap(trap)
    );

    wire unused_trap = trap;
endmodule
