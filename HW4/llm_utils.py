from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path
from typing import Any

from openai import OpenAI, RateLimitError
from pydantic import BaseModel, Field


def load_dotenv() -> None:
    for parent in [Path.cwd(), *Path.cwd().parents]:
        env_path = parent / ".env"
        if not env_path.exists():
            continue
        for raw_line in env_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
        return


load_dotenv()


DEFAULT_MODEL = os.environ.get("LLM_MODEL", "gpt-5.4")
DEFAULT_BASE_URL = os.environ.get("OPENAI_BASE_URL", "")
DEFAULT_API_KEY = os.environ.get("OPENAI_API_KEY", "")


class RtlSolution(BaseModel):
    module_sv: str = Field(
        min_length=1,
        description="Complete raw SystemVerilog module source code.",
    )
    confidence: int = Field(ge=0, le=100)


def make_client(api_key: str = "", base_url: str = "", timeout: float = 120.0) -> OpenAI:
    resolved_api_key = api_key or DEFAULT_API_KEY
    if not resolved_api_key:
        raise ValueError("Missing OpenAI API key. Set OPENAI_API_KEY or pass --api-key.")

    kwargs: dict[str, Any] = {
        "api_key": resolved_api_key,
        "timeout": timeout,
    }
    if base_url or DEFAULT_BASE_URL:
        kwargs["base_url"] = base_url or DEFAULT_BASE_URL
    return OpenAI(**kwargs)


def rate_limit_delay(exc: BaseException, fallback: float = 25.0) -> float:
    text = str(exc)
    match = re.search(r"try again in ([0-9.]+)s", text, re.IGNORECASE)
    if match:
        return max(float(match.group(1)) + 2.0, 1.0)
    return fallback


def is_rate_limit_error(exc: BaseException) -> bool:
    if isinstance(exc, RateLimitError):
        return True
    text = f"{type(exc).__name__}: {exc}".lower()
    return "ratelimiterror" in text or "rate limit" in text or "rate_limit_exceeded" in text


def chat_completion_create_with_retries(
    client: OpenAI,
    *,
    max_retries: int = 8,
    base_delay: float = 25.0,
    **kwargs: Any,
) -> Any:
    for attempt in range(max_retries + 1):
        try:
            return client.chat.completions.create(**kwargs)
        except Exception as exc:
            if not is_rate_limit_error(exc) or attempt >= max_retries:
                raise
            delay = rate_limit_delay(exc, fallback=base_delay * (attempt + 1))
            print(f"Rate limited; sleeping {delay:.1f}s before retry {attempt + 1}/{max_retries}.", flush=True)
            time.sleep(delay)


def extract_json_object(text: str) -> str:
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end < start:
        raise ValueError("Could not find a JSON object in model output.")
    return text[start : end + 1]


def extract_code_block(text: str) -> str:
    match = re.search(r"```(?:systemverilog|verilog)?\s*\n(.*?)```", text, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()

    module_match = re.search(r"(module\s+\w+\b.*?endmodule)", text, re.DOTALL | re.IGNORECASE)
    if module_match:
        return module_match.group(1).strip()

    raise ValueError("Could not find SystemVerilog module source in model output.")


def extract_confidence(text: str) -> int:
    match = re.search(r"confidence\s*[:=]?\s*(\d{1,3})", text, re.IGNORECASE)
    if not match:
        raise ValueError("Could not find confidence in model output.")
    confidence = int(match.group(1))
    if not 0 <= confidence <= 100:
        raise ValueError(f"Confidence {confidence} is out of range.")
    return confidence


def parse_solution(raw_text: str) -> RtlSolution:
    try:
        return RtlSolution.model_validate_json(extract_json_object(raw_text))
    except Exception:
        return RtlSolution(
            module_sv=extract_code_block(raw_text),
            confidence=extract_confidence(raw_text),
        )


def complete_json(
    client: OpenAI,
    *,
    model: str,
    messages: list[dict[str, Any]],
    temperature: float | None,
) -> tuple[RtlSolution, str]:
    kwargs: dict[str, Any] = {
        "model": model,
        "messages": messages,
    }
    if temperature is not None:
        kwargs["temperature"] = temperature
    response = chat_completion_create_with_retries(client, **kwargs)
    raw_text = response.choices[0].message.content or ""
    return parse_solution(raw_text), raw_text


def tool_schema_get_problem_spec() -> dict[str, Any]:
    return {
        "type": "function",
        "function": {
            "name": "get_problem_spec",
            "description": "Fetch the full problem statement, interface, and success criteria for a benchmark problem.",
            "parameters": {
                "type": "object",
                "properties": {
                    "problem_id": {
                        "type": "string",
                        "description": "Problem identifier such as P1, P2, ..., P10.",
                    }
                },
                "required": ["problem_id"],
                "additionalProperties": False,
            },
        },
    }


def tool_schema_lint_candidate() -> dict[str, Any]:
    return {
        "type": "function",
        "function": {
            "name": "lint_candidate",
            "description": "Compile a SystemVerilog candidate against the problem interface without running hidden tests.",
            "parameters": {
                "type": "object",
                "properties": {
                    "problem_id": {"type": "string"},
                    "module_sv": {"type": "string"},
                },
                "required": ["problem_id", "module_sv"],
                "additionalProperties": False,
            },
        },
    }


def tool_schema_run_public_tests() -> dict[str, Any]:
    return {
        "type": "function",
        "function": {
            "name": "run_public_tests",
            "description": "Run the public simulator testbench for a candidate solution and return public feedback only.",
            "parameters": {
                "type": "object",
                "properties": {
                    "problem_id": {"type": "string"},
                    "module_sv": {"type": "string"},
                },
                "required": ["problem_id", "module_sv"],
                "additionalProperties": False,
            },
        },
    }


def tool_schema_get_repo_type_context() -> dict[str, Any]:
    return {
        "type": "function",
        "function": {
            "name": "get_repo_type_context",
            "description": "Fetch whitelisted package constants and typedefs from pkg/types.sv that are relevant to a problem. Does not expose the target implementation file.",
            "parameters": {
                "type": "object",
                "properties": {
                    "problem_id": {"type": "string"},
                },
                "required": ["problem_id"],
                "additionalProperties": False,
            },
        },
    }


def tool_schema_get_repo_neighbor_context() -> dict[str, Any]:
    return {
        "type": "function",
        "function": {
            "name": "get_repo_neighbor_context",
            "description": "Fetch short whitelisted neighboring repo snippets or design notes. The current target source file is never returned.",
            "parameters": {
                "type": "object",
                "properties": {
                    "problem_id": {"type": "string"},
                },
                "required": ["problem_id"],
                "additionalProperties": False,
            },
        },
    }


TOOL_SCHEMAS = [
    tool_schema_get_problem_spec(),
    tool_schema_get_repo_type_context(),
    tool_schema_get_repo_neighbor_context(),
    tool_schema_lint_candidate(),
    tool_schema_run_public_tests(),
]


def json_dumps(data: Any) -> str:
    return json.dumps(data, indent=2, sort_keys=True)
