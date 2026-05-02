"""`redmine version ...` — project versions (releases / milestones)."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Manage project versions (a.k.a. releases / milestones).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine version list -p mobile\n"
        "redmine version create -p mobile --name v2.0 --due-date 2026-12-31\n"
        "redmine version update 7 --status closed\n"
        "redmine version delete 7 -y\n"
        "```\n\n"
        "Status is one of: `open`, `locked`, `closed`."
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help=(
        "List versions in a project.\n\n"
        "**Example:** `redmine version list -p mobile --json | jq '.[] | {id, name, status}'`"
    ),
)
def list_versions(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    items = c.get(f"/projects/{project}/versions.json").get("versions", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Name", "name"), ("Status", "status"),
                 ("Due", "due_date"), ("Sharing", "sharing")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help="Get a version by ID.\n\n**Example:** `redmine version get 7 --json`",
)
def get_version(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    obj = c.get(f"/versions/{id}.json").get("version", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Create a version in a project.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine version create -p mobile --name v2.0\n"
        "redmine version create -p mobile --name v2.1 --due-date 2026-12-31 \\\n"
        "                                 --description 'Holiday release'\n"
        "redmine version create -p mobile --name shared --sharing tree\n"
        "```\n\n"
        "Sharing: `none`, `descendants`, `hierarchy`, `tree`, `system`."
    ),
)
def create_version(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    name: str = typer.Option(..., "--name"),
    description: Optional[str] = typer.Option(None, "--description"),
    status: Optional[str] = typer.Option(None, "--status",
                                         help="open|locked|closed"),
    due_date: Optional[str] = typer.Option(None, "--due-date", help="YYYY-MM-DD"),
    sharing: Optional[str] = typer.Option(None, "--sharing"),
    wiki_page: Optional[str] = typer.Option(None, "--wiki-page-title"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    body: dict = {"name": name}
    if description: body["description"] = description
    if status: body["status"] = status
    if due_date: body["due_date"] = due_date
    if sharing: body["sharing"] = sharing
    if wiki_page: body["wiki_page_title"] = wiki_page
    obj = c.post(f"/projects/{project}/versions.json", json={"version": body}).get("version", {})
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"created version {name} (id={obj.get('id')})"
    )


@app.command(
    "update",
    help=(
        "Update a version.\n\n"
        "**Example:** `redmine version update 7 --status closed`"
    ),
)
def update_version(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    name: Optional[str] = typer.Option(None, "--name"),
    description: Optional[str] = typer.Option(None, "--description"),
    status: Optional[str] = typer.Option(None, "--status"),
    due_date: Optional[str] = typer.Option(None, "--due-date"),
    sharing: Optional[str] = typer.Option(None, "--sharing"),
):
    c = _client(ctx)
    body: dict = {}
    if name is not None: body["name"] = name
    if description is not None: body["description"] = description
    if status is not None: body["status"] = status
    if due_date is not None: body["due_date"] = due_date
    if sharing is not None: body["sharing"] = sharing
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/versions/{id}.json", json={"version": body})
    typer.echo(f"updated version {id}")


@app.command(
    "delete",
    help="Delete a version. Prompts unless `-y`.\n\n**Example:** `redmine version delete 7 -y`",
)
def delete_version(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete version {id}?", abort=True)
    c.delete(f"/versions/{id}.json")
    typer.echo(f"deleted version {id}")
