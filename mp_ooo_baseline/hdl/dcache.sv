module dcache 
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [ADDR_SIZE-1:0]  ufp_addr,
    input   logic   [3:0]            ufp_rmask,
    input   logic   [3:0]            ufp_wmask,
    output  logic   [ADDR_SIZE-1:0]  ufp_rdata,
    input   logic   [ADDR_SIZE-1:0]  ufp_wdata,
    output  logic                    ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [ADDR_SIZE-1:0]         dfp_addr,
    output  logic                           dfp_read,
    output  logic                           dfp_write,
    input   logic   [BLOCK_SIZE_BITS-1:0]   dfp_rdata,
    output  logic   [BLOCK_SIZE_BITS-1:0]   dfp_wdata,
    input   logic                            dfp_resp,
    input   logic   [ADDR_SIZE-1:0]  dfp_addr_resp, 
    input    branch_flush_t   branch_flush
);

    // array for each of the ways per set to use the data array
    logic                         data_csb      [NUM_WAYS]; // chip select set low when selected
    logic                         data_web      [NUM_WAYS]; // web: write enable set low during stores 
    logic   [SET_BITS-1:0]        data_addr     [NUM_WAYS]; // addr for data array
    logic   [BLOCK_SIZE_BITS-1:0] data_din      [NUM_WAYS]; // used when web is high (stores)
    logic   [BLOCK_SIZE_BITS-1:0] data_dout     [NUM_WAYS]; // always assigned
    logic   [BLOCK_SIZE-1:0]      data_wmask    [NUM_WAYS];

    // array for each of the ways per set to use the tag array
    logic                  tag_csb   [NUM_WAYS]; // chip select set low when selected
    logic                  tag_web   [NUM_WAYS]; // web: write enable set low during stores 
    logic   [SET_BITS-1:0] tag_addr  [NUM_WAYS]; // addr for tag array
    logic   [TAG_BITS-1:0] tag_din   [NUM_WAYS]; // used when web is high (stores)
    logic   [TAG_BITS-1:0] tag_dout  [NUM_WAYS]; // always assigned

    // array for each of the ways per set to use the valid array
    logic                  valid_csb   [NUM_WAYS]; // chip select set low when selected
    logic                  valid_web   [NUM_WAYS]; // web: write enable set low during stores 
    logic   [SET_BITS-1:0] valid_addr  [NUM_WAYS]; // addr for valid array
    logic                  valid_din   [NUM_WAYS]; // used when web is high (stores)
    logic                  valid_dout  [NUM_WAYS]; // always assigned

    // array for each of the ways per set to use the dirty array
    logic                  dirty_csb   [NUM_WAYS]; // chip select set low when selected
    logic                  dirty_web   [NUM_WAYS]; // web: write enable set low during stores 
    logic   [SET_BITS-1:0] dirty_addr  [NUM_WAYS]; // addr for dirty array
    logic                  dirty_din   [NUM_WAYS]; // used when web is high (stores)
    logic                  dirty_dout  [NUM_WAYS]; // always assigned

    logic                    plru_csb, plru_web;
    logic [SET_BITS-1:0]     plru_addr;
    logic [PLRU_BITS-1:0]    plru_din;
    logic [PLRU_BITS-1:0]    plru_dout;

    // Registered request captured when leaving IDLE
    logic [ADDR_SIZE-1:0]        req_addr, req_wdata;
    logic [3:0]         req_rmask, req_wmask;
    logic               req_is_load, req_is_store;
    logic [SET_BITS-1:0] req_set_index;

    generate for (genvar i = 0; i < NUM_WAYS; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (data_csb[i]),
            .web0       (data_web[i]),
            .wmask0     (data_wmask[i]),
            .addr0      (data_addr[i]),
            .din0       (data_din[i]),
            .dout0      (data_dout[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       (tag_csb[i]),
            .web0       (tag_web[i]),
            .addr0      (tag_addr[i]),
            .din0       (tag_din[i]),
            .dout0      (tag_dout[i])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (valid_csb[i]),
            .web0       (valid_web[i]),
            .addr0      (valid_addr[i]),
            .din0       (valid_din[i]),
            .dout0      (valid_dout[i])
        );
        sp_ff_array dirty_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (dirty_csb[i]),
            .web0       (dirty_web[i]),
            .addr0      (dirty_addr[i]),
            .din0       (dirty_din[i]),
            .dout0      (dirty_dout[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (PLRU_BITS)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (plru_csb),
        .web0       (plru_web),
        .addr0      (plru_addr),
        .din0       (plru_din),
        .dout0      (plru_dout)
    );

    typedef enum logic [1:0]  {
        idle,
        compare_tag,
        write_back,
        allocate 
    } state_e;

    state_e state, next_state;
    
    logic [NUM_WAYS-1:0] hit_in_way;
    logic hit;
    logic [WAY_BITS-1:0] hit_index;
    always_comb begin
        hit_index = '0;
        for (integer i = 0; i< NUM_WAYS; i++) begin
            hit_in_way[i] = valid_dout [i] && (tag_dout[i] == req_addr[ADDR_SIZE-1:ADDR_SIZE - TAG_BITS]); // 31:9
            if (hit_in_way[i]) begin
                hit_index = WAY_BITS'($unsigned(i)); 
            end
        end
    end
    assign hit = (|hit_in_way) && state == compare_tag;

    logic [WAY_BITS-1:0] lru_way_index;
    always_comb begin
        unique casez (plru_dout) 
            3'b00?: lru_way_index = 2'b00;  // way 0
            3'b01?: lru_way_index = 2'b01;  // way 1
            3'b1?0: lru_way_index = 2'b10;  // way 2
            3'b1?1: lru_way_index = 2'b11;  // way 3
        endcase
    end

    logic dirty_lru;
    assign dirty_lru = dirty_dout[lru_way_index];

    logic op_load, op_store;
    logic live_is_load, live_is_store;
    assign live_is_load = (ufp_rmask != 4'b0);
    assign live_is_store = (ufp_wmask != 4'b0);
    assign op_load = (state == idle)? live_is_load : req_is_load;
    assign op_store = (state == idle)? live_is_store : req_is_store;

    always_comb begin // decides what the next state should be 
        unique case (state)
            idle: begin
                if (op_load || op_store) begin // wait for a valid read or write request
                    next_state = compare_tag;
                end else begin
                    next_state = idle;
                end
            end
            compare_tag: begin
                if (hit) begin
                    next_state = idle;
                end else if (dirty_lru) begin
                    next_state = write_back;
                end else begin
                    next_state = allocate;
                end
            end
            write_back: begin
                if (dfp_resp) begin
                    next_state = allocate;
                end else begin
                    next_state = write_back;
                end
            end
            allocate: begin
                if (dfp_resp) begin
                    next_state = idle;
                end
                else begin
                    next_state = allocate;
                end
            end
        endcase
    end

    logic[SET_BITS-1:0] set_index;
    logic [SET_BITS-1:0] live_set_index;
    assign live_set_index = ufp_addr[SET_BITS+OFFSET_BITS-1:OFFSET_BITS]; // 8:5
    assign set_index = (state == idle)? live_set_index : req_set_index;
    // Use this set index to now assign the set addresses for each of the arrays

    // Logic for updating the PLRU
    logic [PLRU_BITS-1:0] plru_nxt;
    always_comb begin
        plru_nxt = plru_dout;
        unique case (hit_index)
            2'b00: begin plru_nxt[2] = 1'b1; plru_nxt[1] = 1'b1; end
            2'b01: begin plru_nxt[2] = 1'b1; plru_nxt[1] = 1'b0; end
            2'b10: begin plru_nxt[2] = 1'b0; plru_nxt[0] = 1'b1; end
            2'b11: begin plru_nxt[2] = 1'b0; plru_nxt[0] = 1'b0; end
        endcase
    end
    
    logic [4:0] base; 
    logic [BLOCK_SIZE_BITS-1:0] data_to_write;

    always_comb begin // sets control signals for the datapath based on current state
        ufp_resp = 1'b0;
        ufp_rdata = '0;
        dfp_read = 1'b0;
        dfp_write = 1'b0;
        dfp_addr = '0;
        dfp_wdata = '0;

        for (integer i=0;i<NUM_WAYS;i++) begin
            tag_csb[i]='0;   tag_web[i]='1;   tag_addr[i]=set_index;   tag_din[i]='0;
            valid_csb[i]='0; valid_web[i]='1; valid_addr[i]=set_index; valid_din[i]='0;
            dirty_csb[i]='0; dirty_web[i]='1; dirty_addr[i]=set_index; dirty_din[i]='0;

            data_csb[i]='0;  data_web[i]='1;  data_addr[i]=set_index;
            data_din[i]='0; data_wmask[i]='0;
        end
        plru_csb = 1'b0; plru_web=1'b1; plru_addr=set_index; plru_din='0;

        // Create the mask for data to write
        base = {req_addr[4:2], 2'b00};
        
        unique case (state)
            idle: begin
            end
            compare_tag: begin
                if (op_load && hit) begin
                    ufp_rdata = data_dout[hit_index][base*8 +: 32]; 
                    ufp_resp = 1'b1;
                    plru_web = 1'b0; 
                    plru_din = plru_nxt;
                end else if (op_store && hit) begin
                    data_to_write = data_dout[hit_index];
                    data_to_write[(base+0)*8 +: 8] = req_wmask[0] ? req_wdata[7:0]   : data_to_write[(base+0)*8 +: 8];
                    data_to_write[(base+1)*8 +: 8] = req_wmask[1] ? req_wdata[15:8]  : data_to_write[(base+1)*8 +: 8];
                    data_to_write[(base+2)*8 +: 8] = req_wmask[2] ? req_wdata[23:16] : data_to_write[(base+2)*8 +: 8];
                    data_to_write[(base+3)*8 +: 8] = req_wmask[3] ? req_wdata[31:24] : data_to_write[(base+3)*8 +: 8];
          
                    data_web[hit_index] = 1'b0;
                    data_din[hit_index] = data_to_write; // masked version of ufp_wdata
                    data_wmask[hit_index] = '1;
                
                    dirty_web[hit_index] = 1'b0;
                    dirty_din[hit_index] = 1'b1;

                    valid_web[hit_index] = 1'b0;
                    valid_din[hit_index] = 1'b1;
                    
                    ufp_resp = 1'b1;
                    
                    plru_web = 1'b0; 
                    plru_din = plru_nxt;
                end
            end
            write_back: begin
                dfp_write = 1'b1;
                dfp_addr = {tag_dout[lru_way_index], set_index, {OFFSET_BITS{1'b0}} };
                dfp_wdata = data_dout[lru_way_index];
            end
            allocate: begin
                dfp_read = 1'b1;
                dfp_addr = {req_addr[31:9], set_index, {OFFSET_BITS{1'b0}} };

                if (dfp_resp && (dfp_addr_resp == dfp_addr) ) begin
                    data_web    [lru_way_index] = 1'b0;
                    data_din    [lru_way_index] = dfp_rdata;
                    data_wmask  [lru_way_index] = {BLOCK_SIZE{1'b1}}; // writing full block

                    valid_web   [lru_way_index] = 1'b0;
                    valid_din   [lru_way_index] = 1'b1;

                    dirty_web   [lru_way_index] = 1'b0;
                    dirty_din   [lru_way_index] = 1'b0;

                    tag_web     [lru_way_index] = 1'b0;
                    tag_din     [lru_way_index] = req_addr[ADDR_SIZE-1:ADDR_SIZE - TAG_BITS]; // 31:9

                    plru_web = 1'b0; 
                    plru_din = plru_nxt;
                end
            end
        endcase
    end

    // always_ff @ (posedge clk) begin // advances the state to next state 
    //      if (rst) begin
    //         state <= idle;
    //     end else begin
    //         state <= next_state;
    //     end
    // end

    always_ff @ (posedge clk) begin // advances the state to next state 
        if (rst) begin
            state <= idle;
        end else begin
            state <= next_state;
        end
    end


    //|| (branch_flush.valid && branch_flush.branch_taken && (branch_flush.branchtg_addr[31:5] != ufp_addr[31:5]))

    always_ff @(posedge clk) begin
        if (rst) begin
            req_addr      <= '0;
            req_wdata     <= '0;
            req_rmask     <= '0;
            req_wmask     <= '0;
            req_is_load   <= 1'b0;
            req_is_store  <= 1'b0;
            req_set_index <= '0;
        end 
        else if (branch_flush.valid && branch_flush.branch_taken) begin
           req_addr      <= '0;
            req_wdata     <= '0;
            req_rmask     <= '0;
            req_wmask     <= '0;
            req_is_load   <= 1'b0;
            req_is_store  <= 1'b0;
            req_set_index <= '0;
        end
        else if (state == idle && (live_is_load || live_is_store)) begin
            req_addr      <= ufp_addr;
            req_wdata     <= ufp_wdata;
            req_rmask     <= ufp_rmask;
            req_wmask     <= ufp_wmask;
            req_is_load   <= live_is_load;
            req_is_store  <= live_is_store;
            req_set_index <= live_set_index; 
        end
    end

endmodule : dcache