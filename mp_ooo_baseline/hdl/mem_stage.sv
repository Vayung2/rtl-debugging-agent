
module mem_stage
import rv32i_types::*;
(

  input execute2memory_t execute2memory, 
  input logic clk, 
  input logic rst, 



  output memory2writeback_t memory2writeback, 

  //d-cache requests
  output logic [ADDR_SIZE-1:0]  dmem_addr , 
  output logic [3:0]  dmem_rmask , 
  output logic [3:0]  dmem_wmask , 
  output logic [31:0]  dmem_wdata , 

  input logic dmem_resp, 
  input logic [31:0] dmem_rdata, 

  input commit2store_t commit2store, 

  output store2commit_t store2commit , 

  output lsq2rob_t lsq2rob, 





  output logic mem_stall, 

  input branch_flush_t branch_flush 

); 




logic lsq_empty ; 
logic lsq_filled  ; 

lsq_entry_t lsq_arr [LSQ_QUEUE_DEPTH-1:0]; 

logic [LSQ_WIDTH-1:0] lsq_idx;

logic alloc_lsq ; 

FU_result lsqresult ; 

FU_result issued_entry ; 


logic [LSQ_WIDTH-1:0] issued_entry_idx ; 

logic req_pending ;
logic [LSQ_WIDTH-1:0] pending_idx ; 


logic lsready_found;


integer count ; 

logic has_older_store;




always_comb begin
    count = 0;
    for(integer i = 0; i < LSQ_QUEUE_DEPTH; i++) begin
        if(lsq_arr[i].valid) begin
            count = count + 1;
        end
    end
end

assign lsq_empty = (count == 0);

assign lsq_filled = (count == LSQ_QUEUE_DEPTH-1);





always_ff @(posedge clk ) begin

    if(rst) begin 
        
        for(integer i = 0; i < LSQ_QUEUE_DEPTH; i++) begin

            lsq_arr[i] <= '0 ; 
            
       end


       req_pending <= '0 ; 
       pending_idx <= '0 ; 

       
       
    end
// branch handling 
    else if(branch_flush.valid && branch_flush.branch_taken) begin

        for(integer i = 0; i < LSQ_QUEUE_DEPTH; i++) begin

                lsq_arr[i] <= '0 ; 
                
        end

            req_pending <= '0 ; 
            pending_idx <= '0 ; 
            

    end
    else begin 
        if(alloc_lsq && lsqresult.result_ready) begin 

            for(integer unsigned i = 0; i < LSQ_QUEUE_DEPTH; i++) begin

                if(lsq_arr[i].valid == 0) begin 

                    lsq_arr[i].valid <= 1'b1 ; 
                    lsq_arr[i].rob_idx <= lsqresult.rob_idx ; 
                    
                    lsq_arr[i].phy_rd <= lsqresult.phy_rd ; 
                    lsq_arr[i].completed <= 1'b0 ; 
                    lsq_arr[i].issued <= '0 ; 
                    lsq_arr[i].dmem_addr <= lsqresult.result ; 
                    lsq_arr[i].dmem_rdata <= '0 ; 
                    lsq_arr[i].store_commited <= 1'b0 ; 

                    lsq_arr[i].loadunsigned <= lsqresult.loadunsigned ;  
                    if(lsqresult.is_load) begin 
                        lsq_arr[i].is_load <= 1'b1 ; 
                        lsq_arr[i].has_rd <= 1'b1 ; 
                        lsq_arr[i].dmem_rmask <= lsqresult.dmem_rmask ; 
                    end
                    else if(lsqresult.is_store) begin 


                        lsq_arr[i].is_store <= 1'b1 ;
                        lsq_arr[i].has_rd <= 1'b0 ; 
                        lsq_arr[i].dmem_wmask <= lsqresult.dmem_wmask ; 
                        lsq_arr[i].dmem_wdata <= lsqresult.dmem_wdata ; 
                    end

                    break ; 
                end 
            end
        end


//marking store ready 2 commit 

    if(commit2store.valid) begin 
        for(integer unsigned i = 0 ; i < LSQ_QUEUE_DEPTH; i++) begin
            if((lsq_arr[i].rob_idx == commit2store.rob_idx) &&  (lsq_arr[i].is_store) && (lsq_arr[i].valid) && !lsq_arr[i].completed) begin
                lsq_arr[i].store_commited <= 1'b1 ; 
                break;
            end 
        end
    end




// marking ready entry as issued on the next cycle 

    if (lsready_found && !req_pending) begin
        lsq_arr[issued_entry_idx].issued <= 1'b1;

        req_pending <= 1'b1;

        pending_idx <= issued_entry_idx;
    end



    //mark completed when dmem_resp recieved:
    if (dmem_resp && req_pending) begin

            lsq_arr[pending_idx].completed <= 1'b1;
            
            // For loads: store the received data
            if (!lsq_arr[pending_idx].is_store) begin
                lsq_arr[pending_idx].dmem_rdata <= dmem_rdata;
            end

             req_pending <= 1'b0;
    end



// freeing completed entry slots 


// freeing completed entry slots  — loads *and* stores
for (integer unsigned i = 0; i < LSQ_QUEUE_DEPTH; i++) begin
    if (lsq_arr[i].valid && lsq_arr[i].completed) begin
        lsq_arr[i] <= '0;
    end
end



end

    
end



logic [LSQ_WIDTH-1:0] min_lsqrob_entry_idx;

logic [ROB_IDX_WIDTH-1:0] min_rob_idx;




// finding the oldest rob entry to send to cache 

 logic [ROB_IDX_WIDTH-1:0] diff;



//active logic to keep checking rdata and issued entry, using pending_idx, which gets deasserted next cycle 
always_comb begin


    memory2writeback.alu_result = execute2memory.alu_result; 
    memory2writeback.mul_result = execute2memory.mul_result;
    memory2writeback.div_result = execute2memory.div_result;
    memory2writeback.cmp_result = execute2memory.cmp_result;
    
    
    memory2writeback.LScomplete_result = '0;
    
 
    alloc_lsq = 1'b0; 
    lsq2rob = '0; 
    mem_stall = 1'b0;
    store2commit = '0;

    lsqresult = '0 ; 
    has_older_store = '0 ; 




        lsready_found = 1'b0;
        min_rob_idx = '1;  // Maximum value
        min_lsqrob_entry_idx = '0;
        issued_entry_idx = '0 ; 

        dmem_addr = '0;
        dmem_rmask = '0;
        dmem_wmask = '0;
        dmem_wdata = '0;
        
        // Scanning all entries

        // only search for the next slot to issue there are no requests pending 



        if(req_pending) begin

            dmem_addr = lsq_arr[pending_idx].dmem_addr ; 
            if(lsq_arr[pending_idx].is_store) begin 

                dmem_wmask = lsq_arr[pending_idx].dmem_wmask ; 
                dmem_wdata = lsq_arr[pending_idx].dmem_wdata ; 


            end 
            else begin 
                 dmem_rmask = lsq_arr[pending_idx].dmem_rmask ; 

            end
        end

        

        if(!req_pending) begin  
                for(integer unsigned i = 0; i < LSQ_QUEUE_DEPTH; i++) begin
                    if(lsq_arr[i].valid && !lsq_arr[i].issued && !lsq_arr[i].completed) begin

                        if (lsq_arr[i].is_store && !lsq_arr[i].store_commited) begin
                            continue;
                        end

                     

                        if (lsq_arr[i].is_load) begin
                                has_older_store = 1'b0;

                             
                                for (integer unsigned j = 0; j < LSQ_QUEUE_DEPTH; j++) begin
                                    if (lsq_arr[j].valid &&
                                        lsq_arr[j].is_store &&
                                        !lsq_arr[j].completed &&
                                        (lsq_arr[j].dmem_addr[31:2] == lsq_arr[i].dmem_addr[31:2])) begin
                                        
                                        // Check if store is older with wrap-around handling
                                       
                                        diff = lsq_arr[i].rob_idx - lsq_arr[j].rob_idx;
                                        
                                        // Store is older if: diff is positive, not wrapped, and within half ROB size
                                        if (diff[ROB_IDX_WIDTH-1] == 1'b0 && diff > '0 && diff <= ROB_IDX_WIDTH'(unsigned'(ROB_SIZE)/2)) begin
                                            has_older_store = 1'b1;
                                            break;
                                        end
                                    end
                                end

                                if (has_older_store) begin
                                    continue;
                                end
                            end



                        if(!lsready_found) begin
                            // First valid entry found
                            min_rob_idx = lsq_arr[i].rob_idx;
                            min_lsqrob_entry_idx = LSQ_WIDTH'(i);
                            issued_entry_idx = LSQ_WIDTH'(i);
                            lsready_found = 1'b1;
                        end else if (lsq_arr[i].rob_idx < min_rob_idx) begin
                            // Found older entry
                            min_rob_idx = lsq_arr[i].rob_idx;
                            min_lsqrob_entry_idx = LSQ_WIDTH'(i);
                            issued_entry_idx = LSQ_WIDTH'(i);
                        end
                    end
                end


                
                
                // Output, send requests to d cache 
                if(lsready_found && lsq_arr[issued_entry_idx].valid) begin

                    dmem_addr = lsq_arr[issued_entry_idx].dmem_addr;
                    
                    if (lsq_arr[issued_entry_idx].is_store) begin
                        dmem_wmask = lsq_arr[issued_entry_idx].dmem_wmask;
                        dmem_wdata = lsq_arr[issued_entry_idx].dmem_wdata;  // Already formatted
                    end else begin
                        dmem_rmask = lsq_arr[issued_entry_idx].dmem_rmask;
                    end
                end

    end
        




//pass through logic
    
    if(execute2memory.agu_result.result_ready ) begin 
        if(lsq_filled) begin 
            mem_stall = 1'b1; 
        end else begin
            alloc_lsq = 1'b1; 
            lsqresult = execute2memory.agu_result;
            
            // Update ROB with memory info
            if(execute2memory.agu_result.is_load) begin 
                lsq2rob.valid = 1'b1; 
                lsq2rob.rob_idx = execute2memory.agu_result.rob_idx; 
                lsq2rob.is_load = 1'b1; 
                lsq2rob.dmem_addr = execute2memory.agu_result.result; 
                lsq2rob.dmem_rmask = execute2memory.agu_result.dmem_rmask;


            end else if(execute2memory.agu_result.is_store) begin 
                lsq2rob.valid = 1'b1; 
                lsq2rob.rob_idx = execute2memory.agu_result.rob_idx; 
                lsq2rob.is_store = 1'b1; 
                lsq2rob.dmem_addr = execute2memory.agu_result.result; 
                lsq2rob.dmem_wmask = execute2memory.agu_result.dmem_wmask; 
                lsq2rob.dmem_wdata = execute2memory.agu_result.dmem_wdata;
                
               //store sent to wb
                // memory2writeback.LScomplete_result.result_ready = 1'b1;
                // memory2writeback.LScomplete_result.rob_idx = execute2memory.agu_result.rob_idx;
                // memory2writeback.LScomplete_result.is_store = 1'b1;
                // memory2writeback.LScomplete_result.has_rd = 1'b0;
                // memory2writeback.LScomplete_result.phy_rd = '0;
                // memory2writeback.LScomplete_result.result = '0;
            end
        end
    end

// load writeback
    if (dmem_resp && req_pending && !lsq_arr[pending_idx].is_store && !(branch_flush.valid && branch_flush.branch_taken)) begin
        memory2writeback.LScomplete_result.result_ready = 1'b1;
        memory2writeback.LScomplete_result.is_load = 1'b1;
        memory2writeback.LScomplete_result.phy_rd = lsq_arr[pending_idx].phy_rd;
        memory2writeback.LScomplete_result.rob_idx = lsq_arr[pending_idx].rob_idx;
        memory2writeback.LScomplete_result.has_rd = lsq_arr[pending_idx].has_rd;

       
        case (lsq_arr[pending_idx].dmem_rmask)
            4'b0001: begin 
                // memory2writeback.LScomplete_result.result = {{24{dmem_rdata[7]}}, dmem_rdata[7:0]};
                if (lsq_arr[pending_idx].loadunsigned) begin
                    memory2writeback.LScomplete_result.result = {24'b0, dmem_rdata[7:0]};
                end else begin 
                    memory2writeback.LScomplete_result.result = {{24{dmem_rdata[7]}}, dmem_rdata[7:0]};
                end
            end
            4'b0010: begin 
                // memory2writeback.LScomplete_result.result = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                if (lsq_arr[pending_idx].loadunsigned) begin
                    memory2writeback.LScomplete_result.result = {24'b0, dmem_rdata[15:8]};
                end else begin 
                    memory2writeback.LScomplete_result.result = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                end
            end
            4'b0100: begin 
                // memory2writeback.LScomplete_result.result = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                 if (lsq_arr[pending_idx].loadunsigned) begin
                    memory2writeback.LScomplete_result.result = {24'b0, dmem_rdata[23:16]};
                end else begin 
                    memory2writeback.LScomplete_result.result = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                end
            end
            4'b1000: begin
                // memory2writeback.LScomplete_result.result = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
                if (lsq_arr[pending_idx].loadunsigned) begin
                    memory2writeback.LScomplete_result.result = {24'b0, dmem_rdata[31:24]};
                end else begin 
                    memory2writeback.LScomplete_result.result =   {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
                end
            end

            
            4'b0011: begin // LH - halfword 0
                if (lsq_arr[pending_idx].loadunsigned) begin
                    memory2writeback.LScomplete_result.result = {16'b0, dmem_rdata[15:0]};
                end else begin 
                    memory2writeback.LScomplete_result.result = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
                end
            end
            4'b1100: begin // LH - halfword 1
                // memory2writeback.LScomplete_result.result = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
                 if (lsq_arr[pending_idx].loadunsigned) begin
                    memory2writeback.LScomplete_result.result = {16'b0, dmem_rdata[31:16]};
                end else begin 
                    memory2writeback.LScomplete_result.result = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
                end
            end
            4'b1111: begin // LW - full word
                memory2writeback.LScomplete_result.result = dmem_rdata;
            end
            default: begin
                memory2writeback.LScomplete_result.result = dmem_rdata;
            end
        endcase
     end

     else if (dmem_resp && req_pending && lsq_arr[pending_idx].is_store  && !(branch_flush.valid && branch_flush.branch_taken)) begin
                store2commit.store_ack = 1'b1;
                store2commit.rob_idx = lsq_arr[pending_idx].rob_idx;

                
     end

    end











endmodule: mem_stage