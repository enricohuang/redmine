"""Shared helpers for resource commands."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Iterable


def read_text_input(value: str | None, file: Path | None, *, name: str = "input") -> str | None:
    """Resolve a text body from --value / --file / '-' (stdin). Returns None if all empty."""
    if value is not None and file is not None:
        raise ValueError(f"specify only one of inline {name} or --{name}-file")
    if file is not None:
        if str(file) == "-":
            return sys.stdin.read()
        return Path(file).read_text(encoding="utf-8")
    if value == "-":
        return sys.stdin.read()
    return value


def parse_kv(items: Iterable[str]) -> dict[str, str]:
    """Parse `key=value` pairs from `--field` repeated options."""
    out: dict[str, str] = {}
    for it in items:
        if "=" not in it:
            raise ValueError(f"expected key=value, got: {it}")
        k, v = it.split("=", 1)
        out[k.strip()] = v
    return out


def parse_id_list(value: str | None) -> list[int]:
    """Parse a comma-separated list of integer IDs."""
    if not value:
        return []
    return [int(x.strip()) for x in value.split(",") if x.strip()]
