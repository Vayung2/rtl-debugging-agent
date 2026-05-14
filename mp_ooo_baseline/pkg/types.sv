package rv32i_types;
  typedef enum logic [6:0] {
    op_lui       = 7'b0110111, // load upper imemediate (U type)
    op_auipc     = 7'b0010111, // add upper imemediate PC (U type)
    op_jal       = 7'b1101111, // jump and link (J type)
    op_jalr      = 7'b1100111, // jump and link register (I type)
    op_br        = 7'b1100011, // branch (B type)
    op_load      = 7'b0000011, // load (I type)
    op_store     = 7'b0100011, // store (S type)
    op_imm       = 7'b0010011, // arith ops with register/imemediate operands (I type)
    op_reg       = 7'b0110011  // arith ops with register operands (R type)
  } rv32i_opcode;

  typedef enum logic [2:0] {
    beq  = 3'b000,
    bne  = 3'b001,
    blt  = 3'b100,
    bge  = 3'b101,
    bltu = 3'b110,
    bgeu = 3'b111
  } branch_funct3_t;

  typedef enum logic [2:0] {
    lb  = 3'b000,
    lh  = 3'b001,
    lw  = 3'b010,
    lbu = 3'b100,
    lhu = 3'b101
  } load_funct3_t;

  typedef enum logic [2:0] {
    sb = 3'b000,
    sh = 3'b001,
    sw = 3'b010
  } store_funct3_t;

  typedef enum logic [2:0] {
    add  = 3'b000, //check logic 30 for sub if op_reg opcode
    sll  = 3'b001,
    slt  = 3'b010,
    sltu = 3'b011,
    axor = 3'b100,
    sr   = 3'b101, //check logic 30 for logical/arithmetic
    aor  = 3'b110,
    aand = 3'b111
  } arith_funct3_t;

  typedef enum logic [2:0] {
    alu_add = 3'b000,
    alu_sll = 3'b001,
    alu_sra = 3'b010,
    alu_sub = 3'b011,
    alu_xor = 3'b100,
    alu_srl = 3'b101,
    alu_or  = 3'b110,
    alu_and = 3'b111
  } alu_ops;

  typedef enum logic {
    rs1_out = 1'b0,
    pc_out  = 1'b1
  } alu_m1_sel_t;

  // RV32 Parameters
  localparam integer ADDR_SIZE = 32;
  localparam integer ADDR_BITS = $clog2(ADDR_SIZE);
  localparam integer ARF_SIZE = 32;
  localparam integer ARF_IDX_WIDTH = $clog2(ARF_SIZE);

  // Cache Parameters
  localparam integer NUM_SETS = 16;
  localparam integer NUM_WAYS = 4;    // no. of ways per set
  localparam integer WAY_BITS = $clog2(NUM_WAYS);    // log 2 (4)
  localparam integer BLOCK_SIZE = 32; // in bytes
  localparam integer BLOCK_SIZE_BITS = BLOCK_SIZE * 8; // 256
  localparam integer OFFSET_BITS = 5; // [4:0]
  localparam integer SET_BITS = 4; // [8:5]
  localparam integer TAG_BITS = 32 - SET_BITS - OFFSET_BITS; // 23 bits
  localparam integer PLRU_BITS = NUM_WAYS - 1; // 3 bits

  // Burst Adapter Parameters
  localparam integer BURST_SIZE = 64;
  localparam integer BURST_COUNT = BLOCK_SIZE_BITS/BURST_SIZE; // 4
  
  // ROB Parameters
  localparam integer ROB_SIZE = 32;
  localparam integer ROB_IDX_WIDTH = $clog2(ROB_SIZE);

  // PRF, RAT Parameters
  localparam integer PRF_SIZE = 64;
  localparam integer PRF_IDX_WIDTH = $clog2(PRF_SIZE);

  // Issue Stage and Reservation Station Parameters
  localparam integer RS_SIZE = 16;
  localparam integer RS_IDX_WIDTH = $clog2(RS_SIZE);

  localparam integer MUL_QUEUE_DEPTH = 4;
  localparam integer DIV_QUEUE_DEPTH = 8;
  localparam integer MUL_STAGES = 1;

  localparam integer LSQ_QUEUE_DEPTH = 32 ; 
  localparam integer LSQ_WIDTH = $clog2(LSQ_QUEUE_DEPTH) ; 

  // localparam integer QUEUE_SIZE = 32; not allowed to use this acc to campuswire @vayun
  // localparam integer QUEUE_ENTRIES = 8;

  typedef struct packed{
    logic valid; 
    logic [6:0] opcode ; 
    logic [31:0] pc ; 
    logic has_rd ; 
    logic [4:0] arf_rs1;
    logic [4:0] arf_rs2 ;
    logic [31:0] instruction;
    logic [4:0] arf_rd ; 
    logic [5:0] new_phy_rd ; 
    logic [5:0] old_phy_rd ; 
    logic is_load ; 
    logic is_store ; 

    logic [3:0] dmem_rmask ; 
    logic [3:0] dmem_wmask ; 
    logic [ADDR_SIZE-1:0] dmem_addr ; 
    logic [ADDR_SIZE-1:0] dmem_wdata ;
    logic [ADDR_SIZE-1:0] dmem_rdata ; 
      
    logic jump ; 
    logic branch ; 
    logic branch_taken ; 
    logic [31:0] branchtg_addr ; 
    logic [5:0] branchfrlist_checpt ; 
    logic [5:0] branchtail_checpt ; 
    logic [5:0] freelistcount; 


    logic ready2commit ; 
    logic exception ; 
   
  }rob_entry_t ; 



//important: commond broadcast bus going to PRF, ROB, AND Issue queue, output of the writeback stage
  typedef struct packed{
    logic complete ; 
    logic [ROB_IDX_WIDTH-1:0] rob_idx;  // update based on the size of rob instantiated
    logic [5:0] phy_rd ; 
    logic has_rd ; 
  }common_data_bus_t ; 



  typedef struct packed {
    logic [ROB_IDX_WIDTH-1:0] rob_head_idx ; 
    logic commit ; 
    logic [31:0] pc ; 
    logic has_rd ; 
    logic [4:0] arf_rd ; 
    logic [5:0] new_phy_rd ; 
    logic [5:0] old_phy_rd ; 
    logic [4:0] arf_rs1;
    logic [4:0] arf_rs2 ;
    logic [31:0] instruction;
    logic is_load ; 
    logic is_store ; 
    
    logic [3:0] dmem_rmask ; 
    logic [3:0] dmem_wmask ; 
    logic [ADDR_SIZE-1:0] dmem_addr ; 
    logic [ADDR_SIZE-1:0] dmem_wdata ;

    logic jump ; 
    logic branch ; 
    logic branch_taken ; 
    logic [31:0] branchtg_addr ; 
  } rob2commit_t;



  typedef struct packed{   // final commit stage output which updated the arf
    logic [4:0] dest_arch_reg ; 
    logic [31:0] dest_arch_value ; 
    logic wr_enable ; 
  } commit2arf_t ; 




  typedef struct packed{
    logic [5:0] prf_rd_idx ; 
    logic [31:0] prf_rd_data ; 
    logic ready ;
  }writeback2prf_t ; 



  typedef struct packed {  // basically to allocate the new rd , based on the free list output, coming from the rename stage 
     logic alloc_en ; 
     logic [5:0] prf_rd_alloc_idx ; 
  } rename2prf_t  ;



  typedef struct packed {
    logic alloc_ack ; 
  } rename2frlist_t;




  typedef struct packed { 
    logic alloc_valid ; 
    logic [5:0] new_phy_rd ; 
    logic [5:0]  freelist_head; 
    logic [5:0]  freelist_tail ; 
    logic [5:0]  freelistcount ; 
  } frlist2rename_t;


  // new structs

    typedef struct packed {  // basically to read readybits
     logic [5:0] prf_rs1_ready; 
     logic [5:0] prf_rs2_ready ; 
  } rename2prf_ready_t  ;



//return to rename the ready bits 
  typedef struct packed {
    logic rs1_ready ; 
    logic rs2_ready ; 
  } prf2rename_readybits_t;





  typedef struct packed {
    logic free_en ; 
    logic [5:0] old_phy_rd ; 
  } commit2frlist_t;



  typedef struct packed { // struct defining what each RS entry contains

    logic valid ; // indicating if slot in RS is empty or filled
    logic [31:0] pc ; 
    logic [6:0] opcode ;
    logic [2:0] funct3 ; 
    logic [6:0] funct7 ; 
    logic [5:0] phy_src1 ;
    logic [5:0] phy_src2 ;
    logic phy_src1_ready ;
    logic phy_src2_ready ;
    logic has_rd ; 
    logic [5:0] phy_dest ;
    logic [ROB_IDX_WIDTH-1:0] rob_idx ;
    logic is_load ; 
    logic is_store ; 
    logic is_branch ;
    logic is_jump ; 

    logic has_imm ; 
    logic [31:0] imm ;


  } rs_entry_t;



// packet from dispatch indicating which particular RS- functional unit it needs to be sent to

  typedef struct packed {

    logic valid ;
    logic [31:0] pc ; 
    logic [2:0] rs_type ;   // which particular rs it gets routed to
    logic [6:0] opcode ; 
    logic [5:0] phy_src1 ;
    logic [5:0] phy_src2 ;
    logic phy_src1_ready ;
    logic phy_src2_ready ;
    logic [5:0] phy_dest ;
    logic [ROB_IDX_WIDTH-1:0] rob_idx ;
    logic [2:0] funct3; 
    logic [6:0] funct7;
    logic has_imm;
    logic [31:0]imm;  
    logic has_rd;
    logic is_store ; 
    logic is_load ; 
    logic is_branch ; 
    logic is_jump ; 
 

  } dispatch2rs_t;



  typedef struct packed {
    logic valid;
    logic [31:0] pc;
    logic [31:0] instruction ; 
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [4:0] rs1_a;
    logic [4:0] rs2_a;
    logic [4:0] rd_a;
    logic has_rd;
    logic is_alu_op;
    logic is_mul;
    logic is_div;
    logic is_load;
    logic is_store;
    logic is_branch;
    logic is_auipc;
    logic is_jal;
    logic is_jalr;
    logic uses_imm;
    logic [31:0]imm;
    logic [3:0] rmask;
    logic [3:0] wmask;
  } decode2rename_t;




  typedef struct packed {
    logic [31:0] pc;
    logic valid;
    logic [31:0] instruction ; 
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [5:0] p_src1 ; 
    logic [5:0] p_src2 ; 
   
    logic phy_src1_ready ;
    logic phy_src2_ready ;
    logic has_rd ; 
    logic [4:0] rd_a;
    logic [5:0] new_phy_rd ;
    logic [5:0] old_phy_rd ; 
    logic uses_imm;
    logic [31:0]imm;

    //rvfi 
    logic [4:0] rs1_a ; 
    logic [4:0] rs2_a ; 
    logic is_load;
    logic is_store;
    logic is_branch;
    logic is_jump ; 

    logic [5:0] freelist_head;  // only send 2 rob when it is a branch 
     logic [5:0] freelist_tail;

     logic [5:0] freelistcount ; 

    
  } rename2dispatch_t;






  typedef struct packed {

    logic alloc_en;
    logic [6:0]opcode;
    logic [31:0]pc;
    logic [5:0]old_phy_rd;
    logic [5:0]new_phy_rd;
    logic has_rd_check;
    logic [4:0] arf_rd;
    logic [4:0] arf_rs1;
    logic [4:0] arf_rs2 ;
    logic [31:0] instruction;
    logic jump ; 
    logic branch ; 
    logic branch_taken ; 
    logic [31:0] branchtg_addr ; 
    logic is_store ; 
    logic is_load ; 
    logic [31:0] dmem_addr ; 
    logic [3:0] dmem_rmask ; 
    logic [3:0] dmem_wmask ; 
    logic [31:0] dmem_wdata ; 
    logic [31:0] dmem_rdata ; 


     logic [5:0]freelist_head_checkpoint; // only matters it for branches
      logic [5:0]freelist_tail_checkpoint; 
     logic [5:0]freelistcount ; 


    


  } dispatch_2_rob_t;


  typedef struct packed {
    logic valid;
    logic [2:0] rs_type ; 
    rs_entry_t issued_entry ; 
    logic [31:0] phy_src1_v ; 
    logic [31:0] phy_src2_v ; 
    
  } issue2execute_t;


  typedef struct packed {
    logic result_ready;
    logic [31:0] result;
    logic [5:0] phy_rd;
    logic [ROB_IDX_WIDTH-1:0] rob_idx;
    logic has_rd;
    logic is_load;
    logic is_store;

    logic store_commited ; // set when the store at rob head and ready2commit

    logic loadunsigned ; 

    logic [31:0] dmem_rdata ; 
    logic [3:0] dmem_rmask;
    logic [3:0] dmem_wmask;
    logic [31:0] dmem_wdata;
  } FU_result;


    // typedef struct packed {
    // logic result_ready;
    // logic [31:0] result;
    // logic [5:0] phy_rd;
    // logic [ROB_IDX_WIDTH-1:0] rob_idx;
    // logic has_rd;
    // logic is_load;
    // logic is_store;

    // logic store_commited ; // set when the store at rob head and ready2commit

    // logic [31:0] dmem_rdata ; 
    // logic [3:0] dmem_rmask;
    // logic [3:0] dmem_wmask;
    // logic [31:0] dmem_wdata;
    // } LS_result;



  typedef struct packed {
    FU_result alu_result;
    FU_result mul_result;
    FU_result div_result;
    FU_result cmp_result;

    FU_result agu_result ; 
  } execute2memory_t;



// pass through for everything loads/stores
  typedef struct packed {
    FU_result alu_result;
    FU_result mul_result;
    FU_result div_result;
    FU_result cmp_result;

    FU_result LScomplete_result ; 
  } memory2writeback_t;





  // lsq entry

  typedef struct packed {
    logic valid ; 
    logic is_load ; 
    logic is_store ; 
    logic completed ; 
    logic issued ; 
    
    logic [ROB_IDX_WIDTH-1:0] rob_idx ; 
    logic has_rd ; 
    logic [PRF_IDX_WIDTH-1:0] phy_rd ; 
    logic store_commited ; 

    logic loadunsigned; 

    logic [3:0] dmem_rmask ; 
    logic [3:0] dmem_wmask ; 
    logic [ADDR_SIZE-1:0] dmem_addr ; 
    logic [ADDR_SIZE-1:0] dmem_wdata ;
    logic [ADDR_SIZE-1:0] dmem_rdata ;  
    
  } lsq_entry_t;



// update the rob with the dmem value when it gets lsq allocation 
typedef struct packed {

  logic valid ; 

  logic is_store ; 
  logic is_load ;

  logic [3:0] dmem_rmask ; 
  logic [3:0] dmem_wmask ; 
  logic [ADDR_SIZE-1:0] dmem_addr ; 
  logic [ADDR_SIZE-1:0] dmem_wdata ;
  logic [ADDR_SIZE-1:0] dmem_rdata ;  

  logic [ROB_IDX_WIDTH-1:0] rob_idx ; 

} lsq2rob_t;


  typedef struct packed {

    logic valid ; 

    logic [ROB_IDX_WIDTH-1:0] rob_idx ; 
    
  } commit2store_t;

  typedef struct packed {

    logic store_ack  ; // acnkowledgement when store completes only then release the rob head and send to rvfi

    logic [ROB_IDX_WIDTH-1:0] rob_idx ; 

    
  } store2commit_t;


  // branch resolution from execute 2 rob

  typedef struct packed {

    logic valid ; 

    logic [ROB_IDX_WIDTH-1:0] rob_idx ; 
    logic cmp_result ; 
    
  } branchres2rob_t;


  // branch resolution from execute 2 rob

  typedef struct packed {

    logic valid ; 

    logic [ROB_IDX_WIDTH-1:0] rob_idx ; 
    logic jalr ; 
    logic jal ; 
    logic [31:0] rs1 ; 
    
  } jumpresrob_t;



  typedef struct packed {

    logic valid ; 
    logic [ROB_IDX_WIDTH-1:0] rob_idx ; 
    logic branch ; 
    logic branch_taken ; 
    logic [31:0] branchtg_addr ; 
    logic jump ; 
    logic [5:0] commitrd ; // writeback value of jump should not be flushed
    
  } branch_flush_t;




// commit 2 rat update

typedef struct packed {

  logic commit_update ; 
  logic [4:0] commit_rd_idx ; 
  logic [5:0] commit_phy_rd ; 
  
} commit2rat_t;



// rob 2 free list (for mispredicts)

typedef struct packed {

    logic valid;
    logic [5:0] freelist_head;    
    logic [5:0] freelist_tail ;  
    logic [5:0] freelistcount ; 
    logic jump_flush ;          
    

  
} rob2frlist_t;




  typedef struct packed {


    logic valid;
    logic [31:0] inst;
    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic [31:0] rs1_rdata;
    logic [31:0] rs2_rdata;
    logic [4:0] rd_addr;
    logic [31:0] rd_wdata;
    logic [31:0] pc_rdata;
    logic [31:0] pc_wdata;
    // Memory signals (all zero for CP2)
    logic [31:0] mem_addr;
    logic [3:0] mem_rmask;
    logic [3:0] mem_wmask;
    logic [31:0] mem_rdata;
    logic [31:0] mem_wdata;

    
  } commit_rvfi_package;

































  typedef struct packed {
    logic read_request;
    logic [ADDR_SIZE-1:0] address;
    logic [SET_BITS-1:0] set_index;
    logic [TAG_BITS-1:0] tag;
  } pipelined_icache_fetch_to_compare_tag_t;


  typedef struct packed {
    logic   [ADDR_SIZE-1:0]  ufp_rdata;
    logic   [BLOCK_SIZE_BITS-1:0] ufp_cacheline;
    logic                    hit;
    logic                    read_request;
    logic   [WAY_BITS-1:0]  lru_way_index;
    logic   [PLRU_BITS-1:0]  plru_nxt;
    logic  [ADDR_SIZE-1:0]  address;
  } pipelined_icache_compare_tag_outputs_t;

endpackage