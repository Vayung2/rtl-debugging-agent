from __future__ import annotations

import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from problem_bank import PASS_MARKER, ProblemSpec


DEFAULT_SIM_TIMEOUT = 30


@dataclass
class SimResult:
    ok: bool
    simulator: str | None
    stage: str
    reason: str
    stdout: str
    stderr: str
    workdir: str | None


def find_simulator(preferred: str = "verilator") -> tuple[str, list[str]]:
    if preferred == "verilator":
        verilator = shutil.which("verilator")
        if verilator:
            return "verilator", [verilator]
        iverilog = shutil.which("iverilog")
        if iverilog:
            return "iverilog", [iverilog]
    else:
        iverilog = shutil.which("iverilog")
        if iverilog:
            return "iverilog", [iverilog]
        verilator = shutil.which("verilator")
        if verilator:
            return "verilator", [verilator]

    raise FileNotFoundError(
        "Could not find Verilator or Icarus Verilog in PATH. Install Verilator or iverilog first."
    )


def summarize_failure(stdout: str, stderr: str) -> str:
    combined = "\n".join(part for part in [stdout.strip(), stderr.strip()] if part.strip())
    if not combined:
        return "Simulation failed without compiler or runtime output."

    for line in reversed(combined.splitlines()):
        stripped = line.strip()
        if stripped.startswith("FAIL"):
            return stripped

    error_lines = [line.strip() for line in combined.splitlines() if line.strip().startswith("%Error:")]
    for line in error_lines:
        if "Exiting due to" not in line:
            return line
    if error_lines:
        return error_lines[0]

    for line in reversed(combined.splitlines()):
        stripped = line.strip()
        if stripped:
            return stripped
    return "Simulation failed without a recognizable error line."


def _write_sources(workdir: Path, module_sv: str, testbench_sv: str) -> tuple[Path, Path]:
    candidate_path = workdir / "candidate.sv"
    tb_path = workdir / "tb.sv"
    candidate_path.write_text(module_sv, encoding="utf-8")
    tb_path.write_text(testbench_sv, encoding="utf-8")
    return candidate_path, tb_path


def _run_verilator(
    workdir: Path,
    candidate_path: Path,
    tb_path: Path,
    timeout: int,
) -> SimResult:
    compile_cmd = [
        "verilator",
        "--binary",
        "--timing",
        "--sv",
        "-Wno-fatal",
        "--top-module",
        "tb",
        str(tb_path),
        str(candidate_path),
    ]
    compile_result = subprocess.run(
        compile_cmd,
        cwd=workdir,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    if compile_result.returncode != 0:
        return SimResult(
            ok=False,
            simulator="verilator",
            stage="compile",
            reason=summarize_failure(compile_result.stdout, compile_result.stderr),
            stdout=compile_result.stdout,
            stderr=compile_result.stderr,
            workdir=str(workdir),
        )

    binary_path = workdir / "obj_dir" / "Vtb"
    if not binary_path.exists():
        return SimResult(
            ok=False,
            simulator="verilator",
            stage="compile",
            reason=f"Expected Verilator binary was not created at {binary_path}",
            stdout=compile_result.stdout,
            stderr=compile_result.stderr,
            workdir=str(workdir),
        )

    run_result = subprocess.run(
        [str(binary_path)],
        cwd=workdir,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    ok = run_result.returncode == 0 and PASS_MARKER in run_result.stdout
    return SimResult(
        ok=ok,
        simulator="verilator",
        stage="run",
        reason=PASS_MARKER if ok else summarize_failure(run_result.stdout, run_result.stderr),
        stdout=compile_result.stdout + run_result.stdout,
        stderr=compile_result.stderr + run_result.stderr,
        workdir=str(workdir),
    )


def _run_iverilog(
    workdir: Path,
    candidate_path: Path,
    tb_path: Path,
    timeout: int,
) -> SimResult:
    vvp = shutil.which("vvp")
    if not vvp:
        return SimResult(
            ok=False,
            simulator="iverilog",
            stage="compile",
            reason="Found iverilog but not vvp. Install the full Icarus Verilog toolchain.",
            stdout="",
            stderr="",
            workdir=str(workdir),
        )

    output_path = workdir / "tb.out"
    compile_result = subprocess.run(
        [
            "iverilog",
            "-g2012",
            "-o",
            str(output_path),
            str(tb_path),
            str(candidate_path),
        ],
        cwd=workdir,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    if compile_result.returncode != 0:
        return SimResult(
            ok=False,
            simulator="iverilog",
            stage="compile",
            reason=summarize_failure(compile_result.stdout, compile_result.stderr),
            stdout=compile_result.stdout,
            stderr=compile_result.stderr,
            workdir=str(workdir),
        )

    run_result = subprocess.run(
        [vvp, str(output_path)],
        cwd=workdir,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    ok = run_result.returncode == 0 and PASS_MARKER in run_result.stdout
    return SimResult(
        ok=ok,
        simulator="iverilog",
        stage="run",
        reason=PASS_MARKER if ok else summarize_failure(run_result.stdout, run_result.stderr),
        stdout=compile_result.stdout + run_result.stdout,
        stderr=compile_result.stderr + run_result.stderr,
        workdir=str(workdir),
    )


def run_problem_testbench(
    problem: ProblemSpec,
    module_sv: str,
    *,
    use_public_tb: bool,
    preferred_simulator: str = "verilator",
    timeout: int = DEFAULT_SIM_TIMEOUT,
    keep_temp: bool = False,
) -> SimResult:
    simulator, _ = find_simulator(preferred_simulator)
    testbench = problem.public_testbench if use_public_tb else problem.hidden_testbench

    workdir = Path(tempfile.mkdtemp(prefix=f"{problem.problem_id.lower()}_"))

    try:
        candidate_path, tb_path = _write_sources(workdir, module_sv, testbench)
        if simulator == "verilator":
            result = _run_verilator(workdir, candidate_path, tb_path, timeout)
        else:
            result = _run_iverilog(workdir, candidate_path, tb_path, timeout)
        return result
    finally:
        if not keep_temp:
            shutil.rmtree(workdir, ignore_errors=True)


def lint_problem_module(
    problem: ProblemSpec,
    module_sv: str,
    *,
    preferred_simulator: str = "verilator",
    timeout: int = DEFAULT_SIM_TIMEOUT,
    keep_temp: bool = False,
) -> SimResult:
    simulator, _ = find_simulator(preferred_simulator)
    workdir = Path(tempfile.mkdtemp(prefix=f"{problem.problem_id.lower()}_lint_"))

    try:
        if simulator == "verilator":
            candidate_path = workdir / "candidate.sv"
            candidate_path.write_text(module_sv, encoding="utf-8")
            result = subprocess.run(
                ["verilator", "--lint-only", "--sv", "-Wall", "-Wno-fatal", str(candidate_path)],
                cwd=workdir,
                text=True,
                capture_output=True,
                timeout=timeout,
            )
            return SimResult(
                ok=result.returncode == 0,
                simulator="verilator",
                stage="compile",
                reason="lint passed" if result.returncode == 0 else summarize_failure(result.stdout, result.stderr),
                stdout=result.stdout,
                stderr=result.stderr,
                workdir=str(workdir),
            )

        candidate_path = workdir / "candidate.sv"
        candidate_path.write_text(module_sv, encoding="utf-8")
        result = subprocess.run(
            ["iverilog", "-g2012", "-t", "null", str(candidate_path)],
            cwd=workdir,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
        return SimResult(
            ok=result.returncode == 0,
            simulator="iverilog",
            stage="compile",
            reason="lint passed" if result.returncode == 0 else summarize_failure(result.stdout, result.stderr),
            stdout=result.stdout,
            stderr=result.stderr,
            workdir=str(workdir),
        )
    finally:
        if not keep_temp:
            shutil.rmtree(workdir, ignore_errors=True)
