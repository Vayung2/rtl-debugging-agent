from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


REPO_ROOT = Path(__file__).resolve().parent
HW4_DIR = REPO_ROOT / "HW4"
if str(HW4_DIR) not in sys.path:
    sys.path.insert(0, str(HW4_DIR))

from problem_bank import ProblemSpec, get_problem  # noqa: E402


Mutator = Callable[[str], str]


@dataclass(frozen=True)
class RepairCase:
    case_id: str
    problem_id: str
    bug_class: str
    bug_summary: str
    expected_failure: str
    trace_summary: str
    mutator: Mutator
    real_commit: str = ""
    real_commit_message: str = ""
    custom_testbench: str | None = None
    distractor_files: tuple[str, ...] = ()

    @property
    def problem(self) -> ProblemSpec:
        return get_problem(self.problem_id)

    def reference_sv(self) -> str:
        return self.problem.reference_solution

    def buggy_sv(self) -> str:
        return self.mutator(self.reference_sv())

    def candidate_sources(self) -> list[tuple[str, str]]:
        sources = [(self.problem.source_file or f"{self.problem.module_name}.sv", self.buggy_sv())]
        for rel_path in self.distractor_files:
            path = REPO_ROOT / rel_path
            sources.append((rel_path, path.read_text(encoding="utf-8")))
        return sources

    def candidate_interfaces(self) -> list[tuple[str, str]]:
        return [(path, _module_header(source)) for path, source in self.candidate_sources()]


def _replace_once(text: str, old: str, new: str, case_id: str) -> str:
    if old not in text:
        raise ValueError(f"{case_id}: mutation anchor not found")
    return text.replace(old, new, 1)


def _module_header(source: str, max_lines: int = 80) -> str:
    lines = source.splitlines()
    for idx, line in enumerate(lines):
        if line.strip().startswith(");"):
            return "\n".join(lines[: min(idx + 1, max_lines)])
    return "\n".join(lines[:max_lines])


def p6_ignore_branch_flush(text: str) -> str:
    return _replace_once(
        text,
        "else if(branch_flush.valid && branch_flush.branch_taken) begin",
        "else if(branch_flush.valid && !branch_flush.branch_taken) begin",
        "P6_FLUSH",
    )


def p6_drop_pc_payload(text: str) -> str:
    return _replace_once(
        text,
        "pc_temp[tail_index] <= write_pc;",
        "pc_temp[tail_index] <= write_data;",
        "P6_PC",
    )


def p7_respond_one_beat_early(text: str) -> str:
    return _replace_once(
        text,
        "if (burstcnt_nxt == 2'b11) begin",
        "if (burstcnt_nxt == 2'b10) begin",
        "P7_EARLY_RESP",
    )


def p7_pack_last_beat_wrong_lane(text: str) -> str:
    return _replace_once(
        text,
        "2'b11: burstreg_next[4*BURST_SIZE-1:3*BURST_SIZE] = bmem_rdata;",
        "2'b11: burstreg_next[BURST_SIZE-1:0] = bmem_rdata;",
        "P7_LANE",
    )


def p8_lose_same_cycle_commit_on_flush(text: str) -> str:
    return _replace_once(
        text,
        "rat_table[i] <= commit2rat.commit_phy_rd;",
        "rat_table[i] <= commited_rat_table[i];",
        "P8_COMMIT_FLUSH",
    )


def p8_remove_same_cycle_spec_bypass(text: str) -> str:
    first = """    if(specrd_idx != '0) begin 
        if(read_rs1_idx == specrd_idx ) begin 
            rs1_phy_idx = specrd_mapping ; 
        end 
    end 

    if(specrd_idx != '0 && read_rs1_idx == specrd_idx) begin 
        rs1_phy_idx = specrd_mapping;
    end"""
    second = """    if(specrd_idx != '0) begin 
        if(read_rs2_idx == specrd_idx ) begin 
            rs2_phy_idx = specrd_mapping ; 

        end
    end 

    if(specrd_idx != '0 && read_rs2_idx == specrd_idx) begin 
        rs2_phy_idx = specrd_mapping;
    end"""
    text = _replace_once(text, first, "", "P8_REAL_RAT_BYPASS")
    text = _replace_once(text, second, "", "P8_REAL_RAT_BYPASS")
    return text


def p7_remove_icache_chosen_start_gate(text: str) -> str:
    return _replace_once(
        text,
        "start_read = (burststate == idle) && (cache_read != 1'b0) && i_cache_chosen;",
        "start_read = (burststate == idle) && (cache_read != 1'b0);",
        "P7_REAL_ICACHE_ARB",
    )


def p10_register_dispatch_index(text: str) -> str:
    text = _replace_once(
        text,
        "        //rob_idx_dispatch <= '0;",
        "        rob_idx_dispatch <= '0;",
        "P10_REAL_ROB_IDX",
    )
    text = _replace_once(
        text,
        "            // rob_idx_dispatch <= tail_index; ",
        "            rob_idx_dispatch <= tail_index; ",
        "P10_REAL_ROB_IDX",
    )
    text = _replace_once(
        text,
        "assign rob_idx_dispatch = tail_index;",
        "// Historical bug: rob_idx_dispatch was registered in the sequential block.",
        "P10_REAL_ROB_IDX",
    )
    return text


def p9_allocation_count_stuck(text: str) -> str:
    return _replace_once(
        text,
        "2'b10: count <= count - 6'd1;  // Alloc only",
        "2'b10: count <= count;          // Alloc only",
        "P9_ALLOC_COUNT",
    )


def p10_cdb_marks_head_instead_of_target(text: str) -> str:
    return _replace_once(
        text,
        "rob_queue[common_data_bus.rob_idx].ready2commit <= 1'b1;",
        "rob_queue[head_index].ready2commit <= 1'b1;",
        "P10_CDB_TARGET",
    )


def p9_restore_from_speculative_checkpoint_on_flush(text: str) -> str:
    old = """if (rob2frlist.valid) begin
                // FLUSH: Restore from committed
                    // freelist_fifo <= committed_frlist;
                    // head <= committed_head;
                    // tail <= committed_tail;
                    // count <= 6'd32;


                    if (commit2frlist.free_en) begin
                        // Manually apply commit to get correct restored state
                        freelist_fifo <= committed_frlist;
                        // Patch in the newly freed register at the new tail position
                        freelist_fifo[committed_tail] <= commit2frlist.old_phy_rd;
                        head <= (committed_head == freelist_last) ? 6'd0 : committed_head + 6'd1;
                        // Tail advances by 1 from current committed_tail
                        tail <= (committed_tail == freelist_last) ? 6'd0 : committed_tail + 6'd1;
                        count <= 6'd32;
                    end else begin
                        // Normal flush: just restore from committed
                        freelist_fifo <= committed_frlist;
                        head <= committed_head;
                        tail <= committed_tail;
                        count <= 6'd32;
                    end
                end"""
    new = """if (rob2frlist.valid) begin
                    head <= rob2frlist.freelist_head;
                    tail <= rob2frlist.freelist_tail;
                    count <= rob2frlist.freelistcount;
                end"""
    return _replace_once(text, old, new, "P9_REAL_FLUSH_RESTORE")


def p10_jalr_target_missing_rs1_base(text: str) -> str:
    return _replace_once(
        text,
        "rob_queue[jumpresrob.rob_idx].branchtg_addr <= (jumpresrob.rs1 + rob_queue[jumpresrob.rob_idx].branchtg_addr) & 32'hFFFFFFFE;  // ← FIX!",
        "rob_queue[jumpresrob.rob_idx].branchtg_addr <= rob_queue[jumpresrob.rob_idx].branchtg_addr & 32'hFFFFFFFE;",
        "P10_REAL_JALR_TARGET",
    )


P7_REAL_ICACHE_ARB_TB = r"""`timescale 1ns/1ps
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
    rst=1; bmem_ready=1; bmem_rvalid=0; bmem_raddr=0; bmem_rdata=0;
    cache_addr=32'h4000; cache_read=0; i_cache_chosen=0;
    tick(); rst=0;
    cache_read=1; #1;
    if (bmem_read) begin $display("FAIL icache_started_while_dcache_chosen"); $fatal(1); end
    tick(); cache_read=0;
    repeat (4) begin
      bmem_rvalid=1; bmem_raddr=32'h4000; bmem_rdata=64'h8888;
      tick();
    end
    bmem_rvalid=0; #1;
    if (cache_resp) begin $display("FAIL responded_to_unchosen_icache_request"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
"""


P10_REAL_ROB_IDX_TB = r"""`timescale 1ns/1ps
module tb;
  import rv32i_types::*;
  logic clk=0,rst,commit_ack,robfull,robempty;
  logic [ROB_IDX_WIDTH-1:0] rob_idx_dispatch;
  dispatch_2_rob_t dispatch_2_rob; common_data_bus_t common_data_bus; rob2commit_t rob2commit;
  lsq2rob_t lsq2robpack; branchres2rob_t branchres2rob; branch_flush_t branch_flush; jumpresrob_t jumpresrob; rob2frlist_t rob2frlist;
  rob dut(.*);
  always #5 clk=~clk;
  task tick; begin @(posedge clk); #1; end endtask
  initial begin
    rst=1; commit_ack=0; dispatch_2_rob='0; common_data_bus='0; lsq2robpack='0; branchres2rob='0; branch_flush='0; jumpresrob='0;
    tick(); rst=0; #1;
    dispatch_2_rob.alloc_en=1; dispatch_2_rob.has_rd_check=1; dispatch_2_rob.arf_rd=5'd1; dispatch_2_rob.new_phy_rd=6'd33;
    if (rob_idx_dispatch !== 5'd0) begin $display("FAIL first_dispatch_index"); $fatal(1); end
    tick();
    dispatch_2_rob.arf_rd=5'd2; dispatch_2_rob.new_phy_rd=6'd34; #1;
    if (rob_idx_dispatch !== 5'd1) begin $display("FAIL second_dispatch_index_not_combinational"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
"""


P8_REAL_RAT_BYPASS_TB = r"""`timescale 1ns/1ps
module tb;
  import rv32i_types::*;
  logic clk=0, rst, wr_enable;
  logic [ADDR_BITS-1:0] read_rs1_idx, read_rs2_idx, read_rs3_idx, write_rd_idx, specrd_idx;
  logic [PRF_IDX_WIDTH-1:0] write_phy_rd, specrd_mapping, rs1_phy_idx, rs2_phy_idx, rs3_phy_idx;
  commit2rat_t commit2rat; branch_flush_t branch_flush;
  rat dut(.*);
  always #5 clk=~clk;
  task tick; begin @(posedge clk); #1; end endtask
  initial begin
    rst=1; wr_enable=0; read_rs1_idx=5'd1; read_rs2_idx=5'd2; read_rs3_idx=5'd3;
    write_rd_idx=0; write_phy_rd=0; specrd_idx=0; specrd_mapping=0; commit2rat='0; branch_flush='0;
    tick(); rst=0; #1;
    specrd_idx=5'd1; specrd_mapping=6'd44; #1;
    if (rs1_phy_idx!==6'd44) begin $display("FAIL speculative_bypass"); $fatal(1); end
    read_rs2_idx=5'd1; #1;
    if (rs2_phy_idx!==6'd44) begin $display("FAIL speculative_bypass_rs2"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
"""


P9_REAL_FLUSH_RESTORE_TB = r"""`timescale 1ns/1ps
module tb;
  import rv32i_types::*;
  logic clk=0,rst,frlist_full,frlist_empty;
  rename2frlist_t rename2frlist; commit2frlist_t commit2frlist; frlist2rename_t frlist2rename; rob2frlist_t rob2frlist;
  freelist dut(.*);
  always #5 clk=~clk;
  task tick; begin @(posedge clk); #1; end endtask
  initial begin
    rst=1; rename2frlist='0; commit2frlist='0; rob2frlist='0;
    tick(); rst=0; #1;
    repeat (3) begin
      rename2frlist.alloc_ack=1; tick();
      rename2frlist.alloc_ack=0; tick();
    end
    commit2frlist.free_en=1; commit2frlist.old_phy_rd=6'd9; tick();
    commit2frlist='0; #1;
    if (frlist2rename.freelistcount !== 6'd30) begin $display("FAIL setup_commit_count"); $fatal(1); end
    rob2frlist.valid=1;
    rob2frlist.freelist_head=6'd3;
    rob2frlist.freelist_tail=6'd1;
    rob2frlist.freelistcount=6'd30;
    commit2frlist.free_en=1;
    commit2frlist.old_phy_rd=6'd11;
    tick();
    rob2frlist='0; commit2frlist='0; #1;
    if (frlist2rename.freelistcount !== 6'd32) begin $display("FAIL restored_from_speculative_checkpoint"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
"""


P10_REAL_JALR_TARGET_TB = r"""`timescale 1ns/1ps
module tb;
  import rv32i_types::*;
  logic clk=0,rst,commit_ack,robfull,robempty;
  logic [ROB_IDX_WIDTH-1:0] rob_idx_dispatch;
  dispatch_2_rob_t dispatch_2_rob; common_data_bus_t common_data_bus; rob2commit_t rob2commit;
  lsq2rob_t lsq2robpack; branchres2rob_t branchres2rob; branch_flush_t branch_flush; jumpresrob_t jumpresrob; rob2frlist_t rob2frlist;
  rob dut(.*);
  always #5 clk=~clk;
  task tick; begin @(posedge clk); #1; end endtask
  initial begin
    rst=1; commit_ack=0; dispatch_2_rob='0; common_data_bus='0; lsq2robpack='0; branchres2rob='0; branch_flush='0; jumpresrob='0;
    tick(); rst=0; #1;
    dispatch_2_rob.alloc_en=1;
    dispatch_2_rob.jump=1;
    dispatch_2_rob.branchtg_addr=32'h0000_0007;
    tick();
    dispatch_2_rob='0; #1;
    jumpresrob.valid=1;
    jumpresrob.rob_idx=5'd0;
    jumpresrob.jalr=1;
    jumpresrob.rs1=32'h0000_1000;
    tick();
    jumpresrob='0; #1;
    if (rob2commit.branchtg_addr !== 32'h0000_1006) begin $display("FAIL jalr_target_missing_rs1_base"); $fatal(1); end
    $display("VERDICT: PASS"); $finish;
  end
endmodule
"""


CASE_LIST: list[RepairCase] = [
    RepairCase(
        case_id="fetch_queue_flush_ignored",
        problem_id="P6",
        bug_class="flush_priority",
        bug_summary="The fetch/decode queue ignores a taken branch flush, so stale entries remain visible.",
        expected_failure="FAIL branch_flush_did_not_clear",
        trace_summary=(
            "After two writes, the head entry is read correctly. On the next cycle "
            "branch_flush.valid=1 and branch_flush.branch_taken=1, but empty remains 0 "
            "and filled does not reflect a cleared queue. Head/tail state behaved as if "
            "normal FIFO state was preserved through recovery."
        ),
        mutator=p6_ignore_branch_flush,
    ),
    RepairCase(
        case_id="fetch_queue_pc_payload_corrupt",
        problem_id="P6",
        bug_class="payload_integrity",
        bug_summary="The queue enqueues instruction data but drops the matching PC payload.",
        expected_failure="FAIL first_head_value",
        trace_summary=(
            "Cycle after the first enqueue: write_data=0x000000aa and write_pc=0x80000000 "
            "were accepted while the queue was not full. The exposed head has the expected "
            "instruction data but read_pc is zero, showing that the PC array did not capture "
            "the enqueue payload."
        ),
        mutator=p6_drop_pc_payload,
    ),
    RepairCase(
        case_id="icache_burst_resp_one_beat_early",
        problem_id="P7",
        bug_class="multi_beat_protocol",
        bug_summary="The burst adapter asserts cache_resp after the third beat instead of the fourth.",
        expected_failure="FAIL no_response_after_four_beats",
        trace_summary=(
            "The adapter sees four bmem_rvalid beats for address 0x2000. cache_resp rises "
            "while burst count corresponds to the third accepted beat, then returns idle; "
            "when the fourth beat arrives the response expected by the testbench is absent."
        ),
        mutator=p7_respond_one_beat_early,
    ),
    RepairCase(
        case_id="icache_burst_lane3_overwrites_lane0",
        problem_id="P7",
        bug_class="multi_beat_protocol",
        bug_summary="The fourth 64-bit memory beat overwrites lane 0 instead of lane 3.",
        expected_failure="FAIL packed_burst_lanes",
        trace_summary=(
            "Four matching beats are accepted for one cache-line request. The response cycle "
            "arrives at the right time, but cache_rdata[63:0] contains the last beat and "
            "cache_rdata[255:192] is missing it, indicating a lane-indexing bug in burst packing."
        ),
        mutator=p7_pack_last_beat_wrong_lane,
    ),
    RepairCase(
        case_id="rat_commit_lost_during_flush",
        problem_id="P8",
        bug_class="ooo_recovery",
        bug_summary="A branch flush restores the speculative RAT from stale committed state and loses a simultaneous commit update.",
        expected_failure="FAIL same_cycle_commit_flush_lost",
        trace_summary=(
            "The RAT first renames architectural register 5 to physical 46. In the same cycle, "
            "commit2rat.commit_update=1 for architectural register 5 and branch_flush is taken. "
            "After recovery, rs1_phy_idx for register 5 is not 46, so the flush copied the old "
            "committed map instead of preserving the same-cycle commit."
        ),
        mutator=p8_lose_same_cycle_commit_on_flush,
    ),
    RepairCase(
        case_id="icache_reads_when_dcache_selected",
        problem_id="P7",
        bug_class="real_history_arbitration",
        bug_summary="Historical i-cache burst adapter bug: cache_read could start a memory transaction even when the i-cache was not chosen.",
        expected_failure="FAIL icache_started_while_dcache_chosen",
        trace_summary=(
            "At idle, cache_read=1 while i_cache_chosen=0. bmem_read still pulses and the adapter "
            "captures the request address, which means the instruction side is stealing the memory "
            "port during a data-cache arbitration window."
        ),
        mutator=p7_remove_icache_chosen_start_gate,
        real_commit="bbb61a8",
        real_commit_message="fixed one more arbitration issue",
        custom_testbench=P7_REAL_ICACHE_ARB_TB,
        distractor_files=(
            "mp_ooo_baseline/hdl/d_burst_adapter.sv",
            "mp_ooo_baseline/hdl/icache.sv",
        ),
    ),
    RepairCase(
        case_id="rat_missing_same_cycle_rename_bypass",
        problem_id="P8",
        bug_class="real_history_rename_bypass",
        bug_summary="Historical RAT bug: same-cycle speculative destination bypass was missing for source reads.",
        expected_failure="FAIL speculative_bypass",
        trace_summary=(
            "Immediately after reset, read_rs1_idx names the same architectural register as "
            "specrd_idx, and specrd_mapping carries the newly allocated physical register. "
            "rs1_phy_idx still returns the old table value, so the combinational read path is "
            "not bypassing the same-cycle speculative rename mapping."
        ),
        mutator=p8_remove_same_cycle_spec_bypass,
        real_commit="513f159",
        real_commit_message="j test rat fix",
        custom_testbench=P8_REAL_RAT_BYPASS_TB,
        distractor_files=(
            "mp_ooo_baseline/hdl/rename_stage.sv",
            "mp_ooo_baseline/hdl/dispatch.sv",
        ),
    ),
    RepairCase(
        case_id="rob_dispatch_tag_stale",
        problem_id="P10",
        bug_class="real_history_dispatch_index",
        bug_summary="Historical ROB bug: rob_idx_dispatch was registered, so dispatch observed a stale ROB index.",
        expected_failure="FAIL second_dispatch_index_not_combinational",
        trace_summary=(
            "After the first allocation, the tail has advanced. Before the second allocation edge, "
            "dispatch needs rob_idx_dispatch=1 for the entry it is about to allocate. The buggy "
            "registered output still reports the previous value, so downstream rename/issue metadata "
            "would carry the wrong ROB tag."
        ),
        mutator=p10_register_dispatch_index,
        real_commit="582bf6c",
        real_commit_message="fixed multiplication, rob issues",
        custom_testbench=P10_REAL_ROB_IDX_TB,
        distractor_files=(
            "mp_ooo_baseline/hdl/execute.sv",
            "mp_ooo_baseline/hdl/commit_stage.sv",
        ),
    ),
    RepairCase(
        case_id="freelist_flush_restores_speculative_checkpoint",
        problem_id="P9",
        bug_class="real_history_freelist_recovery",
        bug_summary="Historical freelist bug: branch recovery restored a speculative checkpoint instead of the committed freelist shadow state.",
        expected_failure="FAIL restored_from_speculative_checkpoint",
        trace_summary=(
            "After three speculative allocations and one committed free, a branch recovery arrives "
            "with an old ROB checkpoint while the same cycle commits another free. The buggy design "
            "loads head/tail/count directly from rob2frlist, leaving freelistcount at 30 instead of "
            "restoring the coherent committed state with all 32 physical registers available."
        ),
        mutator=p9_restore_from_speculative_checkpoint_on_flush,
        real_commit="2c76489",
        real_commit_message="freelist fix",
        custom_testbench=P9_REAL_FLUSH_RESTORE_TB,
        distractor_files=(
            "mp_ooo_baseline/hdl/rob.sv",
            "mp_ooo_baseline/hdl/rename_stage.sv",
        ),
    ),
    RepairCase(
        case_id="rob_jalr_target_missing_rs1_base",
        problem_id="P10",
        bug_class="real_history_jump_target",
        bug_summary="Historical ROB/JALR bug: the jump target used only the immediate field and forgot to add the resolved rs1 base.",
        expected_failure="FAIL jalr_target_missing_rs1_base",
        trace_summary=(
            "A JALR entry is allocated with immediate target bits 0x7. The execute/jump result "
            "later supplies rs1=0x1000. The repaired ROB should publish branch target 0x1006, "
            "but the buggy update masks the immediate alone and reports 0x6."
        ),
        mutator=p10_jalr_target_missing_rs1_base,
        real_commit="5ae5544",
        real_commit_message="jump fix",
        custom_testbench=P10_REAL_JALR_TARGET_TB,
        distractor_files=(
            "mp_ooo_baseline/hdl/execute.sv",
            "mp_ooo_baseline/hdl/commit_stage.sv",
        ),
    ),
    RepairCase(
        case_id="freelist_alloc_count_stuck",
        problem_id="P9",
        bug_class="ooo_resource_accounting",
        bug_summary="The freelist advances its head on allocation but fails to decrement the available-register count.",
        expected_failure="FAIL three_allocations",
        trace_summary=(
            "After reset, the freelist exposes physical register 32 and count 32. Three accepted "
            "allocations advance the head to the entry that should expose physical register 35, "
            "but the reported count remains too high instead of dropping to 29. The allocation "
            "data path and the resource-accounting path are inconsistent."
        ),
        mutator=p9_allocation_count_stuck,
    ),
    RepairCase(
        case_id="rob_cdb_marks_head_not_target",
        problem_id="P10",
        bug_class="ooo_completion_ordering",
        bug_summary="The ROB marks the head entry complete on any CDB completion instead of marking the CDB target ROB index.",
        expected_failure="FAIL younger_ready_committed_before_head",
        trace_summary=(
            "Two entries are dispatched. The common data bus first completes the younger entry "
            "at ROB index 1, while the head at index 0 is still incomplete. rob2commit.commit "
            "nevertheless becomes high, so the CDB completion appears to have updated the head "
            "entry rather than the indexed entry named by common_data_bus.rob_idx."
        ),
        mutator=p10_cdb_marks_head_instead_of_target,
    ),
]


CASES: dict[str, RepairCase] = {
    case.case_id: case
    for case in CASE_LIST
}


ALIASES: dict[str, str] = {
    "P6_FLUSH": "fetch_queue_flush_ignored",
    "P6_PC": "fetch_queue_pc_payload_corrupt",
    "P7_EARLY_RESP": "icache_burst_resp_one_beat_early",
    "P7_LANE": "icache_burst_lane3_overwrites_lane0",
    "P8_COMMIT_FLUSH": "rat_commit_lost_during_flush",
    "P7_REAL_ICACHE_ARB": "icache_reads_when_dcache_selected",
    "P8_REAL_RAT_BYPASS": "rat_missing_same_cycle_rename_bypass",
    "P10_REAL_ROB_IDX": "rob_dispatch_tag_stale",
    "P9_REAL_FLUSH_RESTORE": "freelist_flush_restores_speculative_checkpoint",
    "P10_REAL_JALR_TARGET": "rob_jalr_target_missing_rs1_base",
    "P9_ALLOC_COUNT": "freelist_alloc_count_stuck",
    "P10_CDB_TARGET": "rob_cdb_marks_head_not_target",
}


def all_case_ids() -> list[str]:
    return [case.case_id for case in CASE_LIST]


def get_case(case_id: str) -> RepairCase:
    resolved = ALIASES.get(case_id.upper(), case_id)
    try:
        return CASES[resolved]
    except KeyError as exc:
        known = ", ".join(all_case_ids())
        raise KeyError(f"Unknown case_id '{case_id}'. Expected one of: {known}") from exc
