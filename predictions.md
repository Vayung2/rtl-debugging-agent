# Predictions

Date: 2026-05-14

Project title: **Verification-Guided RTL Repair Agent Using Simulation Logs and Waveform Summaries**

Primary hypothesis: adding simulator failure logs will improve one-shot RTL repair success over the buggy RTL alone, and adding a short waveform-derived signal summary will improve success further on bugs whose root cause is temporal or protocol-level.

Specific predictions:

- `rtl_only` will fix the simplest local payload bug (`fetch_queue_pc_payload_corrupt`) more often than the temporal and OoO bugs, because the suspicious assignment is visible in the code.
- `sim_log` will help cases with informative testbench failures, especially `icache_burst_resp_one_beat_early` and `rat_commit_lost_during_flush`, because the failure reason names the violated protocol.
- `sim_log_trace` will help most on `icache_burst_lane3_overwrites_lane0` and `rat_commit_lost_during_flush`, where the relevant evidence is a relation among signals over multiple cycles rather than a single compile error or missing assignment.
- The hardest baseline cases should be `freelist_alloc_count_stuck`, `rob_cdb_marks_head_not_target`, and `rob_dispatch_tag_stale`, because the model must connect an observed failure to resource accounting or indexed completion in a larger microarchitectural module.
- Waveform summaries may hurt if the model overfits to the exact displayed transaction instead of repairing the general RTL rule.

Primary metric: hidden-verifier pass rate after one repair attempt.

Secondary metrics: compile success, failure reason after attempted repair, pass rate by bug class, and examples where extra evidence changed the patch.
