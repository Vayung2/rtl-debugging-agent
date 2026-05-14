
module cpu
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  logic   [ADDR_SIZE-1:0]      bmem_addr,
    output  logic                        bmem_read,
    output  logic                        bmem_write,
    output  logic   [BURST_SIZE-1:0]     bmem_wdata,
    input   logic                        bmem_ready,
    input   logic   [ADDR_SIZE-1:0]      bmem_raddr,
    input   logic   [BURST_SIZE-1:0]     bmem_rdata,
    input   logic                        bmem_rvalid
);

// I-Cache, I_LineBuffer, IFetch Signals
logic  [ADDR_SIZE-1 : 0]     imem_rdata;
logic  [3:0]                 imem_mask;
logic                        imem_stall;
logic [BLOCK_SIZE_BITS-1:0]  i_ufp_cacheline;
logic                        i_ufp_resp;   
logic [ADDR_SIZE-1:0]        icache_to_adapter_addr;
logic                        icache_to_adapter_read;
logic [BLOCK_SIZE_BITS-1:0]  adapter_to_icache_rdata;
logic                        adapter_to_icache_resp;
logic [ADDR_SIZE-1:0]        i_bmem_addr;
logic                        i_bmem_read;
logic                        i_bmem_write;
logic [BURST_SIZE-1:0]       i_bmem_wdata;
logic                        i_bmem_ready;
logic [ADDR_SIZE-1:0]        i_bmem_raddr;
logic [BURST_SIZE-1:0]       i_bmem_rdata;
logic                        i_bmem_rvalid;

// D-Cache
logic  [ADDR_SIZE-1 : 0]     d_ufp_wdata;
logic  [ADDR_SIZE-1 : 0]     dmem_rdata;
logic  [ADDR_SIZE-1 : 0]     dmem_wdata;
logic  [3:0]                 dmem_rmask;
logic  [3:0]                 dmem_wmask;
logic                        dmem_stall;
logic                        d_ufp_resp;   
logic [ADDR_SIZE-1:0]        dcache_to_adapter_addr;
logic                        dcache_to_adapter_read;
logic                        dcache_to_adapter_write;
logic [BLOCK_SIZE_BITS-1:0]  adapter_to_dcache_rdata;
logic [BLOCK_SIZE_BITS-1:0]  dcache_to_adapter_wdata;
logic                        adapter_to_dcache_resp;
logic [ADDR_SIZE-1:0]        d_bmem_addr;
logic                        d_bmem_read;
logic                        d_bmem_write;
logic [BURST_SIZE-1:0]       d_bmem_wdata;
logic                        d_bmem_ready;
logic [ADDR_SIZE-1:0]        d_bmem_raddr;
logic [BURST_SIZE-1:0]       d_bmem_rdata;
logic                        d_bmem_rvalid;
logic [ADDR_SIZE-1:0] d_cache_addr_resp; 

// Arbitration Logic between the burst adapters of the I-Cache, D-Cache to BMEM:
enum logic [1:0]{
    idle,
    icache, 
    dcache
}arbiter_state, arbiter_state_nxt; 

logic choose_dcache;

always_ff @(posedge clk) begin
    if (rst) begin
        arbiter_state <= idle;
    end else begin
        arbiter_state <= arbiter_state_nxt;
    end
end

always_comb begin
    if ((dcache_to_adapter_read || dcache_to_adapter_write)) begin
        arbiter_state_nxt = dcache;
    end else begin
        arbiter_state_nxt = icache;
    end
end

assign choose_dcache = arbiter_state_nxt == dcache;

assign bmem_addr = choose_dcache ? d_bmem_addr : i_bmem_addr;
assign bmem_read = choose_dcache ? d_bmem_read : i_bmem_read;
assign bmem_write = choose_dcache ? d_bmem_write :i_bmem_write;
assign bmem_wdata = choose_dcache ? d_bmem_wdata : i_bmem_wdata;

assign i_bmem_ready = choose_dcache ? '0 : bmem_ready;
assign i_bmem_raddr = choose_dcache ? '0 : bmem_raddr;
assign i_bmem_rdata = choose_dcache ? '0 : bmem_rdata;
assign i_bmem_rvalid = choose_dcache ? '0 : bmem_rvalid;

assign d_bmem_ready = choose_dcache ? bmem_ready : '0;
assign d_bmem_raddr = choose_dcache ? bmem_raddr : '0;
assign d_bmem_rdata = choose_dcache ? bmem_rdata : '0;
assign d_bmem_rvalid = choose_dcache ? bmem_rvalid : '0;

// Interfaces between all modules:
logic  [ADDR_SIZE-1:0]       pc, pc_next, imem_addr, dmem_addr;
common_data_bus_t common_data_bus;


// lsq 2 rob

lsq2rob_t lsq2rob  ; 

branchres2rob_t branchres2rob ; 

jumpresrob_t jumpresrob ; 

rob2frlist_t rob2frlist ; 

commit2store_t commit2store ; 
store2commit_t store2commit ; 

// flush signal from commit to all stage
branch_flush_t branch_flush ; 

logic [ADDR_SIZE-1:0] cache_addr_resp;

logic branchtaken ; 
logic [31:0] branch_target_addr ; 
assign branchtaken = (branch_flush.valid && branch_flush.branch_taken) ? 1'b1 : 1'b0  ; 
assign branch_target_addr = (branch_flush.valid && branch_flush.branch_taken) ? branch_flush.branchtg_addr : 1'b0  ; 



// 1. Fetch to Decode
logic                        write_to_instfifo ; 
logic                        read_from_instfifo;
logic                        instr_queue_empty;
logic                        instr_queue_fill; 
logic                        writetoqueue; 
logic [ADDR_SIZE-1:0]        write_instr_fifo ; 
logic [ADDR_SIZE - 1:0]      write_pc_fifo;
logic [ADDR_SIZE - 1:0]      read_instr_fifo ; 
logic [ADDR_SIZE - 1 :0]     read_pc_fifo;

// 2. Decode to Rename
decode2rename_t decode2rename;
decode2rename_t decode2rename_reg;
logic           rename_stall;

// 3. Rename to Dispatch
rename2dispatch_t rename2dispatch;
rename2dispatch_t rename2dispatch_reg;
logic             dispatch_stall;

// 4. Dispatch to RS (Inside Issue)
dispatch2rs_t dispatch2issue;
dispatch2rs_t dispatch2issue_reg;
logic         issue_stall;

// Dispatch to ROB (Combinational)
dispatch_2_rob_t dispatch_2_rob;

//ROB to Dispatch (Combinational)
logic [ROB_IDX_WIDTH-1:0] rob_idx_dispatch;
logic robfull;

// Rename submodules 
rename2frlist_t rename_to_frlist;
frlist2rename_t frlist_to_rename;
rename2prf_t rename_to_prf;
logic frlist_empty_sig, frlist_full_sig;

// 5. Issue to Execute 
issue2execute_t issue2execute;
issue2execute_t issue2execute_reg;
logic          execute_stall;

// 6. Execute to Writeback
execute2memory_t execute2memory;
execute2memory_t execute2memory_reg;
logic               mem_stall;


// 7- 
memory2writeback_t memory2writeback;
memory2writeback_t memory2writeback_reg;
logic              writeback_stall;




// Writeback to PRF
writeback2prf_t wb_to_prf;

// PRF to Rename and Rename to PRF
prf2rename_readybits_t prf2renameready ; 
rename2prf_ready_t rename2prfreadyidx ;

// PRF to Issue
logic [5:0] prf_rs1_issue_idx, prf_rs2_issue_idx;
logic [31:0] prf_rs1_data, prf_rs2_data;

// PRF to Commit
logic [31:0] rd_commit_data;
logic [PRF_IDX_WIDTH-1:0] rd_commit_idx;

// ROB to Commit
rob2commit_t rob2commit;
logic commit_ack ;
logic robempty;

// Commit to RVFI
commit2frlist_t commit_to_frlist;
commit2arf_t commit_to_arf;

commit2rat_t commit2rat ; 

// rvfi signals 
commit_rvfi_package commit2rvfi, commit2rvfi_reg;
logic [4:0] arf_rvfi_rs1_idx, arf_rvfi_rs2_idx;
logic [31:0] arf_rvfi_rs1_data, arf_rvfi_rs2_data;

always_ff @(posedge clk) begin
    if (rst) begin
        pc <= 32'haaaa_a000;
        commit2rvfi_reg <= '0 ; 
    end 
    
    else begin
        pc <= pc_next;  
        commit2rvfi_reg <= commit2rvfi;
    end
end

// Advance Fetch Logic
assign writetoqueue = write_to_instfifo && !instr_queue_fill ; 
assign pc_next = branchtaken? branch_target_addr : ((writetoqueue) ? (pc + 32'd4) : pc);


// 1-  decode to rename back pressure system 
always_ff @(posedge clk) begin
    if (rst || branchtaken) begin
        decode2rename_reg <= '0 ;   
    end else begin
        if(rename_stall) begin 
            decode2rename_reg <= decode2rename_reg ; 
        end else begin 
            decode2rename_reg <= decode2rename; 
        end        
    end
end

// 2 - rename to dispatch back pressure 
always_ff @(posedge clk) begin
    if (rst || branchtaken) begin
        rename2dispatch_reg <= '0;
    end else begin
        if (dispatch_stall) begin 
            rename2dispatch_reg <= rename2dispatch_reg;

            if (common_data_bus.complete && common_data_bus.has_rd) begin
                if (common_data_bus.phy_rd == rename2dispatch_reg.p_src1)
                    rename2dispatch_reg.phy_src1_ready <= 1'b1;
                if (common_data_bus.phy_rd == rename2dispatch_reg.p_src2)
                    rename2dispatch_reg.phy_src2_ready <= 1'b1;
            end

        end else begin 
            rename2dispatch_reg <= rename2dispatch;
        end
    end
end

//3 -  dispatch to issue  bck pressure 
always_ff @(posedge clk) begin
    if (rst || branchtaken) begin
        dispatch2issue_reg <= '0 ; 
    end else begin
        if(issue_stall) begin 
            dispatch2issue_reg <= dispatch2issue_reg ; 

            if (common_data_bus.complete && common_data_bus.has_rd) begin
                if (common_data_bus.phy_rd == dispatch2issue_reg.phy_src1)
                    dispatch2issue_reg.phy_src1_ready <= 1'b1;
                if (common_data_bus.phy_rd == dispatch2issue_reg.phy_src2)
                    dispatch2issue_reg.phy_src2_ready <= 1'b1;
            end

        end else begin 
            dispatch2issue_reg <= dispatch2issue; 
        end    
    end
end

//4 -  issue to execute bck pressure 
always_ff @(posedge clk) begin
    if (rst  || branchtaken)  begin
        issue2execute_reg <= '0 ; 
    end else begin
        if(issue_stall) begin 
            issue2execute_reg <=  issue2execute_reg ; 
        end else begin 
             issue2execute_reg <= issue2execute; 
        end    
    end
end

//5 -  execute to wb back presure 
always_ff @(posedge clk) begin
    if (rst || branchtaken) begin
        execute2memory_reg <= '0 ;     
    end else begin
        if(mem_stall) begin 
            execute2memory_reg <=  execute2memory_reg; 
        end else begin 
             execute2memory_reg <= execute2memory; 
        end     
    end
end



//6 - last ff block mem to wb:

always_ff @(posedge clk) begin
    if (rst || branchtaken) begin
        memory2writeback_reg <= '0;     
    end else begin
        if(writeback_stall) begin 
            memory2writeback_reg <= memory2writeback_reg;
        end else begin 
            memory2writeback_reg <= memory2writeback;
        end     
    end
end






















logic alu_filled ; 
logic mul_filled ; 
logic div_filled ; 
logic cmp_filled ; 
logic loadstore_filled ; 

if_stage fetch_inst(
    .pc(pc),
    .pc_next(pc_next),
    .imem_resp(i_ufp_resp),
    // .imem_cache_line(i_ufp_cacheline),
    .imem_rdata(imem_rdata),
    .branch_mispredict(1'b0), 
    .imem_addr(imem_addr),
    .imem_mask(imem_mask),
    .imem_stall(imem_stall),
    .write_inst_queue(write_to_instfifo), 
    .instruction_out(write_instr_fifo),
    .pc_out (write_pc_fifo),  // this will go to the i queue
    .branch_flush(branch_flush)
);

icache i_cache(
    .clk(clk),
    .rst(rst),
    .ufp_addr(imem_addr), 
    .ufp_rmask(imem_mask),
    .ufp_rdata(imem_rdata),
    .ufp_cacheline(i_ufp_cacheline),
    .ufp_resp(i_ufp_resp),
    .dfp_addr(icache_to_adapter_addr),
    .dfp_read(icache_to_adapter_read),
    .dfp_rdata(adapter_to_icache_rdata),
    .dfp_resp(adapter_to_icache_resp),
    .branch_flush (branch_flush),
    .dfp_addr_resp(cache_addr_resp)
);


dcache d_cache(
    .clk(clk),
    .rst(rst),

    .ufp_addr(dmem_addr), 
    .ufp_rmask(dmem_rmask),
    .ufp_wmask(dmem_wmask),
    .ufp_rdata(dmem_rdata),
    .ufp_wdata(d_ufp_wdata),
    .ufp_resp(d_ufp_resp),

    .dfp_addr(dcache_to_adapter_addr),
    .dfp_read(dcache_to_adapter_read),
    .dfp_write(dcache_to_adapter_write),
    .dfp_rdata(adapter_to_dcache_rdata),
    .dfp_wdata(dcache_to_adapter_wdata),
    .dfp_resp(adapter_to_dcache_resp),
    .dfp_addr_resp(d_cache_addr_resp), 
    .branch_flush (branch_flush)
);

i_burst_adapter burst_adapter_i(
    .clk(clk),
    .rst(rst),
    .bmem_ready(i_bmem_ready),
    .bmem_raddr(i_bmem_raddr),
    .bmem_rdata(i_bmem_rdata),
    .bmem_rvalid(i_bmem_rvalid),
    .bmem_addr(i_bmem_addr),
    .bmem_read(i_bmem_read),
    .bmem_write(i_bmem_write),
    .bmem_wdata(i_bmem_wdata),
    .cache_addr(icache_to_adapter_addr),
    .cache_read(icache_to_adapter_read),
    .cache_rdata(adapter_to_icache_rdata),
    .cache_resp(adapter_to_icache_resp),
    .i_cache_chosen(!choose_dcache),
    .cache_addr_resp(cache_addr_resp)
);

d_burst_adapter burst_adapter_d(
    .clk(clk),
    .rst(rst),
    .bmem_ready(d_bmem_ready),
    .bmem_raddr(d_bmem_raddr),
    .bmem_rdata(d_bmem_rdata),
    .bmem_rvalid(d_bmem_rvalid),
    .bmem_addr(d_bmem_addr),
    .bmem_read(d_bmem_read),
    .bmem_write(d_bmem_write),
    .bmem_wdata(d_bmem_wdata),
    .cache_addr(dcache_to_adapter_addr),
    .cache_read(dcache_to_adapter_read),
    .cache_write(dcache_to_adapter_write),
    .cache_wdata(dcache_to_adapter_wdata),
    .d_cache_chosen(choose_dcache),
    .cache_rdata(adapter_to_dcache_rdata),
    .cache_resp(adapter_to_dcache_resp),
    .cache_addr_resp(d_cache_addr_resp)
);

fetch_decode_queue fd_queue (
    .clk(clk),
    .rst(rst),
    .write(writetoqueue),
    .read(read_from_instfifo),
    .write_data(write_instr_fifo),
    .write_pc(write_pc_fifo), 
    .read_data(read_instr_fifo),
    .read_pc(read_pc_fifo),
    .filled(instr_queue_fill),
    .empty (instr_queue_empty), 
    .branch_flush(branch_flush)
);

id_stage decode_inst(
    .instruction(read_instr_fifo),
    .pc_in(read_pc_fifo),
    .queue_empty(instr_queue_empty),
    .decode_out(decode2rename),
    .read_queue(read_from_instfifo), 
    .rename_stall(rename_stall)
);

physicalregfile prf_inst(
    .clk(clk),
    .rst(rst),
    .wb2prf(wb_to_prf),
    .rename_alloc_rd(rename_to_prf),
    .rs1_idx(prf_rs1_issue_idx),
    .rs2_idx(prf_rs2_issue_idx),
    .rd_commit_idx (rd_commit_idx),
    .rs1_data(prf_rs1_data),
    .rs2_data(prf_rs2_data),
    .rd_commit_data (rd_commit_data), 
    .rename2prf_ready(rename2prfreadyidx), 
    .prf2renameready(prf2renameready), 
    .branch_flush(branch_flush), 
    .commit2rat(commit2rat)

);

freelist frlist_inst(
    .clk(clk),
    .rst(rst),
    .rename2frlist(rename_to_frlist),
    .commit2frlist(commit_to_frlist),
    .frlist2rename(frlist_to_rename),
    .frlist_full(frlist_full_sig),
    .frlist_empty(frlist_empty_sig), 
    .rob2frlist(rob2frlist)
);

rename_stage rename_inst(
    .clk(clk),
    .rst(rst),
    .decode2rename(decode2rename_reg),  
    .frlist2rename(frlist_to_rename),
    .frlist_empty(frlist_empty_sig),
    .rename2frlist(rename_to_frlist),
    .prf2renameready(prf2renameready),
    .rename2dispatch(rename2dispatch),
    .rename2prf(rename_to_prf),
    .rename_stall(rename_stall),
    .rename2prfreadyidx(rename2prfreadyidx), 
    .dispatch_stall(dispatch_stall), 
    .commit2rat(commit2rat), 
    .branch_flush(branch_flush)                              
);

dispatch dispatch_inst (
    .rename2dispatch(rename2dispatch_reg),
    .rob_idx_dispatch(rob_idx_dispatch),
    .dispatch2rs(dispatch2issue),
    .dispatch_2_rob(dispatch_2_rob),
    .robfull(robfull),
    .cdb_wakeup (common_data_bus), 
    .alu_filled(alu_filled), 
    .mul_filled(mul_filled), 
    .div_filled(div_filled), 
    .cmp_filled(cmp_filled), 
    .loadstore_filled(loadstore_filled),
    .dispatch_stall(dispatch_stall)
);

rob rob_inst (
    .clk (clk),
    .rst (rst),
    .dispatch_2_rob (dispatch_2_rob),
    .common_data_bus (common_data_bus),
    .rob_idx_dispatch (rob_idx_dispatch),
    .rob2commit (rob2commit),
    .robfull (robfull),
    .robempty (robempty),
    .commit_ack (commit_ack), 
    .lsq2robpack(lsq2rob), 
    .branchres2rob(branchres2rob), 
    .branch_flush(branch_flush), 
    .rob2frlist(rob2frlist), 
    .jumpresrob(jumpresrob)

);

issue_stage issue_inst (
    .clk (clk),
    .rst (rst),
    .common_data_bus (common_data_bus),
    .dispatch2issue (dispatch2issue),
    .prf_rs1_data (prf_rs1_data),
    .prf_rs2_data (prf_rs2_data),
    .prf_rs1_tag (prf_rs1_issue_idx),
    .prf_rs2_tag (prf_rs2_issue_idx),
    .issue2execute (issue2execute), 
    .alu_filled(alu_filled), 
    .mul_filled(mul_filled), 
    .div_filled(div_filled), 
    .cmp_filled(cmp_filled), 
    .loadstore_filled(loadstore_filled),
    .execute_stall(execute_stall), 
    .issue_stall(issue_stall), 
     .branch_flush(branch_flush)
);

execute execute_inst (
    .clk (clk),
    .rst (rst),
    .issue2execute (issue2execute_reg),
    .execute2mem (execute2memory), // change this to the execute2mem signal after making mem
    .execute_stall (execute_stall), 
   
    .mem_stall(mem_stall), 

    .branchres2rob(branchres2rob), 
    .branch_flush(branch_flush), 
    .jumpresrob(jumpresrob)
);




// new mem stage 

mem_stage mem_inst (
    .clk(clk),
    .rst(rst),
    
    // From execute
    .execute2memory(execute2memory_reg),
    
    // To writeback
    .memory2writeback(memory2writeback),
    
    // D-cache interface
    .dmem_addr(dmem_addr),
    .dmem_rmask(dmem_rmask),
    .dmem_wmask(dmem_wmask),
    .dmem_wdata(d_ufp_wdata),
    .dmem_resp(d_ufp_resp),
    .dmem_rdata(dmem_rdata),
    
    // Commit interface
    .commit2store(commit2store),
    .store2commit(store2commit),
    
    // ROB update
    .lsq2rob(lsq2rob),
    
    // Stall signal
    .mem_stall(mem_stall), 

    .branch_flush(branch_flush)
);






writeback_stage writeback_inst (
    .clk(clk),
    .rst(rst),
    .memory2writeback (memory2writeback_reg), // change this to mem to wb signal after making mem stage
    .common_data_bus (common_data_bus),
    .writeback2prf (wb_to_prf),
    .writeback_stall(writeback_stall), 
    .branch_flush(branch_flush)
);

commit_stage commit_inst (
    // .clk(clk),   // ADD
    // .rst(rst),   // ADD
    .rob2commit_in (rob2commit),  
    .rob_empty (robempty), 
    .prf_rd_val (rd_commit_data), 
    .commit2arf_rd (commit_to_arf),
    .commtit2frlist_rd (commit_to_frlist),
    .prf_commitrd_idx (rd_commit_idx),
    .rob_commit_ack (commit_ack), 
    .arf_rs1_read_idx(arf_rvfi_rs1_idx),
    .arf_rs2_read_idx(arf_rvfi_rs2_idx),
    .arf_rs1_read_data(arf_rvfi_rs1_data),
    .arf_rs2_read_data(arf_rvfi_rs2_data),
    .commit2rvfi(commit2rvfi), 
    .commit2store(commit2store),
    .store2commit(store2commit), 
    .branch_flush(branch_flush), 
    .commit2rat(commit2rat)
);

archregfile arf_inst (
    .clk (clk),
    .rst (rst),
    .commit2arch (commit_to_arf),
    .rvfi_rs1_idx(arf_rvfi_rs1_idx),
    .rvfi_rs2_idx(arf_rvfi_rs2_idx),
    .rvfi_rs1_data(arf_rvfi_rs1_data),
    .rvfi_rs2_data(arf_rvfi_rs2_data)
);

logic [63:0] rvfi_order;
always_ff @(posedge clk) begin
    if (rst) begin
        rvfi_order <= '0;
    end else begin
        if (commit2rvfi_reg.valid) begin
            rvfi_order <= rvfi_order + 64'h1;
        end
    end
end

endmodule : cpu