module pipelined_icache_compare_tag
import rv32i_types::*;
(
    input   pipelined_icache_fetch_to_compare_tag_t    from_fetch,
    input  logic [TAG_BITS-1:0]         tag_dout     [NUM_WAYS],    
    input  logic                        valid_dout   [NUM_WAYS],
    input  logic [BLOCK_SIZE_BITS-1:0]  data_dout    [NUM_WAYS],
    input  logic [PLRU_BITS-1:0]        plru_dout,
    
    output  pipelined_icache_compare_tag_outputs_t     to_cache
);

    logic [NUM_WAYS-1:0] hit_in_way;
    logic hit;
    logic [WAY_BITS-1:0] hit_index;
    always_comb begin
        hit_index = '0;
        for (integer i = 0; i< NUM_WAYS; i++) begin
            hit_in_way[i] = valid_dout [i] && (tag_dout[i] == from_fetch.address[ADDR_SIZE-1:ADDR_SIZE - TAG_BITS]); // 31:9
            if (hit_in_way[i]) begin
                hit_index = WAY_BITS'($unsigned(i)); 
            end
        end
    end
    assign hit = (|hit_in_way);

    logic [WAY_BITS-1:0] lru_way_index;
    // always_comb begin
    //     unique casez (plru_dout) 
    //         3'b00?: lru_way_index = 2'b00;  // way 0
    //         3'b01?: lru_way_index = 2'b01;  // way 1
    //         3'b1?0: lru_way_index = 2'b10;  // way 2
    //         3'b1?1: lru_way_index = 2'b11;  // way 3
    //     endcase
    // end
    always_comb begin
        unique case (plru_dout)
            1'b0: lru_way_index = 1'b0;  // way 0
            1'b1: lru_way_index = 1'b1;  // way 1
        endcase
    end

     // Logic for updating the PLRU
    logic [PLRU_BITS-1:0] plru_nxt;
    // always_comb begin
    //     plru_nxt = plru_dout;
    //     unique case (hit_index)
    //         2'b00: begin plru_nxt[2] = 1'b1; plru_nxt[1] = 1'b1; end
    //         2'b01: begin plru_nxt[2] = 1'b1; plru_nxt[1] = 1'b0; end
    //         2'b10: begin plru_nxt[2] = 1'b0; plru_nxt[0] = 1'b1; end
    //         2'b11: begin plru_nxt[2] = 1'b0; plru_nxt[0] = 1'b0; end
    //     endcase
    // end
    always_comb begin
        case (hit_index)
            1'b0: plru_nxt = 1'b1;  // hit way 0, so way 1 becomes LRU
            1'b1: plru_nxt = 1'b0;  // hit way 1, so way 0 becomes LRU
        endcase
    end

    logic [4:0] base; 
    assign base = {from_fetch.address[4:2], 2'b00};

    always_comb begin
        to_cache.read_request = from_fetch.read_request;
        to_cache.lru_way_index = lru_way_index;
        to_cache.address = from_fetch.address;
        to_cache.plru_nxt = plru_nxt;
        
        if (hit && from_fetch.read_request) begin
            to_cache.ufp_rdata = data_dout[hit_index][base*8 +: 32]; 
            to_cache.ufp_cacheline = data_dout[hit_index];
            to_cache.hit = 1'b1;
            // We do below in top level
            // plru_web = 1'b0; 
            // plru_din = plru_nxt;
        end else begin
            to_cache.ufp_rdata = '0;
            to_cache.ufp_cacheline = '0;
            to_cache.hit = 1'b0;
        end
    end

endmodule