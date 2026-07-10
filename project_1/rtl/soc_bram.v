`timescale 1ns / 1ps

module soc_bram #(
    parameter integer WORDS = 8192,
    parameter INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        valid,
    output reg         ready,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg  [31:0] rdata
);
    integer i;
    reg [31:0] mem [0:WORDS-1];
    wire [31:0] word_addr = addr[31:2];

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'h0000_0013; // addi x0, x0, 0
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (!resetn) begin
            ready <= 1'b0;
            rdata <= 32'h0000_0000;
        end else begin
            ready <= valid;
            if (valid) begin
                rdata <= mem[word_addr];
                if (wstrb[0]) mem[word_addr][7:0]   <= wdata[7:0];
                if (wstrb[1]) mem[word_addr][15:8]  <= wdata[15:8];
                if (wstrb[2]) mem[word_addr][23:16] <= wdata[23:16];
                if (wstrb[3]) mem[word_addr][31:24] <= wdata[31:24];
            end
        end
    end
endmodule
