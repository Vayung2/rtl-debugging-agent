from __future__ import annotations

import argparse
import json
import sys
from dataclasses import replace
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent
HW4_DIR = REPO_ROOT / "HW4"
if str(HW4_DIR) not in sys.path:
    sys.path.insert(0, str(HW4_DIR))

from problem_bank import REAL_TYPES_PREFIX  # noqa: E402
from sim_harness import DEFAULT_SIM_TIMEOUT, run_problem_testbench  # noqa: E402

from bug_cases import RepairCase, all_case_ids, get_case


def tail(text: str, limit: int = 1200) -> str:
    return text[-limit:] if len(text) > limit else text


def collect_artifacts(
    case: RepairCase,
    *,
    simulator: str = "verilator",
    timeout: int = DEFAULT_SIM_TIMEOUT,
    use_public_tb: bool = False,
) -> dict[str, Any]:
    problem = case.problem
    if case.custom_testbench is not None:
        problem = replace(problem, hidden_testbench=REAL_TYPES_PREFIX + case.custom_testbench)
    buggy_sv = case.buggy_sv()
    sim = run_problem_testbench(
        problem,
        buggy_sv,
        use_public_tb=use_public_tb,
        preferred_simulator=simulator,
        timeout=timeout,
        keep_temp=False,
    )
    return {
        "case_id": case.case_id,
        "problem_id": case.problem_id,
        "title": problem.title,
        "bug_class": case.bug_class,
        "bug_summary": case.bug_summary,
        "expected_failure": case.expected_failure,
        "real_commit": case.real_commit,
        "real_commit_message": case.real_commit_message,
        "compile": {
            "ok": sim.stage == "run",
            "stage": sim.stage,
            "reason": "compiled successfully before simulation" if sim.stage == "run" else sim.reason,
            "stdout_tail": tail(sim.stdout, 800) if sim.stage != "run" else "",
            "stderr_tail": tail(sim.stderr, 800) if sim.stage != "run" else "",
        },
        "simulation": {
            "pass": sim.ok,
            "stage": sim.stage,
            "reason": sim.reason,
            "stdout_tail": tail(sim.stdout),
            "stderr_tail": tail(sim.stderr),
        },
        "trace_summary": case.trace_summary,
    }


def format_artifacts_for_prompt(artifacts: dict[str, Any], condition: str) -> str:
    if condition == "rtl_only":
        return ""
    sim = artifacts["simulation"]
    compile_result = artifacts["compile"]
    parts = [
        "Debug artifacts:",
        f"- Compile ok: {compile_result['ok']}; compile reason: {compile_result['reason']}",
        f"- Simulation pass: {sim['pass']}; stage: {sim['stage']}; reason: {sim['reason']}",
    ]
    if sim["stdout_tail"]:
        parts.append("Simulation stdout tail:\n" + sim["stdout_tail"])
    if sim["stderr_tail"]:
        parts.append("Simulation stderr tail:\n" + sim["stderr_tail"])
    if condition == "sim_log_trace":
        parts.append("Waveform-derived signal summary:\n" + artifacts["trace_summary"])
    return "\n\n".join(parts)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Collect lint/simulation/trace artifacts for final-project bug cases.")
    parser.add_argument("--cases", nargs="+", default=all_case_ids(), choices=all_case_ids())
    parser.add_argument("--simulator", choices=["verilator", "iverilog"], default="verilator")
    parser.add_argument("--timeout", type=int, default=DEFAULT_SIM_TIMEOUT)
    parser.add_argument("--public", action="store_true", help="Use public testbenches instead of hidden validation testbenches.")
    parser.add_argument("--output-json", default="artifacts.json")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = [
        collect_artifacts(get_case(case_id), simulator=args.simulator, timeout=args.timeout, use_public_tb=args.public)
        for case_id in args.cases
    ]
    Path(args.output_json).write_text(json.dumps(rows, indent=2), encoding="utf-8")
    print(f"Wrote {args.output_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
