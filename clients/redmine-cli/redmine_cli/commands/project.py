"""`redmine project ...` — project CRUD."""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import typer

from ..output import emit_list, emit_object
from ._helpers import parse_id_list, read_text_input

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Manage projects.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine project list\n"
        "redmine project get mobile               # by identifier\n"
        "redmine project create --identifier docs --name 'Docs'\n"
        "redmine project update mobile --description 'Mobile app'\n"
        "redmine project archive mobile           # hide from active project lists\n"
        "redmine project unarchive mobile\n"
        "redmine project close mobile             # read-only mode\n"
        "redmine project reopen mobile\n"
        "redmine project delete docs -y\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help=(
        "List visible projects.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine project list\n"
        "redmine project list --all --json | jq '.[] | {id, identifier, name}'\n"
        "redmine project list --include trackers,issue_categories\n"
        "```"
    ),
)
def list_projects(
    ctx: typer.Context,
    include: Optional[str] = typer.Option(None, "--include", help="trackers,issue_categories,enabled_modules,..."),
    limit: int = typer.Option(25, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    """List visible projects."""
    c = _client(ctx)
    params = {"include": include} if include else {}
    if all_pages:
        items = list(c.paginate("/projects.json", key="projects", **params))
    else:
        params["limit"] = limit
        items = c.get("/projects.json", **params).get("projects", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Identifier", "identifier"), ("Name", "name"),
                 ("Public", "is_public"), ("Status", "status")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help=(
        "Fetch a project by numeric ID or identifier.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine project get mobile\n"
        "redmine project get 1\n"
        "redmine project get mobile --include enabled_modules,trackers\n"
        "```"
    ),
)
def get_project(
    ctx: typer.Context,
    id_or_identifier: str = typer.Argument(..., metavar="PROJECT"),
    include: Optional[str] = typer.Option(
        "trackers,issue_categories,enabled_modules", "--include",
        help="Pass empty string to disable.",
    ),
    json_mode: bool = typer.Option(False, "--json"),
):
    """Fetch a single project by numeric ID or identifier."""
    c = _client(ctx)
    params = {"include": include} if include else {}
    data = c.get(f"/projects/{id_or_identifier}.json", **params)
    obj = data.get("project", data)
    if json_mode:
        emit_object(obj, json_mode=True)
        return
    fields = ["id", "identifier", "name", "description", "homepage",
              "is_public", "status", "parent", "created_on", "updated_on",
              "trackers", "issue_categories", "enabled_modules"]
    emit_object({f: obj.get(f) for f in fields if f in obj}, json_mode=False)


@app.command(
    "create",
    help=(
        "Create a project.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine project create --identifier docs --name 'Docs'\n"
        "redmine project create --identifier api --name API \\\n"
        "                       --modules issue_tracking,wiki,news --public\n"
        "redmine project create --identifier sub --name Sub --parent docs\n"
        "```\n\n"
        "Identifier must be URL-safe (lowercase, dashes — no spaces)."
    ),
)
def create_project(
    ctx: typer.Context,
    identifier: str = typer.Option(..., "--identifier", help="URL-safe identifier (lowercase, dashes)."),
    name: str = typer.Option(..., "--name"),
    description: Optional[str] = typer.Option(None, "--description"),
    description_file: Optional[Path] = typer.Option(None, "--description-file"),
    homepage: Optional[str] = typer.Option(None, "--homepage"),
    is_public: bool = typer.Option(False, "--public"),
    parent: Optional[str] = typer.Option(None, "--parent", help="Parent project ID or identifier."),
    inherit_members: bool = typer.Option(False, "--inherit-members"),
    tracker_ids: Optional[str] = typer.Option(None, "--trackers", help="Comma-separated tracker IDs."),
    enabled_module_names: Optional[str] = typer.Option(
        None, "--modules", help="Comma-separated module names (issue_tracking,wiki,...)."),
    json_mode: bool = typer.Option(False, "--json"),
):
    """Create a project."""
    c = _client(ctx)
    desc = read_text_input(description, description_file, name="description")
    body = {"identifier": identifier, "name": name}
    if desc is not None: body["description"] = desc
    if homepage: body["homepage"] = homepage
    if is_public: body["is_public"] = True
    if parent is not None: body["parent_id"] = parent
    if inherit_members: body["inherit_members"] = True
    if tracker_ids: body["tracker_ids"] = parse_id_list(tracker_ids)
    if enabled_module_names:
        body["enabled_module_names"] = [m.strip() for m in enabled_module_names.split(",") if m.strip()]
    data = c.post("/projects.json", json={"project": body})
    obj = data.get("project", data)
    if json_mode:
        emit_object(obj, json_mode=True)
    else:
        emit_object({k: obj.get(k) for k in ("id", "identifier", "name")}, json_mode=False)


@app.command(
    "update",
    help=(
        "Update a project.\n\n"
        "**Example:** `redmine project update mobile --description 'New copy'`"
    ),
)
def update_project(
    ctx: typer.Context,
    id_or_identifier: str = typer.Argument(..., metavar="PROJECT"),
    name: Optional[str] = typer.Option(None, "--name"),
    description: Optional[str] = typer.Option(None, "--description"),
    description_file: Optional[Path] = typer.Option(None, "--description-file"),
    homepage: Optional[str] = typer.Option(None, "--homepage"),
    is_public: Optional[bool] = typer.Option(None, "--public/--private"),
    parent: Optional[str] = typer.Option(None, "--parent"),
):
    """Update a project."""
    c = _client(ctx)
    desc = read_text_input(description, description_file, name="description")
    body: dict = {}
    if name is not None: body["name"] = name
    if desc is not None: body["description"] = desc
    if homepage is not None: body["homepage"] = homepage
    if is_public is not None: body["is_public"] = is_public
    if parent is not None: body["parent_id"] = parent
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/projects/{id_or_identifier}.json", json={"project": body})
    typer.echo(f"updated {id_or_identifier}")


@app.command(
    "delete",
    help=(
        "Delete a project — **wipes all its issues, wiki, attachments, etc.** "
        "Prompts unless `-y` is passed. No undo.\n\n"
        "**Example:** `redmine project delete docs -y`"
    ),
)
def delete_project(
    ctx: typer.Context,
    id_or_identifier: str = typer.Argument(..., metavar="PROJECT"),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    """Delete a project (irreversible — wipes issues, wiki, etc)."""
    c = _client(ctx)
    if not yes:
        typer.confirm(
            f"Really delete project '{id_or_identifier}' and ALL its data?",
            abort=True,
        )
    c.delete(f"/projects/{id_or_identifier}.json")
    typer.echo(f"deleted {id_or_identifier}")


@app.command(
    "archive",
    help=(
        "Archive a project — hides it from active project lists. Reversible "
        "via `redmine project unarchive`.\n\n"
        "**Example:** `redmine project archive mobile`"
    ),
)
def archive_project(
    ctx: typer.Context,
    id_or_identifier: str = typer.Argument(..., metavar="PROJECT"),
):
    """Archive a project (hides it from active project lists)."""
    c = _client(ctx)
    c.put(f"/projects/{id_or_identifier}/archive.json")
    typer.echo(f"archived {id_or_identifier}")


@app.command(
    "unarchive",
    help=(
        "Unarchive a previously archived project.\n\n"
        "**Example:** `redmine project unarchive mobile`"
    ),
)
def unarchive_project(
    ctx: typer.Context,
    id_or_identifier: str = typer.Argument(..., metavar="PROJECT"),
):
    """Unarchive a previously archived project."""
    c = _client(ctx)
    c.put(f"/projects/{id_or_identifier}/unarchive.json")
    typer.echo(f"unarchived {id_or_identifier}")


@app.command(
    "close",
    help=(
        "Close a project — puts it in read-only mode. Reversible via "
        "`redmine project reopen`.\n\n"
        "**Example:** `redmine project close mobile`"
    ),
)
def close_project(
    ctx: typer.Context,
    id_or_identifier: str = typer.Argument(..., metavar="PROJECT"),
):
    """Close a project (puts it in read-only mode)."""
    c = _client(ctx)
    c.put(f"/projects/{id_or_identifier}/close.json")
    typer.echo(f"closed {id_or_identifier}")


@app.command(
    "reopen",
    help=(
        "Reopen a previously closed project.\n\n"
        "**Example:** `redmine project reopen mobile`"
    ),
)
def reopen_project(
    ctx: typer.Context,
    id_or_identifier: str = typer.Argument(..., metavar="PROJECT"),
):
    """Reopen a previously closed project."""
    c = _client(ctx)
    c.put(f"/projects/{id_or_identifier}/reopen.json")
    typer.echo(f"reopened {id_or_identifier}")
