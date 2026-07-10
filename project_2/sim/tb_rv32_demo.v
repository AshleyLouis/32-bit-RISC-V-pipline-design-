`timescale 1ns / 1ps

// Verifies the interactive demo firmware (programs/demo.hex) on BOTH cores at
// once, from identical stimulus: the multi-cycle rv32_soc and the pipelined
// rv32_soc_pipeline. Checks the deterministic modes (CAFE, live mirror, 5050)
// and prints the measured cycles / instret / CPI*100 for each core so the
// pipeline speedup is visible in the transcript.
module tb_rv32_demo;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg [7:0] sw = 8'h00;
    reg [7:0] dip_sw = 8'h00;

    wire [15:0] led_mc, led_p;
    wire [7:0]  seg0_mc, seg1_mc, sel_mc, seg0_p, seg1_p, sel_p;
    wire        trap_mc, trap_p;
    integer i;

    always #5 clk = ~clk;

    rv32_soc #(.BRAM_WORDS(256), .INIT_FILE("programs/demo.hex")) mc (
        .clk(clk), .resetn(resetn), .sw(sw), .dip_sw(dip_sw),
        .led(led_mc), .seg0(seg0_mc), .seg1(seg1_mc), .seg_sel(sel_mc), .trap(trap_mc));

    rv32_soc_pipeline #(.BRAM_WORDS(256), .INIT_FILE("programs/demo.hex")) pipe (
        .clk(clk), .resetn(resetn), .sw(sw), .dip_sw(dip_sw),
        .led(led_p), .seg0(seg0_p), .seg1(seg1_p), .seg_sel(sel_p), .trap(trap_p));

    initial begin
        $dumpfile("tb_rv32_demo.vcd");
        $dumpvars(0, tb_rv32_demo);

        repeat (4) @(posedge clk);
        resetn <= 1'b1;

        // Boot completes when mode 2 (dip_sw=2) shows 0x5050 (BCD of 5050).
        dip_sw <= 8'd2; sw <= 8'd0;
        i = 0;
        while (led_p !== 16'h5050 && i < 3000000) begin @(posedge clk); i = i + 1; end
        if (led_p !== 16'h5050) begin
            $display("FAIL: pipeline boot/mode2 timeout, led=%h", led_p); $finish; end
        $display("OK  : pipeline boot done @ ~%0d cycles, mode2 led=%h", i, led_p);

        i = 0;
        while (led_mc !== 16'h5050 && i < 6000000) begin @(posedge clk); i = i + 1; end
        if (led_mc !== 16'h5050) begin
            $display("FAIL: multi-cycle boot/mode2 timeout, led=%h", led_mc); $finish; end
        $display("OK  : multi-cycle boot done @ ~%0d cycles, mode2 led=%h", i, led_mc);

        if (trap_p || trap_mc) begin
            $display("FAIL: a core entered trap (pipe=%b mc=%b)", trap_p, trap_mc); $finish; end

        // ---- mode 0: CAFE -------------------------------------------------
        dip_sw <= 8'd0; sw <= 8'd0; repeat (400) @(posedge clk);
        if (led_p  !== 16'hcafe) begin $display("FAIL: mode0 pipe led=%h exp=cafe", led_p);  $finish; end
        if (led_mc !== 16'hcafe) begin $display("FAIL: mode0 mc led=%h exp=cafe", led_mc); $finish; end
        $display("OK  : mode0 CAFE   pipe=%h mc=%h", led_p, led_mc);

        // ---- mode 1: live mirror {dip_sw,sw}=0x0123 -----------------------
        dip_sw <= 8'd1; sw <= 8'h23; repeat (400) @(posedge clk);
        if (led_p  !== 16'h0123) begin $display("FAIL: mode1 pipe led=%h exp=0123", led_p);  $finish; end
        if (led_mc !== 16'h0123) begin $display("FAIL: mode1 mc led=%h exp=0123", led_mc); $finish; end
        $display("OK  : mode1 mirror pipe=%h mc=%h", led_p, led_mc);

        // ---- mode 2: 5050 -------------------------------------------------
        dip_sw <= 8'd2; sw <= 8'd0; repeat (400) @(posedge clk);
        if (led_p  !== 16'h5050) begin $display("FAIL: mode2 pipe led=%h exp=5050", led_p);  $finish; end
        if (led_mc !== 16'h5050) begin $display("FAIL: mode2 mc led=%h exp=5050", led_mc); $finish; end
        $display("OK  : mode2 5050   pipe=%h mc=%h", led_p, led_mc);

        // ---- modes 3/4/5: report the measured metrics (packed BCD) --------
        dip_sw <= 8'd3; repeat (400) @(posedge clk);
        $display("METRIC cycles :  pipe=%h  mc=%h", led_p, led_mc);
        dip_sw <= 8'd4; repeat (400) @(posedge clk);
        $display("METRIC instret:  pipe=%h  mc=%h", led_p, led_mc);
        dip_sw <= 8'd5; repeat (400) @(posedge clk);
        $display("METRIC CPIx100:  pipe=%h  mc=%h  (e.g. 0119 = 1.19, 0528 = 5.28)", led_p, led_mc);

        $display("PASS: demo firmware verified on both cores");
        $finish;
    end
endmodule
