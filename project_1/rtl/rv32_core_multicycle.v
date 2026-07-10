`timescale 1ns / 1ps

module rv32_core_multicycle (
    input  wire        clk,
    input  wire        resetn,

    output wire        mem_valid,
    input  wire        mem_ready,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_wstrb,
    input  wire [31:0] mem_rdata,

    output reg         trap,
    output wire        retire_valid,
    output wire        mem_wait
);
    localparam S_FETCH  = 3'd0;
    localparam S_DECODE = 3'd1;
    localparam S_EXEC   = 3'd2;
    localparam S_MEM    = 3'd3;
    localparam S_WB     = 3'd4;
    localparam S_TRAP   = 3'd5;

    localparam OPCODE_LUI    = 7'b0110111;
    localparam OPCODE_AUIPC  = 7'b0010111;
    localparam OPCODE_JAL    = 7'b1101111;
    localparam OPCODE_JALR   = 7'b1100111;
    localparam OPCODE_BRANCH = 7'b1100011;
    localparam OPCODE_LOAD   = 7'b0000011;
    localparam OPCODE_STORE  = 7'b0100011;
    localparam OPCODE_IMM    = 7'b0010011;
    localparam OPCODE_REG    = 7'b0110011;

    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_AND  = 4'd2;
    localparam ALU_OR   = 4'd3;
    localparam ALU_XOR  = 4'd4;
    localparam ALU_SLL  = 4'd5;
    localparam ALU_SRL  = 4'd6;
    localparam ALU_SRA  = 4'd7;
    localparam ALU_SLT  = 4'd8;
    localparam ALU_SLTU = 4'd9;

    reg [2:0]  state;
    reg [31:0] pc;
    reg [31:0] instr;

    reg [31:0] mem_addr_q;
    reg [31:0] mem_wdata_q;
    reg [3:0]  mem_wstrb_q;

    reg [4:0]  wb_rd;
    reg [31:0] wb_data;
    reg        wb_we;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    wire [4:0] rd     = instr[11:7];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    wire [31:0] rs1_rdata;
    wire [31:0] rs2_rdata;
    wire        rf_we = (state == S_WB) && wb_we;
    wire [31:0] load_addr = rs1_rdata + imm_i;
    wire [31:0] store_addr = rs1_rdata + imm_s;

    rv32_regfile regfile (
        .clk(clk),
        .resetn(resetn),
        .we(rf_we),
        .waddr(wb_rd),
        .wdata(wb_data),
        .raddr1(rs1),
        .raddr2(rs2),
        .rdata1(rs1_rdata),
        .rdata2(rs2_rdata)
    );

    reg [3:0] alu_op;
    reg [31:0] alu_b;
    wire [31:0] alu_y;

    rv32_alu alu (
        .op(alu_op),
        .a(rs1_rdata),
        .b(alu_b),
        .y(alu_y)
    );

    assign mem_valid = (state == S_FETCH) || (state == S_MEM);
    assign mem_addr  = (state == S_FETCH) ? pc : mem_addr_q;
    assign mem_wdata = (state == S_MEM) ? mem_wdata_q : 32'h0000_0000;
    assign mem_wstrb = (state == S_MEM) ? mem_wstrb_q : 4'b0000;

    assign retire_valid = (state == S_WB);
    assign mem_wait = mem_valid && !mem_ready;

    always @* begin
        alu_op = ALU_ADD;
        alu_b = (opcode == OPCODE_REG) ? rs2_rdata : imm_i;

        if (opcode == OPCODE_REG) begin
            case (funct3)
                3'b000: alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                3'b001: alu_op = ALU_SLL;
                3'b010: alu_op = ALU_SLT;
                3'b011: alu_op = ALU_SLTU;
                3'b100: alu_op = ALU_XOR;
                3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                3'b110: alu_op = ALU_OR;
                3'b111: alu_op = ALU_AND;
                default: alu_op = ALU_ADD;
            endcase
        end else if (opcode == OPCODE_IMM) begin
            case (funct3)
                3'b000: alu_op = ALU_ADD;
                3'b001: alu_op = ALU_SLL;
                3'b010: alu_op = ALU_SLT;
                3'b011: alu_op = ALU_SLTU;
                3'b100: alu_op = ALU_XOR;
                3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                3'b110: alu_op = ALU_OR;
                3'b111: alu_op = ALU_AND;
                default: alu_op = ALU_ADD;
            endcase
        end
    end

    function branch_taken;
        input [2:0]  branch_funct3;
        input [31:0] a;
        input [31:0] b;
        begin
            case (branch_funct3)
                3'b000: branch_taken = (a == b);
                3'b001: branch_taken = (a != b);
                3'b100: branch_taken = ($signed(a) < $signed(b));
                3'b101: branch_taken = ($signed(a) >= $signed(b));
                3'b110: branch_taken = (a < b);
                3'b111: branch_taken = (a >= b);
                default: branch_taken = 1'b0;
            endcase
        end
    endfunction

    function valid_reg_alu;
        input [2:0] f3;
        input [6:0] f7;
        begin
            case (f3)
                3'b000: valid_reg_alu = (f7 == 7'b0000000) || (f7 == 7'b0100000);
                3'b101: valid_reg_alu = (f7 == 7'b0000000) || (f7 == 7'b0100000);
                default: valid_reg_alu = (f7 == 7'b0000000);
            endcase
        end
    endfunction

    function valid_imm_alu;
        input [2:0] f3;
        input [6:0] f7;
        begin
            case (f3)
                3'b001: valid_imm_alu = (f7 == 7'b0000000);
                3'b101: valid_imm_alu = (f7 == 7'b0000000) || (f7 == 7'b0100000);
                default: valid_imm_alu = 1'b1;
            endcase
        end
    endfunction

    task enter_trap;
        begin
            trap <= 1'b1;
            state <= S_TRAP;
            wb_we <= 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_FETCH;
            pc <= 32'h0000_0000;
            instr <= 32'h0000_0013;
            mem_addr_q <= 32'h0000_0000;
            mem_wdata_q <= 32'h0000_0000;
            mem_wstrb_q <= 4'b0000;
            wb_rd <= 5'd0;
            wb_data <= 32'h0000_0000;
            wb_we <= 1'b0;
            trap <= 1'b0;
        end else begin
            case (state)
                S_FETCH: begin
                    wb_we <= 1'b0;
                    if (mem_ready) begin
                        instr <= mem_rdata;
                        state <= S_DECODE;
                    end
                end

                S_DECODE: begin
                    state <= S_EXEC;
                end

                S_EXEC: begin
                    wb_rd <= rd;
                    wb_data <= 32'h0000_0000;
                    wb_we <= 1'b0;
                    mem_wstrb_q <= 4'b0000;

                    case (opcode)
                        OPCODE_LUI: begin
                            wb_data <= imm_u;
                            wb_we <= (rd != 5'd0);
                            pc <= pc + 32'd4;
                            state <= S_WB;
                        end

                        OPCODE_AUIPC: begin
                            wb_data <= pc + imm_u;
                            wb_we <= (rd != 5'd0);
                            pc <= pc + 32'd4;
                            state <= S_WB;
                        end

                        OPCODE_JAL: begin
                            wb_data <= pc + 32'd4;
                            wb_we <= (rd != 5'd0);
                            pc <= pc + imm_j;
                            state <= S_WB;
                        end

                        OPCODE_JALR: begin
                            if (funct3 == 3'b000) begin
                                wb_data <= pc + 32'd4;
                                wb_we <= (rd != 5'd0);
                                pc <= (rs1_rdata + imm_i) & 32'hffff_fffe;
                                state <= S_WB;
                            end else begin
                                enter_trap();
                            end
                        end

                        OPCODE_BRANCH: begin
                            if (branch_taken(funct3, rs1_rdata, rs2_rdata))
                                pc <= pc + imm_b;
                            else
                                pc <= pc + 32'd4;
                            state <= S_WB;
                        end

                        OPCODE_LOAD: begin
                            if (funct3 == 3'b010 && load_addr[1:0] == 2'b00) begin
                                mem_addr_q <= load_addr;
                                mem_wstrb_q <= 4'b0000;
                                wb_rd <= rd;
                                wb_we <= (rd != 5'd0);
                                state <= S_MEM;
                            end else begin
                                enter_trap();
                            end
                        end

                        OPCODE_STORE: begin
                            if (funct3 == 3'b010 && store_addr[1:0] == 2'b00) begin
                                mem_addr_q <= store_addr;
                                mem_wdata_q <= rs2_rdata;
                                mem_wstrb_q <= 4'b1111;
                                wb_we <= 1'b0;
                                state <= S_MEM;
                            end else begin
                                enter_trap();
                            end
                        end

                        OPCODE_IMM: begin
                            if (valid_imm_alu(funct3, funct7)) begin
                                wb_data <= alu_y;
                                wb_we <= (rd != 5'd0);
                                pc <= pc + 32'd4;
                                state <= S_WB;
                            end else begin
                                enter_trap();
                            end
                        end

                        OPCODE_REG: begin
                            if (valid_reg_alu(funct3, funct7)) begin
                                wb_data <= alu_y;
                                wb_we <= (rd != 5'd0);
                                pc <= pc + 32'd4;
                                state <= S_WB;
                            end else begin
                                enter_trap();
                            end
                        end

                        default: begin
                            enter_trap();
                        end
                    endcase
                end

                S_MEM: begin
                    if (mem_ready) begin
                        if (mem_wstrb_q == 4'b0000)
                            wb_data <= mem_rdata;
                        pc <= pc + 32'd4;
                        state <= S_WB;
                    end
                end

                S_WB: begin
                    wb_we <= 1'b0;
                    state <= S_FETCH;
                end

                S_TRAP: begin
                    state <= S_TRAP;
                end

                default: begin
                    enter_trap();
                end
            endcase
        end
    end
endmodule
