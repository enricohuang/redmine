"""Output helpers — JSON or rich tables, depending on --json flag."""

from __future__ import annotations

import json as _json
import sys
from typing import Any, Iterable

from rich.console import Console
from rich.table import Table

_console = Console()
_err = Console(stderr=True)


def info(msg: str) -> None:
    _err.print(msg)


def emit_json(data: Any) -> None:
    sys.stdout.write(_json.dumps(data, indent=2, default=str, ensure_ascii=False))
    sys.stdout.write("\n")


def emit_object(obj: dict, *, fields: list[str] | None = None, json_mode: bool = False) -> None:
    if json_mode:
        emit_json(obj)
        return
    fields = fields or list(obj.keys())
    table = Table(show_header=False, box=None, pad_edge=False)
    table.add_column("field", style="bold cyan", no_wrap=True)
    table.add_column("value", overflow="fold")
    for f in fields:
        v = obj.get(f)
        table.add_row(f, _format_value(v))
    _console.print(table)


def emit_list(items: Iterable[dict], *, columns: list[tuple[str, str]],
              json_mode: bool = False, title: str | None = None) -> None:
    """Print a list as a table or JSON array.

    columns = list of (header, dotted_path) — dotted_path can dig into nested dicts.
    """
    items = list(items)
    if json_mode:
        emit_json(items)
        return
    if not items:
        info("(no results)")
        return
    table = Table(title=title, show_lines=False, header_style="bold")
    for header, _ in columns:
        table.add_column(header, overflow="fold")
    for item in items:
        row = [_format_value(_dig(item, path)) for _, path in columns]
        table.add_row(*row)
    _console.print(table)


def _dig(obj: Any, path: str) -> Any:
    cur = obj
    for part in path.split("."):
        if cur is None:
            return None
        if isinstance(cur, dict):
            cur = cur.get(part)
        else:
            return None
    return cur


def _format_value(v: Any) -> str:
    if v is None:
        return "-"
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, (list, tuple)):
        return ", ".join(str(x) for x in v) if v else "-"
    if isinstance(v, dict):
        if "name" in v:
            return str(v["name"])
        if "title" in v:
            return str(v["title"])
        return _json.dumps(v, default=str)
    return str(v)
