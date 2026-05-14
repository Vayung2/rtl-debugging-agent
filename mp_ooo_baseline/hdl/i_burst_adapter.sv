// Collects the bursts of 64 from the DRAM, 
// packs it into 256 bits (cache block size)
// and then sends it to the cache 

// It has 2 states:
// 1. IDLE: waits for a read request from the cache
// 2. READ: sends 4 read requests to the DRAM and collects the data
module i_burst_adapter
import rv32i_types::*;
(
    input  logic clk,
    input  logic rst,

    input   logic                         bmem_ready,
    input   logic   [ADDR_SIZE-1:0]       bmem_raddr,
    input   logic   [BURST_SIZE-1:0]      bmem_rdata,
    input   logic                         bmem_rvalid,

    output  logic   [ADDR_SIZE-1:0]       bmem_addr,
    output  logic                         bmem_read,
    output  logic                         bmem_write,
    output  logic   [BURST_SIZE-1:0]      bmem_wdata,

    input  logic    [ADDR_SIZE-1:0]       cache_addr,
    input  logic                          cache_read,
    input  logic                          i_cache_chosen,
    // input  logic                          cache_write,
    // input  logic    [BLOCK_SIZE_BITS-1:0] cache_wdata,
    
    output logic    [BLOCK_SIZE_BITS-1:0] cache_rdata,
    output logic                          cache_resp,
    output logic [ADDR_SIZE-1:0]          cache_addr_resp
);
logic [1:0] burstcnt, burstcnt_nxt; 

logic lint_evasion1;
logic [31:0]lint_evasion2;

assign lint_evasion1 = bmem_ready;
assign lint_evasion2 = bmem_raddr;

logic [BLOCK_SIZE_BITS-1:0] burstreg; 
logic [BLOCK_SIZE_BITS-1:0] burstreg_next; 

logic [ADDR_SIZE-1:0] addr_reg, addr_reg_nxt; 

enum logic [1:0]{
    idle,
    read, 
    write
}burststate, burststate_nxt; 

always_ff @(posedge clk) begin 
    if(rst) begin
        burststate <= idle; 
        burstcnt <= '0; 
        burstreg <= '0; 
        addr_reg <= '0; 
    end else begin 
        burststate <= burststate_nxt; 
        burstcnt <= burstcnt_nxt; 
        burstreg <= burstreg_next; 
        addr_reg <= addr_reg_nxt; 
    end
end 

logic start_read;
logic read_active;
logic [ADDR_SIZE-1:0] active_addr;

always_comb begin
    bmem_addr    = addr_reg; 
    bmem_read    = 1'b0; 
    bmem_write   = 1'b0; 
    bmem_wdata   = '0;

    cache_rdata  = burstreg; 
    cache_resp   = 1'b0; 

    burststate_nxt = burststate; 
    burstcnt_nxt   = burstcnt; 
    burstreg_next  = burstreg; 
    addr_reg_nxt   = addr_reg; 
    cache_addr_resp = '0;

    
    
    start_read = (burststate == idle) && (cache_read != 1'b0) && i_cache_chosen;

    read_active = (burststate == read) || start_read;

    active_addr = (burststate == read) ? addr_reg : cache_addr;

    unique case (burststate)
      idle: begin
        if (start_read) begin
            burststate_nxt = read;
            addr_reg_nxt   = cache_addr;
            bmem_addr      = cache_addr;
            bmem_read      = 1'b1;
            burstcnt_nxt   = 2'b00;
            burstreg_next  = '0;
        end
      end

      read: begin
        bmem_read = 1'b0;
        if (!i_cache_chosen) begin
            burststate_nxt = idle;
            burstcnt_nxt   = 2'b00;
        end
      end

      default: begin
        burststate_nxt = idle;
      end
    endcase

   
    if (read_active && bmem_rvalid && (bmem_raddr == active_addr)) begin
        case (burstcnt_nxt)  
          2'b00: burstreg_next[BURST_SIZE-1:0]              = bmem_rdata; 
          2'b01: burstreg_next[2*BURST_SIZE-1:BURST_SIZE]   = bmem_rdata; 
          2'b10: burstreg_next[3*BURST_SIZE-1:2*BURST_SIZE] = bmem_rdata; 
          2'b11: burstreg_next[4*BURST_SIZE-1:3*BURST_SIZE] = bmem_rdata; 
        endcase

        if (burstcnt_nxt == 2'b11) begin
            cache_resp      = 1'b1;
            cache_rdata     = burstreg_next;
            cache_addr_resp = active_addr;
            burststate_nxt  = idle;
            burstcnt_nxt    = 2'b00;
        end else begin
            burstcnt_nxt    = burstcnt_nxt + 2'b01;
        end
    end
end


endmodule: i_burst_adapter