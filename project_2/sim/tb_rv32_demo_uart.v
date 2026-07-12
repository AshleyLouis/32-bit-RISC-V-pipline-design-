`timescale 1ns / 1ps

// Verifies the MERGED demo_uart firmware on the pipeline SoC:
//   (1) with dip_sw=0 the display shows CAFE (original demo path intact),
//   (2) with dip_sw=6 it hands off to the serial monitor and answers UART.
module tb_rv32_demo_uart;
    localparam integer CLKF = 10000, BAUD = 1000, BITC = CLKF / BAUD;

    reg clk = 1'b0, resetn = 1'b0;
    reg [7:0] sw = 8'h00, dip_sw = 8'h00;
    wire [15:0] led;
    wire [7:0] seg0, seg1, seg_sel;
    wire trap;
    reg  rx = 1'b1;
    wire tx;
    integer i;

    always #5 clk = ~clk;

    rv32_soc_pipeline #(
        .BRAM_WORDS(8192), .INIT_FILE("programs/demo_uart.hex"),
        .CLK_FREQ(CLKF), .BAUD_RATE(BAUD)
    ) dut (
        .clk(clk), .resetn(resetn), .sw(sw), .dip_sw(dip_sw),
        .led(led), .seg0(seg0), .seg1(seg1), .seg_sel(seg_sel),
        .uart_rx_pin(rx), .uart_tx_pin(tx), .trap(trap)
    );

    task send_byte(input [7:0] b);
        begin
            rx = 0; repeat (BITC) @(posedge clk);
            for (i=0;i<8;i=i+1) begin rx=b[i]; repeat(BITC) @(posedge clk); end
            rx = 1; repeat (BITC) @(posedge clk);
        end
    endtask
    task recv_byte(output [7:0] b);
        begin
            @(negedge tx);
            repeat (BITC + BITC/2) @(posedge clk);
            for (i=0;i<8;i=i+1) begin b[i]=tx; repeat(BITC) @(posedge clk); end
        end
    endtask
    reg [7:0] g [0:15]; integer n;
    task collect(input integer c); begin for(n=0;n<c;n=n+1) recv_byte(g[n]); end endtask

    initial begin
        $dumpfile("tb_rv32_demo_uart.vcd"); $dumpvars(0, tb_rv32_demo_uart);
        repeat (4) @(posedge clk); resetn <= 1'b1;

        // ---- 1. demo view mode 0 -> CAFE on LED (original path preserved) ----
        // Boot runs the sum-1..100 benchmark + CPI divide + 4x to_bcd before the
        // display loop, so allow generous time to reach mode 0.
        dip_sw <= 8'h00;
        for (i=0;i<60000;i=i+1) begin
            @(posedge clk);
            if (led == 16'hCAFE) i = 100000;   // break
        end
        if (led !== 16'hCAFE) begin
            $display("FAIL: demo mode 0 led=%h (expected CAFE)", led); $finish;
        end
        $display("PASS: demo mode 0 shows CAFE");

        // ---- 2. switch to mode 6 -> monitor answers ping ----
        dip_sw <= 8'h06;           // dip_sw[2:0] = 6
        // give the firmware time to notice the switch + print banner, then ping
        // (banner is 9 bytes; just wait for the LED marker 0x0060)
        for (i=0;i<20000;i=i+1) begin
            @(posedge clk);
            if (led == 16'h0060) i = 100000;   // entered monitor
        end
        if (led !== 16'h0060) begin
            $display("FAIL: mode 6 did not enter monitor (led=%h)", led); $finish;
        end
        $display("PASS: mode 6 entered monitor (LED marker 0060)");

        // drain the banner that the monitor prints on entry (9 bytes)
        collect(9);
        // ping
        send_byte("P");
        collect(5);
        if (g[0]!=="P"||g[1]!=="O"||g[2]!=="N"||g[3]!=="G") begin
            $display("FAIL: monitor ping %c%c%c%c", g[0],g[1],g[2],g[3]); $finish;
        end
        $display("PASS: monitor ping -> PONG in merged firmware");

        $display("ALL DEMO_UART MERGED TESTS PASSED");
        $finish;
    end

    initial begin #80_000_000; $display("FAIL: demo_uart tb timeout"); $finish; end
endmodule
