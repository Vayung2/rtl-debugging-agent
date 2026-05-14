module physicalregfile
import rv32i_types::*;
(
    input clk, 
    input rst,
    input writeback2prf_t wb2prf, 
    input rename2prf_t   rename_alloc_rd, 
    input logic [PRF_IDX_WIDTH-1:0] rs1_idx, 
    input logic [PRF_IDX_WIDTH-1:0] rs2_idx,

    input rename2prf_ready_t rename2prf_ready,
    input logic [PRF_IDX_WIDTH-1:0] rd_commit_idx, 

    output prf2rename_readybits_t prf2renameready,
    output logic [ADDR_SIZE-1:0] rs1_data, 
   
    output logic [ADDR_SIZE-1:0] rs2_data, 
    
    output logic [ADDR_SIZE - 1:0] rd_commit_data,  // wired to commit stage in the cpu (only he commit stage can use this one ), 

    input commit2rat_t commit2rat, 

    input branch_flush_t branch_flush
);

// data array 
logic [ADDR_SIZE-1:0] prf_data_array [PRF_SIZE-1:0] ; 

logic prf_ready_arr [PRF_SIZE-1:0] ; 

// commit ready
logic commit_ready_arr [PRF_SIZE-1:0] ;


assign rs1_data = (rs1_idx == '0) ? '0 : prf_data_array[rs1_idx];
assign rs2_data = (rs2_idx == '0) ? '0 : prf_data_array[rs2_idx];

// assign prf2renameready.rs1_ready = (rename2prf_ready.prf_rs1_ready == '0) ? 1'b1 : prf_ready_arr[rename2prf_ready.prf_rs1_ready];

always_comb begin
    if( (rename2prf_ready.prf_rs1_ready != '0)) begin 
        if(wb2prf.prf_rd_idx == rename2prf_ready.prf_rs1_ready ) begin 
            prf2renameready.rs1_ready = 1'b1 ; 
        end else begin 
            prf2renameready.rs1_ready = prf_ready_arr[rename2prf_ready.prf_rs1_ready]; 

    end
    end else begin 
        prf2renameready.rs1_ready = '0; 

    end
    
end


always_comb begin 

    if( (rename2prf_ready.prf_rs2_ready != '0)) begin 
        if(wb2prf.prf_rd_idx == rename2prf_ready.prf_rs2_ready ) begin 
            prf2renameready.rs2_ready = 1'b1 ; 
        end else begin 
            prf2renameready.rs2_ready = prf_ready_arr[rename2prf_ready.prf_rs2_ready]; 

    end
    end else begin 
        prf2renameready.rs2_ready = '0; 

    end

    
end



// assign prf2renameready.rs2_ready = (rename2prf_ready.prf_rs2_ready == '0) ? 1'b1 : prf_ready_arr[rename2prf_ready.prf_rs2_ready];

assign rd_commit_data = (rd_commit_idx == '0) ? '0 : prf_data_array[rd_commit_idx] ; 


always_ff @(posedge clk) begin 
    if(rst) begin 
         for(integer unsigned i = 0; i < PRF_SIZE; i++ ) begin 
            if (i < 32) begin
                prf_data_array[i] <= '0;  // Should copy from ARF ideally
                prf_ready_arr[i] <= 1'b1;    // Initial state is ready
                commit_ready_arr[i] <= 1'b1 ; 
            end else begin
        // P32-P63: unallocated
                prf_data_array[i] <= '0;
                prf_ready_arr[i] <= 1'b0;    // Not ready
                commit_ready_arr[i] <= 1'b0 ; 
            end
        end
    end


    else begin 

    //      if(commit2rat.commit_update) begin
    //         commit_ready_arr[commit2rat.commit_phy_rd] <= 1'b1;   // first commit the rd of the jump 
    //     end
        
    //     if(branch_flush.valid && branch_flush.branch_taken) begin 
            
    //         if(branch_flush.jump) begin 
    //         prf_ready_arr[branch_flush.commitrd] <= 1'b1 ; 
    //         commit_ready_arr[branch_flush.commitrd] <= 1'b1;
    //     end


    //     for(integer unsigned i = 0 ; i < PRF_SIZE; i++) begin

    //         if((6'(i) == branch_flush.commitrd) && branch_flush.jump) begin 
    //             continue ; 
    //         end

    //         prf_ready_arr[i] <= commit_ready_arr[i] ;  


    //     end

       
    // end

    // else begin 
    //     if(rename_alloc_rd.alloc_en) begin 
    //         prf_ready_arr[rename_alloc_rd.prf_rd_alloc_idx] <= 1'b0 ; 

    //     end
    //     if(wb2prf.ready && (wb2prf.prf_rd_idx != '0)) begin 
    //         prf_data_array[wb2prf.prf_rd_idx] <= wb2prf.prf_rd_data ; 
    //         prf_ready_arr[wb2prf.prf_rd_idx] <= 1'b1 ; 
    //     end
    // end
    

    if(commit2rat.commit_update) begin
        commit_ready_arr[commit2rat.commit_phy_rd] <= 1'b1;
    end
    
    if(branch_flush.valid && branch_flush.branch_taken) begin 
        if(branch_flush.jump) begin 
            prf_ready_arr[branch_flush.commitrd] <= 1'b1; 
            commit_ready_arr[branch_flush.commitrd] <= 1'b1;
        end
        
        for(integer unsigned i = 0; i < PRF_SIZE; i++) begin
            if((6'(i) == branch_flush.commitrd) && branch_flush.jump) begin 
                continue;
            end
            

            if(commit2rat.commit_update && (commit2rat.commit_phy_rd == 6'(i))) begin
                prf_ready_arr[i] <= 1'b1; 
            end else begin
                prf_ready_arr[i] <= commit_ready_arr[i];  
            end
        end
    end
    else begin 
        if(rename_alloc_rd.alloc_en) begin 
            prf_ready_arr[rename_alloc_rd.prf_rd_alloc_idx] <= 1'b0; 
            commit_ready_arr[rename_alloc_rd.prf_rd_alloc_idx] <= 1'b0;
        end
        if(wb2prf.ready && (wb2prf.prf_rd_idx != '0)) begin 
            prf_data_array[wb2prf.prf_rd_idx] <= wb2prf.prf_rd_data; 
            prf_ready_arr[wb2prf.prf_rd_idx] <= 1'b1; 
        end
    end

    end


end

endmodule: physicalregfile