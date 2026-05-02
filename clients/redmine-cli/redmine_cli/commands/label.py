"""`redmine label ...` — manage project labels (fork feature)."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object

app = typer.Typer(no_args_is_help=True)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command("list")
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


@app.command("get")
def get_label(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    data = c.get(f"/labels/{id}.json").get("label")
    emit_object(data or {}, json_mode=json_mode)


@app.command("create")
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


@app.command("update")
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


@app.command("delete")
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
