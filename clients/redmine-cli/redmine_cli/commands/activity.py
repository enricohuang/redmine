"""`redmine activity ...` — read-only activity stream.

Wraps Redmine's `GET /activity.json` (singular!) and the project-scoped
variant `GET /projects/:id/activity.json`. Response key is `activities`.
"""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list


app = typer.Typer(
    no_args_is_help=True,
    rich_markup_mode="markdown",
    help=(
        "Read-only: project / global activity feed.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine activity list\n"
        "redmine activity list -p demo --limit 50\n"
        "redmine activity list --user-id 1 --json\n"
        "redmine activity list -p demo --with-subprojects --all\n"
        "```\n\n"
        "Note: `--from DATE` is interpreted by Redmine as the *end* of a window "
        "ending at that date (default window is `Setting.activity_days_default`, "
        "usually 30 days). It is **not** a `since` filter."
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help=(
        "List recent activity events. Global by default; project-scoped with `-p`.\n\n"
        "**Example:** `redmine activity list -p demo --json | jq '.[] | {type, title}'`"
    ),
)
def list_activity(
    ctx: typer.Context,
    project: Optional[str] = typer.Option(
        None, "-p", "--project",
        help="Project id or identifier; omit for the global feed.",
    ),
    from_date: Optional[str] = typer.Option(
        None, "--from",
        help="End-date of the window (YYYY-MM-DD). Redmine returns events "
             "in the N days *up to* this date (N = activity_days_default).",
    ),
    user_id: Optional[int] = typer.Option(
        None, "--user-id",
        help="Filter to events authored by this user id.",
    ),
    with_subprojects: bool = typer.Option(
        False, "--with-subprojects",
        help="When project-scoped, also include events from subprojects.",
    ),
    limit: int = typer.Option(25, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    path = f"/projects/{project}/activity.json" if project else "/activity.json"
    params: dict = {}
    if from_date:
        params["from"] = from_date
    if user_id is not None:
        params["user_id"] = user_id
    if with_subprojects:
        params["with_subprojects"] = 1

    if all_pages:
        items = list(c.paginate(path, key="activities", page_size=limit, **params))
    else:
        items = c.get(path, limit=limit, **params).get("activities", [])

    emit_list(
        items,
        columns=[
            ("Type", "type"),
            ("When", "datetime"),
            ("Project", "project.name"),
            ("Author", "author.name"),
            ("Title", "title"),
        ],
        json_mode=json_mode,
    )
