`timescale 1ns / 1ps

module rv32_soc #(
    parameter integer BRAM_WORDS = 8192,
    parameter INIT_FILE = "",
    parameter integer CLK_FREQ = 100_000_000,
    parameter integer BAUD_RATE = 9600
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [7:0]  sw,
    input  wire [7:0]  dip_sw,
    output wire [15:0] led,
    output wire [7:0]  seg0,
    output wire [7:0]  seg1,
    output wire [7:0]  seg_sel,
    input  wire        uart_rx_pin,
    output wire        uart_tx_pin,
    output wire        trap
);
    wire        cpu_mem_valid;
    wire        cpu_mem_ready;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [3:0]  cpu_mem_wstrb;
    wire [31:0] cpu_mem_rdata;
    wire        cpu_retire;
    wire        cpu_mem_wait;

    wire        irq_timer;
    wire        uart_irq;
    wire        irq_external = uart_irq;

    rv32_core_multicycle cpu (
        .clk(clk),
        .resetn(resetn),
        .mem_valid(cpu_mem_valid),
        .mem_ready(cpu_mem_ready),
        .mem_addr(cpu_mem_addr),
        .mem_wdata(cpu_mem_wdata),
        .mem_wstrb(cpu_mem_wstrb),
        .mem_rdata(cpu_mem_rdata),
        .irq_timer(irq_timer),
        .irq_external(irq_external),
        .trap(trap),
        .retire_valid(cpu_retire),
        .mem_wait(cpu_mem_wait)
    );

    wire bram_sel = cpu_mem_valid && (cpu_mem_addr[31:15] == 17'h00000);
    wire gpio_sel = cpu_mem_valid && (cpu_mem_addr[31:4] == 28'h1000000);
    wire perf_sel = cpu_mem_valid && (cpu_mem_addr[31:4] == 28'h1000001);
    wire uart_sel = cpu_mem_valid && (cpu_mem_addr[31:4] == 28'h1000003);
    wire clint_sel = cpu_mem_valid && (cpu_mem_addr[31:4] == 28'h1000004);
    wire irqst_sel = cpu_mem_valid && (cpu_mem_addr[31:4] == 28'h1000005);
    wire unmapped_sel = cpu_mem_valid && !bram_sel && !gpio_sel && !perf_sel &&
                        !uart_sel && !clint_sel && !irqst_sel;

    wire        bram_ready;
    wire [31:0] bram_rdata;

    soc_bram #(
        .WORDS(BRAM_WORDS),
        .INIT_FILE(INIT_FILE)
    ) bram (
        .clk(clk),
        .resetn(resetn),
        .valid(bram_sel),
        .ready(bram_ready),
        .addr(cpu_mem_addr),
        .wdata(cpu_mem_wdata),
        .wstrb(cpu_mem_wstrb),
        .rdata(bram_rdata)
    );

    wire        gpio_ready;
    wire [31:0] gpio_rdata;

    soc_gpio gpio (
        .clk(clk),
        .resetn(resetn),
        .valid(gpio_sel),
        .ready(gpio_ready),
        .addr(cpu_mem_addr[3:0]),
        .wdata(cpu_mem_wdata),
        .wstrb(cpu_mem_wstrb),
        .rdata(gpio_rdata),
        .sw(sw),
        .dip_sw(dip_sw),
        .led(led),
        .seg0(seg0),
        .seg1(seg1),
        .seg_sel(seg_sel)
    );

    reg [63:0] cycle_counter;
    reg [63:0] instret_counter;
    reg [31:0] mem_wait_counter;
    reg        perf_ready;
    reg [31:0] perf_rdata;

    always @(posedge clk) begin
        if (!resetn) begin
            cycle_counter <= 64'd0;
            instret_counter <= 64'd0;
            mem_wait_counter <= 32'd0;
            perf_ready <= 1'b0;
            perf_rdata <= 32'h0000_0000;
        end else begin
            cycle_counter <= cycle_counter + 64'd1;
            if (cpu_retire)
                instret_counter <= instret_counter + 64'd1;
            if (cpu_mem_wait)
                mem_wait_counter <= mem_wait_counter + 32'd1;

            perf_ready <= perf_sel;
            if (perf_sel) begin
                case (cpu_mem_addr[3:2])
                    2'd0: perf_rdata <= cycle_counter[31:0];
                    2'd1: perf_rdata <= instret_counter[31:0];
                    2'd2: perf_rdata <= mem_wait_counter;
                    2'd3: perf_rdata <= {31'd0, trap};
                    default: perf_rdata <= 32'h0000_0000;
                endcase
            end
        end
    end

    // ---- interrupt peripherals (combinational read, ready == select) ------
    wire [31:0] uart_rdata;
    soc_uart #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) uart (
        .clk(clk), .resetn(resetn),
        .valid(uart_sel), .addr(cpu_mem_addr[3:0]),
        .wdata(cpu_mem_wdata), .wstrb(cpu_mem_wstrb), .rdata(uart_rdata),
        .rx_pin(uart_rx_pin), .tx_pin(uart_tx_pin), .irq(uart_irq)
    );

    wire [31:0] clint_rdata;
    soc_clint clint (
        .clk(clk), .resetn(resetn),
        .valid(clint_sel), .addr(cpu_mem_addr[3:0]),
        .wdata(cpu_mem_wdata), .wstrb(cpu_mem_wstrb), .rdata(clint_rdata),
        .irq_timer(irq_timer)
    );

    wire [31:0] irq_status = {30'b0, irq_timer, uart_irq};

    assign cpu_mem_ready = (bram_sel && bram_ready) ||
                           (gpio_sel && gpio_ready) ||
                           (perf_sel && perf_ready) ||
                           uart_sel || clint_sel || irqst_sel ||
                           unmapped_sel;

    assign cpu_mem_rdata = bram_sel ? bram_rdata :
                            gpio_sel ? gpio_rdata :
                            perf_sel ? perf_rdata :
                            uart_sel ? uart_rdata :
                            clint_sel ? clint_rdata :
                            irqst_sel ? irq_status :
                            32'hbad0_add0;
endmodule
