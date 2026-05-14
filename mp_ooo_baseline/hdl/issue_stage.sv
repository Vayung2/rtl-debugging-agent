module issue_stage
import rv32i_types::*;
(

    input clk, 
    input rst, 
    input common_data_bus_t common_data_bus, 

    input dispatch2rs_t dispatch2issue, 

    input [31:0] prf_rs1_data, 
    input [31:0] prf_rs2_data, 

    output logic [5:0] prf_rs1_tag, 
    output logic [5:0] prf_rs2_tag, 

    output issue2execute_t issue2execute, 

    input execute_stall, 

    output logic alu_filled, 
    output logic mul_filled, 
    output logic div_filled, 
    output logic cmp_filled,
    output logic loadstore_filled,  
    
    output logic issue_stall, 
    input branch_flush_t branch_flush

    

);

// instantiate all the rs module for each functional unit

assign issue_stall = execute_stall ; 

dispatch2rs_t dispatch2alu, dispatch2cmp, dispatch2mul, dispatch2div, dispatch2loadstore ; 

logic dispatchvalid_alu, dispatchvalid_cmp, dispatchvalid_mul, dispatchvalid_div, dispatchvalid_loadstore; 


rs_entry_t alu_ready_entry;
logic [RS_IDX_WIDTH-1:0] alu_ready_idx;
logic alu_no_ready;

logic alu_empty;

// From CMP RS
rs_entry_t cmp_ready_entry;
logic [RS_IDX_WIDTH-1:0] cmp_ready_idx;
logic cmp_no_ready;

logic cmp_empty;

// From MUL RS
rs_entry_t mul_ready_entry;
logic [RS_IDX_WIDTH-1:0] mul_ready_idx;
logic mul_no_ready;

logic mul_empty;

// From DIV RS
rs_entry_t div_ready_entry;
logic [RS_IDX_WIDTH-1:0] div_ready_idx;
logic div_no_ready;


logic div_empty;

// from loads store rs

rs_entry_t loadstore_ready_entry;
logic [RS_IDX_WIDTH-1:0] loadstore_ready_idx;
logic loadstore_no_ready;


logic loadstore_empty;



logic alu_issue_grant ; 
logic [RS_IDX_WIDTH-1:0] alu_issue_idx; 

logic cmp_issue_grant ; 
logic [RS_IDX_WIDTH-1:0] cmp_issue_idx ; 

logic mul_issue_grant ; 
logic [RS_IDX_WIDTH-1:0] mul_issue_idx ; 

logic div_issue_grant ; 
logic [RS_IDX_WIDTH-1:0] div_issue_idx ; 

logic loadstore_issue_grant ; 
logic [RS_IDX_WIDTH-1:0] loadstore_issue_idx ; 



rs_entry_t selected_entry;
logic selected_valid;
logic [2:0] selected_rs_type;
logic [ROB_IDX_WIDTH-1:0] min_rob_idx;

always_comb begin 

     dispatch2alu = '0 ; 
     dispatch2mul = '0 ; 
     dispatch2div = '0 ; 
     dispatch2cmp = '0 ; 
     dispatch2loadstore = '0 ; 

     dispatchvalid_alu = '0 ; 
     dispatchvalid_cmp = '0 ; 
     dispatchvalid_mul = '0 ; 
     dispatchvalid_div = '0 ; 
     dispatchvalid_loadstore = '0 ; 

     

     // 010 - div, 011- alu, cmp - 101, 100 - slt, sltu
        if(dispatch2issue.valid) begin
            if(dispatch2issue.rs_type == 3'b001) begin // mul 
                
                dispatch2mul = dispatch2issue ; 
                dispatchvalid_mul = 1'b1 ; 

            end
            else if(dispatch2issue.rs_type == 3'b010) begin // div
                
                dispatch2div = dispatch2issue ; 
                dispatchvalid_div = 1'b1 ; 

            end
            else if(dispatch2issue.rs_type == 3'b101) begin // load/store
                
                dispatch2loadstore = dispatch2issue ; 
                dispatchvalid_loadstore = 1'b1 ; 

            end
            else if (dispatch2issue.rs_type == 3'b011) begin // alu 
                
                dispatch2alu = dispatch2issue ; 
                dispatchvalid_alu = 1'b1 ; 

            end
            else if(dispatch2issue.rs_type == 3'b100) begin // cmp 
                
                dispatch2cmp = dispatch2issue ; 
                dispatchvalid_cmp  = 1'b1 ; 
            end
        end


end

rs_queue_module alu_rs_inst(
    .clk(clk),
    .rst(rst),
    .dispatch2rs(dispatch2alu),
    .cdb_wakeup(common_data_bus),
    .issue_grant(alu_issue_grant),
    .issue_idx(alu_issue_idx),
    .dispatchvalid(dispatchvalid_alu),
    .ready_rs_entry(alu_ready_entry),
    .ready_rs_entry_idx(alu_ready_idx),
    .no_ready_entries(alu_no_ready),
    .rs_filled(alu_filled),
    .rs_empty(alu_empty), 
     .branch_flush(branch_flush)
);

rs_queue_module cmp_rs_inst(
    .clk(clk),
    .rst(rst),
    .dispatch2rs(dispatch2cmp),
    .cdb_wakeup(common_data_bus),
    .issue_grant(cmp_issue_grant),
    .issue_idx(cmp_issue_idx),
    .dispatchvalid(dispatchvalid_cmp),
    .ready_rs_entry(cmp_ready_entry),
    .ready_rs_entry_idx(cmp_ready_idx),
    .no_ready_entries(cmp_no_ready),
    .rs_filled(cmp_filled),
    .rs_empty(cmp_empty), 
    .branch_flush(branch_flush)
);

rs_queue_module mul_rs_inst(
    .clk(clk),
    .rst(rst),
    .dispatch2rs(dispatch2mul),
    .cdb_wakeup(common_data_bus),
    .issue_grant(mul_issue_grant),
    .issue_idx(mul_issue_idx),
    .dispatchvalid(dispatchvalid_mul),
    .ready_rs_entry(mul_ready_entry),
    .ready_rs_entry_idx(mul_ready_idx),
    .no_ready_entries(mul_no_ready),
    .rs_filled(mul_filled),
    .rs_empty(mul_empty), 
     .branch_flush(branch_flush)
);

rs_queue_module div_rs_inst(
    .clk(clk),
    .rst(rst),
    .dispatch2rs(dispatch2div),
    .cdb_wakeup(common_data_bus),
    .issue_grant(div_issue_grant),
    .issue_idx(div_issue_idx),
    .dispatchvalid(dispatchvalid_div),
    .ready_rs_entry(div_ready_entry),
    .ready_rs_entry_idx(div_ready_idx),
    .no_ready_entries(div_no_ready),
    .rs_filled(div_filled),
    .rs_empty(div_empty), 
     .branch_flush(branch_flush)
);


//new load store queue
rs_queue_module loadstore_rs_inst(
    .clk(clk),
    .rst(rst),
    .dispatch2rs(dispatch2loadstore),
    .cdb_wakeup(common_data_bus),
    .issue_grant(loadstore_issue_grant),
    .issue_idx(loadstore_issue_idx),
    .dispatchvalid(dispatchvalid_loadstore),
    .ready_rs_entry(loadstore_ready_entry),
    .ready_rs_entry_idx(loadstore_ready_idx),
    .no_ready_entries(loadstore_no_ready),
    .rs_filled(loadstore_filled),
    .rs_empty(loadstore_empty), 
     .branch_flush(branch_flush)
);





    always_comb begin
        
        selected_valid = 1'b0;
        selected_entry = '0;
        selected_rs_type = 3'b0;
        min_rob_idx = 5'b11111;
        
        alu_issue_grant = 1'b0;
        alu_issue_idx = '0;
        cmp_issue_grant = 1'b0;
        cmp_issue_idx = '0;
        mul_issue_grant = 1'b0;
        mul_issue_idx = '0;

        div_issue_grant = 1'b0;
        div_issue_idx = '0;

        loadstore_issue_grant = 1'b0;
        loadstore_issue_idx = '0;


        
        
        if(!execute_stall) begin 
            if (!alu_no_ready) begin
                if (!selected_valid || alu_ready_entry.rob_idx < min_rob_idx) begin
                    min_rob_idx = alu_ready_entry.rob_idx;
                    selected_entry = alu_ready_entry;
                    selected_rs_type = 3'b011; // ALU FOR NORMAL INST
                    selected_valid = 1'b1;
                end
            end
            
        
            if (!cmp_no_ready) begin
                if (!selected_valid || cmp_ready_entry.rob_idx < min_rob_idx) begin
                    min_rob_idx = cmp_ready_entry.rob_idx;
                    selected_entry = cmp_ready_entry;
                    selected_rs_type = 3'b100; // CMP
                    selected_valid = 1'b1;
                end
            end
            
            
            if (!mul_no_ready) begin
                if (!selected_valid || mul_ready_entry.rob_idx < min_rob_idx) begin
                    min_rob_idx = mul_ready_entry.rob_idx;
                    selected_entry = mul_ready_entry;
                    selected_rs_type = 3'b001; // MUL
                    selected_valid = 1'b1;
                end
            end
            
            
            if (!div_no_ready) begin
                if (!selected_valid || div_ready_entry.rob_idx < min_rob_idx) begin
                    min_rob_idx = div_ready_entry.rob_idx;
                    selected_entry = div_ready_entry;
                    selected_rs_type = 3'b010; // DIV
                    selected_valid = 1'b1;
                end
            end


            //new check load store rs
            if (!loadstore_no_ready) begin
                if (!selected_valid || loadstore_ready_entry.rob_idx < min_rob_idx) begin
                    min_rob_idx = loadstore_ready_entry.rob_idx;
                    selected_entry = loadstore_ready_entry;
                    selected_rs_type = 3'b101; // LOAD STORE ALU
                    selected_valid = 1'b1;
                end
            end

    end

        
        
        if (selected_valid) begin
            case (selected_rs_type)
                3'b011: begin  // ALU
                    alu_issue_grant = 1'b1;
                    alu_issue_idx = alu_ready_idx;
                end
                 3'b100: begin  // CMP
                    cmp_issue_grant = 1'b1;
                    cmp_issue_idx = cmp_ready_idx;
                end
                3'b001: begin  // MUL
                    mul_issue_grant = 1'b1;
                    mul_issue_idx = mul_ready_idx;
                end
                3'b010: begin  // DIV
                    div_issue_grant = 1'b1;
                    div_issue_idx = div_ready_idx;
                end
                3'b101: begin  // LOADSTORE
                    loadstore_issue_grant = 1'b1;
                    loadstore_issue_idx = loadstore_ready_idx;
                end
            endcase
        end
    end





    always_comb begin

       

        
        if (selected_valid) begin
            prf_rs1_tag = selected_entry.phy_src1;
            prf_rs2_tag = selected_entry.phy_src2;
        end else begin
            prf_rs1_tag = 6'b0;
            prf_rs2_tag = 6'b0;
        end
        
        
        issue2execute = '0;
         issue2execute.valid = selected_valid;
        if (selected_valid) begin



            issue2execute.issued_entry = selected_entry;

            issue2execute.rs_type = selected_rs_type;

            issue2execute.phy_src1_v = prf_rs1_data;
           // issue2execute.phy_src2_v = selected_entry.has_imm ? selected_entry.imm : prf_rs2_data;

           if((selected_entry.opcode == op_reg) || selected_entry.is_store || selected_entry.is_branch) begin

               issue2execute.phy_src2_v = prf_rs2_data;


           end else begin
                issue2execute.phy_src2_v = selected_entry.imm   ; 
           end
        end
    end



















endmodule: issue_stage