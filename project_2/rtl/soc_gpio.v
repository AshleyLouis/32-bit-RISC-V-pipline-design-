`timescale 1ns / 1ps

module soc_gpio (
    input  wire        clk,
    input  wire        resetn,
    input  wire        valid,
    output reg         ready,
    input  wire [3:0]  addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg  [31:0] rdata,

    input  wire [7:0]  sw,
    input  wire [7:0]  dip_sw,
    output wire [15:0] led,
    output reg  [7:0]  seg0,
    output reg  [7:0]  seg1,
    output reg  [7:0]  seg_sel
);
    reg [15:0] led_reg;
    reg [31:0] display_reg;
    reg [15:0] scan_div;

    assign led = led_reg;

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

    always @(posedge clk) begin
        if (!resetn) begin
            ready <= 1'b0;
            rdata <= 32'h0000_0000;
            led_reg <= 16'h0000;
            display_reg <= 32'h0000_0000;
            scan_div <= 16'h0000;
            seg0 <= 8'h00;
            seg1 <= 8'h00;
            seg_sel <= 8'h00;
        end else begin
            ready <= valid;
            scan_div <= scan_div + 16'd1;

            seg_sel <= 8'b0000_0001 << scan_digit;
            if (scan_digit < 3'd4) begin
                seg0 <= seg_pattern;
                seg1 <= 8'h00;
            end else begin
                seg0 <= 8'h00;
                seg1 <= seg_pattern;
            end

            if (valid) begin
                case (addr[3:2])
                    2'd0: begin
                        rdata <= {16'h0000, led_reg};
                        if (wstrb != 4'b0000)
                            led_reg <= wdata[15:0];
                    end
                    2'd1: begin
                        rdata <= {16'h0000, dip_sw, sw};
                    end
                    2'd2: begin
                        rdata <= display_reg;
                        if (wstrb != 4'b0000)
                            display_reg <= wdata;
                    end
                    2'd3: begin
                        rdata <= 32'h0000_0000;
                    end
                    default: begin
                        rdata <= 32'h0000_0000;
                    end
                endcase
            end
        end
    end
endmodule
