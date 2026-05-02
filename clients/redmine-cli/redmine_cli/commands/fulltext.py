"""`redmine fulltext ...` — fork-only attachment fulltext indexer API.

These endpoints authenticate with **`X-Redmine-Indexer-Key`**, NOT the
per-user `X-Redmine-API-Key` used by every other command. The indexer key
is server-wide (`Setting.attachment_indexer_api_key`) and stored in
`hosts.yml` under the host (sibling to `url`/`users`); env var
`REDMINE_INDEXER_KEY` overrides it.

Designed for an external worker that polls `list --status pending`,
extracts text out-of-band, and pushes results back via `update`/`batch`.

**Examples:**

```
redmine fulltext list --status pending --json
redmine fulltext get 42 --json
redmine fulltext update 42 --status indexed --content-file extracted.txt \\
                           --extractor-version pdftotext-22.05
redmine fulltext batch --file results.json
```
"""

from __future__ import annotations

import json as _json
from pathlib import Path
from typing import Any, Optional

import typer

from ..client import APIError, Client, EXIT_AUTH, die
from ..config import AuthError
from ..output import emit_json, emit_list, emit_object
from ._helpers import read_text_input

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Attachment fulltext indexer API (Redmine fork only).\n\n"
        "Uses a separate `X-Redmine-Indexer-Key` header, not the regular "
        "API key. Configure with `redmine auth login --indexer-key <KEY>` "
        "or `REDMINE_INDEXER_KEY` env var.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine fulltext list --status pending\n"
        "redmine fulltext get 42 --json\n"
        "redmine fulltext update 42 --status indexed --content 'hello world'\n"
        "redmine fulltext batch --file results.json\n"
        "```"
    ),
)


def _indexer_client(ctx) -> Client:
    """Build a Client whose Session sends X-Redmine-Indexer-Key.

    Errors with exit code 4 (EXIT_AUTH) when no indexer key is configured
    AND `REDMINE_INDEXER_KEY` env var is not set.
    """
    from ..cli import get_credential
    cred = get_credential(ctx)
    try:
        indexer_headers = cred.indexer_headers
    except AuthError as e:
        die(str(e), code=EXIT_AUTH)
    c = Client(cred)
    # Replace API-key header with the indexer key for this Client only.
    c.session.headers.pop("X-Redmine-API-Key", None)
    c.session.headers.update(indexer_headers)
    return c


# --------------------------------------------------------------------- list

@app.command(
    "list",
    help=(
        "List attachments for fulltext indexing. Defaults to `pending`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine fulltext list --status pending\n"
        "redmine fulltext list --status failed --limit 50 --json\n"
        "redmine fulltext list --all --json | jq '.[].id'\n"
        "```"
    ),
)
def list_attachments(
    ctx: typer.Context,
    status: str = typer.Option(
        "pending", "--status",
        help="Filter: pending | indexed | failed | skipped | all",
    ),
    limit: int = typer.Option(100, "--limit", help="Max results per page (server caps at 1000)."),
    all_pages: bool = typer.Option(False, "--all", help="Walk all pages until exhausted."),
    content_type: Optional[str] = typer.Option(None, "--content-type", help="Filter by MIME type."),
    since: Optional[str] = typer.Option(None, "--since", help="ISO8601 datetime; only newer attachments."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _indexer_client(ctx)
    base_params: dict[str, Any] = {"status": status}
    if content_type:
        base_params["content_type"] = content_type
    if since:
        base_params["since"] = since

    if all_pages:
        # Paginate manually because this endpoint isn't a standard Redmine
        # listing — `total_count` is at the top level but we still want the
        # status/content_type filters preserved on every page.
        items: list[dict] = []
        offset = 0
        while True:
            data = c.get(
                "/attachments/fulltext.json",
                **base_params, limit=min(limit, 1000), offset=offset,
            )
            page = data.get("attachments", [])
            if not page:
                break
            items.extend(page)
            total = data.get("total_count")
            offset += len(page)
            if total is not None and offset >= total:
                break
            if len(page) < min(limit, 1000):
                break
    else:
        data = c.get("/attachments/fulltext.json", **base_params, limit=limit)
        items = data.get("attachments", [])

    emit_list(
        items,
        columns=[
            ("ID", "id"),
            ("Filename", "filename"),
            ("Type", "content_type"),
            ("Size", "filesize"),
            ("Status", "fulltext.status"),
            ("Indexed", "fulltext.indexed_at"),
        ],
        json_mode=json_mode,
    )


# ---------------------------------------------------------------------- get

@app.command(
    "get",
    help=(
        "Show fulltext indexing status of one attachment.\n\n"
        "**Example:** `redmine fulltext get 42 --json`"
    ),
)
def get_one(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _indexer_client(ctx)
    data = c.get(f"/attachments/{id}/fulltext.json")
    obj = data.get("attachment", data)
    emit_object(obj, json_mode=json_mode)


# ------------------------------------------------------------------- update

VALID_STATUSES = {"indexed", "failed", "skipped", "pending"}


@app.command(
    "update",
    help=(
        "Update fulltext content/status for one attachment.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine fulltext update 42 --status indexed --content 'extracted text'\n"
        "redmine fulltext update 42 --status indexed --content-file out.txt \\\n"
        "                           --extractor-version pdftotext-22.05\n"
        "redmine fulltext update 42 --status failed --error-message 'pw protected'\n"
        "redmine fulltext update 42 --status skipped --error-message 'binary'\n"
        "redmine fulltext update 42 --status pending           # reset for re-index\n"
        "```"
    ),
)
def update_one(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    status: str = typer.Option(..., "--status", help="indexed | failed | skipped | pending"),
    content: Optional[str] = typer.Option(None, "--content", help="Inline extracted text (or '-' for stdin)."),
    content_file: Optional[Path] = typer.Option(None, "--content-file", help="Read extracted text from file."),
    error_message: Optional[str] = typer.Option(None, "--error-message"),
    extractor_version: Optional[str] = typer.Option(None, "--extractor-version"),
    json_mode: bool = typer.Option(False, "--json"),
):
    if status not in VALID_STATUSES:
        die(f"invalid --status '{status}'. Must be one of: {sorted(VALID_STATUSES)}", code=2)

    text = read_text_input(content, content_file, name="content")
    fulltext: dict[str, Any] = {"status": status}
    if text is not None:
        fulltext["content"] = text
    if error_message is not None:
        fulltext["error_message"] = error_message
    if extractor_version is not None:
        fulltext["extractor_version"] = extractor_version

    c = _indexer_client(ctx)
    data = c.patch(f"/attachments/{id}/fulltext.json", json={"fulltext": fulltext})
    obj = (data or {}).get("attachment", data) if isinstance(data, dict) else None
    if json_mode:
        emit_object(obj or {"id": id, "status": status}, json_mode=True)
    else:
        typer.echo(f"updated attachment {id} -> {status}")


# -------------------------------------------------------------------- batch

@app.command(
    "batch",
    help=(
        "Batch-update fulltext for many attachments from a JSON file.\n\n"
        "The file may be either the full payload\n"
        "`{\"attachments\": [{\"id\": ..., \"status\": ..., ...}]}`\n"
        "or a bare array `[{\"id\": ..., ...}, ...]` (auto-wrapped).\n\n"
        "**Example:** `redmine fulltext batch --file results.json --json`"
    ),
)
def batch_update(
    ctx: typer.Context,
    file: Path = typer.Option(..., "--file", exists=True, dir_okay=False, readable=True,
                              help="JSON file with the batch payload."),
    json_mode: bool = typer.Option(False, "--json"),
):
    raw = file.read_text(encoding="utf-8")
    try:
        payload = _json.loads(raw)
    except _json.JSONDecodeError as e:
        die(f"invalid JSON in {file}: {e}", code=2)

    if isinstance(payload, list):
        body = {"attachments": payload}
    elif isinstance(payload, dict) and isinstance(payload.get("attachments"), list):
        body = payload
    else:
        die("batch file must be a JSON array, or an object with an 'attachments' array.", code=2)

    c = _indexer_client(ctx)
    try:
        result = c.post("/attachments/fulltext/batch.json", json=body)
    except APIError as e:
        die(str(e), code=e.exit_code)

    if json_mode:
        emit_json(result)
    else:
        successes = (result or {}).get("success", [])
        errors = (result or {}).get("errors", [])
        typer.echo(f"batch: {len(successes)} succeeded, {len(errors)} failed")
        for err in errors:
            typer.echo(f"  ! id={err.get('id')}: {err.get('error')}", err=True)
