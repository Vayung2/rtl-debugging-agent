module rob
import rv32i_types::*;
(
    input clk, 
    input rst, 
    input dispatch_2_rob_t dispatch_2_rob,  //input from dispatch stage to allocate an entry in rob, 
    input common_data_bus_t common_data_bus,  //input - basically complete signal broadcast to the rob
    input logic commit_ack,    // when rob asks commit stage if the rob head is ready to commit, the commit stage responds back
    output logic [ROB_IDX_WIDTH-1:0] rob_idx_dispatch , // returning the rob index to the dispatch stage after allocation to pass onto next stages
    output logic robfull,                          // sends this is if rob is full 
    output logic robempty,
    output rob2commit_t rob2commit , 

    input lsq2rob_t lsq2robpack , 

    input branchres2rob_t branchres2rob, 
    input branch_flush_t branch_flush, 

    input jumpresrob_t jumpresrob , 

    output rob2frlist_t rob2frlist
); 

  rob_entry_t rob_queue [ROB_SIZE-1:0];  // rob declaration 
  logic [ROB_IDX_WIDTH:0] head; 
  logic [ROB_IDX_WIDTH:0] tail;
  logic [ROB_IDX_WIDTH-1:0] head_index, tail_index;
  
  assign head_index = head[ROB_IDX_WIDTH-1:0];
  assign tail_index = tail[ROB_IDX_WIDTH-1:0];
  
  logic empty; 
  assign empty = (head == tail) ? 1'b1 : 1'b0 ; 

  assign robempty = empty; 
  assign robfull = ((head_index == tail_index) && head[ROB_IDX_WIDTH] != tail[ROB_IDX_WIDTH]) ? 1'b1 :1'b0;

 

  always_ff @(posedge clk) begin
    if(rst) begin
        head <= '0;
        tail <= '0;
        //rob_idx_dispatch <= '0;

    end
    // else if (branch_flush.valid && branch_flush.branch_taken) begin


     

    // end 
    else begin 


        if(commit_ack && !empty) begin 
            head <= head + 4'd1;
            rob_queue[head_index] <= '0;
            
        end



        if (branch_flush.valid && branch_flush.branch_taken) begin
           // tail <= head;  // Reset tail to current head


            if (commit_ack && !empty) begin
                tail <= head + 4'd1;  
            end else begin
                tail <= head;         
           end
            
            // Clear all entries
            for(integer i = 0; i < ROB_SIZE; i++) begin
                rob_queue[i] <= '0;
            end
        end
        else if(dispatch_2_rob.alloc_en == 1'b1 && !robfull) begin
            rob_queue[tail_index].valid <= 1'b1; 
            rob_queue[tail_index].opcode <= dispatch_2_rob.opcode; 
            rob_queue[tail_index].pc <= dispatch_2_rob.pc; 

            rob_queue[tail_index].branch <= dispatch_2_rob.branch;
            rob_queue[tail_index].branch_taken <= dispatch_2_rob.branch_taken ; 
            rob_queue[tail_index].branchtg_addr <= dispatch_2_rob.branchtg_addr ; 

            rob_queue[tail_index].jump <= dispatch_2_rob.jump ; 

            rob_queue[tail_index].exception <= 1'b0;
            rob_queue[tail_index].arf_rs1 <= dispatch_2_rob.arf_rs1;
            rob_queue[tail_index].arf_rs2 <= dispatch_2_rob.arf_rs2;
            rob_queue[tail_index].instruction <= dispatch_2_rob.instruction;

            rob_queue[tail_index].is_load <= dispatch_2_rob.is_load;
            rob_queue[tail_index].is_store <= dispatch_2_rob.is_store;

            rob_queue[tail_index].dmem_addr <= dispatch_2_rob.dmem_addr;
            rob_queue[tail_index].dmem_rmask <= dispatch_2_rob.dmem_rmask;
            rob_queue[tail_index].dmem_wmask <= dispatch_2_rob.dmem_wmask;
            rob_queue[tail_index].dmem_wdata <= dispatch_2_rob.dmem_wdata;


            rob_queue[tail_index].branchfrlist_checpt <= dispatch_2_rob.freelist_head_checkpoint; // useful when restoring free for mispredict
            rob_queue[tail_index].branchtail_checpt <= dispatch_2_rob.freelist_tail_checkpoint;

             rob_queue[tail_index].freelistcount <= dispatch_2_rob.freelistcount ; 
            




            // rob_idx_dispatch <= tail_index; 
            tail <= tail + 4'd1;

            if((dispatch_2_rob.has_rd_check == 1'b1) ) begin
                rob_queue[tail_index].has_rd <= 1'b1; 
                rob_queue[tail_index].arf_rd <= dispatch_2_rob.arf_rd; 
                rob_queue[tail_index].old_phy_rd <= dispatch_2_rob.old_phy_rd; 
                rob_queue[tail_index].new_phy_rd <= dispatch_2_rob.new_phy_rd;
                rob_queue[tail_index].ready2commit <= 1'b0;  // Wait for CDB
            end else begin
                rob_queue[tail_index].has_rd <= 1'b0;
                rob_queue[tail_index].arf_rd <= '0;
                rob_queue[tail_index].old_phy_rd <= '0;
                rob_queue[tail_index].new_phy_rd <= '0;
                if(dispatch_2_rob.branch || dispatch_2_rob.is_store || dispatch_2_rob.jump) begin 
                    rob_queue[tail_index].ready2commit <= 1'b0;
                end else begin 
                    rob_queue[tail_index].ready2commit <= 1'b1;
                end
                
            end
        end

        

        if(common_data_bus.complete && !empty) begin
            rob_queue[common_data_bus.rob_idx].ready2commit <= 1'b1;
        end

        


        // update a load/store rob entry
        if(lsq2robpack.valid) begin 

            if(lsq2robpack.is_load) begin  
                rob_queue[lsq2robpack.rob_idx].is_load <= lsq2robpack.is_load;
                rob_queue[lsq2robpack.rob_idx].dmem_addr <= lsq2robpack.dmem_addr;
                rob_queue[lsq2robpack.rob_idx].dmem_rmask <= lsq2robpack.dmem_rmask;
                
            end else if(lsq2robpack.is_store) begin  
                rob_queue[lsq2robpack.rob_idx].is_store <= lsq2robpack.is_store;
                rob_queue[lsq2robpack.rob_idx].dmem_addr <= lsq2robpack.dmem_addr;
                rob_queue[lsq2robpack.rob_idx].dmem_wmask <= lsq2robpack.dmem_wmask;
                rob_queue[lsq2robpack.rob_idx].dmem_wdata <= lsq2robpack.dmem_wdata;
                rob_queue[lsq2robpack.rob_idx].ready2commit <= 1'b1;
            end
        end



        // branch resolution check 

        if(branchres2rob.valid && rob_queue[branchres2rob.rob_idx].branch) begin 
            if(branchres2rob.cmp_result == 1'b1) begin // set as branch taken
                
                rob_queue[branchres2rob.rob_idx].branch_taken <= 1'b1 ; 

            end
            rob_queue[branchres2rob.rob_idx].ready2commit <= 1'b1;
        end



        if(jumpresrob.valid) begin 

            if(jumpresrob.jalr) begin 
                rob_queue[jumpresrob.rob_idx].branchtg_addr <= (jumpresrob.rs1 + rob_queue[jumpresrob.rob_idx].branchtg_addr) & 32'hFFFFFFFE;  // ← FIX!
                
            end
        end
    end 
end

assign rob_idx_dispatch = tail_index;

  // active logic - feeding the commit stage with the rob head entry info
  always_comb begin
    rob2commit.rob_head_idx = head_index ; 
    rob2commit.commit = rob_queue[head_index].ready2commit ;
    rob2commit.pc = rob_queue[head_index].pc ;
    rob2commit.has_rd = rob_queue[head_index].has_rd ;
    rob2commit.arf_rd = rob_queue[head_index]. arf_rd ;
    rob2commit.new_phy_rd = rob_queue[head_index].new_phy_rd ;
    rob2commit.old_phy_rd = rob_queue[head_index].old_phy_rd ;
    rob2commit.arf_rs1 = rob_queue[head_index].arf_rs1 ;
    rob2commit.arf_rs2 = rob_queue[head_index].arf_rs2 ;


    rob2commit.jump = rob_queue[head_index].jump ; 

    rob2commit.branch = rob_queue[head_index].branch ; 
    rob2commit.branch_taken = rob_queue[head_index].branch_taken ; 
    rob2commit.branchtg_addr  = rob_queue[head_index].branchtg_addr ; 

    
    rob2commit.is_load = rob_queue[head_index].is_load ; 
    rob2commit.is_store = rob_queue[head_index].is_store ; 
    rob2commit.dmem_addr = rob_queue[head_index].dmem_addr ;
    rob2commit.dmem_rmask = rob_queue[head_index].dmem_rmask ; 
    rob2commit.dmem_wmask = rob_queue[head_index].dmem_wmask ;  
    rob2commit.dmem_wdata = rob_queue[head_index].dmem_wdata ; 

    rob2commit.instruction = rob_queue[head_index].instruction ;


    rob2frlist.valid = branch_flush.valid && branch_flush.branch_taken;

    rob2frlist.freelist_head = rob_queue[head_index].branchfrlist_checpt ; 
     rob2frlist.freelist_tail = rob_queue[head_index].branchtail_checpt ; 

     rob2frlist.freelistcount = rob_queue[head_index].freelistcount ; 

     rob2frlist.jump_flush = rob_queue[head_index].jump ; 


     


    

  end

endmodule: rob

