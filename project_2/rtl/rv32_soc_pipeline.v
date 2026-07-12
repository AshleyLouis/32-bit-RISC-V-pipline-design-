`timescale 1ns / 1ps

module rv32_soc_pipeline #(
    parameter integer BRAM_WORDS = 8192,
    parameter INIT_FILE = "",
    parameter integer CLK_FREQ = 50_000_000,
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
    wire [31:0] instr_addr;
    wire [31:0] instr_rdata;

    wire        cpu_mem_valid;
    wire        cpu_mem_ready;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [3:0]  cpu_mem_wstrb;
    wire [31:0] cpu_mem_rdata;
    wire        cpu_retire;
    wire        cpu_mem_wait;
    wire [31:0] pipe_stalls;
    wire [31:0] pipe_flushes;

    wire        irq_timer;
    wire        uart_irq;
    wire        irq_external = uart_irq;

    rv32_core_pipeline cpu (
        .clk(clk),
        .resetn(resetn),
        .instr_addr(instr_addr),
        .instr_rdata(instr_rdata),
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
        .mem_wait(cpu_mem_wait),
        .stall_counter(pipe_stalls),
        .flush_counter(pipe_flushes)
    );

    wire bram_data_sel = cpu_mem_valid && (cpu_mem_addr[31:15] == 17'h00000);
    wire gpio_sel = cpu_mem_valid && (cpu_mem_addr[31:4] == 28'h1000000);
    // Perf counters occupy 0x1000_0010..0x1000_002F, NON-overlapping with GPIO
    // (0x1000_0000..0x000F). This matches the multi-cycle SoC's map for
    // cycle/instret/mem_wait, so one program reads counters on both cores.
    // (Previously perf_sel was addr[31:5]==0x0800000 = 0x1000_0000..0x001F,
    // which overlapped GPIO and let GPIO shadow every counter but flushes.)
    wire perf_sel = cpu_mem_valid && (cpu_mem_addr[31:4] == 28'h1000001 ||
                                      cpu_mem_addr[31:4] == 28'h1000002);
    // New interrupt-related peripherals (avoid the old perf/gpio overlap):
    wire uart_sel = cpu_mem_valid && (cpu_mem_addr[31:4] == 28'h1000003); // 0x30
    wire clint_sel = cpu_mem_valid && (cpu_mem_addr[31:4] == 28'h1000004); // 0x40
    wire irqst_sel = cpu_mem_valid && (cpu_mem_addr[31:4] == 28'h1000005); // 0x50
    wire unmapped_sel = cpu_mem_valid && !bram_data_sel && !gpio_sel && !perf_sel &&
                        !uart_sel && !clint_sel && !irqst_sel;

    wire        bram_ready;
    wire [31:0] bram_rdata;

    soc_bram_dual #(
        .WORDS(BRAM_WORDS),
        .INIT_FILE(INIT_FILE)
    ) bram (
        .clk(clk),
        .instr_addr(instr_addr),
        .instr_rdata(instr_rdata),
        .data_valid(bram_data_sel),
        .data_ready(bram_ready),
        .data_addr(cpu_mem_addr),
        .data_wdata(cpu_mem_wdata),
        .data_wstrb(cpu_mem_wstrb),
        .data_rdata(bram_rdata)
    );

    reg [15:0] led_reg;
    reg [31:0] display_reg;
    reg [15:0] scan_div;
    reg [7:0] seg0_reg;
    reg [7:0] seg1_reg;
    reg [7:0] seg_sel_reg;

    assign led = led_reg;
    assign seg0 = seg0_reg;
    assign seg1 = seg1_reg;
    assign seg_sel = seg_sel_reg;

    function [7:0] hex_to_seg;
        input [3:0] value;
        begin
            case (value)
                4'h0: hex_to_seg = 8'b0011_1111;
                4'h1: hex_to_seg = 8'b0000_0110;
                4'h2: hex_to_seg = 8'b0101_1011;
                4'h3: hex_to_seg = 8'b0100_1111;
                4'h4: hex_to_seg = 8'b0110_0110;
                4'h5: hex_to_seg = 8'b0110_1101;
                4'h6: hex_to_seg = 8'b0111_1101;
                4'h7: hex_to_seg = 8'b0000_0111;
                4'h8: hex_to_seg = 8'b0111_1111;
                4'h9: hex_to_seg = 8'b0110_1111;
                4'ha: hex_to_seg = 8'b0111_0111;
                4'hb: hex_to_seg = 8'b0111_1100;
                4'hc: hex_to_seg = 8'b0011_1001;
                4'hd: hex_to_seg = 8'b0101_1110;
                4'he: hex_to_seg = 8'b0111_1001;
                4'hf: hex_to_seg = 8'b0111_0001;
                default: hex_to_seg = 8'b0000_0000;
            endcase
        end
    endfunction

    function [3:0] selected_nibble;
        input [31:0] value;
        input [2:0]  digit;
        begin
            case (digit)
                3'd0: selected_nibble = value[3:0];
                3'd1: selected_nibble = value[7:4];
                3'd2: selected_nibble = value[11:8];
                3'd3: selected_nibble = value[15:12];
                3'd4: selected_nibble = value[19:16];
                3'd5: selected_nibble = value[23:20];
                3'd6: selected_nibble = value[27:24];
                3'd7: selected_nibble = value[31:28];
                default: selected_nibble = 4'h0;
            endcase
        end
    endfunction

    wire [2:0] scan_digit = scan_div[15:13];
    wire [7:0] seg_pattern = hex_to_seg(selected_nibble(display_reg, scan_digit));
    wire [31:0] gpio_rdata = (cpu_mem_addr[3:2] == 2'd0) ? {16'h0000, led_reg} :
            (cpu_mem_addr[3:2] == 2'd1) ? {16'h0000, dip_sw, sw} :
            (cpu_mem_addr[3:2] == 2'd2) ? display_reg :
            32'h0000_0000;

    always @(posedge clk) begin
        if (!resetn) begin
            led_reg <= 16'h0000;
            display_reg <= 32'h0000_0000;
            scan_div <= 16'h0000;
            seg0_reg <= 8'h00;
            seg1_reg <= 8'h00;
            seg_sel_reg <= 8'h00;
        end else begin
            scan_div <= scan_div + 16'd1;
            seg_sel_reg <= 8'b0000_0001 << scan_digit;
            if (scan_digit < 3'd4) begin
                seg0_reg <= seg_pattern;
                seg1_reg <= 8'h00;
            end else begin
                seg0_reg <= 8'h00;
                seg1_reg <= seg_pattern;
            end

            if (gpio_sel && cpu_mem_wstrb != 4'b0000) begin
                case (cpu_mem_addr[3:2])
                    2'd0: led_reg <= cpu_mem_wdata[15:0];
                    2'd2: display_reg <= cpu_mem_wdata;
                    default: begin end
                endcase
            end
        end
    end

    reg [63:0] cycle_counter;
    reg [63:0] instret_counter;
    reg [31:0] mem_wait_counter;
    // Word index within 0x1000_0000..0x2F: 0x10->4, 0x14->5, 0x18->6, 0x1C->7,
    // 0x20->8. Addresses 0x10/0x14/0x18 line up with the multi-cycle SoC.
    wire [31:0] perf_rdata = (cpu_mem_addr[5:2] == 4'd4) ? cycle_counter[31:0]   :
            (cpu_mem_addr[5:2] == 4'd5) ? instret_counter[31:0] :
            (cpu_mem_addr[5:2] == 4'd6) ? mem_wait_counter      :
            (cpu_mem_addr[5:2] == 4'd7) ? pipe_stalls           :
            (cpu_mem_addr[5:2] == 4'd8) ? pipe_flushes          :
            32'h0000_0000;

    always @(posedge clk) begin
        if (!resetn) begin
            cycle_counter <= 64'd0;
            instret_counter <= 64'd0;
            mem_wait_counter <= 32'd0;
        end else begin
            cycle_counter <= cycle_counter + 64'd1;
            if (cpu_retire)
                instret_counter <= instret_counter + 64'd1;
            if (cpu_mem_wait)
                mem_wait_counter <= mem_wait_counter + 32'd1;
        end
    end

    // ---- interrupt peripherals --------------------------------------------
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

    // IRQ_STATUS snapshot for the ISR to dispatch external sources.
    wire [31:0] irq_status = {30'b0, irq_timer, uart_irq};

    assign cpu_mem_ready = (bram_data_sel && bram_ready) || gpio_sel || perf_sel ||
            uart_sel || clint_sel || irqst_sel || unmapped_sel;
    assign cpu_mem_rdata = bram_data_sel ? bram_rdata :
            gpio_sel ? gpio_rdata :
            perf_sel ? perf_rdata :
            uart_sel ? uart_rdata :
            clint_sel ? clint_rdata :
            irqst_sel ? irq_status :
            32'hbad0_add0;
endmodule
