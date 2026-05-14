module id_stage
import rv32i_types::*;
(
    input  logic [31:0] instruction, 
    input  logic  queue_empty, 
    input  logic [31:0] pc_in, // this will come from i queue
    output decode2rename_t decode_out,
   
    output logic  read_queue,      // Connect to queue's read input
    input  logic  rename_stall
);



    // Internal signals for instruction field extraction
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [6:0]  opcode;
    logic [31:0] i_imm;
    logic [31:0] s_imm;
    logic [31:0] b_imm;
    logic [31:0] u_imm;
    logic [31:0] j_imm;
    logic [31:0] auipc_imm;
    logic [4:0]  rs1_s;
    logic [4:0]  rs2_s;
    logic [4:0]  rd_s;

    assign opcode = instruction[6:0];
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];

    assign rd_s  = instruction[11:7];


    assign rs1_s  = instruction[19:15];


    assign rs2_s = (opcode == op_reg || opcode == op_store || opcode == op_br) ? instruction[24:20] : 5'd0;

    assign i_imm = {{21{instruction[31]}}, instruction[30:20]};
    assign s_imm = {{21{instruction[31]}}, instruction[30:25], instruction[11:7]};


    assign b_imm = {{20{instruction[31]}}, instruction[7], instruction[30:25], instruction[11:8], 1'b0};

    assign u_imm = {instruction[31:12], 12'h000};
    
    assign j_imm = {{12{instruction[31]}}, instruction[19:12], instruction[20], instruction[30:21], 1'b0};
    assign auipc_imm = u_imm + pc_in;

    assign read_queue = !queue_empty && !rename_stall; 


    always_comb begin
        // Default values
        decode_out = '0;
        
        if (read_queue) begin
            decode_out.valid = 1'b1;
            decode_out.pc = pc_in;
            decode_out.instruction = instruction ; 
            decode_out.opcode = opcode;
            decode_out.funct3 = funct3;
            decode_out.funct7 = funct7;
            decode_out.rs1_a = rs1_s;
            decode_out.rs2_a = rs2_s;
            decode_out.rd_a = rd_s;
            
            decode_out.has_rd = ((opcode == op_lui) || (opcode == op_auipc) || (opcode == op_jal) || (opcode == op_jalr) || (opcode == op_load) || (opcode == op_imm) || (opcode == op_reg)) && (rd_s != 5'b0);
            
            decode_out.is_alu_op = (opcode == op_imm) || (opcode == op_reg && funct7 != 7'b0000001) || (opcode == op_lui) || (opcode == op_auipc);
            
            decode_out.is_mul = (opcode == op_reg) && (funct7 == 7'b0000001) && (funct3[2] == 1'b0);
            
            decode_out.is_div = (opcode == op_reg) && (funct7 == 7'b0000001) && (funct3[2] == 1'b1);
            
            decode_out.is_load = (opcode == op_load);
            decode_out.is_store = (opcode == op_store);
            decode_out.is_branch = (opcode == op_br);
            decode_out.is_auipc = (opcode == op_auipc);
            decode_out.is_jal = (opcode == op_jal);
            decode_out.is_jalr = (opcode == op_jalr);

            decode_out.uses_imm = (opcode == op_imm) ||  (opcode == op_load) ||  (opcode == op_store) || (opcode == op_lui) || (opcode == op_auipc) || (opcode == op_jalr) || (opcode == op_jal) ||  (opcode == op_br);
            case(opcode)
                op_lui:  decode_out.imm = u_imm;
                op_load : decode_out.imm = i_imm; // for load
                op_auipc : decode_out.imm =  auipc_imm;

                op_jal:decode_out.imm = j_imm;

                op_jalr, op_imm: decode_out.imm = i_imm;

                op_store: decode_out.imm = s_imm;

                op_br: decode_out.imm = b_imm;
                default: decode_out.imm = 32'h0;
            endcase
        end
    end

endmodule : id_stage