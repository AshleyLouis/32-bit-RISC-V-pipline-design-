`timescale 1ns / 1ps

// Memory-mapped UART peripheral: wraps the byte-level uart_rx / uart_tx cores
// and adds a TX data register, an RX holding register with a rx_valid latch,
// status/control registers, and a level interrupt line (irq).
//
// Register map (word offsets from the peripheral base, see rv32_soc*.v):
//   +0x0  TX     : W byte -> start transmit;  R bit0 = tx_busy
//   +0x4  RX     : R -> received byte; reading clears rx_valid
//   +0x8  STATUS : R bit0 = rx_valid, bit1 = tx_busy
//   +0xC  CTRL   : RW bit0 = rx_ie, bit1 = tx_ie   (interrupt enables)
//
// irq = (rx_valid & rx_ie) | (tx_ready & tx_ie), fed to the SoC IRQ aggregator.
module soc_uart #(
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer BAUD_RATE = 9600
) (
    input  wire        clk,
    input  wire        resetn,

    input  wire        valid,      // bus access to this peripheral this cycle
    input  wire [3:0]  addr,       // byte address within the peripheral
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output wire [31:0] rdata,

    input  wire        rx_pin,
    output wire        tx_pin,

    output wire        irq
);
    wire       rst_n = resetn;

    // ---- RX core ----------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_done;
    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx_pin(rx_pin),
        .rx_data(rx_data), .rx_done(rx_done)
    );

    // ---- TX core ----------------------------------------------------------
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
        .clk(clk), .rst_n(rst_n), .tx_pin(tx_pin),
        .tx_data(tx_data), .tx_start(tx_start), .tx_busy(tx_busy)
    );

    // ---- RX holding register + valid latch --------------------------------
    reg [7:0] rx_hold;
    reg       rx_valid;
    reg [1:0] ctrl;              // {tx_ie, rx_ie}
    wire      rx_ie = ctrl[0];
    wire      tx_ie = ctrl[1];

    assign irq = (rx_valid & rx_ie) | (~tx_busy & tx_ie);

    // Combinational read: the bus muxes on the peripheral select, and both the
    // pipeline (samples mem_rdata the same cycle as mem_valid) and multi-cycle
    // (ready == valid) cores expect same-cycle read data.
    assign rdata = (addr[3:2] == 2'd0) ? {31'b0, tx_busy} :
                   (addr[3:2] == 2'd1) ? {24'b0, rx_hold} :
                   (addr[3:2] == 2'd2) ? {30'b0, tx_busy, rx_valid} :
                                         {30'b0, ctrl};

    wire acc_tx   = valid && (addr[3:2] == 2'd0);
    wire acc_rx   = valid && (addr[3:2] == 2'd1);
    wire acc_ctrl = valid && (addr[3:2] == 2'd3);
    wire is_write = (wstrb != 4'b0000);

    always @(posedge clk) begin
        if (!resetn) begin
            tx_data  <= 8'd0;
            tx_start <= 1'b0;
            rx_hold  <= 8'd0;
            rx_valid <= 1'b0;
            ctrl     <= 2'b00;
        end else begin
            tx_start <= 1'b0;               // one-cycle pulse

            // Read clears rx_valid, but a byte arriving this cycle wins (set
            // is evaluated last so it overrides a simultaneous clear).
            if (acc_rx && !is_write)
                rx_valid <= 1'b0;
            if (rx_done) begin
                rx_hold  <= rx_data;
                rx_valid <= 1'b1;
            end

            // ---- other bus side-effects (single-cycle valid pulse) ----
            if (acc_tx && is_write && !tx_busy) begin
                tx_data  <= wdata[7:0];
                tx_start <= 1'b1;
            end
            if (acc_ctrl && is_write)
                ctrl <= wdata[1:0];
        end
    end
endmodule
