module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_pin,
    output reg  [7:0] rx_data,
    output reg        rx_done
);

    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;  // 10417

    // 状态机
    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_cnt;
    reg        rx_pin_d, rx_pin_dd;
    wire       rx_falling;

    // 检测下降沿 (起始位)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_pin_d  <= 1'b1;
            rx_pin_dd <= 1'b1;
        end else begin
            rx_pin_d  <= rx_pin;
            rx_pin_dd <= rx_pin_d;
        end
    end
    assign rx_falling = rx_pin_dd && !rx_pin_d;

    // 主状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            clk_cnt  <= 16'd0;
            bit_cnt  <= 3'd0;
            rx_data  <= 8'd0;
            rx_done  <= 1'b0;
        end else begin
            rx_done <= 1'b0;  // 默认拉低
            
            case (state)
                IDLE: begin
                    if (rx_falling) begin
                        state   <= START;
                        clk_cnt <= 16'd0;
                    end
                end
                
                START: begin
                    // 采样起始位中间点 (BIT_PERIOD/2)
                    if (clk_cnt == BIT_PERIOD / 2 - 1) begin
                        if (!rx_pin_d) begin  // 确认是低电平
                            state   <= DATA;
                            clk_cnt <= 16'd0;
                            bit_cnt <= 3'd0;
                        end else begin
                            state <= IDLE;  // 干扰，回到空闲
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                DATA: begin
                    // 每个数据位中间采样
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        clk_cnt <= 16'd0;
                        rx_data <= {rx_pin_d, rx_data[7:1]};  // LSB first
                        if (bit_cnt == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                STOP: begin
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        state   <= IDLE;
                        rx_done <= 1'b1;  // 接收完成
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule