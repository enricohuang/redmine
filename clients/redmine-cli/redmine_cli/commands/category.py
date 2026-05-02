"""`redmine category ...` — issue categories (per-project)."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Manage per-project issue categories.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine category list -p mobile\n"
        "redmine category create -p mobile --name Backend --assigned-to 7\n"
        "redmine category update 3 --name 'Backend (legacy)'\n"
        "redmine category delete 3 -y\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help="List categories in a project.\n\n**Example:** `redmine category list -p mobile`",
)
def list_categories(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    items = c.get(f"/projects/{project}/issue_categories.json").get("issue_categories", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Name", "name"), ("Assigned to", "assigned_to.name")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help="Get a category by ID.\n\n**Example:** `redmine category get 3 --json`",
)
def get_category(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    obj = c.get(f"/issue_categories/{id}.json").get("issue_category", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Create a category in a project.\n\n"
        "**Example:** `redmine category create -p mobile --name Backend --assigned-to 7`"
    ),
)
def create_category(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    name: str = typer.Option(..., "--name"),
    assigned_to: Optional[int] = typer.Option(None, "--assigned-to",
                                              help="Default assignee user ID."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    body: dict = {"name": name}
    if assigned_to is not None: body["assigned_to_id"] = assigned_to
    obj = c.post(f"/projects/{project}/issue_categories.json",
                 json={"issue_category": body}).get("issue_category", {})
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"created category '{name}' (id={obj.get('id')})"
    )


@app.command(
    "update",
    help="Update a category.\n\n**Example:** `redmine category update 3 --name New`",
)
def update_category(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    name: Optional[str] = typer.Option(None, "--name"),
    assigned_to: Optional[int] = typer.Option(None, "--assigned-to"),
):
    c = _client(ctx)
    body: dict = {}
    if name is not None: body["name"] = name
    if assigned_to is not None: body["assigned_to_id"] = assigned_to
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/issue_categories/{id}.json", json={"issue_category": body})
    typer.echo(f"updated category {id}")


@app.command(
    "delete",
    help=(
        "Delete a category. Optionally reassign issues using "
        "`--reassign-to ID`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine category delete 3 -y\n"
        "redmine category delete 3 --reassign-to 4 -y\n"
        "```"
    ),
)
def delete_category(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    reassign_to: Optional[int] = typer.Option(None, "--reassign-to"),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete category {id}?", abort=True)
    path = f"/issue_categories/{id}.json"
    if reassign_to is not None:
        path += f"?reassign_to_id={reassign_to}"
    c.delete(path)
    typer.echo(f"deleted category {id}")
