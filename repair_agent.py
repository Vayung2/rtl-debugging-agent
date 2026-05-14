from __future__ import annotations

import json
import sys
import time
from dataclasses import replace
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent
HW4_DIR = REPO_ROOT / "HW4"
if str(HW4_DIR) not in sys.path:
    sys.path.insert(0, str(HW4_DIR))

from llm_utils import (  # noqa: E402
    DEFAULT_API_KEY,
    DEFAULT_BASE_URL,
    DEFAULT_MODEL,
    RtlSolution,
    complete_json,
    make_client,
)
from problem_bank import REAL_TYPES_PREFIX  # noqa: E402
from sim_harness import run_problem_testbench  # noqa: E402
from verifier import verify  # noqa: E402

from artifacts import collect_artifacts, format_artifacts_for_prompt
from bug_cases import RepairCase


CONDITIONS = ["rtl_only", "sim_log", "sim_log_trace"]


SYSTEM_PROMPT = """You are an RTL repair assistant.

You are given a SystemVerilog module from a processor RTL project.
It may have one or more behavioral bugs, or it may need only a small local fix.
Repair the module while preserving the exact module name, ports, package imports, and parameters.
Use any debug artifacts as evidence, but do not overfit to one displayed value if the underlying protocol rule is broader.

Return exactly one JSON object with:
{
  "module_sv": "...complete repaired SystemVerilog source...",
  "confidence": 0-100
}

Do not include markdown fences or commentary outside the JSON object."""


def build_repair_prompt(case: RepairCase, condition: str, artifacts: dict[str, Any]) -> str:
    problem = case.problem
    artifact_text = format_artifacts_for_prompt(artifacts, condition)
    if condition == "rtl_only":
        return (
            "Repair the following RTL implementation. Preserve the public interface exactly.\n\n"
            "Module interface:\n"
            f"{problem.interface}\n\n"
            "Buggy RTL to repair:\n"
            f"{case.buggy_sv()}\n"
        )

    prompt = (
        "Repair the following RTL implementation.\n\n"
        "Problem statement:\n"
        f"{problem.problem_statement}\n\n"
        "Required interface:\n"
        f"{problem.interface}\n\n"
        "Success criteria:\n"
        f"{problem.success_criteria}\n\n"
        f"{artifact_text}\n\n"
        "Buggy RTL to repair:\n"
        f"{case.buggy_sv()}\n"
    )
    return prompt


def format_candidate_sources(case: RepairCase) -> str:
    chunks = []
    for path, source in case.candidate_sources():
        chunks.append(f"--- BEGIN {path} ---\n{source}\n--- END {path} ---")
    return "\n\n".join(chunks)


def format_candidate_interfaces(case: RepairCase) -> str:
    chunks = []
    for path, header in case.candidate_interfaces():
        chunks.append(f"--- BEGIN {path} INTERFACE ---\n{header}\n--- END {path} INTERFACE ---")
    return "\n\n".join(chunks)


def build_localization_prompt(case: RepairCase, condition: str, artifacts: dict[str, Any]) -> str:
    artifact_text = format_artifacts_for_prompt(artifacts, condition)
    if condition == "rtl_only":
        return (
            "A processor regression is failing, but no failure log is available in this condition. "
            "You only have the public interfaces of plausible files. Pick the most likely module "
            "and write a repaired implementation for that module. Return the complete source for "
            "one module as module_sv.\n\n"
            "Candidate module interfaces:\n"
            f"{format_candidate_interfaces(case)}\n"
        )
    else:
        context = (
            "A processor regression is failing. Use the debug artifacts to localize the fault across "
            "the candidate RTL files, then repair the most likely buggy file. Return the complete "
            "source for the single file you changed as module_sv.\n\n"
            f"{artifact_text}\n"
        )

    return (
        f"{context}\n"
        "Candidate RTL files:\n"
        f"{format_candidate_sources(case)}\n"
    )


def repair_once(
    case: RepairCase,
    *,
    condition: str,
    model: str = DEFAULT_MODEL,
    api_key: str = DEFAULT_API_KEY,
    base_url: str = DEFAULT_BASE_URL,
    request_timeout: float = 120.0,
    temperature: float | None = 0.2,
    simulator: str = "verilator",
    sim_timeout: int = 30,
    localize: bool = False,
    max_prompt_chars: int = 36000,
) -> dict[str, Any]:
    if condition not in CONDITIONS:
        raise ValueError(f"Unknown condition {condition!r}; expected one of {CONDITIONS}")

    artifacts = collect_artifacts(case, simulator=simulator, timeout=sim_timeout)
    client = make_client(api_key=api_key, base_url=base_url, timeout=request_timeout)
    started = time.perf_counter()
    user_prompt = (
        build_localization_prompt(case, condition, artifacts)
        if localize
        else build_repair_prompt(case, condition, artifacts)
    )
    if len(user_prompt) > max_prompt_chars:
        user_prompt = shrink_prompt(user_prompt, max_prompt_chars)

    solution, raw_text = complete_json(
        client,
        model=model,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        temperature=temperature,
    )
    repair_seconds = round(time.perf_counter() - started, 3)
    verdict = verify_solution_for_case(case, solution, simulator=simulator, timeout=sim_timeout)
    return {
        "case_id": case.case_id,
        "problem_id": case.problem_id,
        "condition": condition,
        "bug_class": case.bug_class,
        "real_commit": case.real_commit,
        "real_commit_message": case.real_commit_message,
        "task_mode": "localize" if localize else "exact_module",
        "input_failure": artifacts["simulation"]["reason"],
        "pass": verdict["pass"],
        "reason": verdict["reason"],
        "confidence": solution.confidence,
        "repair_seconds": repair_seconds,
        "raw_output_present": bool(raw_text),
        "prompt_chars": len(user_prompt),
        "repaired_module_sv": solution.module_sv,
    }


def shrink_prompt(prompt: str, max_chars: int) -> str:
    if len(prompt) <= max_chars:
        return prompt
    marker = "Candidate RTL files:\n"
    if marker not in prompt:
        return prompt[:max_chars]
    prefix, candidates = prompt.split(marker, 1)
    budget = max_chars - len(prefix) - len(marker) - 1200
    chunks = candidates.split("\n\n--- BEGIN ")
    trimmed = []
    per_chunk = max(2500, budget // max(1, len(chunks)))
    for idx, chunk in enumerate(chunks):
        if idx == 0:
            text = chunk
        else:
            text = "--- BEGIN " + chunk
        if len(text) > per_chunk:
            text = text[:per_chunk] + "\n// ... context truncated to fit token budget ...\n"
        trimmed.append(text)
    return prefix + marker + "\n\n".join(trimmed)


def verify_reference_and_bug(case: RepairCase, *, simulator: str = "verilator", timeout: int = 30) -> dict[str, Any]:
    reference = RtlSolution(module_sv=case.reference_sv(), confidence=100)
    buggy = RtlSolution(module_sv=case.buggy_sv(), confidence=0)
    return {
        "case_id": case.case_id,
        "reference": verify_solution_for_case(case, reference, simulator=simulator, timeout=timeout),
        "buggy": verify_solution_for_case(case, buggy, simulator=simulator, timeout=timeout),
    }


def verify_solution_for_case(
    case: RepairCase,
    solution: RtlSolution,
    *,
    simulator: str = "verilator",
    timeout: int = 30,
) -> dict[str, Any]:
    if case.custom_testbench is None:
        return verify(case.problem_id, solution, timeout=timeout, keep_temp=False, simulator=simulator)

    problem = replace(case.problem, hidden_testbench=REAL_TYPES_PREFIX + case.custom_testbench)
    sim_result = run_problem_testbench(
        problem,
        solution.module_sv,
        use_public_tb=False,
        preferred_simulator=simulator,
        timeout=timeout,
        keep_temp=False,
    )
    return {
        "pass": sim_result.ok,
        "details": {
            "problem_id": problem.problem_id,
            "title": problem.title,
            "simulator": sim_result.simulator,
            "stage": sim_result.stage,
        },
        "reason": "Hidden verification testbench passed." if sim_result.ok else sim_result.reason,
    }


def write_json(path: str | Path, data: Any) -> None:
    Path(path).write_text(json.dumps(data, indent=2), encoding="utf-8")
