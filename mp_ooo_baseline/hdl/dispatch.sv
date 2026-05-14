module dispatch 
import rv32i_types::*;
(
    input rename2dispatch_t rename2dispatch,
    input logic [ROB_IDX_WIDTH-1:0] rob_idx_dispatch,
    output dispatch2rs_t dispatch2rs,
    output dispatch_2_rob_t dispatch_2_rob,
    input logic robfull,
   

    input common_data_bus_t  cdb_wakeup, 

    input logic alu_filled, 
    input logic mul_filled, 
    input logic div_filled, 
    input logic cmp_filled, 
    input logic loadstore_filled,

    output dispatch_stall
);

logic [2:0] rs_type;



always_comb begin
  rs_type = 3'b000;
  if ((rename2dispatch.opcode == op_reg) &&
           (rename2dispatch.funct7 == 7'b0000001) &&
           ((rename2dispatch.funct3 == 3'b000) || (rename2dispatch.funct3 == 3'b001) || (rename2dispatch.funct3 == 3'b010) || (rename2dispatch.funct3 == 3'b011) )) begin
    rs_type = 3'b001;
  end

  else if ((rename2dispatch.opcode == op_reg) &&
           (rename2dispatch.funct7 == 7'b0000001) &&
           (rename2dispatch.funct3 == 3'b100 || rename2dispatch.funct3 == 3'b101 || rename2dispatch.funct3 == 3'b110 || rename2dispatch.funct3 == 3'b111 )) begin
    rs_type = 3'b010;
  end

  else if ( ((rename2dispatch.opcode == op_imm) && !(rename2dispatch.funct3 == 3'b010 || rename2dispatch.funct3 == 3'b011) &&  !(rename2dispatch.is_load || rename2dispatch.is_store)) ||
              ((rename2dispatch.opcode == op_reg) &&
              (rename2dispatch.funct7 == 7'b0100000 || rename2dispatch.funct7 == 7'b0000000 ) &&  
              !(rename2dispatch.funct3 == 3'b010 || rename2dispatch.funct3 == 3'b011)) ||
              (rename2dispatch.opcode == op_lui) ||
              (rename2dispatch.opcode == op_auipc)  || (rename2dispatch.opcode == op_jal) || (rename2dispatch.opcode == op_jalr)) begin
      rs_type = 3'b011;
  end
  else if ( ((rename2dispatch.opcode == op_reg) || (rename2dispatch.opcode == op_imm)) &&
       (rename2dispatch.funct3 == 3'b010 || rename2dispatch.funct3 == 3'b011) ) begin
    rs_type = 3'b100; 
  end

  else if (rename2dispatch.is_load || rename2dispatch.is_store) begin
    rs_type = 3'b101; // load n store reservation station
  end

  else if (rename2dispatch.is_branch) begin
    rs_type = 3'b100; // CMP

  end
end


logic rs_full_for_instruction;

always_comb begin
    case (rs_type)
        3'b001: rs_full_for_instruction = mul_filled;  // MUL
        3'b010: rs_full_for_instruction = div_filled;  // DIV
        3'b011: rs_full_for_instruction = alu_filled;  // ALU
        3'b100: rs_full_for_instruction = cmp_filled;  // CMP
        3'b101: rs_full_for_instruction = loadstore_filled ; // loadstore
        default: rs_full_for_instruction = 1'b0;
    endcase
end


assign dispatch_stall = robfull || rs_full_for_instruction;





always_comb begin
    dispatch2rs = '0;
    dispatch_2_rob = '0;
    if (!dispatch_stall && rename2dispatch.valid) begin
        dispatch2rs.valid = 1'b1;
        dispatch2rs.rs_type = rs_type;
        dispatch2rs.pc = rename2dispatch.pc;
        dispatch2rs.opcode = rename2dispatch.opcode;
        dispatch2rs.funct3 = rename2dispatch.funct3 ; 
        dispatch2rs.funct7 = rename2dispatch.funct7 ; 
        dispatch2rs.phy_src1 = rename2dispatch.p_src1;
        dispatch2rs.phy_src2 = rename2dispatch.p_src2;
        
        dispatch2rs.phy_dest = rename2dispatch.new_phy_rd;
        dispatch2rs.rob_idx = rob_idx_dispatch;
        dispatch2rs.has_imm = rename2dispatch.uses_imm;
        dispatch2rs.imm = rename2dispatch.imm;
        dispatch2rs.has_rd = rename2dispatch.has_rd;
        dispatch2rs.is_store = rename2dispatch.is_store ; 
        dispatch2rs.is_load = rename2dispatch.is_load ; 
        dispatch2rs.is_branch = rename2dispatch.is_branch ; 
        dispatch2rs.is_jump =  rename2dispatch.is_jump ;

        dispatch_2_rob.freelist_head_checkpoint = rename2dispatch.freelist_head; // useful for branches
         dispatch_2_rob.freelist_tail_checkpoint = rename2dispatch.freelist_tail;
         dispatch_2_rob.freelistcount = rename2dispatch.freelistcount;


        dispatch_2_rob.alloc_en = 1'b1;
        dispatch_2_rob.opcode = rename2dispatch.opcode;
        dispatch_2_rob.has_rd_check = rename2dispatch.has_rd;
        dispatch_2_rob.old_phy_rd = rename2dispatch.old_phy_rd;
        dispatch_2_rob.new_phy_rd = rename2dispatch.new_phy_rd;
        dispatch_2_rob.pc = rename2dispatch.pc;
        dispatch_2_rob.arf_rd = rename2dispatch.rd_a;
        dispatch_2_rob.instruction = rename2dispatch.instruction ; 
        dispatch_2_rob.arf_rs1 = rename2dispatch.rs1_a ; 
        dispatch_2_rob.arf_rs2 =  rename2dispatch.rs2_a ;
        dispatch_2_rob.branch = rename2dispatch.is_branch ; 

        dispatch_2_rob.jump = rename2dispatch.is_jump ;
        
        //dispatch_2_rob.branch_taken = 1'b0 ; // without branch prediction we always predict not taken for now 
        //dispatch_2_rob.branchtg_addr = rename2dispatch.pc + rename2dispatch.imm ; 
        dispatch_2_rob.is_store = rename2dispatch.is_store ; 
        dispatch_2_rob.is_load = rename2dispatch.is_load ; 

        dispatch_2_rob.dmem_addr = '0 ; // not yet calculated
        dispatch_2_rob.dmem_rmask = '0 ;
        dispatch_2_rob.dmem_wmask = '0 ;
        dispatch_2_rob.dmem_wdata = '0 ;
        dispatch_2_rob.dmem_rdata = '0 ; 


        if((rename2dispatch.is_jump && rename2dispatch.opcode == 7'b1101111) || (rename2dispatch.is_branch)) begin 
          // jal

          dispatch_2_rob.branchtg_addr = rename2dispatch.pc + rename2dispatch.imm ; 

        end else if((rename2dispatch.is_jump && rename2dispatch.opcode == 7'b1100111)) begin 

          dispatch_2_rob.branchtg_addr = rename2dispatch.imm ; ; // need to add rs1


        end



        if((rename2dispatch.is_jump)) begin
          dispatch_2_rob.branch_taken = 1'b1 ; 

        end else if(rename2dispatch.is_branch) begin 

           dispatch_2_rob.branch_taken = 1'b0 ;       
        end
     
    end

    dispatch2rs.phy_src1_ready = rename2dispatch.phy_src1_ready;
    dispatch2rs.phy_src2_ready = rename2dispatch.phy_src2_ready;

    if(cdb_wakeup.complete && cdb_wakeup.has_rd && rename2dispatch.valid) begin 
      if((cdb_wakeup.phy_rd == rename2dispatch.p_src1)) begin 
          dispatch2rs.phy_src1_ready  = 1'b1; 
      end
      if((cdb_wakeup.phy_rd == rename2dispatch.p_src2)) begin 
         dispatch2rs.phy_src2_ready  = 1'b1; 
      end    
  end
end

endmodule: dispatch







