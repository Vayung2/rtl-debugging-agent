module commit_stage
import rv32i_types::*;
(
    input rob2commit_t rob2commit_in , 
    input logic rob_empty, 
    input logic [31:0] prf_rd_val,

    // input logic clk,
    // input logic rst,

    output commit2arf_t  commit2arf_rd, 
    output commit2frlist_t commtit2frlist_rd, 
    output logic [5:0] prf_commitrd_idx, 
    output logic rob_commit_ack,  // connect to commit_ack on the cpu.sv

    // rvfi output 
    output commit_rvfi_package commit2rvfi, 

        
    output commit2store_t commit2store,
    input store2commit_t store2commit,  


     // ARF reads for RVFI
    output logic [4:0] arf_rs1_read_idx,
    output logic [4:0] arf_rs2_read_idx,
    input logic [31:0] arf_rs1_read_data,
    input logic [31:0] arf_rs2_read_data, 

    output branch_flush_t branch_flush, 

    output commit2rat_t commit2rat 
); 

 logic commitvalid ; 






always_comb begin 
    rob_commit_ack              = 1'b0;
    prf_commitrd_idx            = '0;
    commit2arf_rd               = '0;
    commtit2frlist_rd           = '0;
    commit2rvfi                 = '0;

     arf_rs1_read_idx = '0;
    arf_rs2_read_idx = '0;

    commitvalid = !rob_empty && rob2commit_in.commit;

    commit2store = '0 ; 

    branch_flush = '0 ; 

    commit2rat = '0 ;



    if(commitvalid) begin 

        // special check for store


        if(rob2commit_in.branch || (rob2commit_in.jump)) begin 


            if(rob2commit_in.has_rd && rob2commit_in.jump) begin 
                    prf_commitrd_idx = rob2commit_in.new_phy_rd ; 
                    commit2arf_rd.dest_arch_reg = rob2commit_in.arf_rd ; 
                    commit2arf_rd.dest_arch_value = prf_rd_val ; 
                    commit2arf_rd.wr_enable = 1'b1 ; 

                    commit2rat.commit_update = 1'b1;
                    commit2rat.commit_rd_idx = rob2commit_in.arf_rd;
                    commit2rat.commit_phy_rd = rob2commit_in.new_phy_rd ; 
                end

            if(rob2commit_in.has_rd && rob2commit_in.jump) begin 
                    commtit2frlist_rd.free_en = 1'b1 ; 
                    commtit2frlist_rd.old_phy_rd = rob2commit_in.old_phy_rd ; 
                end
            
           

            if(rob2commit_in.branch_taken || rob2commit_in.jump) begin 
                branch_flush.valid = 1'b1 ; 
                branch_flush.rob_idx = rob2commit_in.rob_head_idx ; 
                branch_flush.branch_taken = 1'b1 ;
                branch_flush.branchtg_addr  = rob2commit_in.branchtg_addr ; 

                 branch_flush.jump = 1'b0 ; 
                branch_flush.commitrd = '0 ; 

                if(rob2commit_in.jump) begin 
                    branch_flush.jump = 1'b1 ; 
                    branch_flush.commitrd = rob2commit_in.new_phy_rd ; 
                end
            end


            rob_commit_ack = 1'b1 ; 


            commit2rvfi.valid = 1'b1;
            commit2rvfi.inst = rob2commit_in.instruction;
            commit2rvfi.rs1_addr = rob2commit_in.arf_rs1;
            commit2rvfi.rs2_addr = rob2commit_in.arf_rs2;

            commit2rvfi.rd_addr = rob2commit_in.jump ? rob2commit_in.arf_rd : 5'b0 ;  
            commit2rvfi.rd_wdata = rob2commit_in.jump ? prf_rd_val : 32'b0 ; ;  
            commit2rvfi.pc_rdata = rob2commit_in.pc;
            // commit2rvfi.pc_wdata = rob2commit_in.branch_taken ? 
            //                     rob2commit_in.branchtg_addr : 
            //                     (rob2commit_in.pc + 4);


            if(rob2commit_in.jump) begin
                commit2rvfi.pc_wdata = rob2commit_in.branchtg_addr;
            end else begin
                    commit2rvfi.pc_wdata = rob2commit_in.branch_taken ? 
                            rob2commit_in.branchtg_addr : 
                            (rob2commit_in.pc + 4);
                end



            
            // Read ARF for source values
            arf_rs1_read_idx = rob2commit_in.arf_rs1;
            arf_rs2_read_idx = rob2commit_in.arf_rs2;
            commit2rvfi.rs1_rdata = arf_rs1_read_data;
            commit2rvfi.rs2_rdata = arf_rs2_read_data;
            
            // No memory access
            commit2rvfi.mem_addr = 32'b0;
            commit2rvfi.mem_rmask = 4'b0;
            commit2rvfi.mem_wmask = 4'b0;
            commit2rvfi.mem_rdata = 32'b0;
            commit2rvfi.mem_wdata = 32'b0;


        end

        else if(rob2commit_in.is_store) begin 

             commit2store.valid = 1'b1;
            commit2store.rob_idx = rob2commit_in.rob_head_idx;
            
           
            if (store2commit.store_ack && (store2commit.rob_idx == rob2commit_in.rob_head_idx)) begin
                
                rob_commit_ack = 1'b1;
                
                // Free old physical register (stores don't have rd, but might have old mapping)
                if (rob2commit_in.has_rd) begin
                    commtit2frlist_rd.free_en = 1'b1;
                    commtit2frlist_rd.old_phy_rd = rob2commit_in.old_phy_rd;
                end
                
                // RVFI for store
                commit2rvfi.valid = 1'b1;
                commit2rvfi.inst = rob2commit_in.instruction;
                commit2rvfi.rs1_addr = rob2commit_in.arf_rs1;
                commit2rvfi.rs2_addr = rob2commit_in.arf_rs2;
                commit2rvfi.rd_addr = rob2commit_in.arf_rd;
                commit2rvfi.rd_wdata = 32'b0;  // Stores don't write rd
                commit2rvfi.pc_rdata = rob2commit_in.pc;
                commit2rvfi.pc_wdata = rob2commit_in.pc + 4;
                
                arf_rs1_read_idx = rob2commit_in.arf_rs1;
                arf_rs2_read_idx = rob2commit_in.arf_rs2;
                commit2rvfi.rs1_rdata = arf_rs1_read_data;
                commit2rvfi.rs2_rdata = arf_rs2_read_data;
                
               
                commit2rvfi.mem_addr = rob2commit_in.dmem_addr;  
                commit2rvfi.mem_wmask = rob2commit_in.dmem_wmask;  
                commit2rvfi.mem_wdata = rob2commit_in.dmem_wdata; 

                commit2rvfi.mem_rmask = 4'b0;

                commit2rvfi.mem_rdata = 32'b0;
            end





        end


         // load instruction 
        else if(rob2commit_in.is_load) begin 


                if(rob2commit_in.has_rd) begin 
                    prf_commitrd_idx = rob2commit_in.new_phy_rd ; 
                    commit2arf_rd.dest_arch_reg = rob2commit_in.arf_rd ; 
                    commit2arf_rd.dest_arch_value = prf_rd_val ; 
                    commit2arf_rd.wr_enable = 1'b1 ; 
                end

                if(rob2commit_in.has_rd) begin 
                    commtit2frlist_rd.free_en = 1'b1 ; 
                    commtit2frlist_rd.old_phy_rd = rob2commit_in.old_phy_rd ; 
                end
                rob_commit_ack = 1'b1 ; 



                commit2rvfi.valid = 1'b1;
                commit2rvfi.inst = rob2commit_in.instruction;
                commit2rvfi.rs1_addr = rob2commit_in.arf_rs1;
                commit2rvfi.rs2_addr = rob2commit_in.arf_rs2;
                commit2rvfi.rd_addr = rob2commit_in.arf_rd;
                commit2rvfi.rd_wdata = rob2commit_in.has_rd ? prf_rd_val : 32'b0;
                commit2rvfi.pc_rdata = rob2commit_in.pc;
                commit2rvfi.pc_wdata = rob2commit_in.pc + 4;  // Sequential for now
                
                // Read ARF for source values
                arf_rs1_read_idx = rob2commit_in.arf_rs1;
                arf_rs2_read_idx = rob2commit_in.arf_rs2;
                commit2rvfi.rs1_rdata = arf_rs1_read_data;
                commit2rvfi.rs2_rdata = arf_rs2_read_data;
                
               
                commit2rvfi.mem_addr =  rob2commit_in.dmem_addr;
                commit2rvfi.mem_rmask =  rob2commit_in.dmem_rmask;
                commit2rvfi.mem_wmask = 4'b0;
               // commit2rvfi.mem_rdata = rob2commit_in.has_rd ? prf_rd_val : 32'b0;

               case (rob2commit_in.dmem_rmask)
                    4'b0001: commit2rvfi.mem_rdata = {24'b0, prf_rd_val[7:0]};           // Byte at [7:0]
                    4'b0010: commit2rvfi.mem_rdata = {16'b0, prf_rd_val[7:0], 8'b0};     // Byte at [15:8]
                    4'b0100: commit2rvfi.mem_rdata = {8'b0, prf_rd_val[7:0], 16'b0};     // Byte at [23:16]
                    4'b1000: commit2rvfi.mem_rdata = {prf_rd_val[7:0], 24'b0};           // Byte at [31:24]
                    4'b0011: commit2rvfi.mem_rdata = {16'b0, prf_rd_val[15:0]};          // Halfword at [15:0]
                    4'b1100: commit2rvfi.mem_rdata = {prf_rd_val[15:0], 16'b0};          // Halfword at [31:16]
                    4'b1111: commit2rvfi.mem_rdata = prf_rd_val;                         // Full word
                    default: commit2rvfi.mem_rdata = prf_rd_val;
                endcase
                commit2rvfi.mem_wdata = 32'b0;


                // update to rat
                commit2rat.commit_update = 1'b1 ; 
                commit2rat.commit_rd_idx = rob2commit_in.arf_rd;
                commit2rat.commit_phy_rd = rob2commit_in.new_phy_rd ; 


        end
        
        else begin 

                if(rob2commit_in.has_rd && rob2commit_in.arf_rd != 5'd0) begin 
                    prf_commitrd_idx = rob2commit_in.new_phy_rd ; 
                    commit2arf_rd.dest_arch_reg = rob2commit_in.arf_rd ; 
                    commit2arf_rd.dest_arch_value = prf_rd_val ; 
                    commit2arf_rd.wr_enable = 1'b1 ; 
                end

                if(rob2commit_in.has_rd && rob2commit_in.arf_rd != 5'd0) begin 
                    commtit2frlist_rd.free_en = 1'b1 ; 
                    commtit2frlist_rd.old_phy_rd = rob2commit_in.old_phy_rd ; 
                end
                rob_commit_ack = 1'b1 ; 



                commit2rvfi.valid = 1'b1;
                commit2rvfi.inst = rob2commit_in.instruction;
                commit2rvfi.rs1_addr = rob2commit_in.arf_rs1;
                commit2rvfi.rs2_addr = rob2commit_in.arf_rs2;
                commit2rvfi.rd_addr = rob2commit_in.arf_rd;
                commit2rvfi.rd_wdata = rob2commit_in.has_rd ? prf_rd_val : 32'b0;
                commit2rvfi.pc_rdata = rob2commit_in.pc;
                commit2rvfi.pc_wdata = rob2commit_in.pc + 4;  // Sequential for now
                
                // Read ARF for source values
                arf_rs1_read_idx = rob2commit_in.arf_rs1;
                arf_rs2_read_idx = rob2commit_in.arf_rs2;
                commit2rvfi.rs1_rdata = arf_rs1_read_data;
                commit2rvfi.rs2_rdata = arf_rs2_read_data;
                
               
                commit2rvfi.mem_addr = 32'b0;
                commit2rvfi.mem_rmask = 4'b0;
                commit2rvfi.mem_wmask = 4'b0;
                commit2rvfi.mem_rdata = 32'b0;
                commit2rvfi.mem_wdata = 32'b0;


                 // update to rat
            if (rob2commit_in.arf_rd != 5'd0) begin
                commit2rat.commit_update = 1'b1 ; 
                commit2rat.commit_rd_idx = rob2commit_in.arf_rd;
                commit2rat.commit_phy_rd = rob2commit_in.new_phy_rd ; 
            end




    end
    end
end

endmodule: commit_stage



