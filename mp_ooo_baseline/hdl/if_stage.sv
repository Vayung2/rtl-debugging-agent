module if_stage
import rv32i_types::*;
(
    input   logic   [ADDR_SIZE-1:0]       pc, pc_next,
    input   logic                         imem_resp,
    // input   logic   [BLOCK_SIZE_BITS-1:0] imem_cache_line,
    input   logic   [ADDR_SIZE -1 : 0]    imem_rdata,
    input   logic                         branch_mispredict,
    output  logic   [ADDR_SIZE-1:0]       imem_addr,
    output  logic   [3:0]                 imem_mask,
    output  logic                         imem_stall,
    output  logic                         write_inst_queue, 
    output  logic   [ADDR_SIZE-1:0]       instruction_out,
    output  logic   [ADDR_SIZE -1 :0]     pc_out, 

    input branch_flush_t branch_flush
);
    
    logic [31:0] lint_evasion;
    assign lint_evasion = pc_next;

    logic lint_evasion1;
    assign lint_evasion1 = branch_mispredict;

    // Cache interface
    always_comb begin
        imem_addr = pc; 
        imem_mask = 4'b1111;
        imem_stall = ~imem_resp;
    end

    // Write to instruction queue
    always_comb begin
        write_inst_queue = (imem_resp) && !(branch_flush.valid && branch_flush.branch_taken);
        instruction_out  = imem_rdata;
        pc_out           = pc;
    end

endmodule : if_stage