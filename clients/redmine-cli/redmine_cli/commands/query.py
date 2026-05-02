"""`redmine query ...` — read-only listing of saved issue queries.

Wraps Redmine's `GET /queries.json`. Response key is `queries`. Each entry has
`id`, `name`, `is_public`, and `project_id` (null = global / cross-project).

API quirk: `/queries.json` does **not** honour a `project_id` query parameter
(verified against the bundled fork). To get project-scoped queries we list all
and filter on `project_id` client-side. If you need a different filter, ask
for `--json` and pipe through `jq`.
"""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list


app = typer.Typer(
    no_args_is_help=True,
    rich_markup_mode="markdown",
    help=(
        "Read-only: saved issue queries (favourites).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine query list\n"
        "redmine query list --project demo\n"
        "redmine query list --json | jq '.[] | select(.is_public)'\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


def _resolve_project_id(c, project: str) -> Optional[int]:
    """Accept either a numeric id or an identifier; return numeric id or None."""
    if project.isdigit():
        return int(project)
    proj = c.get(f"/projects/{project}.json").get("project", {})
    return proj.get("id")


@app.command(
    "list",
    help=(
        "List saved queries. With `--project`, filter (client-side) to queries "
        "scoped to that project.\n\n"
        "**Example:** `redmine query list --project demo --json`"
    ),
)
def list_queries(
    ctx: typer.Context,
    project: Optional[str] = typer.Option(
        None, "--project",
        help="Project id or identifier; filters client-side (API ignores project_id).",
    ),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    items = c.get("/queries.json").get("queries", [])
    if project is not None:
        pid = _resolve_project_id(c, project)
        items = [q for q in items if q.get("project_id") == pid]
    emit_list(
        items,
        columns=[
            ("ID", "id"),
            ("Name", "name"),
            ("Public", "is_public"),
            ("Project ID", "project_id"),
        ],
        json_mode=json_mode,
    )
