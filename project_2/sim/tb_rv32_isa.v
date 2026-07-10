`timescale 1ns / 1ps

module tb_rv32_isa;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg [7:0] sw = 8'ha5;
    reg [7:0] dip_sw = 8'h5a;
    wire [15:0] led;
    wire [7:0] seg0;
    wire [7:0] seg1;
    wire [7:0] seg_sel;
    wire trap;

    integer cycle;

    always #5 clk = ~clk;

    rv32_soc #(
        .BRAM_WORDS(256),
        .INIT_FILE("programs/isa_selftest.hex")
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
        $dumpfile("tb_rv32_isa.vcd");
        $dumpvars(0, tb_rv32_isa);

        repeat (4) @(posedge clk);
        resetn <= 1'b1;

        for (cycle = 0; cycle < 1000; cycle = cycle + 1) begin
            @(posedge clk);

            if (trap) begin
                $display("FAIL: CPU entered trap at cycle %0d pc=%h instr=%h", cycle, dut.cpu.pc, dut.cpu.instr);
                $finish;
            end

            if (led == 16'hdead) begin
                $display("FAIL: ISA self-test wrote failure code at cycle %0d pc=%h instr=%h", cycle, dut.cpu.pc, dut.cpu.instr);
                $finish;
            end

            if (led == 16'hcafe) begin
                $display("PASS: RV32 ISA/GPIO self-test, cycles=%0d instret=%0d mem_wait=%0d",
                         dut.cycle_counter[31:0],
                         dut.instret_counter[31:0],
                         dut.mem_wait_counter);
                $finish;
            end
        end

        $display("FAIL: timeout, led=%h pc=%h instr=%h state=%0d",
                 led, dut.cpu.pc, dut.cpu.instr, dut.cpu.state);
        $finish;
    end
endmodule
