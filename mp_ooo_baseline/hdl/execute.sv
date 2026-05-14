module execute 
import rv32i_types::*;
(
    input logic clk,
    input logic rst,
    input issue2execute_t issue2execute,

    output execute2memory_t execute2mem,

    output branchres2rob_t branchres2rob, 

    output jumpresrob_t jumpresrob, 
    
    
    output logic execute_stall, 
    input logic mem_stall, 

    input branch_flush_t branch_flush 
);

logic route_to_alu;
logic route_to_mul;
logic route_to_div;
logic route_to_cmp;

logic route_to_agu ; 


 logic signed [63:0] mul_ss, mul_su;
    logic        [63:0] mul_uu;

always_comb begin

    route_to_alu = '0;
    route_to_div = '0;
    route_to_mul = '0;
    route_to_cmp = '0;
    route_to_agu = '0 ; 

    if (issue2execute.rs_type == 3'b001) begin // MULTIPLIR
        route_to_mul = '1;
    end else if (issue2execute.rs_type == 3'b010) begin // DVIDER

        route_to_div = '1;
    end else if (issue2execute.rs_type == 3'b011)  begin // ALUOP
        route_to_alu = '1;


    end else if (issue2execute.rs_type == 3'b100) begin // SLT/SLTU and branch instructions 
        route_to_cmp = '1;

    end else if (issue2execute.rs_type == 3'b101) begin // loads and stores 
        route_to_agu = '1;
    end

end


//    typedef enum logic [1:0]  {
//             idle,
//             start,
//             result_available 
//     } state_e;

//     state_e state, next_state;



logic [2:0] aluop;
logic [31:0] alu_a, alu_b;
logic [31:0] alu_result;
logic [31:0] alu_final_result;

always_comb begin

    jumpresrob = '0 ; 
    alu_a = issue2execute.phy_src1_v;

    if(issue2execute.issued_entry.is_jump) begin 

        jumpresrob.valid = 1'b1 ; 
        jumpresrob.rob_idx = issue2execute.issued_entry.rob_idx ; 

        if(issue2execute.issued_entry.opcode == 7'b1100111) begin 
            jumpresrob.jalr = 1'b1 ; 
            jumpresrob.rs1 = issue2execute.phy_src1_v ; 

        end else begin 
             jumpresrob.jal = 1'b1 ; 
             jumpresrob.rs1 = '0 ; 
        end

        alu_a = issue2execute.issued_entry.pc;

    end
    
    if (issue2execute.issued_entry.has_imm && !(issue2execute.issued_entry.is_jump) ) begin

        alu_b = issue2execute.issued_entry.imm;

    end else if(issue2execute.issued_entry.is_jump) begin 

         alu_b = 32'd4 ;   // pc+ 4 for jump 
    end
    
    else begin

        alu_b = issue2execute.phy_src2_v;
    end
end

always_comb begin
    aluop = alu_add;
    
    case (issue2execute.issued_entry.opcode)
        op_lui, op_auipc, op_jal, op_jalr: begin
            aluop = alu_add; 
        end
        op_imm, op_reg: begin
            case (issue2execute.issued_entry.funct3)
                3'b000: begin // ADD/SUB
                    if (issue2execute.issued_entry.opcode == op_reg && issue2execute.issued_entry.funct7[5]) begin
                        aluop = alu_sub;
                    end else begin
                        aluop = alu_add;
                    end
                end
                3'b001: aluop = alu_sll; // SLL/SLLI

                3'b100: aluop = alu_xor; // XOR/XORI
                3'b101: begin // SRL/SRA/SRLI/SRAI
                    if (issue2execute.issued_entry.funct7[5]) begin
                        aluop = alu_sra;
                    end else begin
                        aluop = alu_srl;
                    end
                end
                3'b110: aluop = alu_or;  // OR/ORI

                3'b111: aluop = alu_and; // AND/ANDI
                default: aluop = alu_add;
            endcase
        end
        default: aluop = alu_add;
    endcase
end

alu alu_inst (
    .aluop(aluop),
    .a(alu_a),
    .b(alu_b),
    .aluout(alu_result)
);

always_comb begin
    case (issue2execute.issued_entry.opcode)
        op_lui, op_auipc: begin
            alu_final_result = issue2execute.issued_entry.imm;
        end
        default: begin
            alu_final_result = alu_result;
        end
    endcase
end




// new alu for address generation 


logic [31:0] agu_a, agu_b;
logic [31:0] agu_result;
logic [31:0] agu_final_result;



always_comb begin
    agu_a = issue2execute.phy_src1_v;
    agu_b = issue2execute.issued_entry.imm;

   
end



alu agu_inst (
    .aluop(alu_add),
    .a(agu_a),
    .b(agu_b),
    .aluout(agu_result)
);




assign agu_final_result = agu_result ; 

logic [1:0]addr_offset;
logic [31:0] sb_data, sh_data;

assign addr_offset = agu_result[1:0];



always_comb begin
    execute2mem.agu_result.result = '0;
    execute2mem.agu_result.is_load = '0;
    execute2mem.agu_result.is_store = '0;
    execute2mem.agu_result.dmem_wmask = '0;
    execute2mem.agu_result.dmem_rmask = '0;
    execute2mem.agu_result.dmem_wdata = '0;
    execute2mem.agu_result.dmem_rdata = '0;
    execute2mem.agu_result.store_commited = '0;
    execute2mem.agu_result.phy_rd = issue2execute.issued_entry.phy_dest;
    execute2mem.agu_result.result_ready = route_to_agu;
    execute2mem.agu_result.rob_idx = issue2execute.issued_entry.rob_idx;
    execute2mem.agu_result.has_rd = '0 ; 

    execute2mem.agu_result.loadunsigned = ((issue2execute.issued_entry.funct3 == 3'b101) || (issue2execute.issued_entry.funct3 == 3'b100)) ; 
    sb_data = '0;
    sh_data = '0;


    if (issue2execute.issued_entry.opcode == op_load) begin
        execute2mem.agu_result.is_load = '1;
        execute2mem.agu_result.has_rd = '1;
        execute2mem.agu_result.result = agu_result;
        case (issue2execute.issued_entry.funct3) 

            lw: execute2mem.agu_result.dmem_rmask = 4'b1111;
            lh,lhu: begin 
                execute2mem.agu_result.dmem_rmask = addr_offset[1] ? 4'b1100 : 4'b0011;
            end
            lb, lbu : begin
                if (addr_offset == 2'b00) begin
                    execute2mem.agu_result.dmem_rmask = 4'b0001;
                
                end else if (addr_offset == 2'b01) begin
                    
                    execute2mem.agu_result.dmem_rmask = 4'b0010;

                end else if (addr_offset == 2'b10) begin
                    execute2mem.agu_result.dmem_rmask = 4'b0100;
                

                end else begin
                    execute2mem.agu_result.dmem_rmask = 4'b1000;
                end
            end

            default: execute2mem.agu_result.dmem_rmask = 4'b0000;
        endcase
    end

    if (issue2execute.issued_entry.opcode == op_store) begin
        unique case (addr_offset)
            2'b00: sb_data = {24'b0, issue2execute.phy_src2_v[7:0]};
            2'b01: sb_data = {16'b0, issue2execute.phy_src2_v[7:0], 8'b0};
            2'b10: sb_data = {8'b0, issue2execute.phy_src2_v[7:0], 16'b0};
            2'b11: sb_data = {issue2execute.phy_src2_v[7:0], 24'b0};
        endcase

        sh_data = addr_offset[1] ? {issue2execute.phy_src2_v[15:0], 16'b0} : {16'b0, issue2execute.phy_src2_v[15:0]};

        execute2mem.agu_result.is_store = '1;
        execute2mem.agu_result.has_rd = '0;
        execute2mem.agu_result.result = agu_result;

        case (issue2execute.issued_entry.funct3)
            sw: begin
                execute2mem.agu_result.dmem_wmask = 4'b1111;
                execute2mem.agu_result.dmem_wdata = issue2execute.phy_src2_v;
            end
            sh: begin 
                execute2mem.agu_result.dmem_wmask = addr_offset[1] ? 4'b1100 : 4'b0011;
                execute2mem.agu_result.dmem_wdata = sh_data;
            end
            sb: begin 
                execute2mem.agu_result.dmem_wdata = sb_data;
                if (addr_offset == 2'b00) begin
                    execute2mem.agu_result.dmem_wmask = 4'b0001;
                
                end else if (addr_offset == 2'b01) begin
                    
                    execute2mem.agu_result.dmem_wmask = 4'b0010;
                    

                end else if (addr_offset == 2'b10) begin
                    execute2mem.agu_result.dmem_wmask = 4'b0100;
                

                end else begin
                    execute2mem.agu_result.dmem_wmask = 4'b1000;
                end

            end
            default: begin
                execute2mem.agu_result.dmem_wmask = 4'b0000;
                // execute2mem.agu_result.dmem_rmask = 4'b0000;
                execute2mem.agu_result.dmem_wdata = '0;
            end
        endcase

    end


end































logic [2:0] cmpop;
logic cmpout;
logic [31:0] cmp_result;
logic [31:0] cmp_a, cmp_b;

always_comb begin
    cmp_a = issue2execute.phy_src1_v;
    if (issue2execute.issued_entry.has_imm && !(issue2execute.issued_entry.is_branch)) begin
        cmp_b = issue2execute.issued_entry.imm;
    end else begin
        cmp_b = issue2execute.phy_src2_v;
    end
end

always_comb begin
    cmpop = beq; // default
    
    if (issue2execute.issued_entry.opcode == op_br) begin
        cmpop = issue2execute.issued_entry.funct3;
    end else if ((issue2execute.issued_entry.opcode == op_imm ||  issue2execute.issued_entry.opcode == op_reg) &&  (issue2execute.issued_entry.funct3 == 3'b010 ||  issue2execute.issued_entry.funct3 == 3'b011)) begin
        if (issue2execute.issued_entry.funct3 == 3'b010) begin
            cmpop = blt;  // SLT/SLTI
        end else begin
            cmpop = bltu; // SLTU/SLTIU
        end
    end
end

// Instantiate CMP
cmp cmp_inst (
    .cmpop(cmpop),
    .a(cmp_a),
    .b(cmp_b),
    .cmpout(cmpout)
);

assign cmp_result = {31'b0, cmpout};







logic [ROB_IDX_WIDTH-1:0]rob_idx_q;


always_ff @(posedge clk) begin

    if (rst) begin
        
        rob_idx_q <= '0;

    end else begin

        rob_idx_q <= issue2execute.issued_entry.rob_idx;  

    end


end



always_ff @(posedge clk) begin
    if (rst) begin
        execute2mem.alu_result <= '0;
        execute2mem.cmp_result <= '0;

        branchres2rob <= '0 ; 
    end

    else if (branch_flush.valid && branch_flush.branch_taken) begin
        branchres2rob <= '0;  

         execute2mem.alu_result <= '0;   
        execute2mem.cmp_result <= '0;
    end 
    
    
    
    else begin
        execute2mem.alu_result.result_ready <= route_to_alu;
        execute2mem.alu_result.result <= alu_final_result;
        execute2mem.alu_result.phy_rd <= issue2execute.issued_entry.phy_dest;
        execute2mem.alu_result.rob_idx <= issue2execute.issued_entry.rob_idx;
        execute2mem.alu_result.has_rd <= issue2execute.issued_entry.has_rd;
        execute2mem.alu_result.is_load <= '0;
        execute2mem.alu_result.is_store <= '0;
        execute2mem.alu_result.store_commited <= '0;
        execute2mem.alu_result.dmem_rdata <= '0;
        execute2mem.alu_result.dmem_rmask <= '0;
        execute2mem.alu_result.dmem_wmask <= '0;
        execute2mem.alu_result.dmem_wdata <= '0;

        execute2mem.alu_result.loadunsigned <= '0;

        
        execute2mem.cmp_result.result_ready <= route_to_cmp;
        execute2mem.cmp_result.result <= cmp_result;
        execute2mem.cmp_result.phy_rd <= issue2execute.issued_entry.phy_dest;
        execute2mem.cmp_result.rob_idx <= issue2execute.issued_entry.rob_idx;
        execute2mem.cmp_result.has_rd <= issue2execute.issued_entry.has_rd;
        execute2mem.cmp_result.is_load <= '0;
        execute2mem.cmp_result.is_store <= '0;
        execute2mem.cmp_result.store_commited <= '0;
        execute2mem.cmp_result.dmem_rdata <= '0;
        execute2mem.cmp_result.dmem_rmask <= '0;
        execute2mem.cmp_result.dmem_wmask <= '0;
        execute2mem.cmp_result.dmem_wdata <= '0;
        execute2mem.cmp_result.loadunsigned <= '0;

        if(issue2execute.issued_entry.opcode == op_br) begin 
            branchres2rob.valid <= 1'b1 ; 
            branchres2rob.rob_idx <= issue2execute.issued_entry.rob_idx;
            branchres2rob.cmp_result <= cmp_result[0];

        end

        



    end
end

always_comb begin
    // execute2mem.mul_result.result_ready = mul_pipe[MUL_STAGES].valid;
    // execute2mem.mul_result.result = mul_result;
    // execute2mem.mul_result.phy_rd = mul_pipe[MUL_STAGES].phy_rd;
    // execute2mem.mul_result.rob_idx = mul_pipe[MUL_STAGES].rob_idx;
    // execute2mem.mul_result.has_rd = mul_pipe[MUL_STAGES].has_rd;
    // execute2mem.mul_result.is_load = '0;
    // execute2mem.mul_result.is_store = '0;
    // execute2mem.mul_result.store_commited = '0;
    // execute2mem.mul_result.dmem_rdata = '0;
    // execute2mem.mul_result.dmem_rmask = '0;
    // execute2mem.mul_result.dmem_wmask = '0;
    // execute2mem.mul_result.dmem_wdata = '0;
    // execute2mem.mul_result.loadunsigned = '0;
    //  execute2mem.mul_result = '0;
    // execute2mem.div_result = '0;


    execute2mem.mul_result.result_ready = route_to_mul;
    execute2mem.mul_result.phy_rd       = issue2execute.issued_entry.phy_dest;
    execute2mem.mul_result.rob_idx      = issue2execute.issued_entry.rob_idx;
    execute2mem.mul_result.has_rd       = issue2execute.issued_entry.has_rd;
    execute2mem.mul_result.is_load      = '0;
    execute2mem.mul_result.is_store     = '0;
    execute2mem.mul_result.store_commited = '0;
    execute2mem.mul_result.loadunsigned = '0;
    execute2mem.mul_result.dmem_rdata   = '0;
    execute2mem.mul_result.dmem_rmask   = '0;
    execute2mem.mul_result.dmem_wmask   = '0;
    execute2mem.mul_result.dmem_wdata   = '0;

   
    // logic signed [63:0] mul_ss, mul_su;
    // logic        [63:0] mul_uu;

    assign mul_ss = $signed(issue2execute.phy_src1_v) * $signed(issue2execute.phy_src2_v);
    assign mul_su = $signed({{32{issue2execute.phy_src1_v[31]}}, issue2execute.phy_src1_v}) * $signed({32'b0, issue2execute.phy_src2_v});
    assign mul_uu = {32'b0, issue2execute.phy_src1_v} * {32'b0, issue2execute.phy_src2_v};

    unique case (issue2execute.issued_entry.funct3)
        3'b000: execute2mem.mul_result.result = mul_ss[31:0];
        3'b001: execute2mem.mul_result.result = mul_ss[63:32];
        3'b010: execute2mem.mul_result.result = mul_su[63:32];
        3'b011: execute2mem.mul_result.result = mul_uu[63:32];
        default: execute2mem.mul_result.result = '0;
    endcase

    // DIV
    execute2mem.div_result.result_ready = route_to_div;
    execute2mem.div_result.phy_rd       = issue2execute.issued_entry.phy_dest;
    execute2mem.div_result.rob_idx      = issue2execute.issued_entry.rob_idx;
    execute2mem.div_result.has_rd       = issue2execute.issued_entry.has_rd;
    execute2mem.div_result.is_load      = '0;
    execute2mem.div_result.is_store     = '0;
    execute2mem.div_result.store_commited = '0;
    execute2mem.div_result.loadunsigned = '0;
    execute2mem.div_result.dmem_rdata   = '0;
    execute2mem.div_result.dmem_rmask   = '0;
    execute2mem.div_result.dmem_wmask   = '0;
    execute2mem.div_result.dmem_wdata   = '0;

    unique case (issue2execute.issued_entry.funct3)
        3'b100: // DIV
            execute2mem.div_result.result = (issue2execute.phy_src2_v == '0) ? '1 :
                                            ($signed(issue2execute.phy_src1_v) / $signed(issue2execute.phy_src2_v));
        3'b101: // DIVU
            execute2mem.div_result.result = (issue2execute.phy_src2_v == '0) ? '1 :
                                            (issue2execute.phy_src1_v / issue2execute.phy_src2_v);
        3'b110: // REM
            execute2mem.div_result.result = (issue2execute.phy_src2_v == '0) ? issue2execute.phy_src1_v :
                                            ($signed(issue2execute.phy_src1_v) % $signed(issue2execute.phy_src2_v));
        3'b111: // REMU
            execute2mem.div_result.result = (issue2execute.phy_src2_v == '0) ? issue2execute.phy_src1_v :
                                            (issue2execute.phy_src1_v % issue2execute.phy_src2_v);
        default:
            execute2mem.div_result.result = '0;
    endcase
end



always_comb begin
    execute_stall = 1'b0;

     
    
    if ((route_to_agu && mem_stall)) begin
        execute_stall = 1'b1;
    end
end

endmodule : execute