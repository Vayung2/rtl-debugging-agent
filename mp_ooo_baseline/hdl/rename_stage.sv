module rename_stage
import rv32i_types::*;
(
    input logic clk, 
    input logic rst, 
    input decode2rename_t decode2rename, 
    input frlist2rename_t frlist2rename, 
    input logic frlist_empty, 


    
    input prf2rename_readybits_t prf2renameready,
    

    output rename2frlist_t rename2frlist,
  
    output rename2dispatch_t rename2dispatch,
    output rename2prf_t rename2prf,

    output logic rename_stall, 
    input logic dispatch_stall, 

    output rename2prf_ready_t rename2prfreadyidx, 

    input commit2rat_t commit2rat, 

    input branch_flush_t branch_flush

);

logic [4:0] read_rs1_idx, read_rs2_idx, read_rs3_idx, write_rd_idx;
logic [5:0] write_phy_rd, rs1_phy_idx, rs2_phy_idx, rs3_phy_idx;
logic wr_enable;
logic stall; 
logic             up_valid;
rename2dispatch_t dispatch_packet_comb;

 logic  [ADDR_BITS-1:0] specrd_idx ; 
logic [PRF_IDX_WIDTH-1:0] specrd_mapping ; 


assign up_valid      = decode2rename.valid;

assign read_rs1_idx = decode2rename.rs1_a; 
// assign read_rs2_idx = decode2rename.uses_imm ? '0: decode2rename.rs2_a; // but does not account for stores

always_comb begin

  read_rs2_idx = '0 ; 
  
  if(decode2rename.is_store || decode2rename.is_branch || (decode2rename.opcode == op_reg)) begin // special check for store and branch which has both store and branch

      read_rs2_idx = decode2rename.rs2_a ; 
  end else if(decode2rename.uses_imm && !(decode2rename.is_store || decode2rename.is_branch || (decode2rename.opcode == op_reg))) begin // i type
      read_rs2_idx = '0 ; 

  end
  
end

assign read_rs3_idx = decode2rename.has_rd ? decode2rename.rd_a : '0; 

assign rename_stall = stall ;


rat rat_rename_inst(
    .clk(clk),
    .rst(rst),
    .read_rs1_idx(read_rs1_idx),        // Read ports
    .read_rs2_idx(read_rs2_idx),
    .read_rs3_idx(read_rs3_idx),
    .rs1_phy_idx(rs1_phy_idx),       // Outputs
    .rs2_phy_idx(rs2_phy_idx),  
    .rs3_phy_idx(rs3_phy_idx),  
    .wr_enable(wr_enable),     // Write port
    .write_phy_rd(write_phy_rd),
    .write_rd_idx(write_rd_idx), 
    .specrd_idx(specrd_idx), 
    .specrd_mapping(specrd_mapping), 
    .commit2rat(commit2rat), 
    .branch_flush(branch_flush)
);

always_comb begin
    // 1 - read rat for source 
    dispatch_packet_comb = '0 ; 

   
    
   
    stall = frlist_empty || (decode2rename.has_rd && !frlist2rename.alloc_valid) || dispatch_stall;
    
    
    dispatch_packet_comb.valid = up_valid && !stall;
    dispatch_packet_comb.pc = decode2rename.pc;
    dispatch_packet_comb.instruction = decode2rename.instruction;
    dispatch_packet_comb.rs1_a = decode2rename.rs1_a;    // 
    dispatch_packet_comb.rs2_a = decode2rename.rs2_a;
    dispatch_packet_comb.opcode = decode2rename.opcode;
    dispatch_packet_comb.funct3 = decode2rename.funct3;
    dispatch_packet_comb.funct7 = decode2rename.funct7;
    dispatch_packet_comb.rd_a = decode2rename.rd_a ; 
    dispatch_packet_comb.p_src1 = rs1_phy_idx;
    
    dispatch_packet_comb.is_load = decode2rename.is_load;
    dispatch_packet_comb.is_store = decode2rename.is_store;
    dispatch_packet_comb.is_branch = decode2rename.is_branch;
    dispatch_packet_comb.is_jump = decode2rename.is_jal ||  decode2rename.is_jalr ;




    
    dispatch_packet_comb.uses_imm = decode2rename.uses_imm;
    if (decode2rename.uses_imm) begin
        dispatch_packet_comb.imm = decode2rename.imm;
        dispatch_packet_comb.p_src2 = (decode2rename.is_store || decode2rename.is_branch) ? rs2_phy_idx : '0;
    end 
    else begin 
        dispatch_packet_comb.p_src2 = rs2_phy_idx; 
        dispatch_packet_comb.imm = '0;
    end

    //2 - get  the free list 
    dispatch_packet_comb.has_rd = decode2rename.has_rd;
    if(decode2rename.has_rd && frlist2rename.alloc_valid) begin 
        dispatch_packet_comb.new_phy_rd = frlist2rename.new_phy_rd; 
        dispatch_packet_comb.old_phy_rd = rs3_phy_idx;  // get the old_phy_rd mapping from rat 

    end

    dispatch_packet_comb.freelist_head = frlist2rename.freelist_head;   // useful for branches
    dispatch_packet_comb.freelist_tail = frlist2rename.freelist_tail;
    dispatch_packet_comb.freelistcount = frlist2rename.freelistcount ; 



    // finally check the prf for src1  and src2 read bits 
    rename2prfreadyidx.prf_rs1_ready = rs1_phy_idx;
    dispatch_packet_comb.phy_src1_ready = (read_rs1_idx == 5'b0) ? 1'b1 : prf2renameready.rs1_ready;  

    if(decode2rename.is_store || decode2rename.is_branch || (decode2rename.opcode == op_reg) ) begin 
      rename2prfreadyidx.prf_rs2_ready = rs2_phy_idx ; 
        dispatch_packet_comb.phy_src2_ready = (read_rs2_idx == 5'b0) ? 1'b1 : prf2renameready.rs2_ready ; 
    end  else begin
            rename2prfreadyidx.prf_rs2_ready = 6'b0;
            dispatch_packet_comb.phy_src2_ready = 1'b1;  // Immediate always ready
    end


    
    rename2dispatch = dispatch_packet_comb;
end


  always_comb begin 
    if (up_valid && !stall && decode2rename.has_rd && frlist2rename.alloc_valid) begin 
      rename2frlist.alloc_ack    = 1'b1;

    end else begin 
      rename2frlist.alloc_ack    = 1'b0;
    end

end

 always_ff @(posedge clk) begin
    if (rst) begin
  
      wr_enable                    <= 1'b0;
      write_rd_idx                 <= '0;
      write_phy_rd                 <= '0;

      specrd_idx <= '0 ; 
      specrd_mapping <= '0 ; 
    end 

    else if (branch_flush.valid && branch_flush.branch_taken) begin
        // Always clear on flush, before checking for new allocations
            wr_enable <= 1'b0;
        write_rd_idx <= '0;
        write_phy_rd <= '0;
        specrd_idx <= '0;
        specrd_mapping <= '0;
    end
    
    
    
    else begin
      // defaults
     
      wr_enable                    <= 1'b0;

      specrd_idx <= '0 ; 
      specrd_mapping <= '0 ; 

      if (up_valid && !stall) begin
        wr_enable   <= decode2rename.has_rd;

        if (decode2rename.has_rd && frlist2rename.alloc_valid) begin
          write_rd_idx                <= decode2rename.rd_a;
          write_phy_rd                <= frlist2rename.new_phy_rd;
        end
      end
      
      if(decode2rename.has_rd && frlist2rename.alloc_valid && dispatch_packet_comb.valid && (dispatch_packet_comb.rd_a !=0)) begin
        specrd_idx <= dispatch_packet_comb.rd_a;
        specrd_mapping <= frlist2rename.new_phy_rd; 
       end



    end
  end


  always_comb begin
  

   rename2prf.alloc_en          = 1'b0;
  rename2prf.prf_rd_alloc_idx   = '0;
  if (up_valid && !stall) begin 
    if (decode2rename.has_rd && frlist2rename.alloc_valid) begin
          rename2prf.alloc_en         = 1'b1;
          rename2prf.prf_rd_alloc_idx = frlist2rename.new_phy_rd;
        end
  end
    
  end


endmodule: rename_stage 

