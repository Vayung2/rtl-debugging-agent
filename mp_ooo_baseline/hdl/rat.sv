module rat
import rv32i_types::*;
(
    input clk, 
    input rst,
    input logic [ADDR_BITS-1:0] read_rs1_idx,
    input logic [ADDR_BITS-1:0] read_rs2_idx,
    input logic [ADDR_BITS-1:0] read_rs3_idx, 
    input logic [ADDR_BITS-1:0] write_rd_idx, 
    input logic [PRF_IDX_WIDTH-1:0] write_phy_rd, 
    input logic wr_enable,
    input [ADDR_BITS-1:0] specrd_idx,
    input [PRF_IDX_WIDTH-1:0] specrd_mapping, 

    
    output logic [PRF_IDX_WIDTH-1:0] rs1_phy_idx,
    output logic [PRF_IDX_WIDTH-1:0] rs2_phy_idx, 
    output logic [PRF_IDX_WIDTH-1:0] rs3_phy_idx, 

    input commit2rat_t commit2rat, 
    input branch_flush_t branch_flush


); 

logic [PRF_IDX_WIDTH-1:0] rat_table [ADDR_SIZE-1:0]; 

logic [PRF_IDX_WIDTH-1:0] commited_rat_table [ADDR_SIZE-1:0]; 
// retirement rat


// assign rs1_phy_idx = rat_table[read_rs1_idx]; 
// assign rs2_phy_idx = rat_table[read_rs2_idx]; 
assign rs3_phy_idx = rat_table[read_rs3_idx]; 


// we need to have speculative rat update for raw hazards , basically check the new phy rd of the instruction going to dispatch


always_ff @(posedge clk) begin 
    if(rst) begin 
        for(integer unsigned i = 0; i < ADDR_SIZE; i++) begin 
            rat_table[i] <= PRF_IDX_WIDTH'(i);
        end

        for(integer unsigned i = 0; i < ADDR_SIZE; i++) begin 
            commited_rat_table[i] <= PRF_IDX_WIDTH'(i);
        end
    end


    // else if(branch_flush.valid && branch_flush.branch_taken) begin 


    //     for(integer unsigned i = 0 ; i < ADDR_SIZE; i++) begin

    //         rat_table[i] <= commited_rat_table[i] ;  


    //     end
    // end


    else begin 

        if(commit2rat.commit_update) begin
            if(commit2rat.commit_rd_idx != '0) begin
                commited_rat_table[commit2rat.commit_rd_idx] <= commit2rat.commit_phy_rd;
            end
        end
     

        if(branch_flush.valid && branch_flush.branch_taken) begin 
            for(integer unsigned i = 0; i < ADDR_SIZE; i++) begin
                if(commit2rat.commit_update && (commit2rat.commit_rd_idx == 5'(i)) && (i != '0)) begin
                    rat_table[i] <= commit2rat.commit_phy_rd;
                end else begin
                    rat_table[i] <= commited_rat_table[i];
        end
        end
        end
        else if(wr_enable) begin  
            if(write_rd_idx != '0) begin 
                rat_table[write_rd_idx] <= write_phy_rd;  
        end 
        end

            
    end
end

// speculative updates

always_comb begin 

    rs1_phy_idx = rat_table[read_rs1_idx]; 
    if(specrd_idx != '0) begin 
        if(read_rs1_idx == specrd_idx ) begin 
            rs1_phy_idx = specrd_mapping ; 
        end 
    end 

    if(specrd_idx != '0 && read_rs1_idx == specrd_idx) begin 
        rs1_phy_idx = specrd_mapping;
    end
    // ALSO check pending write (will update next cycle)
    // else if(wr_enable && read_rs1_idx == write_rd_idx && write_rd_idx != '0) begin
    //     rs1_phy_idx = write_phy_rd;
    // end


end


always_comb begin 


    
    rs2_phy_idx = rat_table[read_rs2_idx]; 
    if(specrd_idx != '0) begin 
        if(read_rs2_idx == specrd_idx ) begin 
            rs2_phy_idx = specrd_mapping ; 

        end
    end 

    if(specrd_idx != '0 && read_rs2_idx == specrd_idx) begin 
        rs2_phy_idx = specrd_mapping;
    end
    // else if(wr_enable && read_rs2_idx == write_rd_idx && write_rd_idx != '0) begin
    //     rs2_phy_idx = write_phy_rd;
    // end


end

endmodule: rat