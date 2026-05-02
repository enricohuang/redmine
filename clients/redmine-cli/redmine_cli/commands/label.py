"""`redmine label ...` — manage project labels (fork feature)."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Manage project labels (fork feature). Labels are colored, "
        "project-scoped tags assignable to issues via `issue create/update --labels`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine label list -p mobile\n"
        "redmine label create -p mobile --name 'v1-bug' --color '#e74c3c'\n"
        "redmine label update 7 --name 'v1-bug-critical'\n"
        "redmine label delete 7 -y\n"
        "```\n\n"
        "Tutorial: `redmine help labels`"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help=(
        "List labels in a project.\n\n"
        "**Example:** `redmine label list -p mobile --json | jq '.[] | {id, name}'`"
    ),
)
def list_labels(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    items = c.get(f"/projects/{project}/labels.json").get("labels", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Name", "name"), ("Color", "color")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help=(
        "Get a label by ID.\n\n"
        "**Example:** `redmine label get 7 --json`"
    ),
)
def get_label(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    data = c.get(f"/labels/{id}.json").get("label")
    emit_object(data or {}, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Create a label in a project. Color is a 6-digit hex like `#9b59b6`; "
        "default is `#0052CC` if omitted.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine label create -p mobile --name 'needs-info'\n"
        "redmine label create -p mobile --name 'v1-bug' --color '#e74c3c'\n"
        "```"
    ),
)
def create_label(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    name: str = typer.Option(..., "--name"),
    color: Optional[str] = typer.Option(None, "--color", help="Hex color, e.g. #9b59b6"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    body: dict = {"name": name}
    if color: body["color"] = color
    data = c.post(f"/projects/{project}/labels.json", json={"label": body})
    obj = data.get("label", data) if isinstance(data, dict) else {}
    if json_mode:
        emit_object(obj, json_mode=True)
    else:
        typer.echo(f"created label '{name}' (id={obj.get('id')})")


@app.command(
    "update",
    help=(
        "Rename or recolor a label.\n\n"
        "**Example:** `redmine label update 7 --name 'critical' --color '#000000'`"
    ),
)
def update_label(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    name: Optional[str] = typer.Option(None, "--name"),
    color: Optional[str] = typer.Option(None, "--color"),
):
    c = _client(ctx)
    body: dict = {}
    if name is not None: body["name"] = name
    if color is not None: body["color"] = color
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/labels/{id}.json", json={"label": body})
    typer.echo(f"updated label {id}")


@app.command(
    "delete",
    help=(
        "Delete a label (also removes it from any issues it's assigned to). "
        "Prompts unless `-y` is passed.\n\n"
        "**Example:** `redmine label delete 7 -y`"
    ),
)
def delete_label(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete label {id}?", abort=True)
    c.delete(f"/labels/{id}.json")
    typer.echo(f"deleted label {id}")
