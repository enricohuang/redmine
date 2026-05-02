"""`redmine issue ...` — issue CRUD."""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import typer

from ..output import emit_list, emit_object
from ..resolvers import (
    resolve_assignee, resolve_category, resolve_priority,
    resolve_status, resolve_tracker, resolve_version,
)
from ._helpers import parse_id_list, parse_kv, read_text_input

app = typer.Typer(no_args_is_help=True)


def _client(ctx: typer.Context):
    from ..cli import get_client
    return get_client(ctx)


def _project_for_issue(c, issue_id: int) -> str:
    """Return the project identifier (or numeric id) for an existing issue.

    Used by `issue update` when the user provides --category/--version by name
    without also moving the issue to a new project; we need to know which
    project's category/version list to scan.
    """
    data = c.get(f"/issues/{issue_id}.json", include="").get("issue", {})
    proj = data.get("project") or {}
    return proj.get("identifier") or str(proj.get("id"))


@app.command("list")
def list_issues(
    ctx: typer.Context,
    project: Optional[str] = typer.Option(None, "-p", "--project", help="Project ID or identifier."),
    status: Optional[str] = typer.Option(None, "--status", help="open (default), closed, *, or status ID."),
    assignee: Optional[str] = typer.Option(None, "--assignee", help="User ID, 'me', or '' for unassigned."),
    author: Optional[str] = typer.Option(None, "--author", help="Author user ID or 'me'."),
    tracker: Optional[int] = typer.Option(None, "--tracker", help="Tracker ID."),
    priority: Optional[int] = typer.Option(None, "--priority", help="Priority ID."),
    parent: Optional[int] = typer.Option(None, "--parent", help="Parent issue ID."),
    query: Optional[int] = typer.Option(None, "--query-id", help="Saved query ID."),
    subject: Optional[str] = typer.Option(None, "--subject", help="Substring filter (uses ~ operator)."),
    sort: Optional[str] = typer.Option(None, "--sort", help="e.g. updated_on:desc,priority:desc"),
    include: Optional[str] = typer.Option(None, "--include", help="journals,attachments,relations,..."),
    limit: int = typer.Option(25, "--limit", help="Items to fetch (use --all to ignore)."),
    all_pages: bool = typer.Option(False, "--all", help="Fetch all pages (ignores --limit)."),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON instead of a table."),
):
    """List issues. Defaults match the Redmine UI (open issues only)."""
    c = _client(ctx)
    params = {
        "project_id": project,
        "status_id": status,
        "assigned_to_id": assignee,
        "author_id": author,
        "tracker_id": tracker,
        "priority_id": priority,
        "parent_id": parent,
        "query_id": query,
        "sort": sort,
        "include": include,
    }
    if subject:
        params["subject"] = f"~{subject}"
    params = {k: v for k, v in params.items() if v is not None}

    if all_pages:
        items = list(c.paginate("/issues.json", key="issues", **params))
    else:
        params["limit"] = limit
        data = c.get("/issues.json", **params)
        items = data.get("issues", [])

    emit_list(
        items,
        columns=[
            ("ID", "id"),
            ("Project", "project.name"),
            ("Tracker", "tracker.name"),
            ("Status", "status.name"),
            ("Priority", "priority.name"),
            ("Assignee", "assigned_to.name"),
            ("Subject", "subject"),
        ],
        json_mode=json_mode,
    )


@app.command("get")
def get_issue(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    include: Optional[str] = typer.Option(
        "journals,attachments,relations,watchers,children,allowed_statuses",
        "--include",
        help="Associations to include (comma-separated). Pass empty string to disable.",
    ),
    json_mode: bool = typer.Option(False, "--json"),
):
    """Fetch a single issue by ID."""
    c = _client(ctx)
    params = {}
    if include:
        params["include"] = include
    data = c.get(f"/issues/{id}.json", **params)
    issue = data.get("issue", data)
    if json_mode:
        emit_object(issue, json_mode=True)
        return
    fields = [
        "id", "project", "tracker", "status", "priority", "author", "assigned_to",
        "subject", "description", "start_date", "due_date", "done_ratio",
        "estimated_hours", "spent_hours", "created_on", "updated_on",
        "category", "fixed_version", "parent", "labels",
    ]
    emit_object({f: issue.get(f) for f in fields if f in issue}, json_mode=False)


@app.command("create")
def create_issue(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project", help="Project ID or identifier."),
    subject: str = typer.Option(..., "-s", "--subject"),
    tracker: Optional[str] = typer.Option(None, "-t", "--tracker", help="Tracker ID or name."),
    description: Optional[str] = typer.Option(None, "--description", help="Inline description (or '-' for stdin)."),
    description_file: Optional[Path] = typer.Option(None, "--description-file", help="Path to description file."),
    status: Optional[str] = typer.Option(None, "--status", help="Status ID or name."),
    priority: Optional[str] = typer.Option(None, "--priority", help="Priority ID or name."),
    assignee: Optional[str] = typer.Option(None, "--assignee", help="User ID, login, or 'me'."),
    parent: Optional[int] = typer.Option(None, "--parent", help="Parent issue ID."),
    category: Optional[str] = typer.Option(None, "--category", help="Category ID or name."),
    version: Optional[str] = typer.Option(None, "--version", help="Fixed version ID or name."),
    start_date: Optional[str] = typer.Option(None, "--start-date"),
    due_date: Optional[str] = typer.Option(None, "--due-date"),
    estimated_hours: Optional[float] = typer.Option(None, "--estimated-hours"),
    done_ratio: Optional[int] = typer.Option(None, "--done-ratio"),
    is_private: bool = typer.Option(False, "--private"),
    label_ids: Optional[str] = typer.Option(None, "--labels", help="Comma-separated label IDs (fork)."),
    custom: list[str] = typer.Option([], "--custom", help="Custom field: id=value (repeatable)."),
    watchers: Optional[str] = typer.Option(None, "--watchers", help="Comma-separated watcher user IDs."),
    json_mode: bool = typer.Option(False, "--json"),
):
    """Create a new issue."""
    c = _client(ctx)
    body_text = read_text_input(description, description_file, name="description")
    body = {"project_id": project, "subject": subject}
    if tracker is not None: body["tracker_id"] = resolve_tracker(c, tracker)
    if body_text is not None: body["description"] = body_text
    if status is not None: body["status_id"] = resolve_status(c, status)
    if priority is not None: body["priority_id"] = resolve_priority(c, priority)
    if assignee is not None: body["assigned_to_id"] = resolve_assignee(c, assignee)
    if parent is not None: body["parent_issue_id"] = parent
    if category is not None: body["category_id"] = resolve_category(c, project, category)
    if version is not None: body["fixed_version_id"] = resolve_version(c, project, version)
    if start_date: body["start_date"] = start_date
    if due_date: body["due_date"] = due_date
    if estimated_hours is not None: body["estimated_hours"] = estimated_hours
    if done_ratio is not None: body["done_ratio"] = done_ratio
    if is_private: body["is_private"] = True
    if label_ids: body["label_ids"] = parse_id_list(label_ids)
    if watchers: body["watcher_user_ids"] = parse_id_list(watchers)
    if custom:
        cf = parse_kv(custom)
        body["custom_fields"] = [{"id": int(k), "value": v} for k, v in cf.items()]

    data = c.post("/issues.json", json={"issue": body})
    issue = data.get("issue", data)
    if json_mode:
        emit_object(issue, json_mode=True)
    else:
        emit_object(
            {k: issue.get(k) for k in ("id", "project", "tracker", "status", "subject")},
            json_mode=False,
        )


@app.command("update")
def update_issue(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    subject: Optional[str] = typer.Option(None, "-s", "--subject"),
    description: Optional[str] = typer.Option(None, "--description"),
    description_file: Optional[Path] = typer.Option(None, "--description-file"),
    status: Optional[str] = typer.Option(None, "--status", help="Status ID or name."),
    priority: Optional[str] = typer.Option(None, "--priority"),
    tracker: Optional[str] = typer.Option(None, "-t", "--tracker"),
    assignee: Optional[str] = typer.Option(None, "--assignee"),
    project: Optional[str] = typer.Option(None, "-p", "--project", help="Move to another project."),
    parent: Optional[int] = typer.Option(None, "--parent"),
    category: Optional[str] = typer.Option(None, "--category"),
    version: Optional[str] = typer.Option(None, "--version"),
    start_date: Optional[str] = typer.Option(None, "--start-date"),
    due_date: Optional[str] = typer.Option(None, "--due-date"),
    estimated_hours: Optional[float] = typer.Option(None, "--estimated-hours"),
    done_ratio: Optional[int] = typer.Option(None, "--done-ratio"),
    note: Optional[str] = typer.Option(None, "-n", "--note", help="Add a comment with the update."),
    note_file: Optional[Path] = typer.Option(None, "--note-file"),
    private_notes: bool = typer.Option(False, "--private-notes"),
    label_ids: Optional[str] = typer.Option(None, "--labels", help="Replace label set."),
    custom: list[str] = typer.Option([], "--custom", help="Custom field: id=value (repeatable)."),
):
    """Update an existing issue. PUT returns no body — exits 0 on success."""
    c = _client(ctx)
    body_desc = read_text_input(description, description_file, name="description")
    body_note = read_text_input(note, note_file, name="note")
    body: dict = {}
    if subject is not None: body["subject"] = subject
    if body_desc is not None: body["description"] = body_desc
    if status is not None: body["status_id"] = resolve_status(c, status)
    if priority is not None: body["priority_id"] = resolve_priority(c, priority)
    if tracker is not None: body["tracker_id"] = resolve_tracker(c, tracker)
    if assignee is not None: body["assigned_to_id"] = resolve_assignee(c, assignee)
    if project is not None: body["project_id"] = project
    if parent is not None: body["parent_issue_id"] = parent
    # Category/version need the *current* project of the issue if not moving;
    # easiest is to look it up. Punt: only resolve if project was given on this call.
    if category is not None:
        body["category_id"] = resolve_category(c, project or _project_for_issue(c, id), category)
    if version is not None:
        body["fixed_version_id"] = resolve_version(c, project or _project_for_issue(c, id), version)
    if start_date: body["start_date"] = start_date
    if due_date: body["due_date"] = due_date
    if estimated_hours is not None: body["estimated_hours"] = estimated_hours
    if done_ratio is not None: body["done_ratio"] = done_ratio
    if body_note is not None:
        body["notes"] = body_note
        if private_notes:
            body["private_notes"] = True
    if label_ids is not None: body["label_ids"] = parse_id_list(label_ids)
    if custom:
        cf = parse_kv(custom)
        body["custom_fields"] = [{"id": int(k), "value": v} for k, v in cf.items()]
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/issues/{id}.json", json={"issue": body})
    typer.echo(f"updated #{id}")


@app.command("delete")
def delete_issue(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes", help="Skip confirmation prompt."),
):
    """Delete an issue (irreversible)."""
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete issue #{id}?", abort=True)
    c.delete(f"/issues/{id}.json")
    typer.echo(f"deleted #{id}")


@app.command("watch")
def watch(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    user_id: int = typer.Option(..., "--user-id", help="User ID to add as watcher."),
):
    """Add a watcher to an issue."""
    c = _client(ctx)
    c.post(f"/issues/{id}/watchers.json", json={"user_id": user_id})
    typer.echo(f"watcher {user_id} added to #{id}")


@app.command("unwatch")
def unwatch(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    user_id: int = typer.Option(..., "--user-id"),
):
    """Remove a watcher from an issue."""
    c = _client(ctx)
    c.delete(f"/issues/{id}/watchers/{user_id}.json")
    typer.echo(f"watcher {user_id} removed from #{id}")
