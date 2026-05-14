module rs_queue_module
import rv32i_types::*;
#(
    parameter RS_SIZE = 16,
    parameter RS_IDX_WIDTH = $clog2(RS_SIZE)
)(
    input clk, 
    input rst, 
    input dispatch2rs_t dispatch2rs, 
    input common_data_bus_t cdb_wakeup,
    input logic dispatchvalid, 
    input logic issue_grant,
    input logic [RS_IDX_WIDTH-1:0] issue_idx,
    output rs_entry_t ready_rs_entry,
    output logic [RS_IDX_WIDTH-1:0] ready_rs_entry_idx, 
    output logic no_ready_entries,
    output logic rs_filled,
    output logic rs_empty, 

    input branch_flush_t branch_flush
); 



logic updated_physrs1_ready ; 
logic updated_physrs2_ready ; 


rs_entry_t rs_arr [RS_SIZE-1:0]; 
integer count; 
always_comb begin
    count = 0;
    for(integer i = 0; i < RS_SIZE; i++) begin
        if(rs_arr[i].valid) begin
            count = count + 1;
        end
    end
end

assign rs_empty = (count == 0);
assign rs_filled = (count == RS_SIZE);

always_ff @(posedge clk) begin 
    if(rst) begin 
        for(integer unsigned i = 0; i < RS_SIZE; i++) begin 
            rs_arr[i] <= '0 ; 
        end
    end 

    else if(branch_flush.valid && branch_flush.branch_taken) begin

        for(integer unsigned i = 0; i < RS_SIZE; i++) begin 
            rs_arr[i] <= '0 ; 
        end

    end
    
    else begin
        if(dispatch2rs.valid && !rs_filled && dispatchvalid) begin 
            for(integer unsigned i = 0 ; i < RS_SIZE; i++) begin 
                if(rs_arr[i].valid ==0) begin 
                    rs_arr[i].valid <= 1'b1; 
                    rs_arr[i].pc  <= dispatch2rs.pc ; 
                    rs_arr[i].opcode <= dispatch2rs.opcode; 
                    rs_arr[i].funct3 <= dispatch2rs.funct3; 
                    rs_arr[i].funct7 <= dispatch2rs.funct7; 
                    rs_arr[i].phy_src1 <= dispatch2rs.phy_src1; 
                    rs_arr[i].phy_src2 <= dispatch2rs.phy_src2; 
                    rs_arr[i].phy_src1_ready <= updated_physrs1_ready; 
                    rs_arr[i].phy_src2_ready <= updated_physrs2_ready; 
                    rs_arr[i].phy_dest <= dispatch2rs.phy_dest; 
                    rs_arr[i].rob_idx <= dispatch2rs.rob_idx; 
                    rs_arr[i].has_imm <= dispatch2rs.has_imm ; 
                    rs_arr[i].imm <= dispatch2rs.imm ; 
                    rs_arr[i].has_rd <= dispatch2rs.has_rd;
                    rs_arr[i].is_store <= dispatch2rs.is_store;
                    rs_arr[i].is_load <= dispatch2rs.is_load;
                    rs_arr[i].is_branch <= dispatch2rs.is_branch;
                    rs_arr[i].is_jump <= dispatch2rs.is_jump ; 

                    break; 
                end
            end        
        end

        if(cdb_wakeup.complete && cdb_wakeup.has_rd) begin 
            for(integer unsigned i = 0; i < RS_SIZE; i++) begin 
                if(rs_arr[i].valid) begin 
                    if((cdb_wakeup.phy_rd == rs_arr[i].phy_src1)) begin 
                        rs_arr[i].phy_src1_ready <= 1'b1; 
                    end
                    if((cdb_wakeup.phy_rd == rs_arr[i].phy_src2)) begin 
                        rs_arr[i].phy_src2_ready <= 1'b1; 
                    end
                end
            end
        end

        if(issue_grant) begin
                rs_arr[issue_idx].valid <= 1'b0;
        end
    end
end




always_comb begin

   
   updated_physrs1_ready = dispatch2rs.phy_src1_ready;
   updated_physrs2_ready = dispatch2rs.phy_src2_ready;
    if(cdb_wakeup.complete && cdb_wakeup.has_rd) begin 
        
        if(dispatch2rs.valid && !rs_filled && dispatchvalid) begin 
            
            if((cdb_wakeup.phy_rd == dispatch2rs.phy_src1)) begin 
                        updated_physrs1_ready= 1'b1; 
            end
            if((cdb_wakeup.phy_rd == dispatch2rs.phy_src2)) begin 
                        updated_physrs2_ready = 1'b1; 
            end
        end
          
        end
    
end





//active logic keeps checking whoch rsentries are ready and outputs one with lowest rob_idx
logic [RS_IDX_WIDTH-1:0] min_rob_entry_idx;
logic found_ready;
logic [ROB_IDX_WIDTH-1:0] min_rob_idx;
 logic entry_ready;

 logic has_older_store ; 




 logic [ROB_IDX_WIDTH-1:0] diff;


always_comb begin
    // Initialize
    found_ready       = 1'b0;
    min_rob_idx       = '1;      // max value
    min_rob_entry_idx = '0;
    entry_ready = 1'b0;

    has_older_store = 1'b0 ; 
   
    for (integer unsigned i = 0; i < RS_SIZE; i++) begin
        if (rs_arr[i].valid) begin
            logic entry_ready;
            entry_ready = 1'b0;

            if (rs_arr[i].is_store) begin
                
                entry_ready = rs_arr[i].phy_src1_ready && rs_arr[i].phy_src2_ready;

            end else if (rs_arr[i].is_load) begin
              
                

        //    for (integer unsigned j = 0; j < RS_SIZE; j++) begin
        //         if (rs_arr[j].valid && rs_arr[j].is_store) begin
                  
        //             diff = rs_arr[i].rob_idx - rs_arr[j].rob_idx;
        //             // Check if store is older: diff should be positive and less than half ROB size
        //             if (diff[ROB_IDX_WIDTH-1] == 1'b0 && diff > '0 && diff <= ROB_IDX_WIDTH'(unsigned'(ROB_SIZE)/2)) begin
        //                 has_older_store = 1'b1;
        //                 break;
        //             end
        //         end
        //     end

            entry_ready = rs_arr[i].phy_src1_ready ;

            end else begin
                
                entry_ready = rs_arr[i].phy_src1_ready && rs_arr[i].phy_src2_ready;
            end

            if (entry_ready) begin
                if (!found_ready || (rs_arr[i].rob_idx < min_rob_idx)) begin
                    min_rob_idx       = rs_arr[i].rob_idx;
                    min_rob_entry_idx = RS_IDX_WIDTH'(i);
                    found_ready       = 1'b1;
                end
            end
        end
    end

    // Output
    if (found_ready) begin
        ready_rs_entry     = rs_arr[min_rob_entry_idx];
        ready_rs_entry_idx = min_rob_entry_idx;
        no_ready_entries   = 1'b0;
    end else begin
        ready_rs_entry     = '0;
        ready_rs_entry_idx = '0;
        no_ready_entries   = 1'b1;
    end
end



endmodule: rs_queue_module