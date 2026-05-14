module pipelined_icache_fetch
import rv32i_types::*;
(
    // cpu side signals, ufp -> upward facing port
    input   logic   [ADDR_SIZE-1:0]  ufp_addr,
    input   logic   [3:0]            ufp_rmask,
    output  pipelined_icache_fetch_to_compare_tag_t    to_compare_tag
);

always_comb begin
    to_compare_tag.read_request = (ufp_rmask != 4'b0000);
    to_compare_tag.address = ufp_addr;
    to_compare_tag.set_index = ufp_addr[SET_BITS + OFFSET_BITS -1 : OFFSET_BITS];
    to_compare_tag.tag = ufp_addr[ADDR_SIZE-1 : ADDR_SIZE - TAG_BITS];
end

endmodule