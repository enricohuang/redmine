"""`redmine time ...` — time entries."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Log and manage time entries (`time_entries` resource).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine time list -p mobile --user me --from 2026-01-01\n"
        "redmine time create -i 1234 --hours 2.5 --activity Development\n"
        "redmine time update 88 --hours 3 --comment 'corrected estimate'\n"
        "redmine time delete 88 -y\n"
        "```\n\n"
        "Activity is the time-tracking activity name or ID. List available "
        "activities with `redmine enumeration list time-entry-activities`."
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


def _resolve_activity(c, value: Optional[str]):
    """Activity id from name (case-insensitive), passing IDs through."""
    if value is None or value.isdigit():
        return value
    items = c.get("/enumerations/time_entry_activities.json").get(
        "time_entry_activities", []
    )
    for item in items:
        if item.get("name", "").lower() == value.lower():
            return int(item["id"])
    valid = ", ".join(repr(i.get("name")) for i in items)
    typer.echo(f"unknown activity '{value}'. Valid: {valid}", err=True)
    raise typer.Exit(code=3)


@app.command(
    "list",
    help=(
        "List time entries.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine time list -p mobile\n"
        "redmine time list --user me --from 2026-01-01 --to 2026-01-31\n"
        "redmine time list -i 1234 --json | jq 'map(.hours) | add'\n"
        "```\n\n"
        "`--user me` is server-side magic; otherwise pass a numeric user ID."
    ),
)
def list_entries(
    ctx: typer.Context,
    project: Optional[str] = typer.Option(None, "-p", "--project"),
    issue: Optional[int] = typer.Option(None, "-i", "--issue"),
    user: Optional[str] = typer.Option(None, "--user", help="User ID or 'me'."),
    activity: Optional[int] = typer.Option(None, "--activity-id"),
    from_date: Optional[str] = typer.Option(None, "--from", help="YYYY-MM-DD."),
    to_date: Optional[str] = typer.Option(None, "--to", help="YYYY-MM-DD."),
    limit: int = typer.Option(25, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    params = {
        "project_id": project,
        "issue_id": issue,
        "user_id": user,
        "activity_id": activity,
        "from": from_date,
        "to": to_date,
    }
    params = {k: v for k, v in params.items() if v is not None}
    if all_pages:
        items = list(c.paginate("/time_entries.json", key="time_entries",
                                page_size=limit, **params))
    else:
        params["limit"] = limit
        items = c.get("/time_entries.json", **params).get("time_entries", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Date", "spent_on"), ("User", "user.name"),
                 ("Issue", "issue.id"), ("Hours", "hours"),
                 ("Activity", "activity.name"), ("Comments", "comments")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help="Fetch a single time entry by ID.\n\n**Example:** `redmine time get 88 --json`",
)
def get_entry(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    obj = _client(ctx).get(f"/time_entries/{id}.json").get("time_entry", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Log a time entry against an issue or a project.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine time create -i 1234 --hours 2.5 --activity Development\n"
        "redmine time create -p mobile --hours 1 --activity Design \\\n"
        "                    --comment 'design review' --date 2026-01-15\n"
        "```"
    ),
)
def create_entry(
    ctx: typer.Context,
    issue: Optional[int] = typer.Option(None, "-i", "--issue"),
    project: Optional[str] = typer.Option(None, "-p", "--project"),
    hours: float = typer.Option(..., "--hours"),
    activity: str = typer.Option(..., "--activity", help="Activity ID or name (e.g. 'Design')."),
    comment: Optional[str] = typer.Option(None, "--comment"),
    date: Optional[str] = typer.Option(None, "--date", help="YYYY-MM-DD (defaults to today)."),
    user: Optional[int] = typer.Option(None, "--user-id", help="Log on behalf of another user (perm-gated)."),
    json_mode: bool = typer.Option(False, "--json"),
):
    if issue is None and project is None:
        typer.echo("error: --issue or --project is required.", err=True)
        raise typer.Exit(code=2)
    c = _client(ctx)
    body: dict = {"hours": hours, "activity_id": _resolve_activity(c, activity)}
    if issue is not None: body["issue_id"] = issue
    if project is not None: body["project_id"] = project
    if comment is not None: body["comments"] = comment
    if date is not None: body["spent_on"] = date
    if user is not None: body["user_id"] = user
    data = c.post("/time_entries.json", json={"time_entry": body})
    obj = data.get("time_entry", data)
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"logged {hours}h (id={obj.get('id')})"
    )


@app.command(
    "update",
    help=(
        "Update a time entry.\n\n"
        "**Example:** `redmine time update 88 --hours 3 --comment 'corrected'`"
    ),
)
def update_entry(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    hours: Optional[float] = typer.Option(None, "--hours"),
    activity: Optional[str] = typer.Option(None, "--activity"),
    comment: Optional[str] = typer.Option(None, "--comment"),
    date: Optional[str] = typer.Option(None, "--date"),
    issue: Optional[int] = typer.Option(None, "-i", "--issue"),
    project: Optional[str] = typer.Option(None, "-p", "--project"),
):
    c = _client(ctx)
    body: dict = {}
    if hours is not None: body["hours"] = hours
    if activity is not None: body["activity_id"] = _resolve_activity(c, activity)
    if comment is not None: body["comments"] = comment
    if date is not None: body["spent_on"] = date
    if issue is not None: body["issue_id"] = issue
    if project is not None: body["project_id"] = project
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/time_entries/{id}.json", json={"time_entry": body})
    typer.echo(f"updated time entry {id}")


@app.command(
    "delete",
    help="Delete a time entry. Prompts unless `-y`.\n\n**Example:** `redmine time delete 88 -y`",
)
def delete_entry(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete time entry {id}?", abort=True)
    c.delete(f"/time_entries/{id}.json")
    typer.echo(f"deleted time entry {id}")
