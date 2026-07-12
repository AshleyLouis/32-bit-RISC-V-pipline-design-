`timescale 1ns / 1ps

// Runs irq_selftest.hex (CSR + ecall + illegal + timer-interrupt self-test)
// on the pipeline SoC and checks the pass code 0xCAFE on the LED port.
module tb_rv32_irq_pipe;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg [7:0] sw = 8'h00;
    reg [7:0] dip_sw = 8'h00;
    wire [15:0] led;
    wire [7:0] seg0, seg1, seg_sel;
    wire trap;
    wire uart_tx;

    integer cycle;

    always #5 clk = ~clk;

    rv32_soc_pipeline #(
        .BRAM_WORDS(8192),
        .INIT_FILE("programs/irq_selftest.hex"),
        .CLK_FREQ(50_000_000),
        .BAUD_RATE(9600)
    ) dut (
        .clk(clk), .resetn(resetn),
        .sw(sw), .dip_sw(dip_sw),
        .led(led), .seg0(seg0), .seg1(seg1), .seg_sel(seg_sel),
        .uart_rx_pin(1'b1), .uart_tx_pin(uart_tx),
        .trap(trap)
    );

    initial begin
        $dumpfile("tb_rv32_irq_pipe.vcd");
        $dumpvars(0, tb_rv32_irq_pipe);
        repeat (4) @(posedge clk);
        resetn <= 1'b1;

        for (cycle = 0; cycle < 2000; cycle = cycle + 1) begin
            @(posedge clk);
            if (led == 16'hCAFE) begin
                $display("PASS: pipeline IRQ self-test (CAFE) at cycle %0d", cycle);
                $finish;
            end
            if (led == 16'hDEAD) begin
                $display("FAIL: pipeline IRQ self-test reported DEAD at cycle %0d", cycle);
                $finish;
            end
            if (trap) begin
                $display("FAIL: pipeline entered fatal trap at cycle %0d", cycle);
                $finish;
            end
        end
        $display("FAIL: pipeline IRQ self-test timed out, led=%h", led);
        $finish;
    end
endmodule
