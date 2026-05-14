from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent
HW4_DIR = REPO_ROOT / "HW4"
if str(HW4_DIR) not in sys.path:
    sys.path.insert(0, str(HW4_DIR))

from llm_utils import DEFAULT_API_KEY, DEFAULT_BASE_URL, DEFAULT_MODEL  # noqa: E402

from bug_cases import all_case_ids, get_case
from repair_agent import CONDITIONS, repair_once, verify_reference_and_bug


def summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    by_condition: dict[str, dict[str, int]] = {}
    by_bug_class: dict[str, dict[str, int]] = {}
    for row in rows:
        cond = row["condition"]
        bug_class = row["bug_class"]
        by_condition.setdefault(cond, {"passes": 0, "total": 0})
        by_condition[cond]["total"] += 1
        by_condition[cond]["passes"] += int(bool(row["pass"]))
        by_bug_class.setdefault(bug_class, {"passes": 0, "total": 0})
        by_bug_class[bug_class]["total"] += 1
        by_bug_class[bug_class]["passes"] += int(bool(row["pass"]))
    return {
        "by_condition": by_condition,
        "by_bug_class": by_bug_class,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the final-project RTL repair evaluation.")
    parser.add_argument("--cases", nargs="+", default=all_case_ids(), choices=all_case_ids())
    parser.add_argument("--real-only", action="store_true", help="Run only cases derived from real ECE 411 bug-fix commits.")
    parser.add_argument("--conditions", nargs="+", default=CONDITIONS, choices=CONDITIONS)
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--api-key", default=DEFAULT_API_KEY)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--request-timeout", type=float, default=120.0)
    parser.add_argument("--simulator", choices=["verilator", "iverilog"], default="verilator")
    parser.add_argument("--sim-timeout", type=int, default=30)
    parser.add_argument("--output-json", default="repair_results.json")
    parser.add_argument("--validate-cases-only", action="store_true")
    parser.add_argument("--localize", action="store_true", help="Show several candidate RTL files and require the model to localize the bug before patching.")
    parser.add_argument("--resume", action="store_true", help="Continue an existing output JSON by skipping completed case/condition/trial rows.")
    parser.add_argument("--max-prompt-chars", type=int, default=36000)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    case_ids = args.cases
    if args.real_only:
        case_ids = [case_id for case_id in case_ids if get_case(case_id).real_commit]
    if args.validate_cases_only:
        validations = [
            verify_reference_and_bug(get_case(case_id), simulator=args.simulator, timeout=args.sim_timeout)
            for case_id in case_ids
        ]
        Path(args.output_json).write_text(json.dumps(validations, indent=2), encoding="utf-8")
        print(f"Wrote {args.output_json}")
        return 0 if all(v["reference"]["pass"] and not v["buggy"]["pass"] for v in validations) else 1

    rows: list[dict[str, Any]] = []
    output_path = Path(args.output_json)
    if args.resume and output_path.exists():
        existing = json.loads(output_path.read_text(encoding="utf-8"))
        rows = existing.get("results", []) if isinstance(existing, dict) else existing
        print(f"Loaded {len(rows)} existing rows from {args.output_json}", flush=True)
    completed = {
        (row.get("case_id"), row.get("condition"), int(row.get("trial", 0)), row.get("task_mode", "exact_module"))
        for row in rows
    }
    task_mode = "localize" if args.localize else "exact_module"
    for case_id in case_ids:
        case = get_case(case_id)
        for condition in args.conditions:
            for trial in range(1, args.trials + 1):
                key = (case.case_id, condition, trial, task_mode)
                if key in completed:
                    print(f"Skipping existing {case.case_id} {condition} trial {trial} ({task_mode})", flush=True)
                    continue
                print(f"Running {case_id} {condition} trial {trial}", flush=True)
                row = repair_once(
                    case,
                    condition=condition,
                    model=args.model,
                    api_key=args.api_key,
                    base_url=args.base_url,
                    request_timeout=args.request_timeout,
                    temperature=args.temperature,
                    simulator=args.simulator,
                    sim_timeout=args.sim_timeout,
                    localize=args.localize,
                    max_prompt_chars=args.max_prompt_chars,
                )
                row["trial"] = trial
                rows.append(row)
                Path(args.output_json).write_text(
                    json.dumps({"results": rows, "summary": summarize(rows)}, indent=2),
                    encoding="utf-8",
                )
    print(f"Wrote {args.output_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
