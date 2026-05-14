module archregfile
import rv32i_types::*;
(
    input logic clk, 
    input logic rst, 
    input commit2arf_t commit2arch,
    input logic [ARF_IDX_WIDTH-1:0] rvfi_rs1_idx,
    output logic [ARF_SIZE-1:0] rvfi_rs1_data,
    input logic [ARF_IDX_WIDTH-1:0] rvfi_rs2_idx,
    output logic [ARF_SIZE-1:0] rvfi_rs2_data
); 

logic [ADDR_SIZE-1:0] archregs [ARF_SIZE-1:0] ;  // arch register file 

assign rvfi_rs1_data = archregs[rvfi_rs1_idx];
assign rvfi_rs2_data = archregs[rvfi_rs2_idx];

always_ff @(posedge clk) begin 
    if(rst) begin 
        for(integer unsigned i = 0; i < ARF_SIZE; i++ ) begin  
            archregs[i] <= '0 ; 
        end
    end else begin 
        if(commit2arch.wr_enable && (commit2arch.dest_arch_reg!= '0)) begin 
            archregs[commit2arch.dest_arch_reg] <= commit2arch.dest_arch_value ; 
        end
    end
end

endmodule: archregfile