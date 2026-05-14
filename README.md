**RTL Debugging Agent for Out-of-Order Processor Bugs**

This project studies a realistic hardware-debug question:

> Which engineering debug artifacts help an LLM repair broken RTL: source context alone, simulator logs, or simulator logs plus waveform-style signal summaries?

The benchmark is built from a Verilator-compatible ECE 411 out-of-order processor codebase. The strongest part of the project is the real-bug pipeline: mine historical RTL bug-fix commits, recreate the bug as a targeted mutation, write a focused verifier, generate debug artifacts, ask an LLM to repair the RTL, and validate the result with hidden simulation tests.

## Main Result

The main real-history fault-localization study uses five bugs mined from ECE 411 commit history, three evidence conditions, and three trials per condition.

| Condition | Passes / Total | Pass rate |
|---|---:|---:|
| RTL only | 6 / 15 | 40.0% |
| Simulation log | 8 / 15 | 53.3% |
| Simulation log + trace summary | 15 / 15 | 100.0% |

The result is stored in `repair_results.json`. The validation artifact `real_case_validation.json` confirms that every reference implementation passes and every injected real-history bug fails before repair.

## Real-History Bugs

| Case | Commit | Bug |
|---|---|---|
| `icache_reads_when_dcache_selected` | `bbb61a8` | I-cache burst adapter starts a memory transaction after losing arbitration. |
| `rat_missing_same_cycle_rename_bypass` | `513f159` | RAT read path misses same-cycle speculative destination bypass. |
| `rob_dispatch_tag_stale` | `582bf6c` | Dispatch observes a stale registered ROB index. |
| `freelist_flush_restores_speculative_checkpoint` | `2c76489` | Branch recovery restores speculative freelist checkpoint instead of committed shadow state. |
| `rob_jalr_target_missing_rs1_base` | `5ae5544` | JALR target update masks the immediate but omits the resolved `rs1` base. |

There are also seven synthetic stress cases for related RTL-debug patterns.

## Files

- `final_report.pdf`: 4-page course report with question, prediction, method, validation, results, discussion, limitations, and reproducibility.
- `predictions.md`: dated prior prediction written before the substantial run.
- `bug_cases.py`: real and synthetic bug definitions, mutations, custom testbenches, and trace summaries.
- `artifacts.py`: debug-artifact generator.
- `repair_agent.py`: LLM repair prompt construction and verifier loop.
- `evaluate.py`: controlled experiment runner with resume support.
- `repair_results.json`: per-trial repair logs and aggregate summary.
- `real_case_validation.json`: reference-pass/buggy-fail validation for the real-history cases.
- `SETUP.md`: dependency and command reference.

## Reproduce

No API keys are committed. Set your key through the environment:

```bash
export OPENAI_API_KEY="..."
```

Validate the real-history bug suite:

```bash
python3 evaluate.py --validate-cases-only --real-only \
  --output-json real_case_validation.json
```

Run or resume the main study:

```bash
python3 evaluate.py --real-only --localize --resume --trials 3 \
  --conditions rtl_only sim_log sim_log_trace \
  --output-json repair_results.json
```

Expected main-study output: 45 real-history repair trials with aggregate pass rates matching the table above.

## Known Failure Modes

- Long prompts can hit token-per-minute limits. The runner supports `--resume` and prompt shrinking so interrupted runs continue from completed rows.
- The trace summaries are concise textual summaries of targeted waveforms, not a production VCD-mining system.
- The verifier checks focused module-level behavior. Passing a hidden testbench is strong evidence for the targeted bug, but not a full-chip proof.
