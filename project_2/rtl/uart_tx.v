module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       rst_n,
    output reg        tx_pin,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx_busy
);

    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_cnt;
    reg [7:0]  tx_data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            clk_cnt    <= 16'd0;
            bit_cnt    <= 3'd0;
            tx_data_reg<= 8'd0;
            tx_pin     <= 1'b1;  // 空闲高电平
            tx_busy    <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx_pin  <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        state       <= START;
                        tx_data_reg <= tx_data;
                        tx_busy     <= 1'b1;
                        clk_cnt     <= 16'd0;
                    end
                end
                
                START: begin
                    tx_pin <= 1'b0;  // 起始位
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        state   <= DATA;
                        clk_cnt <= 16'd0;
                        bit_cnt <= 3'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                DATA: begin
                    tx_pin <= tx_data_reg[bit_cnt];  // LSB first
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        clk_cnt <= 16'd0;
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
                    tx_pin <= 1'b1;  // 停止位
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        state <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule