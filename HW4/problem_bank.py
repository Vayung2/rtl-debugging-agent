from __future__ import annotations

from dataclasses import dataclass, replace
from pathlib import Path


PASS_MARKER = "VERDICT: PASS"


FAMILY_A_CONTEXT = """Family A contains standalone stateful RTL microprotocols. These are not from the OoO processor repo; they serve as the continuity family from HW3 and test whether an LLM can implement cycle-accurate control/state behavior from a written spec."""


FAMILY_A_TRANSFER_HOOKS = """Shared Family A conventions: outputs are cycle-accurate, flush/cancel/error conditions have explicit priority, state must be retained across cycles, and hidden tests emphasize corner-case sequencing rather than just the common path."""


FAMILY_B_CONTEXT = """This problem is a standalone reconstruction of one file from the user's ECE 411 out-of-order RISC-V processor. Treat the source-file analogue as the real design target, not as a toy exercise. The real project used package-typed packets connected through rename, dispatch, common-data-bus wakeup, commit, branch-flush recovery, and memory ordering paths. The verifier keeps the interface local enough to compile in isolation, but it intentionally checks integration-style corner cases that arise only when this block is connected to the rest of an OoO core."""


FAMILY_B_TRANSFER_HOOKS = """Shared Family B conventions: reset clears architectural/speculative state to a known baseline; branch or recovery flushes have highest priority; CDB-style wakeup/completion can coincide with insertion; circular queues need explicit full/empty or count handling; same-cycle producer/consumer events must be merged explicitly; and age/order comparisons must use ROB order rather than physical slot order."""


def _repo_file(path: str) -> str:
    return (Path(__file__).resolve().parents[1] / path).read_text(encoding="utf-8")


REAL_TYPES_PREFIX = r"""`timescale 1ns/1ps
package rv32i_types;
  typedef enum logic [6:0] {
    op_lui = 7'b0110111, op_auipc = 7'b0010111, op_jal = 7'b1101111,
    op_jalr = 7'b1100111, op_br = 7'b1100011, op_load = 7'b0000011,
    op_store = 7'b0100011, op_imm = 7'b0010011, op_reg = 7'b0110011
  } rv32i_opcode;
  localparam integer ADDR_SIZE = 32;
  localparam integer ADDR_BITS = $clog2(ADDR_SIZE);
  localparam integer NUM_SETS = 16;
  localparam integer NUM_WAYS = 4;
  localparam integer WAY_BITS = $clog2(NUM_WAYS);
  localparam integer BLOCK_SIZE = 32;
  localparam integer BLOCK_SIZE_BITS = BLOCK_SIZE * 8;
  localparam integer OFFSET_BITS = 5;
  localparam integer SET_BITS = 4;
  localparam integer TAG_BITS = 32 - SET_BITS - OFFSET_BITS;
  localparam integer PLRU_BITS = NUM_WAYS - 1;
  localparam integer BURST_SIZE = 64;
  localparam integer BURST_COUNT = BLOCK_SIZE_BITS/BURST_SIZE;
  localparam integer ROB_SIZE = 32;
  localparam integer ROB_IDX_WIDTH = $clog2(ROB_SIZE);
  localparam integer PRF_SIZE = 64;
  localparam integer PRF_IDX_WIDTH = $clog2(PRF_SIZE);
  localparam integer RS_SIZE = 16;
  localparam integer RS_IDX_WIDTH = $clog2(RS_SIZE);
  typedef struct packed { logic commit_update; logic [4:0] commit_rd_idx; logic [5:0] commit_phy_rd; } commit2rat_t;
  typedef struct packed { logic valid; logic [ROB_IDX_WIDTH-1:0] rob_idx; logic branch; logic branch_taken; logic [31:0] branchtg_addr; logic jump; logic [5:0] commitrd; } branch_flush_t;
  typedef struct packed { logic alloc_ack; } rename2frlist_t;
  typedef struct packed { logic free_en; logic [5:0] old_phy_rd; } commit2frlist_t;
  typedef struct packed { logic alloc_valid; logic [5:0] new_phy_rd; logic [5:0] freelist_head; logic [5:0] freelist_tail; logic [5:0] freelistcount; } frlist2rename_t;
  typedef struct packed { logic valid; logic [5:0] freelist_head; logic [5:0] freelist_tail; logic [5:0] freelistcount; logic jump_flush; } rob2frlist_t;
  typedef struct packed { logic complete; logic [ROB_IDX_WIDTH-1:0] rob_idx; logic [5:0] phy_rd; logic has_rd; } common_data_bus_t;
  typedef struct packed {
    logic valid; logic [31:0] pc; logic [6:0] opcode; logic [2:0] funct3; logic [6:0] funct7;
    logic [5:0] phy_src1; logic [5:0] phy_src2; logic phy_src1_ready; logic phy_src2_ready;
    logic has_rd; logic [5:0] phy_dest; logic [ROB_IDX_WIDTH-1:0] rob_idx;
    logic is_load; logic is_store; logic is_branch; logic is_jump; logic has_imm; logic [31:0] imm;
  } rs_entry_t;
  typedef struct packed {
    logic valid; logic [31:0] pc; logic [2:0] rs_type; logic [6:0] opcode;
    logic [5:0] phy_src1; logic [5:0] phy_src2; logic phy_src1_ready; logic phy_src2_ready;
    logic [5:0] phy_dest; logic [ROB_IDX_WIDTH-1:0] rob_idx; logic [2:0] funct3; logic [6:0] funct7;
    logic has_imm; logic [31:0] imm; logic has_rd; logic is_store; logic is_load; logic is_branch; logic is_jump;
  } dispatch2rs_t;
  typedef struct packed {
    logic valid; logic [6:0] opcode; logic [31:0] pc; logic has_rd; logic [4:0] arf_rs1; logic [4:0] arf_rs2;
    logic [31:0] instruction; logic [4:0] arf_rd; logic [5:0] new_phy_rd; logic [5:0] old_phy_rd;
    logic is_load; logic is_store; logic [3:0] dmem_rmask; logic [3:0] dmem_wmask; logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata; logic [31:0] dmem_rdata; logic jump; logic branch; logic branch_taken;
    logic [31:0] branchtg_addr; logic [5:0] branchfrlist_checpt; logic [5:0] branchtail_checpt;
    logic [5:0] freelistcount; logic ready2commit; logic exception;
  } rob_entry_t;
  typedef struct packed {
    logic alloc_en; logic [6:0] opcode; logic [31:0] pc; logic [5:0] old_phy_rd; logic [5:0] new_phy_rd;
    logic has_rd_check; logic [4:0] arf_rd; logic [4:0] arf_rs1; logic [4:0] arf_rs2; logic [31:0] instruction;
    logic jump; logic branch; logic branch_taken; logic [31:0] branchtg_addr; logic is_store; logic is_load;
    logic [31:0] dmem_addr; logic [3:0] dmem_rmask; logic [3:0] dmem_wmask; logic [31:0] dmem_wdata; logic [31:0] dmem_rdata;
    logic [5:0] freelist_head_checkpoint; logic [5:0] freelist_tail_checkpoint; logic [5:0] freelistcount;
  } dispatch_2_rob_t;
  typedef struct packed {
    logic [ROB_IDX_WIDTH-1:0] rob_head_idx; logic commit; logic [31:0] pc; logic has_rd; logic [4:0] arf_rd;
    logic [5:0] new_phy_rd; logic [5:0] old_phy_rd; logic [4:0] arf_rs1; logic [4:0] arf_rs2; logic [31:0] instruction;
    logic is_load; logic is_store; logic [3:0] dmem_rmask; logic [3:0] dmem_wmask; logic [31:0] dmem_addr; logic [31:0] dmem_wdata;
    logic jump; logic branch; logic branch_taken; logic [31:0] branchtg_addr;
  } rob2commit_t;
  typedef struct packed { logic valid; logic is_store; logic is_load; logic [3:0] dmem_rmask; logic [3:0] dmem_wmask; logic [31:0] dmem_addr; logic [31:0] dmem_wdata; logic [31:0] dmem_rdata; logic [ROB_IDX_WIDTH-1:0] rob_idx; } lsq2rob_t;
  typedef struct packed { logic valid; logic [ROB_IDX_WIDTH-1:0] rob_idx; logic cmp_result; } branchres2rob_t;
  typedef struct packed { logic valid; logic [ROB_IDX_WIDTH-1:0] rob_idx; logic jalr; logic jal; logic [31:0] rs1; } jumpresrob_t;
  typedef struct packed { logic [4:0] dest_arch_reg; logic [31:0] dest_arch_value; logic wr_enable; } commit2arf_t;
  typedef struct packed { logic valid; logic [ROB_IDX_WIDTH-1:0] rob_idx; } commit2store_t;
  typedef struct packed { logic store_ack; logic [ROB_IDX_WIDTH-1:0] rob_idx; } store2commit_t;
  typedef struct packed { logic valid; logic [63:0] order; logic [31:0] inst; logic [4:0] rs1_addr; logic [4:0] rs2_addr; logic [31:0] rs1_rdata; logic [31:0] rs2_rdata; logic [4:0] rd_addr; logic [31:0] rd_wdata; logic [31:0] pc_rdata; logic [31:0] pc_wdata; logic [31:0] mem_addr; logic [3:0] mem_rmask; logic [3:0] mem_wmask; logic [31:0] mem_rdata; logic [31:0] mem_wdata; } commit_rvfi_package;
endpackage
"""


CACHE_ARRAY_SHIMS = r"""
module mp_cache_data_array (
  input logic clk0,
  input logic csb0,
  input logic web0,
  input logic [31:0] wmask0,
  input logic [3:0] addr0,
  input logic [255:0] din0,
  output logic [255:0] dout0
);
  logic [255:0] mem [15:0];
  assign dout0 = csb0 ? '0 : mem[addr0];
  always_ff @(posedge clk0) begin
    if (!csb0 && !web0) begin
      for (int i = 0; i < 32; i++) if (wmask0[i]) mem[addr0][8*i +: 8] <= din0[8*i +: 8];
    end
  end
endmodule

module mp_cache_tag_array (
  input logic clk0,
  input logic csb0,
  input logic web0,
  input logic [3:0] addr0,
  input logic [22:0] din0,
  output logic [22:0] dout0
);
  logic [22:0] mem [15:0];
  assign dout0 = csb0 ? '0 : mem[addr0];
  always_ff @(posedge clk0) begin
    if (!csb0 && !web0) mem[addr0] <= din0;
  end
endmodule

module sp_ff_array #(
  parameter WIDTH = 1
)(
  input logic clk0,
  input logic rst0,
  input logic csb0,
  input logic web0,
  input logic [3:0] addr0,
  input logic [WIDTH-1:0] din0,
  output logic [WIDTH-1:0] dout0
);
  logic [WIDTH-1:0] mem [15:0];
  assign dout0 = csb0 ? '0 : mem[addr0];
  always_ff @(posedge clk0) begin
    if (rst0) begin
      for (int i = 0; i < 16; i++) mem[i] <= '0;
    end else if (!csb0 && !web0) begin
      mem[addr0] <= din0;
    end
  end
endmodule
"""


@dataclass(frozen=True)
class ProblemSpec:
    problem_id: str
    title: str
    difficulty: str
    module_name: str
    interface: str
    problem_statement: str
    success_criteria: str
    justification: str
    public_testbench: str
    hidden_testbench: str
    reference_solution: str
    failing_solution: str
    family_label: str = ""
    source_file: str = ""
    family_context: str = ""
    transfer_hooks: str = ""

    def prompt(self) -> str:
        context = ""
        if self.family_label or self.source_file or self.family_context:
            context = (
                "Benchmark context:\n"
                f"- Family: {self.family_label or 'unspecified'}\n"
                f"- Source-file analogue: {self.source_file or 'standalone RTL exercise'}\n"
                f"{self.family_context}\n"
                "\n"
            )

        return (
            f"You are solving {self.problem_id}: {self.title}.\n\n"
            "Write a complete SystemVerilog module that exactly matches the required interface.\n"
            "Return exactly one JSON object with keys:\n"
            '- "module_sv": full raw SystemVerilog source code\n'
            '- "confidence": integer from 0 to 100\n\n'
            "Do not use markdown fences. Do not include any text before or after the JSON object.\n\n"
            f"{context}"
            "Problem statement:\n"
            f"{self.problem_statement}\n\n"
            "Required interface:\n"
            f"{self.interface}\n\n"
            "Success criteria:\n"
            f"{self.success_criteria}\n"
        )


P1 = ProblemSpec(
    problem_id="P1",
    title="Retry-Once Request Controller",
    difficulty="Easy",
    module_name="retry_once_ctrl",
    interface="""module retry_once_ctrl (
    input  logic clk,
    input  logic reset,
    input  logic start_i,
    input  logic ack_i,
    input  logic cancel_i,
    output logic req_o,
    output logic busy_o,
    output logic done_pulse_o,
    output logic error_pulse_o
);""",
    problem_statement="""Implement a request controller with one retry attempt.

Behavior:
- On reset, return to IDLE with all outputs low.
- In IDLE, `start_i=1` begins a transaction.
- Attempt 1 lasts exactly two wait cycles: `TRY1_W1` and `TRY1_W2`.
- During each try wait state, `req_o=1` and `busy_o=1`.
- If `ack_i=1` in either try wait state, transition to `DONE_PULSE` on the next cycle.
- If no acknowledgment arrives by the end of `TRY1_W2`, spend exactly one cycle in `COOLDOWN`, with `busy_o=1` and `req_o=0`.
- After cooldown, begin Attempt 2 with `TRY2_W1` and `TRY2_W2`, using the same acknowledgment rules.
- If no acknowledgment arrives by the end of `TRY2_W2`, transition to `ERROR_PULSE` for exactly one cycle.
- `cancel_i` has highest priority while busy. If asserted in any busy state, immediately abandon the transaction and return to IDLE on the next state update, with no done or error pulse.
- `start_i` is ignored outside IDLE.

Use `always_ff @(posedge clk or posedge reset)` for the state register and `always_comb` for next-state logic and Moore-style output decode.""",
    success_criteria="""- The module compiles as SystemVerilog.
- The first attempt lasts at most two wait cycles before either success or cooldown.
- Cooldown is exactly one cycle with `busy_o=1` and `req_o=0`.
- The second attempt also lasts at most two wait cycles.
- `done_pulse_o` and `error_pulse_o` are one-cycle pulses.
- `cancel_i` overrides acknowledgment and timeout progression while busy.""",
    justification="""This is already significantly harder than a textbook FSM because it requires explicit retry sequencing, a non-request cooldown state, and a cancellation priority rule that cuts across multiple active states.""",
    public_testbench=r"""`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic reset;
    logic start_i;
    logic ack_i;
    logic cancel_i;
    logic req_o;
    logic busy_o;
    logic done_pulse_o;
    logic error_pulse_o;

    retry_once_ctrl dut (
        .clk(clk),
        .reset(reset),
        .start_i(start_i),
        .ack_i(ack_i),
        .cancel_i(cancel_i),
        .req_o(req_o),
        .busy_o(busy_o),
        .done_pulse_o(done_pulse_o),
        .error_pulse_o(error_pulse_o)
    );

    always #5 clk = ~clk;

    task automatic step_and_check(
        input logic next_start,
        input logic next_ack,
        input logic next_cancel,
        input logic exp_req,
        input logic exp_busy,
        input logic exp_done,
        input logic exp_error,
        input string label
    );
        begin
            @(negedge clk);
            start_i = next_start;
            ack_i = next_ack;
            cancel_i = next_cancel;
            @(posedge clk);
            #1;
            if (
                req_o !== exp_req || busy_o !== exp_busy ||
                done_pulse_o !== exp_done || error_pulse_o !== exp_error
            ) begin
                $display(
                    "FAIL %s req=%b exp=%b busy=%b exp=%b done=%b exp=%b error=%b exp=%b",
                    label, req_o, exp_req, busy_o, exp_busy, done_pulse_o, exp_done, error_pulse_o, exp_error
                );
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1; start_i = 0; ack_i = 0; cancel_i = 0;
        @(posedge clk);
        reset = 0;

        step_and_check(1, 0, 0, 1, 1, 0, 0, "try1_w1");
        step_and_check(0, 1, 0, 1, 1, 0, 0, "ack_seen");
        step_and_check(0, 0, 0, 0, 0, 1, 0, "done_pulse");
        step_and_check(0, 0, 0, 0, 0, 0, 0, "idle");

        $display("VERDICT: PASS");
        $finish;
    end
endmodule
""",
    hidden_testbench=r"""`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic reset;
    logic start_i;
    logic ack_i;
    logic cancel_i;
    logic req_o;
    logic busy_o;
    logic done_pulse_o;
    logic error_pulse_o;

    retry_once_ctrl dut (
        .clk(clk),
        .reset(reset),
        .start_i(start_i),
        .ack_i(ack_i),
        .cancel_i(cancel_i),
        .req_o(req_o),
        .busy_o(busy_o),
        .done_pulse_o(done_pulse_o),
        .error_pulse_o(error_pulse_o)
    );

    always #5 clk = ~clk;

    task automatic step_and_check(
        input logic next_start,
        input logic next_ack,
        input logic next_cancel,
        input logic exp_req,
        input logic exp_busy,
        input logic exp_done,
        input logic exp_error,
        input string label
    );
        begin
            @(negedge clk);
            start_i = next_start;
            ack_i = next_ack;
            cancel_i = next_cancel;
            @(posedge clk);
            #1;
            if (
                req_o !== exp_req || busy_o !== exp_busy ||
                done_pulse_o !== exp_done || error_pulse_o !== exp_error
            ) begin
                $display(
                    "FAIL %s req=%b exp=%b busy=%b exp=%b done=%b exp=%b error=%b exp=%b",
                    label, req_o, exp_req, busy_o, exp_busy, done_pulse_o, exp_done, error_pulse_o, exp_error
                );
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1; start_i = 0; ack_i = 0; cancel_i = 0;
        @(posedge clk);
        reset = 0;

        step_and_check(0, 0, 0, 0, 0, 0, 0, "idle");
        step_and_check(1, 0, 0, 1, 1, 0, 0, "start_try1");
        step_and_check(0, 0, 0, 1, 1, 0, 0, "try1_w2");
        step_and_check(0, 0, 0, 0, 1, 0, 0, "cooldown");
        step_and_check(0, 0, 0, 1, 1, 0, 0, "try2_w1");
        step_and_check(0, 0, 0, 1, 1, 0, 0, "try2_w2");
        step_and_check(0, 0, 0, 0, 0, 0, 1, "error");
        step_and_check(0, 0, 0, 0, 0, 0, 0, "idle_after_error");

        step_and_check(1, 0, 0, 1, 1, 0, 0, "start_again");
        step_and_check(0, 1, 1, 0, 0, 0, 0, "cancel_beats_ack");
        step_and_check(0, 0, 0, 0, 0, 0, 0, "idle_after_cancel");

        $display("VERDICT: PASS");
        $finish;
    end
endmodule
""",
    reference_solution="""module retry_once_ctrl (
    input  logic clk,
    input  logic reset,
    input  logic start_i,
    input  logic ack_i,
    input  logic cancel_i,
    output logic req_o,
    output logic busy_o,
    output logic done_pulse_o,
    output logic error_pulse_o
);
    typedef enum logic [2:0] {
        IDLE,
        TRY1_W1,
        TRY1_W2,
        COOLDOWN,
        TRY2_W1,
        TRY2_W2,
        DONE_PULSE,
        ERROR_PULSE
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (start_i) next_state = TRY1_W1;
            TRY1_W1: if (cancel_i) next_state = IDLE; else if (ack_i) next_state = DONE_PULSE; else next_state = TRY1_W2;
            TRY1_W2: if (cancel_i) next_state = IDLE; else if (ack_i) next_state = DONE_PULSE; else next_state = COOLDOWN;
            COOLDOWN: if (cancel_i) next_state = IDLE; else next_state = TRY2_W1;
            TRY2_W1: if (cancel_i) next_state = IDLE; else if (ack_i) next_state = DONE_PULSE; else next_state = TRY2_W2;
            TRY2_W2: if (cancel_i) next_state = IDLE; else if (ack_i) next_state = DONE_PULSE; else next_state = ERROR_PULSE;
            DONE_PULSE: next_state = IDLE;
            ERROR_PULSE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always_comb begin
        req_o = 1'b0;
        busy_o = 1'b0;
        done_pulse_o = 1'b0;
        error_pulse_o = 1'b0;
        case (state)
            TRY1_W1, TRY1_W2, TRY2_W1, TRY2_W2: begin
                req_o = 1'b1;
                busy_o = 1'b1;
            end
            COOLDOWN: busy_o = 1'b1;
            DONE_PULSE: done_pulse_o = 1'b1;
            ERROR_PULSE: error_pulse_o = 1'b1;
            default: begin
            end
        endcase
    end
endmodule
""",
    failing_solution="""module retry_once_ctrl (
    input  logic clk,
    input  logic reset,
    input  logic start_i,
    input  logic ack_i,
    input  logic cancel_i,
    output logic req_o,
    output logic busy_o,
    output logic done_pulse_o,
    output logic error_pulse_o
);
    typedef enum logic [1:0] {
        IDLE,
        WAIT1,
        WAIT2,
        DONE_PULSE
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (start_i) next_state = WAIT1;
            WAIT1: if (ack_i) next_state = DONE_PULSE; else next_state = WAIT2;
            WAIT2: if (ack_i) next_state = DONE_PULSE; else next_state = IDLE;
            DONE_PULSE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always_comb begin
        req_o = (state == WAIT1) || (state == WAIT2);
        busy_o = req_o;
        done_pulse_o = (state == DONE_PULSE);
        error_pulse_o = 1'b0;
    end
endmodule
""",
)


P2 = ProblemSpec(
    problem_id="P4",
    title="Fair Locked Arbiter",
    difficulty="Hard",
    module_name="fair_lock_arbiter",
    interface="""module fair_lock_arbiter (
    input  logic clk,
    input  logic reset,
    input  logic req0_i,
    input  logic req1_i,
    input  logic hold_i,
    input  logic flush_i,
    output logic grant0_o,
    output logic grant1_o,
    output logic busy_o
);""",
    problem_statement="""Implement a two-client arbiter with fairness and lock behavior.

Behavior:
- On reset, the arbiter is idle and the fairness pointer prefers client 0.
- If idle and only one request is present, grant that client.
- If idle and both requests are present, grant the client that is currently preferred by the fairness pointer.
- Once a client is granted, `busy_o=1` and the grant remains asserted as long as that client continues requesting.
- If `hold_i=1`, the arbiter must keep the current grant locked, even if the other client is also requesting.
- If `hold_i=0` and both clients are requesting, the current grant may be released only after the current grantee drops its request.
- When a grant is released after a non-flush completion, update the fairness pointer to prefer the other client next time both request simultaneously.
- `flush_i` has highest priority: it clears any current grant immediately on the next state update and does not modify the fairness pointer.

Use `always_ff @(posedge clk or posedge reset)` and Moore-style output decode.""",
    success_criteria="""- The module compiles as SystemVerilog.
- The initial fairness preference is client 0.
- Simultaneous requests alternate fairly across completed grants.
- `hold_i` locks the current grant.
- `flush_i` clears the grant without changing the fairness pointer.
- `busy_o` is high whenever any grant is active.""",
    justification="""This is difficult because correct behavior depends on persistent fairness state, completion semantics, and a flush path that must not accidentally perturb the fairness pointer.""",
    public_testbench=r"""`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic reset;
    logic req0_i;
    logic req1_i;
    logic hold_i;
    logic flush_i;
    logic grant0_o;
    logic grant1_o;
    logic busy_o;

    fair_lock_arbiter dut (
        .clk(clk),
        .reset(reset),
        .req0_i(req0_i),
        .req1_i(req1_i),
        .hold_i(hold_i),
        .flush_i(flush_i),
        .grant0_o(grant0_o),
        .grant1_o(grant1_o),
        .busy_o(busy_o)
    );

    always #5 clk = ~clk;

    task automatic step_and_check(
        input logic next_req0,
        input logic next_req1,
        input logic next_hold,
        input logic next_flush,
        input logic exp_g0,
        input logic exp_g1,
        input logic exp_busy,
        input string label
    );
        begin
            @(negedge clk);
            req0_i = next_req0;
            req1_i = next_req1;
            hold_i = next_hold;
            flush_i = next_flush;
            @(posedge clk);
            #1;
            if (grant0_o !== exp_g0 || grant1_o !== exp_g1 || busy_o !== exp_busy) begin
                $display("FAIL %s g0=%b exp=%b g1=%b exp=%b busy=%b exp=%b",
                    label, grant0_o, exp_g0, grant1_o, exp_g1, busy_o, exp_busy);
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1; req0_i = 0; req1_i = 0; hold_i = 0; flush_i = 0;
        @(posedge clk);
        reset = 0;

        step_and_check(1, 1, 0, 0, 1, 0, 1, "first_tie_goes_0");
        step_and_check(0, 1, 0, 0, 0, 1, 1, "switch_to_1_when_0_drops");
        step_and_check(0, 0, 0, 0, 0, 0, 0, "idle");

        $display("VERDICT: PASS");
        $finish;
    end
endmodule
""",
    hidden_testbench=r"""`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic reset;
    logic req0_i;
    logic req1_i;
    logic hold_i;
    logic flush_i;
    logic grant0_o;
    logic grant1_o;
    logic busy_o;

    fair_lock_arbiter dut (
        .clk(clk),
        .reset(reset),
        .req0_i(req0_i),
        .req1_i(req1_i),
        .hold_i(hold_i),
        .flush_i(flush_i),
        .grant0_o(grant0_o),
        .grant1_o(grant1_o),
        .busy_o(busy_o)
    );

    always #5 clk = ~clk;

    task automatic step_and_check(
        input logic next_req0,
        input logic next_req1,
        input logic next_hold,
        input logic next_flush,
        input logic exp_g0,
        input logic exp_g1,
        input logic exp_busy,
        input string label
    );
        begin
            @(negedge clk);
            req0_i = next_req0;
            req1_i = next_req1;
            hold_i = next_hold;
            flush_i = next_flush;
            @(posedge clk);
            #1;
            if (grant0_o !== exp_g0 || grant1_o !== exp_g1 || busy_o !== exp_busy) begin
                $display("FAIL %s g0=%b exp=%b g1=%b exp=%b busy=%b exp=%b",
                    label, grant0_o, exp_g0, grant1_o, exp_g1, busy_o, exp_busy);
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1; req0_i = 0; req1_i = 0; hold_i = 0; flush_i = 0;
        @(posedge clk);
        reset = 0;

        step_and_check(1, 1, 0, 0, 1, 0, 1, "tie_0");
        step_and_check(1, 1, 1, 0, 1, 0, 1, "hold_locks_0");
        step_and_check(1, 1, 0, 1, 0, 0, 0, "flush_clears_without_rotate");
        step_and_check(1, 1, 0, 0, 1, 0, 1, "tie_0_again_after_flush");
        step_and_check(0, 1, 0, 0, 0, 1, 1, "handoff_to_1");
        step_and_check(0, 0, 0, 0, 0, 0, 0, "idle_after_1");
        step_and_check(1, 1, 0, 0, 1, 0, 1, "tie_now_prefers_0_again");
        step_and_check(1, 0, 0, 0, 1, 0, 1, "handoff_back_to_0");
        step_and_check(0, 0, 0, 0, 0, 0, 0, "idle_done");

        $display("VERDICT: PASS");
        $finish;
    end
endmodule
""",
    reference_solution="""module fair_lock_arbiter (
    input  logic clk,
    input  logic reset,
    input  logic req0_i,
    input  logic req1_i,
    input  logic hold_i,
    input  logic flush_i,
    output logic grant0_o,
    output logic grant1_o,
    output logic busy_o
);
    typedef enum logic [1:0] {
        IDLE,
        GNT0,
        GNT1
    } state_t;

    state_t state, next_state;
    logic prefer0_r, prefer0_next;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            prefer0_r <= 1'b1;
        end else begin
            state <= next_state;
            prefer0_r <= prefer0_next;
        end
    end

    always_comb begin
        next_state = state;
        prefer0_next = prefer0_r;

        if (flush_i) begin
            next_state = IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (req0_i && req1_i) next_state = prefer0_r ? GNT0 : GNT1;
                    else if (req0_i) next_state = GNT0;
                    else if (req1_i) next_state = GNT1;
                end
                GNT0: begin
                    if (!req0_i) begin
                        prefer0_next = 1'b0;
                        if (req1_i) next_state = GNT1;
                        else next_state = IDLE;
                    end
                end
                GNT1: begin
                    if (!req1_i) begin
                        prefer0_next = 1'b1;
                        if (req0_i) next_state = GNT0;
                        else next_state = IDLE;
                    end
                end
                default: next_state = IDLE;
            endcase
        end
    end

    always_comb begin
        grant0_o = (state == GNT0);
        grant1_o = (state == GNT1);
        busy_o = grant0_o || grant1_o;
    end
endmodule
""",
    failing_solution="""module fair_lock_arbiter (
    input  logic clk,
    input  logic reset,
    input  logic req0_i,
    input  logic req1_i,
    input  logic hold_i,
    input  logic flush_i,
    output logic grant0_o,
    output logic grant1_o,
    output logic busy_o
);
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            grant0_o <= 1'b0;
            grant1_o <= 1'b0;
        end else if (flush_i) begin
            grant0_o <= 1'b0;
            grant1_o <= 1'b0;
        end else if (req0_i) begin
            grant0_o <= 1'b1;
            grant1_o <= 1'b0;
        end else begin
            grant0_o <= 1'b0;
            grant1_o <= 1'b0;
        end
    end

    always_comb busy_o = grant0_o;
endmodule
""",
)


P3 = ProblemSpec(
    problem_id="P5",
    title="Escaped Frame Receiver",
    difficulty="Hard",
    module_name="escaped_frame_rx",
    interface="""module escaped_frame_rx (
    input  logic clk,
    input  logic reset,
    input  logic byte_valid_i,
    input  logic [7:0] byte_i,
    output logic busy_o,
    output logic frame_done_o,
    output logic frame_error_o,
    output logic [7:0] payload_xor_o
);""",
    problem_statement="""Implement a byte-oriented frame receiver with escape handling.

Protocol:
- A frame begins with start delimiter `8'h7E`.
- The next unescaped byte is the payload length `N`, where only `1`, `2`, or `3` are legal lengths.
- Then exactly `N` payload bytes follow.
- Then one checksum byte follows. A frame is valid only if checksum equals the XOR of the length byte and all unescaped payload bytes.
- Escape byte is `8'h7D`. Whenever an escape byte appears inside a frame, the next byte is unescaped as `byte_i ^ 8'h20`.
- The start delimiter is only recognized in IDLE.
- If any protocol violation occurs inside a frame, emit `frame_error_o=1` for exactly one cycle and return to IDLE.
- On a valid frame, emit `frame_done_o=1` for exactly one cycle and drive `payload_xor_o` with the XOR of the unescaped payload bytes only.
- Outside `frame_done_o`, `payload_xor_o` may hold its previous value.
- `busy_o=1` while inside a frame but low in IDLE, DONE, and ERROR pulse states.

Use sequential logic with `always_ff @(posedge clk or posedge reset)`.""",
    success_criteria="""- The module compiles as SystemVerilog.
- The receiver handles legal lengths 1, 2, and 3 only.
- Escape processing applies only inside frames and transforms the following byte with XOR 8'h20.
- Checksum uses the length byte and unescaped payload bytes.
- `frame_done_o` and `frame_error_o` are one-cycle pulses.
- `busy_o` correctly reflects in-frame activity.""",
    justification="""This is much harder because correctness depends on multi-byte state, escape semantics, checksum accumulation, and exact frame recovery after errors.""",
    public_testbench=r"""`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic reset;
    logic byte_valid_i;
    logic [7:0] byte_i;
    logic busy_o;
    logic frame_done_o;
    logic frame_error_o;
    logic [7:0] payload_xor_o;

    escaped_frame_rx dut (
        .clk(clk),
        .reset(reset),
        .byte_valid_i(byte_valid_i),
        .byte_i(byte_i),
        .busy_o(busy_o),
        .frame_done_o(frame_done_o),
        .frame_error_o(frame_error_o),
        .payload_xor_o(payload_xor_o)
    );

    always #5 clk = ~clk;

    task automatic send_and_check(
        input logic next_valid,
        input logic [7:0] next_byte,
        input logic exp_busy,
        input logic exp_done,
        input logic exp_error,
        input logic [7:0] exp_xor,
        input string label
    );
        begin
            @(negedge clk);
            byte_valid_i = next_valid;
            byte_i = next_byte;
            @(posedge clk);
            #1;
            if (busy_o !== exp_busy || frame_done_o !== exp_done || frame_error_o !== exp_error || payload_xor_o !== exp_xor) begin
                $display("FAIL %s busy=%b exp=%b done=%b exp=%b err=%b exp=%b xor=%h exp=%h",
                    label, busy_o, exp_busy, frame_done_o, exp_done, frame_error_o, exp_error, payload_xor_o, exp_xor);
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1; byte_valid_i = 0; byte_i = 8'h00;
        @(posedge clk);
        reset = 0;

        send_and_check(1, 8'h7E, 1, 0, 0, 8'h00, "start");
        send_and_check(1, 8'h02, 1, 0, 0, 8'h00, "len2");
        send_and_check(1, 8'h11, 1, 0, 0, 8'h11, "p0");
        send_and_check(1, 8'h22, 1, 0, 0, 8'h33, "p1");
        send_and_check(1, 8'h31, 0, 1, 0, 8'h33, "checksum_ok");

        $display("VERDICT: PASS");
        $finish;
    end
endmodule
""",
    hidden_testbench=r"""`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic reset;
    logic byte_valid_i;
    logic [7:0] byte_i;
    logic busy_o;
    logic frame_done_o;
    logic frame_error_o;
    logic [7:0] payload_xor_o;

    escaped_frame_rx dut (
        .clk(clk),
        .reset(reset),
        .byte_valid_i(byte_valid_i),
        .byte_i(byte_i),
        .busy_o(busy_o),
        .frame_done_o(frame_done_o),
        .frame_error_o(frame_error_o),
        .payload_xor_o(payload_xor_o)
    );

    always #5 clk = ~clk;

    task automatic send_and_check(
        input logic next_valid,
        input logic [7:0] next_byte,
        input logic exp_busy,
        input logic exp_done,
        input logic exp_error,
        input logic [7:0] exp_xor,
        input string label
    );
        begin
            @(negedge clk);
            byte_valid_i = next_valid;
            byte_i = next_byte;
            @(posedge clk);
            #1;
            if (busy_o !== exp_busy || frame_done_o !== exp_done || frame_error_o !== exp_error || payload_xor_o !== exp_xor) begin
                $display("FAIL %s busy=%b exp=%b done=%b exp=%b err=%b exp=%b xor=%h exp=%h",
                    label, busy_o, exp_busy, frame_done_o, exp_done, frame_error_o, exp_error, payload_xor_o, exp_xor);
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1; byte_valid_i = 0; byte_i = 8'h00;
        @(posedge clk);
        reset = 0;

        send_and_check(0, 8'h00, 0, 0, 0, 8'h00, "idle");
        send_and_check(1, 8'h7E, 1, 0, 0, 8'h00, "start1");
        send_and_check(1, 8'h01, 1, 0, 0, 8'h00, "len1");
        send_and_check(1, 8'h7D, 1, 0, 0, 8'h00, "escape");
        send_and_check(1, 8'h5E, 1, 0, 0, 8'h7E, "escaped_payload");
        send_and_check(1, 8'h7F, 0, 1, 0, 8'h7E, "checksum_ok_escape");

        send_and_check(1, 8'h7E, 0, 0, 0, 8'h7E, "start2_seen_while_done_exits");
        send_and_check(1, 8'h7E, 1, 0, 0, 8'h7E, "start2");
        send_and_check(1, 8'h04, 0, 0, 1, 8'h7E, "illegal_len");
        send_and_check(0, 8'h00, 0, 0, 0, 8'h7E, "idle_after_err");

        send_and_check(1, 8'h7E, 1, 0, 0, 8'h7E, "start3");
        send_and_check(1, 8'h02, 1, 0, 0, 8'h00, "len2_b");
        send_and_check(1, 8'h10, 1, 0, 0, 8'h10, "pb0");
        send_and_check(1, 8'h20, 1, 0, 0, 8'h30, "pb1");
        send_and_check(1, 8'h33, 0, 0, 1, 8'h30, "bad_checksum");

        $display("VERDICT: PASS");
        $finish;
    end
endmodule
""",
    reference_solution="""module escaped_frame_rx (
    input  logic clk,
    input  logic reset,
    input  logic byte_valid_i,
    input  logic [7:0] byte_i,
    output logic busy_o,
    output logic frame_done_o,
    output logic frame_error_o,
    output logic [7:0] payload_xor_o
);
    typedef enum logic [2:0] {
        IDLE,
        WAIT_LEN,
        WAIT_PAYLOAD,
        WAIT_CKSUM,
        ESCAPE,
        DONE_PULSE,
        ERROR_PULSE
    } state_t;

    state_t state, next_state, return_state_r, return_state_next;
    logic [1:0] payloads_left_r, payloads_left_next;
    logic [7:0] checksum_acc_r, checksum_acc_next;
    logic [7:0] payload_xor_r, payload_xor_next;
    logic [7:0] esc_byte;

    always_comb esc_byte = byte_i ^ 8'h20;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            return_state_r <= IDLE;
            payloads_left_r <= 2'd0;
            checksum_acc_r <= 8'h00;
            payload_xor_r <= 8'h00;
        end else begin
            state <= next_state;
            return_state_r <= return_state_next;
            payloads_left_r <= payloads_left_next;
            checksum_acc_r <= checksum_acc_next;
            payload_xor_r <= payload_xor_next;
        end
    end

    always_comb begin
        next_state = state;
        return_state_next = return_state_r;
        payloads_left_next = payloads_left_r;
        checksum_acc_next = checksum_acc_r;
        payload_xor_next = payload_xor_r;

        case (state)
            IDLE: begin
                if (byte_valid_i && byte_i == 8'h7E) begin
                    next_state = WAIT_LEN;
                    payloads_left_next = 2'd0;
                    checksum_acc_next = 8'h00;
                end
            end

            WAIT_LEN: begin
                if (byte_valid_i) begin
                    if (byte_i == 8'h7D) begin
                        return_state_next = WAIT_LEN;
                        next_state = ESCAPE;
                    end else if (byte_i >= 8'd1 && byte_i <= 8'd3) begin
                        payloads_left_next = byte_i[1:0];
                        checksum_acc_next = byte_i;
                        next_state = WAIT_PAYLOAD;
                    end else begin
                        next_state = ERROR_PULSE;
                    end
                end
            end

            WAIT_PAYLOAD: begin
                if (byte_valid_i) begin
                    if (byte_i == 8'h7D) begin
                        return_state_next = WAIT_PAYLOAD;
                        next_state = ESCAPE;
                    end else begin
                        checksum_acc_next = checksum_acc_r ^ byte_i;
                        payload_xor_next = (payloads_left_r == 2'd1 && state == WAIT_PAYLOAD && payloads_left_r == 2'd1 && return_state_r == return_state_r)
                            ? (payload_xor_r ^ byte_i)
                            : (payload_xor_r ^ byte_i);
                        if (payloads_left_r == 2'd1) begin
                            next_state = WAIT_CKSUM;
                        end
                        payloads_left_next = payloads_left_r - 2'd1;
                    end
                end
            end

            WAIT_CKSUM: begin
                if (byte_valid_i) begin
                    if (byte_i == 8'h7D) begin
                        return_state_next = WAIT_CKSUM;
                        next_state = ESCAPE;
                    end else if (byte_i == checksum_acc_r) begin
                        next_state = DONE_PULSE;
                    end else begin
                        next_state = ERROR_PULSE;
                    end
                end
            end

            ESCAPE: begin
                if (byte_valid_i) begin
                    if (return_state_r == WAIT_LEN) begin
                        if (esc_byte >= 8'd1 && esc_byte <= 8'd3) begin
                            payloads_left_next = esc_byte[1:0];
                            checksum_acc_next = esc_byte;
                            next_state = WAIT_PAYLOAD;
                        end else begin
                            next_state = ERROR_PULSE;
                        end
                    end else if (return_state_r == WAIT_PAYLOAD) begin
                        checksum_acc_next = checksum_acc_r ^ esc_byte;
                        payload_xor_next = payload_xor_r ^ esc_byte;
                        if (payloads_left_r == 2'd1) next_state = WAIT_CKSUM;
                        else next_state = WAIT_PAYLOAD;
                        payloads_left_next = payloads_left_r - 2'd1;
                    end else if (return_state_r == WAIT_CKSUM) begin
                        if (esc_byte == checksum_acc_r) next_state = DONE_PULSE;
                        else next_state = ERROR_PULSE;
                    end else begin
                        next_state = ERROR_PULSE;
                    end
                end
            end

            DONE_PULSE: next_state = IDLE;
            ERROR_PULSE: next_state = IDLE;
            default: next_state = IDLE;
        endcase

        if (state == IDLE && byte_valid_i && byte_i == 8'h7E) begin
            payload_xor_next = payload_xor_r;
        end
        if (state == WAIT_LEN && byte_valid_i && ((byte_i >= 8'd1 && byte_i <= 8'd3) || byte_i == 8'h7D)) begin
            payload_xor_next = 8'h00;
        end
    end

    always_comb begin
        busy_o = (state == WAIT_LEN) || (state == WAIT_PAYLOAD) || (state == WAIT_CKSUM) || (state == ESCAPE);
        frame_done_o = (state == DONE_PULSE);
        frame_error_o = (state == ERROR_PULSE);
        payload_xor_o = payload_xor_r;
    end
endmodule
""",
    failing_solution="""module escaped_frame_rx (
    input  logic clk,
    input  logic reset,
    input  logic byte_valid_i,
    input  logic [7:0] byte_i,
    output logic busy_o,
    output logic frame_done_o,
    output logic frame_error_o,
    output logic [7:0] payload_xor_o
);
    logic in_frame;
    logic [7:0] xor_r;
    logic [1:0] count_r;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            in_frame <= 1'b0;
            xor_r <= 8'h00;
            count_r <= 2'd0;
            frame_done_o <= 1'b0;
            frame_error_o <= 1'b0;
        end else begin
            frame_done_o <= 1'b0;
            frame_error_o <= 1'b0;
            if (byte_valid_i && byte_i == 8'h7E) begin
                in_frame <= 1'b1;
                count_r <= 2'd0;
                xor_r <= 8'h00;
            end else if (in_frame && byte_valid_i) begin
                xor_r <= xor_r ^ byte_i;
                count_r <= count_r + 2'd1;
                if (count_r == 2'd2) begin
                    frame_done_o <= 1'b1;
                    in_frame <= 1'b0;
                end
            end
        end
    end

    always_comb begin
        busy_o = in_frame;
        payload_xor_o = xor_r;
    end
endmodule
""",
)


P4 = ProblemSpec(
    problem_id="P3",
    title="Replay-Aware Two-Entry FIFO",
    difficulty="Medium",
    module_name="replay_fifo2",
    interface="""module replay_fifo2 (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic replay_i,
    input  logic in_valid,
    input  logic [7:0] in_data,
    output logic in_ready,
    output logic out_valid,
    output logic [7:0] out_data,
    input  logic out_ready
);""",
    problem_statement="""Implement a two-entry FIFO with replay and flush behavior.

Behavior:
- Capacity is exactly two items.
- FIFO order must be preserved.
- `in_ready` is high when at least one free slot is available.
- `out_valid` is high when at least one item is stored.
- If `out_valid && out_ready && !replay_i`, the head item is popped.
- If `replay_i=1` while `out_valid=1`, the current head item must remain at the head even if `out_ready=1`.
- A replayed head item can still coexist with a new enqueue in the same cycle if space remains.
- `flush_i` has highest priority and clears the FIFO on the next state update, regardless of replay or enqueue/dequeue activity.
- `flush_i` also forces `out_valid=0` after the update.

Use `always_ff @(posedge clk or posedge reset)` with combinational output logic.""",
    success_criteria="""- The module compiles as SystemVerilog.
- FIFO order is preserved across enqueue, dequeue, and replay.
- Replay prevents the head item from being popped.
- Simultaneous enqueue and dequeue updates occupancy correctly.
- `flush_i` clears all stored data regardless of other signals.
- `in_ready` and `out_valid` match the actual two-entry occupancy.""",
    justification="""This is difficult because the replay path breaks the usual dequeue semantics and creates several occupancy corner cases when enqueue, dequeue, replay, and flush all interact.""",
    public_testbench=r"""`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic reset;
    logic flush_i;
    logic replay_i;
    logic in_valid;
    logic [7:0] in_data;
    logic in_ready;
    logic out_valid;
    logic [7:0] out_data;
    logic out_ready;

    replay_fifo2 dut (
        .clk(clk),
        .reset(reset),
        .flush_i(flush_i),
        .replay_i(replay_i),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_data(out_data),
        .out_ready(out_ready)
    );

    always #5 clk = ~clk;

    task automatic step_and_check(
        input logic next_flush,
        input logic next_replay,
        input logic next_in_valid,
        input logic [7:0] next_in_data,
        input logic next_out_ready,
        input logic exp_in_ready,
        input logic exp_out_valid,
        input logic [7:0] exp_out_data,
        input string label
    );
        begin
            @(negedge clk);
            flush_i = next_flush;
            replay_i = next_replay;
            in_valid = next_in_valid;
            in_data = next_in_data;
            out_ready = next_out_ready;
            @(posedge clk);
            #1;
            if (in_ready !== exp_in_ready || out_valid !== exp_out_valid || out_data !== exp_out_data) begin
                $display("FAIL %s in_ready=%b exp=%b out_valid=%b exp=%b out_data=%h exp=%h",
                    label, in_ready, exp_in_ready, out_valid, exp_out_valid, out_data, exp_out_data);
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1; flush_i = 0; replay_i = 0; in_valid = 0; in_data = 8'h00; out_ready = 0;
        @(posedge clk);
        reset = 0;

        step_and_check(0, 0, 1, 8'h11, 0, 1, 1, 8'h11, "push1");
        step_and_check(0, 0, 1, 8'h22, 0, 0, 1, 8'h11, "push2");
        step_and_check(0, 1, 0, 8'h00, 1, 0, 1, 8'h11, "replay_keeps_head");
        step_and_check(0, 0, 0, 8'h00, 1, 1, 1, 8'h22, "pop_to_second");

        $display("VERDICT: PASS");
        $finish;
    end
endmodule
""",
    hidden_testbench=r"""`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic reset;
    logic flush_i;
    logic replay_i;
    logic in_valid;
    logic [7:0] in_data;
    logic in_ready;
    logic out_valid;
    logic [7:0] out_data;
    logic out_ready;

    replay_fifo2 dut (
        .clk(clk),
        .reset(reset),
        .flush_i(flush_i),
        .replay_i(replay_i),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_data(out_data),
        .out_ready(out_ready)
    );

    always #5 clk = ~clk;

    task automatic step_and_check(
        input logic next_flush,
        input logic next_replay,
        input logic next_in_valid,
        input logic [7:0] next_in_data,
        input logic next_out_ready,
        input logic exp_in_ready,
        input logic exp_out_valid,
        input logic [7:0] exp_out_data,
        input string label
    );
        begin
            @(negedge clk);
            flush_i = next_flush;
            replay_i = next_replay;
            in_valid = next_in_valid;
            in_data = next_in_data;
            out_ready = next_out_ready;
            @(posedge clk);
            #1;
            if (in_ready !== exp_in_ready || out_valid !== exp_out_valid || out_data !== exp_out_data) begin
                $display("FAIL %s in_ready=%b exp=%b out_valid=%b exp=%b out_data=%h exp=%h",
                    label, in_ready, exp_in_ready, out_valid, exp_out_valid, out_data, exp_out_data);
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1; flush_i = 0; replay_i = 0; in_valid = 0; in_data = 8'h00; out_ready = 0;
        @(posedge clk);
        reset = 0;

        step_and_check(0, 0, 0, 8'h00, 0, 1, 0, 8'h00, "idle");
        step_and_check(0, 0, 1, 8'ha1, 0, 1, 1, 8'ha1, "push_a1");
        step_and_check(0, 0, 1, 8'hb2, 0, 0, 1, 8'ha1, "push_b2");
        step_and_check(0, 1, 0, 8'h00, 1, 0, 1, 8'ha1, "replay_a1");
        step_and_check(0, 0, 1, 8'hc3, 1, 1, 1, 8'hb2, "pop_a1_keep_b2");
        step_and_check(0, 0, 0, 8'h00, 1, 1, 0, 8'hb2, "pop_b2");
        step_and_check(0, 0, 1, 8'hc3, 0, 1, 1, 8'hc3, "push_c3");
        step_and_check(1, 0, 1, 8'hd4, 1, 1, 0, 8'hc3, "flush_beats_all");
        step_and_check(0, 0, 1, 8'he5, 1, 1, 1, 8'he5, "push_after_flush");
        step_and_check(0, 0, 0, 8'h00, 1, 1, 0, 8'he5, "drain");

        $display("VERDICT: PASS");
        $finish;
    end
endmodule
""",
    reference_solution="""module replay_fifo2 (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic replay_i,
    input  logic in_valid,
    input  logic [7:0] in_data,
    output logic in_ready,
    output logic out_valid,
    output logic [7:0] out_data,
    input  logic out_ready
);
    logic [7:0] fifo0_r, fifo1_r;
    logic [1:0] count_r;
    logic pop_i, push_i;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            count_r <= 2'd0;
            fifo0_r <= 8'h00;
            fifo1_r <= 8'h00;
        end else if (flush_i) begin
            count_r <= 2'd0;
        end else begin
            case ({push_i, pop_i})
                2'b10: begin
                    if (count_r == 2'd0) fifo0_r <= in_data;
                    else fifo1_r <= in_data;
                    count_r <= count_r + 2'd1;
                end
                2'b01: begin
                    if (count_r == 2'd2) fifo0_r <= fifo1_r;
                    count_r <= count_r - 2'd1;
                end
                2'b11: begin
                    if (count_r == 2'd1) fifo0_r <= in_data;
                    else if (count_r == 2'd2) begin
                        fifo0_r <= fifo1_r;
                        fifo1_r <= in_data;
                    end
                    count_r <= count_r;
                end
                default: begin
                end
            endcase
        end
    end

    always_comb begin
        in_ready = (count_r != 2'd2);
        out_valid = (count_r != 2'd0);
        out_data = fifo0_r;
        pop_i = out_valid && out_ready && !replay_i;
        push_i = in_valid && in_ready;
    end
endmodule
""",
    failing_solution="""module replay_fifo2 (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic replay_i,
    input  logic in_valid,
    input  logic [7:0] in_data,
    output logic in_ready,
    output logic out_valid,
    output logic [7:0] out_data,
    input  logic out_ready
);
    logic [7:0] fifo0_r, fifo1_r;
    logic [1:0] count_r;

    always_ff @(posedge clk or posedge reset) begin
        if (reset || flush_i) begin
            count_r <= 2'd0;
            fifo0_r <= 8'h00;
            fifo1_r <= 8'h00;
        end else begin
            if (in_valid && count_r != 2'd2) begin
                if (count_r == 2'd0) fifo0_r <= in_data;
                else fifo1_r <= in_data;
                count_r <= count_r + 2'd1;
            end else if (out_valid && out_ready) begin
                if (count_r == 2'd2) fifo0_r <= fifo1_r;
                count_r <= count_r - 2'd1;
            end
        end
    end

    always_comb begin
        in_ready = (count_r != 2'd2);
        out_valid = (count_r != 2'd0);
        out_data = fifo0_r;
    end
endmodule
""",
)


P5 = ProblemSpec(
    problem_id="P2",
    title="Front-End Priority Controller",
    difficulty="Easy",
    module_name="front_end_ctrl",
    interface="""module front_end_ctrl (
    input  logic clk,
    input  logic reset,
    input  logic run_i,
    input  logic stall_i,
    input  logic branch_flush_i,
    input  logic replay_i,
    input  logic pause_req_i,
    input  logic continue_i,
    input  logic mem_done_i,
    input  logic fault_i,
    output logic halted_o,
    output logic fetch_busy_o,
    output logic ld_mar_o,
    output logic ld_ir_o,
    output logic ld_pc_o,
    output logic mem_en_o,
    output logic replay_pulse_o,
    output logic pause_led_o,
    output logic fault_o
);""",
    problem_statement="""Implement a Moore-style front-end controller with strict cross-state priority rules.

States:
- `HALT`
- `FETCH_ADDR`
- `FETCH_WAIT1`
- `FETCH_WAIT2`
- `FETCH_LOAD`
- `DECODE`
- `EXECUTE`
- `REPLAY_PULSE`
- `PAUSE_WAIT_PRESS`
- `PAUSE_WAIT_RELEASE`
- `FAULT_HALT`

Required sequencing:
- Reset enters `HALT`.
- In `HALT`, wait until `run_i==1`, then go to `FETCH_ADDR`.
- `FETCH_ADDR` lasts one cycle and asserts `ld_mar_o=1`, `ld_pc_o=1`, `fetch_busy_o=1`.
- `FETCH_WAIT1` and `FETCH_WAIT2` assert `mem_en_o=1`, `fetch_busy_o=1`.
- In `FETCH_WAIT1`, priority is `fault_i`, then `branch_flush_i`, then hold.
- In `FETCH_WAIT2`, priority is `fault_i`, then `branch_flush_i`, then `mem_done_i`, then hold.
- If `branch_flush_i` is taken in any fetch wait state, return directly to `FETCH_ADDR`.
- `FETCH_LOAD` lasts one cycle and asserts `ld_ir_o=1`, `fetch_busy_o=1`.
- In `DECODE`, priority is `fault_i`, then `branch_flush_i`, then `stall_i`, then advance to `EXECUTE`.
- In `EXECUTE`, priority is `fault_i`, then `branch_flush_i`, then `replay_i`, then `pause_req_i`, then fall through to `FETCH_ADDR`.
- `REPLAY_PULSE` lasts one cycle with `replay_pulse_o=1`, then returns to `FETCH_ADDR`.
- Pause uses a press/release sequence: `PAUSE_WAIT_PRESS` waits for `continue_i==1`, `PAUSE_WAIT_RELEASE` waits for `continue_i==0`, then returns to `FETCH_ADDR`.
- `FAULT_HALT` asserts `halted_o=1` and `fault_o=1`, and remains active until `run_i==0`, then returns to ordinary `HALT`.

Outputs must be Moore-style and depend only on current state.""",
    success_criteria="""- The module compiles as SystemVerilog.
- Fetch sequencing includes two explicit wait states before load.
- `fault_i` has highest priority in fetch/decode/execute.
- `branch_flush_i` beats stall, replay, and pause where applicable.
- `REPLAY_PULSE` is exactly one cycle.
- Pause exit requires a press and release sequence.
- `FAULT_HALT` is sticky until `run_i==0`.""",
    justification="""This problem is designed to stay difficult even with tools because it combines multiple state-local priority ladders, a sticky fault state, replay semantics, branch flush behavior, and pause/resume timing in a single controller.""",
    public_testbench=r"""`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic reset;
    logic run_i;
    logic stall_i;
    logic branch_flush_i;
    logic replay_i;
    logic pause_req_i;
    logic continue_i;
    logic mem_done_i;
    logic fault_i;
    logic halted_o;
    logic fetch_busy_o;
    logic ld_mar_o;
    logic ld_ir_o;
    logic ld_pc_o;
    logic mem_en_o;
    logic replay_pulse_o;
    logic pause_led_o;
    logic fault_o;

    front_end_ctrl dut (
        .clk(clk),
        .reset(reset),
        .run_i(run_i),
        .stall_i(stall_i),
        .branch_flush_i(branch_flush_i),
        .replay_i(replay_i),
        .pause_req_i(pause_req_i),
        .continue_i(continue_i),
        .mem_done_i(mem_done_i),
        .fault_i(fault_i),
        .halted_o(halted_o),
        .fetch_busy_o(fetch_busy_o),
        .ld_mar_o(ld_mar_o),
        .ld_ir_o(ld_ir_o),
        .ld_pc_o(ld_pc_o),
        .mem_en_o(mem_en_o),
        .replay_pulse_o(replay_pulse_o),
        .pause_led_o(pause_led_o),
        .fault_o(fault_o)
    );

    always #5 clk = ~clk;

    task automatic step_and_check(
        input logic next_run,
        input logic next_stall,
        input logic next_flush,
        input logic next_replay,
        input logic next_pause,
        input logic next_continue,
        input logic next_mem_done,
        input logic next_fault,
        input logic exp_halted,
        input logic exp_busy,
        input logic exp_mar,
        input logic exp_ir,
        input logic exp_pc,
        input logic exp_mem,
        input logic exp_replay_pulse,
        input logic exp_pause_led,
        input logic exp_fault_o,
        input string label
    );
        begin
            @(negedge clk);
            run_i = next_run;
            stall_i = next_stall;
            branch_flush_i = next_flush;
            replay_i = next_replay;
            pause_req_i = next_pause;
            continue_i = next_continue;
            mem_done_i = next_mem_done;
            fault_i = next_fault;
            @(posedge clk);
            #1;
            if (
                halted_o !== exp_halted || fetch_busy_o !== exp_busy || ld_mar_o !== exp_mar ||
                ld_ir_o !== exp_ir || ld_pc_o !== exp_pc || mem_en_o !== exp_mem ||
                replay_pulse_o !== exp_replay_pulse || pause_led_o !== exp_pause_led || fault_o !== exp_fault_o
            ) begin
                $display("FAIL %s", label);
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1; run_i = 0; stall_i = 0; branch_flush_i = 0; replay_i = 0;
        pause_req_i = 0; continue_i = 0; mem_done_i = 0; fault_i = 0;
        @(posedge clk);
        reset = 0;

        step_and_check(0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,"halt");
        step_and_check(1,0,0,0,0,0,0,0,0,1,1,0,1,0,0,0,0,"fetch_addr");
        step_and_check(1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,"wait1");
        step_and_check(1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,"wait2");
        step_and_check(1,0,0,0,0,0,1,0,0,1,0,1,0,0,0,0,0,"wait2_done_seen");
        step_and_check(1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,"load");
        step_and_check(1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,"decode");
        step_and_check(1,0,0,1,0,0,0,0,0,0,0,0,0,0,1,0,0,"execute_replay_req");
        step_and_check(1,0,0,0,0,0,0,0,0,1,1,0,1,0,0,0,0,"replay");

        $display("VERDICT: PASS");
        $finish;
    end
endmodule
""",
    hidden_testbench=r"""`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic reset;
    logic run_i;
    logic stall_i;
    logic branch_flush_i;
    logic replay_i;
    logic pause_req_i;
    logic continue_i;
    logic mem_done_i;
    logic fault_i;
    logic halted_o;
    logic fetch_busy_o;
    logic ld_mar_o;
    logic ld_ir_o;
    logic ld_pc_o;
    logic mem_en_o;
    logic replay_pulse_o;
    logic pause_led_o;
    logic fault_o;

    front_end_ctrl dut (
        .clk(clk),
        .reset(reset),
        .run_i(run_i),
        .stall_i(stall_i),
        .branch_flush_i(branch_flush_i),
        .replay_i(replay_i),
        .pause_req_i(pause_req_i),
        .continue_i(continue_i),
        .mem_done_i(mem_done_i),
        .fault_i(fault_i),
        .halted_o(halted_o),
        .fetch_busy_o(fetch_busy_o),
        .ld_mar_o(ld_mar_o),
        .ld_ir_o(ld_ir_o),
        .ld_pc_o(ld_pc_o),
        .mem_en_o(mem_en_o),
        .replay_pulse_o(replay_pulse_o),
        .pause_led_o(pause_led_o),
        .fault_o(fault_o)
    );

    always #5 clk = ~clk;

    task automatic step_and_check(
        input logic next_run,
        input logic next_stall,
        input logic next_flush,
        input logic next_replay,
        input logic next_pause,
        input logic next_continue,
        input logic next_mem_done,
        input logic next_fault,
        input logic exp_halted,
        input logic exp_busy,
        input logic exp_mar,
        input logic exp_ir,
        input logic exp_pc,
        input logic exp_mem,
        input logic exp_replay_pulse,
        input logic exp_pause_led,
        input logic exp_fault_o,
        input string label
    );
        begin
            @(negedge clk);
            run_i = next_run;
            stall_i = next_stall;
            branch_flush_i = next_flush;
            replay_i = next_replay;
            pause_req_i = next_pause;
            continue_i = next_continue;
            mem_done_i = next_mem_done;
            fault_i = next_fault;
            @(posedge clk);
            #1;
            if (
                halted_o !== exp_halted || fetch_busy_o !== exp_busy || ld_mar_o !== exp_mar ||
                ld_ir_o !== exp_ir || ld_pc_o !== exp_pc || mem_en_o !== exp_mem ||
                replay_pulse_o !== exp_replay_pulse || pause_led_o !== exp_pause_led || fault_o !== exp_fault_o
            ) begin
                $display("FAIL %s halted=%b exp=%b busy=%b exp=%b mar=%b exp=%b ir=%b exp=%b pc=%b exp=%b mem=%b exp=%b replay=%b exp=%b led=%b exp=%b fault=%b exp=%b",
                    label, halted_o, exp_halted, fetch_busy_o, exp_busy, ld_mar_o, exp_mar, ld_ir_o, exp_ir,
                    ld_pc_o, exp_pc, mem_en_o, exp_mem, replay_pulse_o, exp_replay_pulse, pause_led_o, exp_pause_led, fault_o, exp_fault_o);
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1; run_i = 0; stall_i = 0; branch_flush_i = 0; replay_i = 0;
        pause_req_i = 0; continue_i = 0; mem_done_i = 0; fault_i = 0;
        @(posedge clk);
        reset = 0;

        step_and_check(1,0,0,0,0,0,0,0,0,1,1,0,1,0,0,0,0,"fetch_addr1");
        step_and_check(1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,"wait1_pre_flush");
        step_and_check(1,0,1,0,0,0,0,0,0,1,1,0,1,0,0,0,0,"flush_from_wait1_seen_in_wait1");
        step_and_check(1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,"fetch_addr_after_flush");
        step_and_check(1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,"wait1_again");
        step_and_check(1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,"wait2_again");
        step_and_check(1,0,0,0,0,0,1,0,0,1,0,1,0,0,0,0,0,"wait2_done");
        step_and_check(1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,"load");
        step_and_check(1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,"decode_stall");
        step_and_check(1,0,1,0,0,0,0,0,0,1,1,0,1,0,0,0,0,"flush_beats_stall_path");
        step_and_check(1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,"fetch_after_decode_flush");
        step_and_check(1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,"wait1_b");
        step_and_check(1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,"wait2_b");
        step_and_check(1,0,0,0,0,0,1,0,0,1,0,1,0,0,0,0,0,"wait2_done_b");
        step_and_check(1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,"load_b");
        step_and_check(1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,"decode_b");
        step_and_check(1,0,0,0,1,0,0,0,0,0,0,0,0,0,0,1,0,"pause_wait_press");
        step_and_check(1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1,0,"pause_wait_release");
        step_and_check(1,0,0,0,0,0,0,0,0,1,1,0,1,0,0,0,0,"fetch_after_pause");
        step_and_check(1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,"wait1_fault");
        step_and_check(1,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,1,"fault_halt");
        step_and_check(1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,"fault_sticky");
        step_and_check(0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,"return_to_halt");

        $display("VERDICT: PASS");
        $finish;
    end
endmodule
""",
    reference_solution="""module front_end_ctrl (
    input  logic clk,
    input  logic reset,
    input  logic run_i,
    input  logic stall_i,
    input  logic branch_flush_i,
    input  logic replay_i,
    input  logic pause_req_i,
    input  logic continue_i,
    input  logic mem_done_i,
    input  logic fault_i,
    output logic halted_o,
    output logic fetch_busy_o,
    output logic ld_mar_o,
    output logic ld_ir_o,
    output logic ld_pc_o,
    output logic mem_en_o,
    output logic replay_pulse_o,
    output logic pause_led_o,
    output logic fault_o
);
    typedef enum logic [3:0] {
        HALT,
        FETCH_ADDR,
        FETCH_WAIT1,
        FETCH_WAIT2,
        FETCH_LOAD,
        DECODE,
        EXECUTE,
        REPLAY_PULSE,
        PAUSE_WAIT_PRESS,
        PAUSE_WAIT_RELEASE,
        FAULT_HALT
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) state <= HALT;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            HALT: if (run_i) next_state = FETCH_ADDR;
            FETCH_ADDR: next_state = FETCH_WAIT1;
            FETCH_WAIT1: begin
                if (fault_i) next_state = FAULT_HALT;
                else if (branch_flush_i) next_state = FETCH_ADDR;
                else next_state = FETCH_WAIT2;
            end
            FETCH_WAIT2: begin
                if (fault_i) next_state = FAULT_HALT;
                else if (branch_flush_i) next_state = FETCH_ADDR;
                else if (mem_done_i) next_state = FETCH_LOAD;
            end
            FETCH_LOAD: next_state = DECODE;
            DECODE: begin
                if (fault_i) next_state = FAULT_HALT;
                else if (branch_flush_i) next_state = FETCH_ADDR;
                else if (stall_i) next_state = DECODE;
                else next_state = EXECUTE;
            end
            EXECUTE: begin
                if (fault_i) next_state = FAULT_HALT;
                else if (branch_flush_i) next_state = FETCH_ADDR;
                else if (replay_i) next_state = REPLAY_PULSE;
                else if (pause_req_i) next_state = PAUSE_WAIT_PRESS;
                else next_state = FETCH_ADDR;
            end
            REPLAY_PULSE: next_state = FETCH_ADDR;
            PAUSE_WAIT_PRESS: if (continue_i) next_state = PAUSE_WAIT_RELEASE;
            PAUSE_WAIT_RELEASE: if (!continue_i) next_state = FETCH_ADDR;
            FAULT_HALT: if (!run_i) next_state = HALT;
            default: next_state = HALT;
        endcase
    end

    always_comb begin
        halted_o = 1'b0;
        fetch_busy_o = 1'b0;
        ld_mar_o = 1'b0;
        ld_ir_o = 1'b0;
        ld_pc_o = 1'b0;
        mem_en_o = 1'b0;
        replay_pulse_o = 1'b0;
        pause_led_o = 1'b0;
        fault_o = 1'b0;
        case (state)
            HALT: halted_o = 1'b1;
            FETCH_ADDR: begin
                fetch_busy_o = 1'b1;
                ld_mar_o = 1'b1;
                ld_pc_o = 1'b1;
            end
            FETCH_WAIT1,
            FETCH_WAIT2: begin
                fetch_busy_o = 1'b1;
                mem_en_o = 1'b1;
            end
            FETCH_LOAD: begin
                fetch_busy_o = 1'b1;
                ld_ir_o = 1'b1;
            end
            REPLAY_PULSE: replay_pulse_o = 1'b1;
            PAUSE_WAIT_PRESS,
            PAUSE_WAIT_RELEASE: pause_led_o = 1'b1;
            FAULT_HALT: begin
                halted_o = 1'b1;
                fault_o = 1'b1;
            end
            default: begin
            end
        endcase
    end
endmodule
""",
    failing_solution="""module front_end_ctrl (
    input  logic clk,
    input  logic reset,
    input  logic run_i,
    input  logic stall_i,
    input  logic branch_flush_i,
    input  logic replay_i,
    input  logic pause_req_i,
    input  logic continue_i,
    input  logic mem_done_i,
    input  logic fault_i,
    output logic halted_o,
    output logic fetch_busy_o,
    output logic ld_mar_o,
    output logic ld_ir_o,
    output logic ld_pc_o,
    output logic mem_en_o,
    output logic replay_pulse_o,
    output logic pause_led_o,
    output logic fault_o
);
    typedef enum logic [2:0] {
        HALT,
        FETCH,
        LOAD,
        DECODE,
        EXECUTE,
        PAUSE,
        FAULT
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) state <= HALT;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            HALT: if (run_i) next_state = FETCH;
            FETCH: if (fault_i) next_state = FAULT; else if (mem_done_i) next_state = LOAD;
            LOAD: next_state = DECODE;
            DECODE: if (stall_i) next_state = DECODE; else next_state = EXECUTE;
            EXECUTE: if (pause_req_i) next_state = PAUSE; else if (replay_i) next_state = FETCH; else next_state = FETCH;
            PAUSE: if (continue_i) next_state = FETCH;
            FAULT: if (!run_i) next_state = HALT;
            default: next_state = HALT;
        endcase
    end

    always_comb begin
        halted_o = (state == HALT) || (state == FAULT);
        fetch_busy_o = (state == FETCH) || (state == LOAD);
        ld_mar_o = (state == FETCH);
        ld_ir_o = (state == LOAD);
        ld_pc_o = (state == FETCH);
        mem_en_o = (state == FETCH);
        replay_pulse_o = 1'b0;
        pause_led_o = (state == PAUSE);
        fault_o = (state == FAULT);
    end
endmodule
""",
)


P6 = ProblemSpec(
    problem_id="P6",
    title="Real Fetch Decode Queue Reconstruction",
    difficulty="Easy",
    module_name="fetch_decode_queue",
    interface="""module fetch_decode_queue
import rv32i_types::*;
 #(
    parameter QUEUE_SIZE = 32,
    parameter QUEUE_ENTRIES = 8
)(
    input logic clk,
    input logic rst,
    input logic write,
    input logic read,
    input logic [QUEUE_SIZE-1 :0]write_data,
    input logic [QUEUE_SIZE-1 : 0]write_pc,
    output logic [QUEUE_SIZE - 1 : 0]read_data,
    output logic [QUEUE_SIZE - 1 :0] read_pc,
    output logic filled,
    output logic empty,
    input branch_flush_t branch_flush
);""",
    problem_statement="""Reconstruct the real `fetch_decode_queue.sv` file from the ECE 411 processor.

This module is the easiest real-repo Family B entry: it is a small circular FIFO
between fetch and decode. It stores an instruction word and its PC, reports
empty/full using wrapped head and tail pointers, supports one read and one write
per cycle when legal, and flushes the queue on a taken branch flush.""",
    success_criteria="""- Exact module name, package import, parameters, and port interface must match `fetch_decode_queue`.
- Reset clears the queue to empty.
- Writes enqueue `write_data` and `write_pc` when the queue is not full.
- Reads dequeue the current head entry when the queue is not empty.
- `empty` is true when head equals tail; `filled` is true when low pointer bits match and wrap bits differ.
- `read_data` and `read_pc` expose the current head entry combinationally.
- A taken `branch_flush` clears both head and tail, making the queue empty.""",
    justification="""This is a real processor file but intentionally easier: no package structs beyond `branch_flush_t`, no memory bus protocol, and a compact FIFO state machine.""",
    public_testbench=REAL_TYPES_PREFIX + r"""
module tb;
  import rv32i_types::*;
  logic clk=0, rst, write, read, filled, empty;
  logic [31:0] write_data, write_pc, read_data, read_pc;
  branch_flush_t branch_flush;
  fetch_decode_queue dut(.*);
  always #5 clk=~clk;
  task tick; begin @(posedge clk); #1; end endtask
  initial begin
    rst=1; write=0; read=0; write_data=0; write_pc=0; branch_flush='0;
    tick(); rst=0; #1;
    if (!empty || filled) begin $display("FAIL reset_flags"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
""",
    hidden_testbench=REAL_TYPES_PREFIX + r"""
module tb;
  import rv32i_types::*;
  logic clk=0, rst, write, read, filled, empty;
  logic [31:0] write_data, write_pc, read_data, read_pc;
  branch_flush_t branch_flush;
  fetch_decode_queue dut(.*);
  always #5 clk=~clk;
  task tick; begin @(posedge clk); #1; end endtask
  initial begin
    rst=1; write=0; read=0; write_data=0; write_pc=0; branch_flush='0;
    tick(); rst=0;
    write=1; write_data=32'h0000_00aa; write_pc=32'h8000_0000; tick();
    write_data=32'h0000_00bb; write_pc=32'h8000_0004; tick();
    write=0; #1;
    if (empty || filled) begin $display("FAIL flags_after_two_writes"); $fatal(1); end
    if (read_data!==32'h0000_00aa || read_pc!==32'h8000_0000) begin $display("FAIL first_head_value"); $fatal(1); end
    read=1; tick(); read=0; #1;
    if (read_data!==32'h0000_00bb || read_pc!==32'h8000_0004) begin $display("FAIL second_head_value"); $fatal(1); end
    branch_flush.valid=1; branch_flush.branch_taken=1; tick(); branch_flush='0; #1;
    if (!empty || filled) begin $display("FAIL branch_flush_did_not_clear"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
""",
    reference_solution=_repo_file("mp_ooo_baseline/hdl/fetch_decode_queue.sv"),
    failing_solution="module fetch_decode_queue; endmodule",
    family_label="Family B: exact OoO processor file reconstruction",
    source_file="mp_ooo_baseline/hdl/fetch_decode_queue.sv",
    family_context=FAMILY_B_CONTEXT,
    transfer_hooks=FAMILY_B_TRANSFER_HOOKS,
)


P7 = ProblemSpec(
    problem_id="P7",
    title="Real Instruction Burst Adapter Reconstruction",
    difficulty="Easy",
    module_name="i_burst_adapter",
    interface="""module i_burst_adapter
import rv32i_types::*;
(
    input  logic clk,
    input  logic rst,
    input  logic                         bmem_ready,
    input  logic   [ADDR_SIZE-1:0]       bmem_raddr,
    input  logic   [BURST_SIZE-1:0]      bmem_rdata,
    input  logic                         bmem_rvalid,
    output logic   [ADDR_SIZE-1:0]       bmem_addr,
    output logic                         bmem_read,
    output logic                         bmem_write,
    output logic   [BURST_SIZE-1:0]      bmem_wdata,
    input  logic    [ADDR_SIZE-1:0]       cache_addr,
    input  logic                          cache_read,
    input  logic                          i_cache_chosen,
    output logic    [BLOCK_SIZE_BITS-1:0] cache_rdata,
    output logic                          cache_resp,
    output logic [ADDR_SIZE-1:0]          cache_addr_resp
);""",
    problem_statement="""Reconstruct the real `i_burst_adapter.sv` file from the ECE 411 processor.

This module is the second easier Family B entry: it adapts a cache-line read request
into four 64-bit burst beats from backing memory, packs them into a 256-bit
cache line, returns `cache_resp` for one cycle when the fourth matching beat
arrives, and abandons an in-flight read if the instruction cache is no longer
chosen.""",
    success_criteria="""- Exact module name and package-typed interface must match `i_burst_adapter`.
- On an idle cache read while `i_cache_chosen` is high, assert `bmem_read` and drive `bmem_addr` with `cache_addr`.
- Collect four matching 64-bit `bmem_rdata` beats into the correct 256-bit lanes.
- Assert `cache_resp` and `cache_addr_resp` only after the fourth matching beat.
- Do not issue writes on the instruction side.
- If `i_cache_chosen` drops during a read, cancel the in-flight transaction.""",
    justification="""This is still approachable because it is a small real repo FSM with one read path and no cache tags, PLRU, or OoO packet state.""",
    public_testbench=REAL_TYPES_PREFIX + r"""
module tb;
  import rv32i_types::*;
  logic clk=0,rst,bmem_ready,bmem_rvalid,bmem_read,bmem_write,cache_read,i_cache_chosen,cache_resp;
  logic [31:0] bmem_raddr,bmem_addr,cache_addr,cache_addr_resp;
  logic [63:0] bmem_rdata,bmem_wdata;
  logic [255:0] cache_rdata;
  i_burst_adapter dut(.*);
  always #5 clk=~clk;
  task tick; begin @(posedge clk); #1; end endtask
  initial begin
    rst=1; bmem_ready=1; bmem_rvalid=0; bmem_raddr=0; bmem_rdata=0; cache_addr=32'h1000; cache_read=0; i_cache_chosen=1;
    tick(); rst=0; cache_read=1; tick(); cache_read=0; #1;
    if (bmem_write || cache_resp) begin $display("FAIL idle_read_start_outputs"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
""",
    hidden_testbench=REAL_TYPES_PREFIX + r"""
module tb;
  import rv32i_types::*;
  logic clk=0,rst,bmem_ready,bmem_rvalid,bmem_read,bmem_write,cache_read,i_cache_chosen,cache_resp;
  logic [31:0] bmem_raddr,bmem_addr,cache_addr,cache_addr_resp;
  logic [63:0] bmem_rdata,bmem_wdata;
  logic [255:0] cache_rdata;
  i_burst_adapter dut(.*);
  always #5 clk=~clk;
  task tick; begin @(posedge clk); #1; end endtask
  initial begin
    rst=1; bmem_ready=1; bmem_rvalid=0; bmem_raddr=0; bmem_rdata=0; cache_addr=32'h2000; cache_read=0; i_cache_chosen=1;
    tick(); rst=0;
    cache_read=1; tick(); cache_read=0;
    for (int i=0; i<3; i++) begin
      bmem_rvalid=1; bmem_raddr=32'h2000; bmem_rdata=64'h1111_0000_0000_0000 + i;
      tick();
    end
    bmem_rvalid=1; bmem_raddr=32'h2000; bmem_rdata=64'h1111_0000_0000_0003; #1;
    if (!cache_resp || cache_addr_resp!==32'h2000) begin $display("FAIL no_response_after_four_beats"); $fatal(1); end
    if (cache_rdata[63:0]!==64'h1111_0000_0000_0000 || cache_rdata[255:192]!==64'h1111_0000_0000_0003) begin $display("FAIL packed_burst_lanes"); $fatal(1); end
    tick(); bmem_rvalid=0; #1;
    if (cache_resp) begin $display("FAIL response_not_one_cycle"); $fatal(1); end
    cache_addr=32'h3000; cache_read=1; tick(); cache_read=0; i_cache_chosen=0; tick(); i_cache_chosen=1; bmem_rvalid=1; bmem_raddr=32'h3000; bmem_rdata=64'hffff; tick(); bmem_rvalid=0; #1;
    if (cache_resp) begin $display("FAIL cancelled_read_responded"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
""",
    reference_solution=_repo_file("mp_ooo_baseline/hdl/i_burst_adapter.sv"),
    failing_solution="module i_burst_adapter; endmodule",
    family_label="Family B: exact OoO processor file reconstruction",
    source_file="mp_ooo_baseline/hdl/i_burst_adapter.sv",
    family_context=FAMILY_B_CONTEXT,
    transfer_hooks=FAMILY_B_TRANSFER_HOOKS,
)


P8 = ProblemSpec(
    problem_id="P8",
    title="Real OoO RAT File Reconstruction",
    difficulty="Medium",
    module_name="rat",
    interface="""module rat
import rv32i_types::*;
(
    input clk,
    input rst,
    input logic [ADDR_BITS-1:0] read_rs1_idx,
    input logic [ADDR_BITS-1:0] read_rs2_idx,
    input logic [ADDR_BITS-1:0] read_rs3_idx,
    input logic [ADDR_BITS-1:0] write_rd_idx,
    input logic [PRF_IDX_WIDTH-1:0] write_phy_rd,
    input logic wr_enable,
    input [ADDR_BITS-1:0] specrd_idx,
    input [PRF_IDX_WIDTH-1:0] specrd_mapping,
    output logic [PRF_IDX_WIDTH-1:0] rs1_phy_idx,
    output logic [PRF_IDX_WIDTH-1:0] rs2_phy_idx,
    output logic [PRF_IDX_WIDTH-1:0] rs3_phy_idx,
    input commit2rat_t commit2rat,
    input branch_flush_t branch_flush
);""",
    problem_statement="""Reconstruct the real `rat.sv` file from the ECE 411 OoO processor.

This is intended to be a medium-difficulty real repo problem, not an impossible exact-recall problem. Use the exact package-style interface shown above and implement the RAT directly inside this module; do not instantiate helper submodules.

Important package facts available through `rv32i_types::*`:
- `ADDR_SIZE` is 32.
- `ADDR_BITS` is 5.
- `PRF_IDX_WIDTH` is 6.
- There is no `REG_COUNT`, `REG_NUM`, or `REGFILE_SIZE` constant.

Maintain a speculative RAT and a committed RAT. Reset maps architectural register i to physical register i. Rename writes update only speculative state. Commit writes update only committed state. Branch recovery restores speculative state from committed state, including a simultaneous commit. x0 must always map to physical register 0. rs1/rs2 reads need same-cycle `specrd_idx` bypass; rs3 reads the speculative table.""",
    success_criteria="""- Exact module name and package-typed interface must match `rat`.
- Use arrays sized by `ADDR_SIZE`; do not invent new package constants.
- Reset initializes both speculative and committed mappings to identity.
- `wr_enable` updates only the speculative RAT for nonzero `write_rd_idx`.
- `commit2rat.commit_update` updates only the committed RAT for nonzero `commit_rd_idx`.
- Branch recovery restores speculative state from committed state and preserves a simultaneous commit.
- x0 is never remapped.
- rs1/rs2 include same-cycle speculative bypass; rs3 reads the speculative table.""",
    justification="""This is medium because type/context tools make compilation achievable, but hidden tests still check OoO recovery and bypass semantics.""",
    public_testbench=REAL_TYPES_PREFIX + r"""
module tb;
  import rv32i_types::*;
  logic clk=0, rst, wr_enable;
  logic [ADDR_BITS-1:0] read_rs1_idx, read_rs2_idx, read_rs3_idx, write_rd_idx, specrd_idx;
  logic [PRF_IDX_WIDTH-1:0] write_phy_rd, specrd_mapping, rs1_phy_idx, rs2_phy_idx, rs3_phy_idx;
  commit2rat_t commit2rat; branch_flush_t branch_flush;
  rat dut(.*);
  always #5 clk=~clk; task tick; begin @(posedge clk); #1; end endtask
  initial begin
    rst=1; wr_enable=0; read_rs1_idx=1; read_rs2_idx=2; read_rs3_idx=3; write_rd_idx=0; write_phy_rd=0; specrd_idx=0; specrd_mapping=0; commit2rat='0; branch_flush='0;
    tick(); rst=0; #1;
    if (rs1_phy_idx!==6'd1 || rs2_phy_idx!==6'd2 || rs3_phy_idx!==6'd3) begin $display("FAIL reset_identity"); $fatal(1); end
    specrd_idx=5'd1; specrd_mapping=6'd44; #1;
    if (rs1_phy_idx!==6'd44) begin $display("FAIL speculative_bypass"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
""",
    hidden_testbench=REAL_TYPES_PREFIX + r"""
module tb;
  import rv32i_types::*;
  logic clk=0, rst, wr_enable;
  logic [ADDR_BITS-1:0] read_rs1_idx, read_rs2_idx, read_rs3_idx, write_rd_idx, specrd_idx;
  logic [PRF_IDX_WIDTH-1:0] write_phy_rd, specrd_mapping, rs1_phy_idx, rs2_phy_idx, rs3_phy_idx;
  commit2rat_t commit2rat; branch_flush_t branch_flush;
  rat dut(.*);
  always #5 clk=~clk; task tick; begin @(posedge clk); #1; end endtask
  initial begin
    rst=1; wr_enable=0; read_rs1_idx=5'd5; read_rs2_idx=5'd0; read_rs3_idx=5'd5; write_rd_idx=0; write_phy_rd=0; specrd_idx=0; specrd_mapping=0; commit2rat='0; branch_flush='0;
    tick(); rst=0; #1;
    wr_enable=1; write_rd_idx=5'd5; write_phy_rd=6'd45; tick(); wr_enable=0; #1;
    if (rs1_phy_idx!==6'd45 || rs3_phy_idx!==6'd45) begin $display("FAIL speculative_write_or_rs3_read"); $fatal(1); end
    branch_flush.valid=1; branch_flush.branch_taken=1; tick(); branch_flush='0; #1;
    if (rs1_phy_idx!==6'd5) begin $display("FAIL flush_restore_committed"); $fatal(1); end
    wr_enable=1; write_rd_idx=5'd5; write_phy_rd=6'd46; tick(); wr_enable=0;
    commit2rat.commit_update=1; commit2rat.commit_rd_idx=5'd5; commit2rat.commit_phy_rd=6'd46; branch_flush.valid=1; branch_flush.branch_taken=1; tick();
    commit2rat='0; branch_flush='0; #1;
    if (rs1_phy_idx!==6'd46) begin $display("FAIL same_cycle_commit_flush_lost"); $fatal(1); end
    wr_enable=1; write_rd_idx=5'd0; write_phy_rd=6'd63; read_rs1_idx=5'd0; tick(); wr_enable=0; #1;
    if (rs1_phy_idx!==6'd0) begin $display("FAIL x0_remapped"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
""",
    reference_solution=_repo_file("mp_ooo_baseline/hdl/rat.sv"),
    failing_solution="module rat; endmodule",
    family_label="Family B: exact OoO processor file reconstruction",
    source_file="mp_ooo_baseline/hdl/rat.sv",
    family_context=FAMILY_B_CONTEXT,
    transfer_hooks=FAMILY_B_TRANSFER_HOOKS,
)

P9 = ProblemSpec(
    problem_id="P9",
    title="Real OoO Freelist File Reconstruction",
    difficulty="Hard",
    module_name="freelist",
    interface="""module freelist
import rv32i_types::*;
(
    input logic clk,
    input logic rst,
    input rename2frlist_t rename2frlist,
    input commit2frlist_t commit2frlist,
    output frlist2rename_t frlist2rename,
    output logic frlist_full,
    output logic frlist_empty,
    input rob2frlist_t rob2frlist
);""",
    problem_statement="""Reconstruct the real `freelist.sv` file from the ECE 411 OoO processor. It is a 32-entry physical-register freelist with speculative allocation, commit-time freeing, committed shadow state, and branch recovery through `rob2frlist`.""",
    success_criteria="""- Exact module name and package-typed interface must match `freelist`.
- Reset exposes P32 first and count 32.
- Allocation consumes one entry without double allocation.
- Commit free appends `old_phy_rd`.
- Recovery restores coherent head/tail/count/content state.""",
    justification="""This is hard because it asks for speculative/committed queue recovery semantics.""",
    public_testbench=REAL_TYPES_PREFIX + r"""
module tb; import rv32i_types::*; logic clk=0,rst,frlist_full,frlist_empty; rename2frlist_t rename2frlist; commit2frlist_t commit2frlist; frlist2rename_t frlist2rename; rob2frlist_t rob2frlist; freelist dut(.*); always #5 clk=~clk; task tick; begin @(posedge clk); #1; end endtask initial begin rst=1; rename2frlist='0; commit2frlist='0; rob2frlist='0; tick(); rst=0; #1; if(!frlist2rename.alloc_valid || frlist2rename.new_phy_rd!==6'd32) begin $display("FAIL reset_freelist"); $fatal(1); end $display("VERDICT: PASS"); $finish; end endmodule
""",
    hidden_testbench=REAL_TYPES_PREFIX + r"""
module tb; import rv32i_types::*; logic clk=0,rst,frlist_full,frlist_empty; rename2frlist_t rename2frlist; commit2frlist_t commit2frlist; frlist2rename_t frlist2rename; rob2frlist_t rob2frlist; freelist dut(.*); always #5 clk=~clk; task tick; begin @(posedge clk); #1; end endtask initial begin rst=1; rename2frlist='0; commit2frlist='0; rob2frlist='0; tick(); rst=0; repeat(3) begin rename2frlist.alloc_ack=1; tick(); rename2frlist.alloc_ack=0; tick(); end #1; if(frlist2rename.new_phy_rd!==6'd35 || frlist2rename.freelistcount!==6'd29) begin $display("FAIL three_allocations"); $fatal(1); end commit2frlist.free_en=1; commit2frlist.old_phy_rd=6'd9; tick(); commit2frlist='0; #1; if(frlist2rename.freelistcount!==6'd30) begin $display("FAIL commit_free_count"); $fatal(1); end rob2frlist.valid=1; commit2frlist.free_en=1; commit2frlist.old_phy_rd=6'd11; tick(); rob2frlist='0; commit2frlist='0; #1; if(frlist2rename.freelistcount!==6'd32) begin $display("FAIL flush_commit_restore_count"); $fatal(1); end $display("VERDICT: PASS"); $finish; end endmodule
""",
    reference_solution=_repo_file("mp_ooo_baseline/hdl/freelist.sv"),
    failing_solution="module freelist; endmodule",
    family_label="Family B: exact OoO processor file reconstruction",
    source_file="mp_ooo_baseline/hdl/freelist.sv",
    family_context=FAMILY_B_CONTEXT,
    transfer_hooks=FAMILY_B_TRANSFER_HOOKS,
)

P10 = ProblemSpec(
    problem_id="P10",
    title="Real ROB File Reconstruction",
    difficulty="Hard",
    module_name="rob",
    interface="""module rob
import rv32i_types::*;
(
    input clk,
    input rst,
    input dispatch_2_rob_t dispatch_2_rob,
    input common_data_bus_t common_data_bus,
    input logic commit_ack,
    output logic [ROB_IDX_WIDTH-1:0] rob_idx_dispatch,
    output logic robfull,
    output logic robempty,
    output rob2commit_t rob2commit,
    input lsq2rob_t lsq2robpack,
    input branchres2rob_t branchres2rob,
    input branch_flush_t branch_flush,
    input jumpresrob_t jumpresrob,
    output rob2frlist_t rob2frlist
);""",
    problem_statement="""Reconstruct the real `rob.sv` reorder buffer file. It allocates dispatch packets, marks arbitrary entries complete from the CDB, exposes only the head to commit, retires on commit_ack, and clears speculative entries on branch flush.""",
    success_criteria="""- Exact package-typed interface must match `rob`.
- Dispatch allocates at tail and returns the allocated ROB index.
- CDB completion marks the target entry ready.
- Only the ready head entry can commit.
- Branch flush clears speculative state and keeps head/tail coherent.""",
    justification="""This is hard because it is a real packet ROB with interacting side channels.""",
    public_testbench=REAL_TYPES_PREFIX + r"""
module tb; import rv32i_types::*; logic clk=0,rst,commit_ack,robfull,robempty; logic [ROB_IDX_WIDTH-1:0] rob_idx_dispatch; dispatch_2_rob_t dispatch_2_rob; common_data_bus_t common_data_bus; rob2commit_t rob2commit; lsq2rob_t lsq2robpack; branchres2rob_t branchres2rob; branch_flush_t branch_flush; jumpresrob_t jumpresrob; rob2frlist_t rob2frlist; rob dut(.*); always #5 clk=~clk; task tick; begin @(posedge clk); #1; end endtask initial begin rst=1; commit_ack=0; dispatch_2_rob='0; common_data_bus='0; lsq2robpack='0; branchres2rob='0; branch_flush='0; jumpresrob='0; tick(); rst=0; dispatch_2_rob.alloc_en=1; dispatch_2_rob.has_rd_check=1; dispatch_2_rob.arf_rd=5'd1; dispatch_2_rob.new_phy_rd=6'd33; tick(); dispatch_2_rob='0; #1; if(robempty) begin $display("FAIL dispatch_not_allocated"); $fatal(1); end $display("VERDICT: PASS"); $finish; end endmodule
""",
    hidden_testbench=REAL_TYPES_PREFIX + r"""
module tb; import rv32i_types::*; logic clk=0,rst,commit_ack,robfull,robempty; logic [ROB_IDX_WIDTH-1:0] rob_idx_dispatch; dispatch_2_rob_t dispatch_2_rob; common_data_bus_t common_data_bus; rob2commit_t rob2commit; lsq2rob_t lsq2robpack; branchres2rob_t branchres2rob; branch_flush_t branch_flush; jumpresrob_t jumpresrob; rob2frlist_t rob2frlist; rob dut(.*); always #5 clk=~clk; task tick; begin @(posedge clk); #1; end endtask initial begin rst=1; commit_ack=0; dispatch_2_rob='0; common_data_bus='0; lsq2robpack='0; branchres2rob='0; branch_flush='0; jumpresrob='0; tick(); rst=0; dispatch_2_rob.alloc_en=1; dispatch_2_rob.has_rd_check=1; dispatch_2_rob.arf_rd=5'd1; dispatch_2_rob.new_phy_rd=6'd33; tick(); dispatch_2_rob.arf_rd=5'd2; dispatch_2_rob.new_phy_rd=6'd34; tick(); dispatch_2_rob='0; #1; common_data_bus.complete=1; common_data_bus.rob_idx=5'd1; common_data_bus.has_rd=1; common_data_bus.phy_rd=6'd34; tick(); common_data_bus='0; #1; if(rob2commit.commit) begin $display("FAIL younger_ready_committed_before_head"); $fatal(1); end common_data_bus.complete=1; common_data_bus.rob_idx=5'd0; common_data_bus.has_rd=1; common_data_bus.phy_rd=6'd33; tick(); common_data_bus='0; #1; if(!rob2commit.commit || rob2commit.arf_rd!==5'd1) begin $display("FAIL head_not_ready_after_cdb"); $fatal(1); end $display("VERDICT: PASS"); $finish; end endmodule
""",
    reference_solution=_repo_file("mp_ooo_baseline/hdl/rob.sv"),
    failing_solution="module rob; endmodule",
    family_label="Family B: exact OoO processor file reconstruction",
    source_file="mp_ooo_baseline/hdl/rob.sv",
    family_context=FAMILY_B_CONTEXT,
    transfer_hooks=FAMILY_B_TRANSFER_HOOKS,
)


PROBLEMS = {
    spec.problem_id: spec
    for spec in [P1, P5, P4, P2, P3, P6, P7, P8, P9, P10]
}


def get_problem(problem_id: str) -> ProblemSpec:
    try:
        return PROBLEMS[problem_id.upper()]
    except KeyError as exc:
        known = ", ".join(sorted(PROBLEMS))
        raise KeyError(f"Unknown problem_id '{problem_id}'. Expected one of: {known}") from exc


def all_problem_ids() -> list[str]:
    return sorted(PROBLEMS, key=lambda pid: int(pid[1:]))
