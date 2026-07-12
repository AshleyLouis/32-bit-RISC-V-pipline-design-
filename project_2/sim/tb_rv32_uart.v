`timescale 1ns / 1ps

// UART-level end-to-end test of the monitor firmware on the pipeline SoC.
// Drives serial bytes into uart_rx_pin at the configured baud and decodes
// bytes shifted out of uart_tx_pin. Uses a low CLK_FREQ/BAUD ratio so a byte
// takes few cycles (fast sim); the RTL is identical to the real build.
module tb_rv32_uart;
    localparam integer CLKF = 10000;   // pretend 10 kHz "clock"
    localparam integer BAUD = 1000;    // 1 kHz baud -> 10 clocks / bit
    localparam integer BITC = CLKF / BAUD;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg [7:0] sw = 8'h00, dip_sw = 8'h00;
    wire [15:0] led;
    wire [7:0] seg0, seg1, seg_sel;
    wire trap;
    reg  rx = 1'b1;         // into DUT uart_rx_pin (idle high)
    wire tx;                // from DUT uart_tx_pin

    always #5 clk = ~clk;   // 100 ns period

    rv32_soc_pipeline #(
        .BRAM_WORDS(8192),
        .INIT_FILE("programs/monitor.hex"),
        .CLK_FREQ(CLKF),
        .BAUD_RATE(BAUD)
    ) dut (
        .clk(clk), .resetn(resetn),
        .sw(sw), .dip_sw(dip_sw),
        .led(led), .seg0(seg0), .seg1(seg1), .seg_sel(seg_sel),
        .uart_rx_pin(rx), .uart_tx_pin(tx),
        .trap(trap)
    );

    integer i;

    // Send one byte at BAUD (LSB first, 8N1).
    task send_byte(input [7:0] b);
        begin
            rx = 1'b0;                          // start bit
            repeat (BITC) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];
                repeat (BITC) @(posedge clk);
            end
            rx = 1'b1;                          // stop bit
            repeat (BITC) @(posedge clk);
        end
    endtask

    // Receive one byte from tx: wait for start bit, sample mid-bit.
    task recv_byte(output [7:0] b);
        begin
            @(negedge tx);                      // start bit edge
            repeat (BITC + BITC/2) @(posedge clk); // to middle of bit0
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = tx;
                repeat (BITC) @(posedge clk);
            end
        end
    endtask

    reg [7:0] got [0:15];
    integer n;

    // Collect the boot banner "RV32I OK\n" (9 bytes).
    task collect(input integer count);
        begin
            for (n = 0; n < count; n = n + 1)
                recv_byte(got[n]);
        end
    endtask

    initial begin
        $dumpfile("tb_rv32_uart.vcd");
        $dumpvars(0, tb_rv32_uart);
        repeat (4) @(posedge clk);
        resetn <= 1'b1;

        // ---- 1. boot banner ----
        collect(9);
        if (got[0]!=="R"||got[1]!=="V"||got[4]!=="I"||got[8]!==8'h0a) begin
            $display("FAIL: banner wrong: %c%c%c%c%c%c%c%c",
                     got[0],got[1],got[2],got[3],got[4],got[5],got[6],got[7]);
            $finish;
        end
        $display("PASS: boot banner");

        // ---- 2. ping ----
        send_byte("P");
        collect(5);   // PONG\n
        if (got[0]!=="P"||got[1]!=="O"||got[2]!=="N"||got[3]!=="G") begin
            $display("FAIL: ping reply %c%c%c%c", got[0],got[1],got[2],got[3]);
            $finish;
        end
        $display("PASS: ping -> PONG");

        // ---- 3. write then read back BRAM word ----
        // W 00000400 DEADBEEF
        send_byte("W");
        send_byte("0");send_byte("0");send_byte("0");send_byte("0");
        send_byte("0");send_byte("4");send_byte("0");send_byte("0");
        send_byte("D");send_byte("E");send_byte("A");send_byte("D");
        send_byte("B");send_byte("E");send_byte("E");send_byte("F");
        collect(3);   // OK\n
        if (got[0]!=="O"||got[1]!=="K") begin $display("FAIL: write no OK"); $finish; end
        // R 00000400 -> =DEADBEEF\n
        send_byte("R");
        send_byte("0");send_byte("0");send_byte("0");send_byte("0");
        send_byte("0");send_byte("4");send_byte("0");send_byte("0");
        collect(10);  // =DEADBEEF\n
        if (got[0]!=="="||got[1]!=="D"||got[2]!=="E"||got[3]!=="A"||got[4]!=="D"
            ||got[5]!=="B"||got[6]!=="E"||got[7]!=="E"||got[8]!=="F") begin
            $display("FAIL: readback %c%c%c%c%c%c%c%c%c",
                     got[0],got[1],got[2],got[3],got[4],got[5],got[6],got[7],got[8]);
            $finish;
        end
        $display("PASS: W/R memory round-trip (DEADBEEF)");

        // ---- 4. RX interrupt: enable, send 'a', expect "!RX41\n" ----
        send_byte("I"); send_byte("e");
        collect(3);   // OK\n
        send_byte("a");            // 0x61 -> uppercased 'A' = 0x41
        collect(6);   // !RX41\n
        if (got[0]!=="!"||got[1]!=="R"||got[2]!=="X"||got[3]!=="4"||got[4]!=="1") begin
            $display("FAIL: RX irq reply %c%c%c%c%c",
                     got[0],got[1],got[2],got[3],got[4]);
            $finish;
        end
        $display("PASS: RX interrupt echo (!RX41)");

        $display("ALL UART MONITOR TESTS PASSED");
        $finish;
    end

    // global watchdog
    initial begin
        #50_000_000;
        $display("FAIL: uart tb global timeout");
        $finish;
    end
endmodule
