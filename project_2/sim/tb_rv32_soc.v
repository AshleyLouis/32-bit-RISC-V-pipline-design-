`timescale 1ns / 1ps

module tb_rv32_soc;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg [7:0] sw = 8'h00;
    reg [7:0] dip_sw = 8'h00;
    wire [15:0] led;
    wire [7:0] seg0;
    wire [7:0] seg1;
    wire [7:0] seg_sel;
    wire trap;

    always #5 clk = ~clk;

    rv32_soc #(
        .BRAM_WORDS(256),
        .INIT_FILE("programs/sw_led.hex")
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .sw(sw),
        .dip_sw(dip_sw),
        .led(led),
        .seg0(seg0),
        .seg1(seg1),
        .seg_sel(seg_sel),
        .trap(trap)
    );

    initial begin
        $dumpfile("tb_rv32_soc.vcd");
        $dumpvars(0, tb_rv32_soc);

        repeat (4) @(posedge clk);
        resetn <= 1'b1;

        sw <= 8'ha5;
        dip_sw <= 8'h5a;
        repeat (80) @(posedge clk);

        if (trap) begin
            $display("FAIL: CPU entered trap");
            $finish;
        end

        if (led !== 16'h5aa5) begin
            $display("FAIL: led=%h expected=5aa5", led);
            $finish;
        end

        sw <= 8'h3c;
        dip_sw <= 8'hc3;
        repeat (80) @(posedge clk);

        if (trap) begin
            $display("FAIL: CPU entered trap after input change");
            $finish;
        end

        if (led !== 16'hc33c) begin
            $display("FAIL: led=%h expected=c33c", led);
            $finish;
        end

        $display("PASS: RV32 SoC switch-to-LED smoke test");
        $finish;
    end
endmodule
