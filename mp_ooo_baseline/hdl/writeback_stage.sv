

module writeback_stage
import rv32i_types::*;
(

    input logic clk, 
    input logic rst, 
    input memory2writeback_t memory2writeback,
    output common_data_bus_t common_data_bus,
    output writeback2prf_t writeback2prf, 
    output logic writeback_stall , 
    input branch_flush_t branch_flush
); 

FU_result select_fu_result;
// logic ready2cdb;__



FU_result read_queue [15:0] ; 

logic [3:0] head, tail ; 

logic [4:0] count ; 

logic resultq_empty ; 

logic resultq_full ; 


logic cdb_taken ; 
assign resultq_empty = (count == 5'd0) ? 1'b1 : 1'b0;


assign writeback_stall = resultq_full ; 
//if debugging make sure tail does not go beyond the head 
always_comb begin 

    resultq_full = 1'b0 ; 
    if((count + memory2writeback.alu_result.result_ready +  memory2writeback.LScomplete_result.result_ready + memory2writeback.cmp_result.result_ready + memory2writeback.mul_result.result_ready + memory2writeback.div_result.result_ready) > 5'd16) begin 
        resultq_full = 1'b1 ; 
    end else begin 
        resultq_full = 1'b0 ;       
end
end


always_ff @(posedge clk) begin
    if(rst) begin 
        head <= '0 ; 
        tail <= '0 ; 
        count <= '0 ; 
         for(integer unsigned i = 0; i < 16; i++) begin 
               read_queue[i] <= '0 ; 
            end
           
        end

        else if(branch_flush.valid && branch_flush.branch_taken) begin 

                head <= '0 ; 
                tail <= '0 ; 
                count <= '0 ; 
                for(integer unsigned i = 0; i < 16; i++) begin 
                    read_queue[i] <= '0 ; 
                    end


        end

        else begin 

            if(!resultq_full) begin 
                 // inserting results into tail
                if (memory2writeback.alu_result.result_ready) begin
                    read_queue[tail] <= memory2writeback.alu_result ; 
                end

               


                if (memory2writeback.LScomplete_result.result_ready) begin
                    read_queue[(tail + memory2writeback.alu_result.result_ready) & 4'hF] <= memory2writeback.LScomplete_result;
                end
                
                // alu + tail + agu
                if (memory2writeback.cmp_result.result_ready) begin
                       read_queue[(tail + memory2writeback.alu_result.result_ready + memory2writeback.LScomplete_result.result_ready) & 4'hF] <= memory2writeback.cmp_result ; 
                end
                //alu+agu+tail+cmp
                if (memory2writeback.mul_result.result_ready) begin
                       read_queue[(tail  + memory2writeback.alu_result.result_ready + memory2writeback.LScomplete_result.result_ready+  memory2writeback.cmp_result.result_ready) & 4'hF] <= memory2writeback.mul_result ; 
                end 
                if (memory2writeback.div_result.result_ready) begin
                       read_queue[(tail + memory2writeback.alu_result.result_ready + memory2writeback.LScomplete_result.result_ready+  memory2writeback.cmp_result.result_ready + memory2writeback.mul_result.result_ready)& 4'hF] <= memory2writeback.div_result ; 
                end

                tail <= (tail +  memory2writeback.alu_result.result_ready + memory2writeback.LScomplete_result.result_ready + memory2writeback.cmp_result.result_ready + memory2writeback.mul_result.result_ready + memory2writeback.div_result.result_ready) & 4'hF;
            end


            if(!resultq_empty && cdb_taken) begin 
                    head <= (head + 1'b1) & 4'hF ; 
            end

            if (!resultq_full && !resultq_empty && cdb_taken) begin
                count <= count + memory2writeback.alu_result.result_ready + memory2writeback.LScomplete_result.result_ready + memory2writeback.cmp_result.result_ready + memory2writeback.mul_result.result_ready + memory2writeback.div_result.result_ready - 1'b1;
            end else if (!resultq_full) begin
                count <= count + memory2writeback.alu_result.result_ready + memory2writeback.LScomplete_result.result_ready + memory2writeback.cmp_result.result_ready + memory2writeback.mul_result.result_ready + memory2writeback.div_result.result_ready;
            end else if (!resultq_empty && cdb_taken) begin
                count <= count -1'b1 ; 
            end else begin
                count <= count;
            end
         end
end
    

assign select_fu_result = read_queue[head] ; 





// Populate CDB and PRF write
always_comb begin 
    common_data_bus = '0;
    writeback2prf = '0;

    cdb_taken = '0 ; 
    
    if (!resultq_empty && !(branch_flush.valid && branch_flush.branch_taken)) begin 
        
        cdb_taken = 1'b1 ; 
        common_data_bus.complete = 1'b1;
        common_data_bus.rob_idx =  select_fu_result.rob_idx;
        common_data_bus.phy_rd = select_fu_result.phy_rd;
        common_data_bus.has_rd = select_fu_result.has_rd;
        
        if (select_fu_result.has_rd) begin
            writeback2prf.ready = 1'b1;
            writeback2prf.prf_rd_idx = select_fu_result.phy_rd;
            writeback2prf.prf_rd_data = select_fu_result.result;
        end else begin
            // Store has no destination 
            writeback2prf.ready = 1'b0;
            writeback2prf.prf_rd_idx = '0;
            writeback2prf.prf_rd_data = '0;
        end
    end 
end


endmodule: writeback_stage














