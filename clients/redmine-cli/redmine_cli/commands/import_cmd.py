"""`redmine import ...` - drive Redmine CSV imports from the CLI."""

from __future__ import annotations

import json as _json
from pathlib import Path
from typing import Optional

import typer

from ..client import die
from ..output import emit_object
from ._helpers import parse_kv


IMPORT_TYPES = {
    "issue": "IssueImport",
    "issues": "IssueImport",
    "IssueImport": "IssueImport",
    "time-entry": "TimeEntryImport",
    "time-entries": "TimeEntryImport",
    "time_entry": "TimeEntryImport",
    "time_entries": "TimeEntryImport",
    "TimeEntryImport": "TimeEntryImport",
    "user": "UserImport",
    "users": "UserImport",
    "UserImport": "UserImport",
}


app = typer.Typer(
    no_args_is_help=True,
    rich_markup_mode="markdown",
    help=(
        "Create and run CSV imports through the JSON import state machine. "
        "Imports are owned by the API user and are addressed by the stable "
        "numeric ID returned by `create`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine import create --type issues --file issues.csv --project 1\n"
        "redmine import settings 42 --separator ';' --encoding ISO-8859-1\n"
        "redmine import auto-map 42\n"
        "redmine import mapping 42 --map project_id=1 --map subject=1 --map tracker=13\n"
        "redmine import run 42\n"
        "redmine import status 42 --json\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


def _import_type(value: str) -> str:
    try:
        return IMPORT_TYPES[value]
    except KeyError:
        valid = ", ".join(sorted(IMPORT_TYPES))
        die(f"unknown import type '{value}'. Valid values: {valid}", code=3)
        raise AssertionError("unreachable")


def _load_mapping_file(path: Path) -> dict:
    data = _json.loads(path.read_text())
    if not isinstance(data, dict):
        die("mapping file must contain a JSON object", code=3)
    mapping = data.get("mapping", data)
    if not isinstance(mapping, dict):
        die("mapping file 'mapping' value must be an object", code=3)
    return {str(k): v for k, v in mapping.items()}


def _emit_import(data: dict, *, json_mode: bool) -> None:
    obj = data.get("import", data)
    if json_mode:
        emit_object(obj, json_mode=True)
        return
    fields = [
        "id", "identifier", "type", "state", "finished",
        "total_items", "processed_items", "saved_items", "unsaved_items",
        "file_available",
    ]
    emit_object({f: obj.get(f) for f in fields if f in obj}, json_mode=False)


@app.command(
    "create",
    help=(
        "Upload a CSV file and create an import. The response includes a "
        "stable numeric ID for subsequent `settings`, `mapping`, `run`, and "
        "`status` calls.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine import create --type issues --file issues.csv\n"
        "redmine import create --type time-entries --file time.csv --project 3 --json\n"
        "```"
    ),
)
def create_import(
    ctx: typer.Context,
    import_type: str = typer.Option(..., "--type", help="issues | time-entries | users."),
    file: Path = typer.Option(..., "--file", exists=True, dir_okay=False, readable=True, help="CSV file to upload."),
    project: Optional[str] = typer.Option(None, "--project", help="Optional target project numeric ID for issue/time imports."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    data = {"type": _import_type(import_type)}
    if project is not None:
        data["project_id"] = project
    with file.open("rb") as fh:
        resp = c.request(
            "POST",
            "/imports.json",
            data=data,
            files={"file": (file.name, fh, "text/csv")},
        )
    _emit_import(resp, json_mode=json_mode)


@app.command(
    "status",
    help=(
        "Show current import state, counts, settings, preview headers, sample "
        "rows, and any per-row results already produced.\n\n"
        "**Example:** `redmine import status 42 --json | jq '.state'`"
    ),
)
def import_status(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric import ID returned by `create`."),
    json_mode: bool = typer.Option(False, "--json"),
):
    resp = _client(ctx).get(f"/imports/{id}.json")
    _emit_import(resp, json_mode=json_mode)


@app.command(
    "settings",
    help=(
        "Validate or update CSV parsing settings. If no setting option is "
        "provided, this prints the current import status without changing it.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine import settings 42 --separator ';' --wrapper '\"' --encoding ISO-8859-1\n"
        "redmine import settings 42 --date-format %Y-%m-%d --notifications\n"
        "```"
    ),
)
def import_settings(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric import ID."),
    separator: Optional[str] = typer.Option(None, "--separator", help="CSV field separator, usually ',' or ';'."),
    wrapper: Optional[str] = typer.Option(None, "--wrapper", help="CSV quote/wrapper character, usually '\"'."),
    encoding: Optional[str] = typer.Option(None, "--encoding", help="CSV encoding, e.g. UTF-8 or ISO-8859-1."),
    date_format: Optional[str] = typer.Option(None, "--date-format", help="Date format such as %Y-%m-%d."),
    notifications: Optional[bool] = typer.Option(
        None, "--notifications/--no-notifications", help="Send notifications for imported objects."
    ),
    json_mode: bool = typer.Option(False, "--json"),
):
    settings: dict[str, str] = {}
    if separator is not None:
        settings["separator"] = separator
    if wrapper is not None:
        settings["wrapper"] = wrapper
    if encoding is not None:
        settings["encoding"] = encoding
    if date_format is not None:
        settings["date_format"] = date_format
    if notifications is not None:
        settings["notifications"] = "1" if notifications else "0"

    c = _client(ctx)
    if settings:
        resp = c.put(f"/imports/{id}/settings.json", json={"import_settings": settings})
    else:
        resp = c.get(f"/imports/{id}/settings.json")
    _emit_import(resp, json_mode=json_mode)


@app.command(
    "auto-map",
    help=(
        "Ask Redmine to auto-map CSV headers to import fields and persist the "
        "resulting mapping. Review with `--json` before running the import.\n\n"
        "**Example:** `redmine import auto-map 42 --json | jq '.settings'`"
    ),
)
def auto_map(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric import ID."),
    json_mode: bool = typer.Option(False, "--json"),
):
    resp = _client(ctx).get(f"/imports/{id}/mapping.json")
    _emit_import(resp, json_mode=json_mode)


@app.command(
    "mapping",
    help=(
        "Apply field mapping for an import. Pass repeatable `--map FIELD=VALUE` "
        "pairs or a JSON mapping file. Values are Redmine import mapping values: "
        "column indexes like `subject=1`, constants like `tracker=value:2`, and "
        "`project_id=1`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine import mapping 42 --map project_id=1 --map subject=1 --map tracker=13\n"
        "redmine import mapping 42 --mapping-file mapping.json --json\n"
        "```"
    ),
)
def import_mapping(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric import ID."),
    mapping: Optional[list[str]] = typer.Option(
        None, "--map", help="Repeatable FIELD=VALUE mapping pair."
    ),
    mapping_file: Optional[Path] = typer.Option(
        None, "--mapping-file", exists=True, dir_okay=False, readable=True,
        help="JSON object, or object with a top-level 'mapping' object.",
    ),
    json_mode: bool = typer.Option(False, "--json"),
):
    body: dict = {}
    if mapping_file is not None:
        body.update(_load_mapping_file(mapping_file))
    if mapping:
        body.update(parse_kv(mapping))
    if not body:
        die("nothing to map; pass --map FIELD=VALUE or --mapping-file", code=3)

    resp = _client(ctx).put(
        f"/imports/{id}/mapping.json",
        json={"import_settings": {"mapping": body}},
    )
    _emit_import(resp, json_mode=json_mode)


@app.command(
    "run",
    help=(
        "Process the next server-sized chunk of rows. Redmine may process only "
        "part of a large import per request; rerun until state is `finished`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine import run 42\n"
        "while [ \"$(redmine import run 42 --json | jq -r '.state')\" != finished ]; do :; done\n"
        "```"
    ),
)
def run_import(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric import ID."),
    json_mode: bool = typer.Option(False, "--json"),
):
    resp = _client(ctx).post(f"/imports/{id}/run.json")
    _emit_import(resp, json_mode=json_mode)
