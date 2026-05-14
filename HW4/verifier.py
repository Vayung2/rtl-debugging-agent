from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from llm_utils import RtlSolution
from problem_bank import ProblemSpec, all_problem_ids, get_problem
from sim_harness import DEFAULT_SIM_TIMEOUT, run_problem_testbench


def verify(
    problem_id: str,
    solution: RtlSolution | dict[str, Any],
    *,
    timeout: int = DEFAULT_SIM_TIMEOUT,
    keep_temp: bool = False,
    simulator: str = "verilator",
) -> dict[str, Any]:
    if isinstance(solution, dict):
        solution = RtlSolution.model_validate(solution)

    problem = get_problem(problem_id)
    sim_result = run_problem_testbench(
        problem,
        solution.module_sv,
        use_public_tb=False,
        preferred_simulator=simulator,
        timeout=timeout,
        keep_temp=keep_temp,
    )

    if sim_result.ok:
        return {
            "pass": True,
            "details": {
                "problem_id": problem.problem_id,
                "title": problem.title,
                "simulator": sim_result.simulator,
                "stage": sim_result.stage,
            },
            "reason": "Hidden verification testbench passed.",
        }

    return {
        "pass": False,
        "details": {
            "problem_id": problem.problem_id,
            "title": problem.title,
            "simulator": sim_result.simulator,
            "stage": sim_result.stage,
            "stdout_tail": sim_result.stdout[-1200:],
            "stderr_tail": sim_result.stderr[-1200:],
            "workdir": sim_result.workdir if keep_temp else None,
        },
        "reason": sim_result.reason,
    }


def verify_manual_case(
    problem: ProblemSpec,
    module_sv: str,
    *,
    use_public_tb: bool,
    timeout: int,
    simulator: str,
) -> dict[str, Any]:
    sim_result = run_problem_testbench(
        problem,
        module_sv,
        use_public_tb=use_public_tb,
        preferred_simulator=simulator,
        timeout=timeout,
        keep_temp=False,
    )
    return {
        "pass": sim_result.ok,
        "reason": sim_result.reason,
        "simulator": sim_result.simulator,
        "stage": sim_result.stage,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run hidden verification on a candidate SystemVerilog solution.")
    parser.add_argument("problem_id", choices=all_problem_ids())
    parser.add_argument("candidate", help="Path to a candidate .sv file.")
    parser.add_argument("--timeout", type=int, default=DEFAULT_SIM_TIMEOUT)
    parser.add_argument("--keep-temp", action="store_true")
    parser.add_argument("--simulator", choices=["verilator", "iverilog"], default="verilator")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    candidate_path = Path(args.candidate).resolve()
    solution = RtlSolution(module_sv=candidate_path.read_text(encoding="utf-8"), confidence=0)
    result = verify(
        args.problem_id,
        solution,
        timeout=args.timeout,
        keep_temp=args.keep_temp,
        simulator=args.simulator,
    )
    print(json.dumps(result, indent=2))
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
