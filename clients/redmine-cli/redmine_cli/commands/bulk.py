"""`redmine bulk ...` — bulk issue operations (fork endpoint)."""

from __future__ import annotations

from typing import Optional

import typer

from ..resolvers import (
    resolve_assignee, resolve_priority, resolve_status, resolve_tracker,
)
from ._helpers import parse_id_list

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Bulk update or delete issues by ID list (fork endpoint). Much faster "
        "than `xargs redmine issue update` for large batches.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine bulk update --ids 100,101,102 --status Closed --note 'swept'\n"
        "redmine bulk update --ids-file ids.txt --priority Low\n"
        "redmine bulk delete --ids 100,101,102 -y\n"
        "```\n\n"
        "`--ids-file` reads one ID per line (handy for piping from `issue list`)."
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


def _read_ids(inline: Optional[str], file: Optional[typer.FileText]) -> list[int]:
    if inline and file:
        typer.echo("error: pass --ids OR --ids-file, not both.", err=True)
        raise typer.Exit(code=2)
    if not inline and not file:
        typer.echo("error: --ids or --ids-file is required.", err=True)
        raise typer.Exit(code=2)
    if inline:
        return parse_id_list(inline)
    return [int(line.strip()) for line in file if line.strip()]


@app.command(
    "update",
    help=(
        "Bulk-update one field across many issues in a single API call.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine bulk update --ids 100,101,102 --status Closed --note 'cleanup'\n"
        "redmine issue list -p old --status open --json | jq -r '.[].id' \\\n"
        "  | redmine bulk update --ids-file - --status Closed -y\n"
        "```\n\n"
        "Status/tracker/priority/assignee accept names or IDs. The server "
        "skips issues you don't have permission for and returns 204 on success."
    ),
)
def bulk_update(
    ctx: typer.Context,
    ids: Optional[str] = typer.Option(None, "--ids", help="Comma-separated issue IDs."),
    ids_file: Optional[typer.FileText] = typer.Option(
        None, "--ids-file", help="Read IDs from file (one per line). Use '-' for stdin."),
    status: Optional[str] = typer.Option(None, "--status"),
    tracker: Optional[str] = typer.Option(None, "--tracker"),
    priority: Optional[str] = typer.Option(None, "--priority"),
    assignee: Optional[str] = typer.Option(None, "--assignee"),
    project: Optional[str] = typer.Option(None, "-p", "--project",
                                          help="Move all to this project."),
    note: Optional[str] = typer.Option(None, "-n", "--note",
                                       help="Comment to add on each updated issue."),
    yes: bool = typer.Option(False, "-y", "--yes",
                             help="Skip the 'about to update N issues' prompt."),
):
    c = _client(ctx)
    issue_ids = _read_ids(ids, ids_file)
    if not issue_ids:
        typer.echo("no issue IDs provided.", err=True)
        raise typer.Exit(code=2)
    issue_body: dict = {}
    if status is not None: issue_body["status_id"] = resolve_status(c, status)
    if tracker is not None: issue_body["tracker_id"] = resolve_tracker(c, tracker)
    if priority is not None: issue_body["priority_id"] = resolve_priority(c, priority)
    if assignee is not None: issue_body["assigned_to_id"] = resolve_assignee(c, assignee)
    if project is not None: issue_body["project_id"] = project
    if note is not None: issue_body["notes"] = note
    if not issue_body:
        typer.echo("nothing to update; pass at least one field.", err=True)
        raise typer.Exit(code=2)

    if not yes:
        typer.confirm(f"About to update {len(issue_ids)} issues. Continue?", abort=True)
    c.post("/issues/bulk_update.json", json={"ids": issue_ids, "issue": issue_body})
    typer.echo(f"bulk updated {len(issue_ids)} issues")


@app.command(
    "delete",
    help=(
        "Bulk delete issues by ID. **Irreversible.** Prompts unless `-y`.\n\n"
        "**Example:** `redmine bulk delete --ids 100,101,102 -y`"
    ),
)
def bulk_delete(
    ctx: typer.Context,
    ids: Optional[str] = typer.Option(None, "--ids"),
    ids_file: Optional[typer.FileText] = typer.Option(None, "--ids-file"),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    issue_ids = _read_ids(ids, ids_file)
    if not yes:
        typer.confirm(f"DELETE {len(issue_ids)} issues? This cannot be undone.",
                      abort=True)
    # Redmine's bulk_destroy is a DELETE on /issues with ids[]= params.
    params = "&".join(f"ids[]={i}" for i in issue_ids)
    c.delete(f"/issues.json?{params}")
    typer.echo(f"bulk deleted {len(issue_ids)} issues")
