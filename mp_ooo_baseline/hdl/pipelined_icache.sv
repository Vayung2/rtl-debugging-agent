module pipelined_icache
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [ADDR_SIZE-1:0]  ufp_addr,
    input   logic   [3:0]            ufp_rmask,
    output  logic   [ADDR_SIZE-1:0]  ufp_rdata,
    output  logic   [BLOCK_SIZE_BITS-1:0] ufp_cacheline,
    output  logic                    ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [ADDR_SIZE-1:0]         dfp_addr,
    output  logic                           dfp_read,
    input   logic   [BLOCK_SIZE_BITS-1:0]   dfp_rdata,
    input   logic                            dfp_resp
);

    logic                         data_csb      [NUM_WAYS];
    logic                         data_web      [NUM_WAYS];
    logic   [SET_BITS-1:0]        data_addr     [NUM_WAYS];
    logic   [BLOCK_SIZE_BITS-1:0] data_din      [NUM_WAYS];
    logic   [BLOCK_SIZE_BITS-1:0] data_dout     [NUM_WAYS];
    logic   [BLOCK_SIZE-1:0]      data_wmask    [NUM_WAYS];

    logic                  tag_csb   [NUM_WAYS];
    logic                  tag_web   [NUM_WAYS];
    logic   [SET_BITS-1:0] tag_addr  [NUM_WAYS];
    logic   [TAG_BITS-1:0] tag_din   [NUM_WAYS];
    logic   [TAG_BITS-1:0] tag_dout  [NUM_WAYS];

    logic                  valid_csb   [NUM_WAYS];
    logic                  valid_web   [NUM_WAYS];
    logic   [SET_BITS-1:0] valid_addr  [NUM_WAYS];
    logic                  valid_din   [NUM_WAYS];
    logic                  valid_dout  [NUM_WAYS];

    logic                    plru_csb, plru_web;
    logic [SET_BITS-1:0]     plru_addr;
    logic [PLRU_BITS-1:0]    plru_din;
    logic [PLRU_BITS-1:0]    plru_dout;

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

    typedef enum logic {
        IDLE,
        ALLOCATING
    } state_t;

    state_t state, state_next;

    pipelined_icache_compare_tag_outputs_t to_cache, to_cache_next;
    pipelined_icache_fetch_to_compare_tag_t to_compare_tag, to_compare_tag_next;

    pipelined_icache_fetch fetch_stage (
        .ufp_addr(ufp_addr),
        .ufp_rmask(ufp_rmask),
        .to_compare_tag(to_compare_tag_next)
    );

    pipelined_icache_compare_tag compare_tag_stage (
        .from_fetch(to_compare_tag),
        .tag_dout(tag_dout),
        .valid_dout(valid_dout),
        .data_dout(data_dout),
        .plru_dout(plru_dout),
        .to_cache(to_cache_next)
    );

    always_comb begin
        state_next = state;
        
        unique case (state)
            IDLE: begin
                if (to_compare_tag_next.read_request && !to_cache_next.hit) begin
                    state_next = ALLOCATING;
                end
            end
            
            ALLOCATING: begin
                if (dfp_resp) begin
                    state_next = IDLE;
                end
            end
            
            default: state_next = IDLE;
        endcase
    end

    logic [SET_BITS-1:0] set_index;
    always_comb begin
        if (state == IDLE) begin
            set_index = to_compare_tag_next.set_index;
        end else begin
            // ALLOCATING: keep using the miss address
            set_index = to_compare_tag.set_index;
        end
    end

    always_comb begin
        for (integer i=0; i<NUM_WAYS; i++) begin
            tag_csb[i]='0;   tag_web[i]='1;   tag_addr[i]=set_index;   tag_din[i]='0;
            valid_csb[i]='0; valid_web[i]='1; valid_addr[i]=set_index; valid_din[i]='0;
            data_csb[i]='0;  data_web[i]='1;  data_addr[i]=set_index;  data_din[i]='0; data_wmask[i]='0;
        end
        plru_csb = 1'b0; plru_web=1'b1; plru_addr=set_index; plru_din='0;
        
        dfp_read = '0;
        dfp_addr = '0;

        unique case (state)
            IDLE: begin
                if (to_cache_next.hit && to_compare_tag_next.read_request) begin 
                    plru_web = 1'b0; 
                    plru_din = to_cache_next.plru_nxt;
                end
                else if (!to_cache_next.hit && to_compare_tag_next.read_request) begin
                    dfp_read = 1'b1;
                    dfp_addr = {to_compare_tag_next.address[ADDR_SIZE-1:ADDR_SIZE-TAG_BITS], 
                                to_compare_tag_next.set_index, 
                                {OFFSET_BITS{1'b0}}};
                end
            end
            
            ALLOCATING: begin
                dfp_read = 1'b1;
                dfp_addr = {to_compare_tag.address[ADDR_SIZE-1:ADDR_SIZE-TAG_BITS], 
                            to_compare_tag.set_index, 
                            {OFFSET_BITS{1'b0}}};
                
                if (dfp_resp) begin
                    data_web    [to_cache_next.lru_way_index] = 1'b0;
                    data_din    [to_cache_next.lru_way_index] = dfp_rdata;
                    data_wmask  [to_cache_next.lru_way_index] = {BLOCK_SIZE{1'b1}};

                    valid_web   [to_cache_next.lru_way_index] = 1'b0;
                    valid_din   [to_cache_next.lru_way_index] = 1'b1;

                    tag_web     [to_cache_next.lru_way_index] = 1'b0;
                    tag_din     [to_cache_next.lru_way_index] = to_compare_tag.address[ADDR_SIZE-1:ADDR_SIZE - TAG_BITS];

                    plru_web = 1'b0; 
                    plru_din = to_cache_next.plru_nxt;
                end
            end
            
            default: begin
                // Do nothing
            end
        endcase
    end

    always_ff @ (posedge clk) begin
        if (rst) begin
            state <= IDLE;
            to_cache <= '0;
            to_compare_tag <= '0;
        end else begin
            state <= state_next;
            
            // Pipeline advances only in IDLE state
            if (state == IDLE) begin
                to_cache <= to_cache_next;
                to_compare_tag <= to_compare_tag_next;
            end
            // During ALLOCATING, pipeline is frozen
        end
    end

    always_comb begin
        ufp_rdata = '0;
        ufp_cacheline = '0;
        ufp_resp = 1'b0;

        if (state == IDLE && to_cache_next.hit && to_compare_tag_next.read_request) begin
            ufp_rdata = to_cache_next.ufp_rdata;
            ufp_cacheline = to_cache_next.ufp_cacheline;
            ufp_resp = 1'b1;
        end else if (state == ALLOCATING && dfp_resp) begin
            logic [4:0] base;
            base = {to_compare_tag.address[4:2], 2'b00};
            ufp_rdata = dfp_rdata[base*8 +: 32];
            ufp_cacheline = dfp_rdata;
            ufp_resp = 1'b1;
        end 
    end
 
endmodule