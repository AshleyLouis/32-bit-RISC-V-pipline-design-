`timescale 1ns / 1ps

module top_ego1_pipeline #(
    parameter INIT_FILE = "programs/sw_led.hex"
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

    // ---- CPU clock: 100 MHz input divided by 2 -> 50 MHz ----------------
    // The pipelined core's branch-resolution path (id_ex_rs1 -> pc_reg,
    // 11 logic levels) misses setup at 100 MHz. Halving the CPU clock gives
    // ~20 ns of budget so timing closes cleanly with margin to spare; the
    // self-test is far from clock-bound so throughput is unaffected.
    // The divider lives only in this FPGA top wrapper, so the ModelSim
    // tb_rv32_pipe_* benches (which drive rv32_soc_pipeline directly) are
    // unaffected.
    (* keep = "true" *) reg clk_div2 = 1'b0;
    always @(posedge clk) begin
        clk_div2 <= ~clk_div2;
    end

    // Route the divided clock onto a global buffer so it uses a real clock
    // network (the XDC create_generated_clock hangs off this BUFG output).
    wire cpu_clk;
    BUFG cpu_clk_bufg (.I(clk_div2), .O(cpu_clk));

    rv32_soc_pipeline #(
        .BRAM_WORDS(8192),
        .INIT_FILE(INIT_FILE),
        .CLK_FREQ(50_000_000),   // cpu_clk is the 50 MHz divided clock
        .BAUD_RATE(9600)
    ) soc (
        .clk(cpu_clk),
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
