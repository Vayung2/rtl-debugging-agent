# Final Project Setup

Project: **Verification-Guided RTL Repair Agent Using Simulation Logs and Waveform Summaries**

This directory reuses the HW4/HW5 RTL benchmark infrastructure. It creates injected bugs in real SystemVerilog modules, gathers Verilator-style debug artifacts, asks an LLM to repair the RTL, and validates the repaired module with the existing HW4 verifier.

## Requirements

- Python 3.9+
- Python packages already used by HW4: `openai`, `pydantic`
- Verilator in `PATH` for the recommended simulator path
- `OPENAI_API_KEY` set in the environment for LLM repair runs

No API keys should be committed. Use:

```bash
export OPENAI_API_KEY="..."
export LLM_MODEL="gpt-5.4"
```

## Validate Bug Cases

Run this first. It checks that each reference module passes and each injected bug fails.

```bash
python3 evaluate.py --validate-cases-only --output-json case_validation.json
```

## Collect Debug Artifacts

This produces the lint/simulation log and waveform-derived summary for each bug case.

```bash
python3 artifacts.py --output-json artifacts.json
```

## Run the Main Study

Default study: twelve bug cases, three evidence conditions, three trials each.

```bash
python3 evaluate.py \
  --trials 3 \
  --conditions rtl_only sim_log sim_log_trace \
  --output-json repair_results.json
```

The output JSON contains per-trial records plus aggregate pass rates by condition and bug class.

To focus only on bugs derived from real ECE 411 bug-fix commits:

```bash
python3 evaluate.py \
  --real-only \
  --trials 3 \
  --conditions rtl_only sim_log sim_log_trace \
  --output-json repair_results.json
```

With the current case bank, `--real-only` runs five real commit-history bugs.

For the more realistic fault-localization study, where the model receives
several plausible RTL files instead of the exact buggy module:

```bash
python3 evaluate.py \
  --real-only \
  --localize \
  --resume \
  --trials 3 \
  --conditions rtl_only sim_log sim_log_trace \
  --output-json repair_results.json
```

## Evidence Conditions

- `rtl_only`: module interface and buggy RTL only. It does not include success criteria, bug class, failure reason, or high-level symptom.
- `sim_log`: problem statement, success criteria, buggy RTL, and simulation failure logs.
- `sim_log_trace`: `sim_log` plus a concise waveform-derived signal timeline summary.

## Current Bug Cases

- `fetch_queue_flush_ignored`: fetch/decode queue ignores taken branch flush.
- `fetch_queue_pc_payload_corrupt`: fetch/decode queue stores the wrong PC payload.
- `icache_burst_resp_one_beat_early`: instruction burst adapter responds after three beats instead of four.
- `icache_burst_lane3_overwrites_lane0`: instruction burst adapter packs the fourth beat into lane 0.
- `icache_reads_when_dcache_selected`: real commit `bbb61a8`, i-cache request starts even when the i-cache is not chosen.
- `rat_commit_lost_during_flush`: RAT loses a simultaneous commit during branch recovery.
- `rat_missing_same_cycle_rename_bypass`: real commit `513f159`, missing same-cycle speculative RAT bypass.
- `freelist_flush_restores_speculative_checkpoint`: real commit `2c76489`, branch recovery restores speculative freelist checkpoint instead of committed shadow state.
- `freelist_alloc_count_stuck`: freelist allocation count is not decremented.
- `rob_cdb_marks_head_not_target`: ROB CDB completion marks the head instead of the target ROB entry.
- `rob_dispatch_tag_stale`: real commit `582bf6c`, stale registered ROB dispatch index.
- `rob_jalr_target_missing_rs1_base`: real commit `5ae5544`, JALR target update omits the resolved rs1 base.
