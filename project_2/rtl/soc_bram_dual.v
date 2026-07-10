`timescale 1ns / 1ps

module soc_bram_dual #(
    parameter integer WORDS = 8192,
    parameter INIT_FILE = ""
) (
    input  wire        clk,

    input  wire [31:0] instr_addr,
    output wire [31:0] instr_rdata,

    input  wire        data_valid,
    output wire        data_ready,
    input  wire [31:0] data_addr,
    input  wire [31:0] data_wdata,
    input  wire [3:0]  data_wstrb,
    output wire [31:0] data_rdata
);
    integer i;
    reg [31:0] mem [0:WORDS-1];

    wire [31:0] instr_word_addr = instr_addr[31:2];
    wire [31:0] data_word_addr = data_addr[31:2];

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'h0000_0013;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    assign instr_rdata = mem[instr_word_addr];
    assign data_rdata = mem[data_word_addr];
    assign data_ready = data_valid;

    always @(posedge clk) begin
        if (data_valid) begin
            if (data_wstrb[0]) mem[data_word_addr][7:0]   <= data_wdata[7:0];
            if (data_wstrb[1]) mem[data_word_addr][15:8]  <= data_wdata[15:8];
            if (data_wstrb[2]) mem[data_word_addr][23:16] <= data_wdata[23:16];
            if (data_wstrb[3]) mem[data_word_addr][31:24] <= data_wdata[31:24];
        end
    end
endmodule
