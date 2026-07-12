`timescale 1ns / 1ps

// CLINT-lite machine timer: a free-running mtime counter and an mtimecmp
// compare register. irq_timer asserts (level) while enabled and mtime >=
// mtimecmp; the ISR clears it by advancing mtimecmp (writing a new deadline).
//
// Register map (word offsets from the peripheral base, see rv32_soc*.v):
//   +0x0  MTIME     : R  low 32 bits of the running counter
//   +0x4  MTIMECMP  : RW compare value; writing clears a pending timer IRQ
//   +0x8  CTRL      : RW bit0 = enable
module soc_clint (
    input  wire        clk,
    input  wire        resetn,

    input  wire        valid,
    input  wire [3:0]  addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output wire [31:0] rdata,

    output wire        irq_timer
);
    reg [31:0] mtime;
    reg [31:0] mtimecmp;
    reg        enable;

    // 32-bit compare is enough for demo cadences at 50 MHz.
    assign irq_timer = enable && (mtime >= mtimecmp);

    // Combinational read (same-cycle for both cores; see soc_uart.v note).
    assign rdata = (addr[3:2] == 2'd0) ? mtime :
                   (addr[3:2] == 2'd1) ? mtimecmp :
                   (addr[3:2] == 2'd2) ? {31'b0, enable} :
                                         32'd0;

    wire is_write = (wstrb != 4'b0000);

    always @(posedge clk) begin
        if (!resetn) begin
            mtime    <= 32'd0;
            mtimecmp <= 32'hFFFF_FFFF;   // no deadline until firmware sets one
            enable   <= 1'b0;
        end else begin
            mtime <= mtime + 32'd1;

            if (valid && is_write) begin
                case (addr[3:2])
                    2'd1: mtimecmp <= wdata;
                    2'd2: enable   <= wdata[0];
                    default: begin end
                endcase
            end
        end
    end
endmodule
