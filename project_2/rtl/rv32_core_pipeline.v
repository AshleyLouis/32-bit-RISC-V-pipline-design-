`timescale 1ns / 1ps

module rv32_core_pipeline (
    input  wire        clk,
    input  wire        resetn,

    output wire [31:0] instr_addr,
    input  wire [31:0] instr_rdata,

    output wire        mem_valid,
    input  wire        mem_ready,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_wstrb,
    input  wire [31:0] mem_rdata,

    output reg         trap,
    output wire        retire_valid,
    output wire        mem_wait,
    output reg  [31:0] stall_counter,
    output reg  [31:0] flush_counter
);
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

    reg [31:0] pc;
    assign instr_addr = pc;

    reg        if_id_valid;
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;

    wire [6:0] id_opcode = if_id_instr[6:0];
    wire [4:0] id_rd = if_id_instr[11:7];
    wire [2:0] id_funct3 = if_id_instr[14:12];
    wire [4:0] id_rs1 = if_id_instr[19:15];
    wire [4:0] id_rs2 = if_id_instr[24:20];
    wire [6:0] id_funct7 = if_id_instr[31:25];

    wire [31:0] id_imm_i = {{20{if_id_instr[31]}}, if_id_instr[31:20]};
    wire [31:0] id_imm_s = {{20{if_id_instr[31]}}, if_id_instr[31:25], if_id_instr[11:7]};
    wire [31:0] id_imm_b = {{19{if_id_instr[31]}}, if_id_instr[31], if_id_instr[7], if_id_instr[30:25], if_id_instr[11:8], 1'b0};
    wire [31:0] id_imm_u = {if_id_instr[31:12], 12'b0};
    wire [31:0] id_imm_j = {{11{if_id_instr[31]}}, if_id_instr[31], if_id_instr[19:12], if_id_instr[20], if_id_instr[30:21], 1'b0};

    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;
    wire        rf_we;
    wire [4:0]  rf_waddr;
    wire [31:0] rf_wdata;

    rv32_regfile regfile (
        .clk(clk),
        .resetn(resetn),
        .we(rf_we),
        .waddr(rf_waddr),
        .wdata(rf_wdata),
        .raddr1(id_rs1),
        .raddr2(id_rs2),
        .rdata1(rf_rdata1),
        .rdata2(rf_rdata2)
    );

    reg        id_ex_valid;
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_rs1_data;
    reg [31:0] id_ex_rs2_data;
    reg [31:0] id_ex_imm;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [4:0]  id_ex_rd;
    reg [2:0]  id_ex_funct3;
    reg [3:0]  id_ex_alu_op;
    reg        id_ex_alu_src_imm;
    reg        id_ex_reg_write;
    reg        id_ex_mem_read;
    reg        id_ex_mem_write;
    reg        id_ex_mem_to_reg;
    reg        id_ex_branch;
    reg        id_ex_jump;
    reg        id_ex_jalr;
    reg        id_ex_lui;
    reg        id_ex_auipc;
    reg        id_ex_illegal;

    reg        ex_mem_valid;
    reg [31:0] ex_mem_alu_result;
    reg [31:0] ex_mem_store_data;
    reg [31:0] ex_mem_wb_data;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_write;
    reg        ex_mem_mem_read;
    reg        ex_mem_mem_write;
    reg        ex_mem_mem_to_reg;
    reg        ex_mem_illegal;

    reg        mem_wb_valid;
    reg [31:0] mem_wb_wb_data;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write;
    reg        mem_wb_illegal;

    wire [31:0] id_rs1_value = (mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == id_rs1) ?
            mem_wb_wb_data : rf_rdata1;
    wire [31:0] id_rs2_value = (mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == id_rs2) ?
            mem_wb_wb_data : rf_rdata2;

    assign rf_we = mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 5'd0;
    assign rf_waddr = mem_wb_rd;
    assign rf_wdata = mem_wb_wb_data;
    assign retire_valid = mem_wb_valid && !mem_wb_illegal;

    assign mem_valid = ex_mem_valid && (ex_mem_mem_read || ex_mem_mem_write);
    assign mem_addr = ex_mem_alu_result;
    assign mem_wdata = ex_mem_store_data;
    assign mem_wstrb = (ex_mem_valid && ex_mem_mem_write) ? 4'b1111 : 4'b0000;
    assign mem_wait = mem_valid && !mem_ready;

    wire id_uses_rs1 = if_id_valid && (id_opcode == OPCODE_IMM || id_opcode == OPCODE_REG ||
            id_opcode == OPCODE_LOAD || id_opcode == OPCODE_STORE ||
            id_opcode == OPCODE_BRANCH || id_opcode == OPCODE_JALR);
    wire id_uses_rs2 = if_id_valid && (id_opcode == OPCODE_REG ||
            id_opcode == OPCODE_STORE || id_opcode == OPCODE_BRANCH);
    wire load_use_hazard = id_ex_valid && id_ex_mem_read && id_ex_rd != 5'd0 &&
            ((id_uses_rs1 && id_rs1 == id_ex_rd) || (id_uses_rs2 && id_rs2 == id_ex_rd));

    function branch_taken;
        input [2:0] f3;
        input [31:0] a;
        input [31:0] b;
        begin
            case (f3)
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

    reg [3:0]  dec_alu_op;
    reg [31:0] dec_imm;
    reg        dec_alu_src_imm;
    reg        dec_reg_write;
    reg        dec_mem_read;
    reg        dec_mem_write;
    reg        dec_mem_to_reg;
    reg        dec_branch;
    reg        dec_jump;
    reg        dec_jalr;
    reg        dec_lui;
    reg        dec_auipc;
    reg        dec_illegal;

    always @* begin
        dec_alu_op = ALU_ADD;
        dec_imm = id_imm_i;
        dec_alu_src_imm = 1'b0;
        dec_reg_write = 1'b0;
        dec_mem_read = 1'b0;
        dec_mem_write = 1'b0;
        dec_mem_to_reg = 1'b0;
        dec_branch = 1'b0;
        dec_jump = 1'b0;
        dec_jalr = 1'b0;
        dec_lui = 1'b0;
        dec_auipc = 1'b0;
        dec_illegal = 1'b0;

        case (id_opcode)
            OPCODE_LUI: begin
                dec_lui = 1'b1;
                dec_imm = id_imm_u;
                dec_reg_write = 1'b1;
            end
            OPCODE_AUIPC: begin
                dec_auipc = 1'b1;
                dec_imm = id_imm_u;
                dec_reg_write = 1'b1;
            end
            OPCODE_JAL: begin
                dec_jump = 1'b1;
                dec_imm = id_imm_j;
                dec_reg_write = 1'b1;
            end
            OPCODE_JALR: begin
                dec_jump = 1'b1;
                dec_jalr = 1'b1;
                dec_imm = id_imm_i;
                dec_reg_write = 1'b1;
                dec_illegal = (id_funct3 != 3'b000);
            end
            OPCODE_BRANCH: begin
                dec_branch = 1'b1;
                dec_imm = id_imm_b;
            end
            OPCODE_LOAD: begin
                dec_alu_src_imm = 1'b1;
                dec_mem_read = 1'b1;
                dec_mem_to_reg = 1'b1;
                dec_reg_write = 1'b1;
                dec_imm = id_imm_i;
                dec_illegal = (id_funct3 != 3'b010);
            end
            OPCODE_STORE: begin
                dec_alu_src_imm = 1'b1;
                dec_mem_write = 1'b1;
                dec_imm = id_imm_s;
                dec_illegal = (id_funct3 != 3'b010);
            end
            OPCODE_IMM: begin
                dec_alu_src_imm = 1'b1;
                dec_reg_write = 1'b1;
                dec_imm = id_imm_i;
                case (id_funct3)
                    3'b000: dec_alu_op = ALU_ADD;
                    3'b001: dec_alu_op = ALU_SLL;
                    3'b010: dec_alu_op = ALU_SLT;
                    3'b011: dec_alu_op = ALU_SLTU;
                    3'b100: dec_alu_op = ALU_XOR;
                    3'b101: dec_alu_op = id_funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: dec_alu_op = ALU_OR;
                    3'b111: dec_alu_op = ALU_AND;
                    default: dec_alu_op = ALU_ADD;
                endcase
                dec_illegal = !valid_imm_alu(id_funct3, id_funct7);
            end
            OPCODE_REG: begin
                dec_reg_write = 1'b1;
                case (id_funct3)
                    3'b000: dec_alu_op = id_funct7[5] ? ALU_SUB : ALU_ADD;
                    3'b001: dec_alu_op = ALU_SLL;
                    3'b010: dec_alu_op = ALU_SLT;
                    3'b011: dec_alu_op = ALU_SLTU;
                    3'b100: dec_alu_op = ALU_XOR;
                    3'b101: dec_alu_op = id_funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: dec_alu_op = ALU_OR;
                    3'b111: dec_alu_op = ALU_AND;
                    default: dec_alu_op = ALU_ADD;
                endcase
                dec_illegal = !valid_reg_alu(id_funct3, id_funct7);
            end
            default: begin
                dec_illegal = 1'b1;
            end
        endcase
    end

    wire [31:0] ex_rs1_fwd = (ex_mem_valid && ex_mem_reg_write && ex_mem_rd != 5'd0 && ex_mem_rd == id_ex_rs1 && !ex_mem_mem_to_reg) ? ex_mem_wb_data :
                             (mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == id_ex_rs1) ? mem_wb_wb_data :
                             id_ex_rs1_data;
    wire [31:0] ex_rs2_fwd = (ex_mem_valid && ex_mem_reg_write && ex_mem_rd != 5'd0 && ex_mem_rd == id_ex_rs2 && !ex_mem_mem_to_reg) ? ex_mem_wb_data :
                             (mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == id_ex_rs2) ? mem_wb_wb_data :
                             id_ex_rs2_data;
    wire [31:0] ex_alu_b = id_ex_alu_src_imm ? id_ex_imm : ex_rs2_fwd;
    wire [31:0] ex_alu_y;

    rv32_alu alu (
        .op(id_ex_alu_op),
        .a(ex_rs1_fwd),
        .b(ex_alu_b),
        .y(ex_alu_y)
    );

    wire ex_branch_taken = id_ex_valid && !id_ex_illegal &&
            ((id_ex_branch && branch_taken(id_ex_funct3, ex_rs1_fwd, ex_rs2_fwd)) || id_ex_jump);
    wire [31:0] ex_branch_target = id_ex_jalr ? ((ex_rs1_fwd + id_ex_imm) & 32'hffff_fffe) :
            (id_ex_pc + id_ex_imm);
    wire [31:0] ex_result = id_ex_lui ? id_ex_imm :
            id_ex_auipc ? (id_ex_pc + id_ex_imm) :
            id_ex_jump ? (id_ex_pc + 32'd4) :
            ex_alu_y;

    always @(posedge clk) begin
        if (!resetn) begin
            pc <= 32'h0000_0000;
            if_id_valid <= 1'b0;
            if_id_pc <= 32'h0000_0000;
            if_id_instr <= 32'h0000_0013;
            id_ex_valid <= 1'b0;
            ex_mem_valid <= 1'b0;
            mem_wb_valid <= 1'b0;
            trap <= 1'b0;
            stall_counter <= 32'd0;
            flush_counter <= 32'd0;
        end else begin
            if (mem_wb_valid && mem_wb_illegal)
                trap <= 1'b1;

            mem_wb_valid <= ex_mem_valid;
            mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_illegal <= ex_mem_illegal;
            mem_wb_wb_data <= ex_mem_mem_to_reg ? mem_rdata : ex_mem_wb_data;

            ex_mem_valid <= id_ex_valid;
            ex_mem_alu_result <= ex_result;
            ex_mem_store_data <= ex_rs2_fwd;
            ex_mem_wb_data <= ex_result;
            ex_mem_rd <= id_ex_rd;
            ex_mem_reg_write <= id_ex_reg_write;
            ex_mem_mem_read <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_mem_to_reg <= id_ex_mem_to_reg;
            ex_mem_illegal <= id_ex_illegal;

            if (ex_branch_taken) begin
                pc <= ex_branch_target;
                if_id_valid <= 1'b0;
                id_ex_valid <= 1'b0;
                flush_counter <= flush_counter + 32'd1;
            end else if (load_use_hazard) begin
                id_ex_valid <= 1'b0;
                stall_counter <= stall_counter + 32'd1;
            end else begin
                pc <= pc + 32'd4;
                if_id_valid <= 1'b1;
                if_id_pc <= pc;
                if_id_instr <= instr_rdata;

                id_ex_valid <= if_id_valid;
                id_ex_pc <= if_id_pc;
                id_ex_rs1_data <= id_rs1_value;
                id_ex_rs2_data <= id_rs2_value;
                id_ex_imm <= dec_imm;
                id_ex_rs1 <= id_rs1;
                id_ex_rs2 <= id_rs2;
                id_ex_rd <= id_rd;
                id_ex_funct3 <= id_funct3;
                id_ex_alu_op <= dec_alu_op;
                id_ex_alu_src_imm <= dec_alu_src_imm;
                id_ex_reg_write <= dec_reg_write;
                id_ex_mem_read <= dec_mem_read;
                id_ex_mem_write <= dec_mem_write;
                id_ex_mem_to_reg <= dec_mem_to_reg;
                id_ex_branch <= dec_branch;
                id_ex_jump <= dec_jump;
                id_ex_jalr <= dec_jalr;
                id_ex_lui <= dec_lui;
                id_ex_auipc <= dec_auipc;
                id_ex_illegal <= dec_illegal;
            end
        end
    end
endmodule
