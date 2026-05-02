"""`redmine board ...` — project discussion boards (forums)."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object

app = typer.Typer(
    no_args_is_help=True,
    rich_markup_mode="markdown",
    help=(
        "Manage project discussion boards (forums).\n\n"
        "Boards are project-scoped containers for `redmine message` topics. "
        "Requires the `boards` module to be enabled on the project.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine board list -p mobile\n"
        "redmine board create -p mobile --name General --description 'Chat'\n"
        "redmine board update 3 --description 'Updated description'\n"
        "redmine board delete 3 -y\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help=(
        "List boards in a project.\n\n"
        "**Example:**\n\n"
        "```\n"
        "redmine board list -p mobile --json | jq '.[].name'\n"
        "```"
    ),
)
def list_boards(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project", help="Project ID or identifier."),
    limit: int = typer.Option(25, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    path = f"/projects/{project}/boards.json"
    if all_pages:
        items = list(c.paginate(path, key="boards", page_size=limit))
    else:
        items = c.get(path, limit=limit).get("boards", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Name", "name"), ("Parent", "parent.name"),
                 ("Topics", "topics_count"), ("Messages", "messages_count"),
                 ("Last", "last_message.subject")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help=(
        "Fetch a single board by numeric ID.\n\n"
        "**Example:**\n\n"
        "```\n"
        "redmine board get 3 --json\n"
        "```"
    ),
)
def get_board(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric board ID."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    obj = c.get(f"/boards/{id}.json").get("board", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Create a board in a project. Returns the new board (looked up by name "
        "since the create endpoint returns 204 No Content).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine board create -p mobile --name General\n"
        "redmine board create -p mobile --name Releases --description 'Release notes'\n"
        "redmine board create -p mobile --name Subforum --parent-id 3\n"
        "```"
    ),
)
def create_board(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project", help="Project ID or identifier."),
    name: str = typer.Option(..., "--name"),
    description: str = typer.Option(..., "--description",
                                    help="Required by the server (HTTP 422 'Description cannot be blank' otherwise)."),
    parent_id: Optional[int] = typer.Option(None, "--parent-id",
                                            help="Numeric ID of a parent board (for sub-forums)."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    body: dict = {"name": name, "description": description}
    if parent_id is not None: body["parent_id"] = parent_id
    # POST /projects/:id/boards.json returns 204 No Content; re-fetch the
    # newly-created board by listing and matching on name (newest match wins).
    c.post(f"/projects/{project}/boards.json", json={"board": body})
    listed = c.get(f"/projects/{project}/boards.json", limit=100).get("boards", [])
    matches = [b for b in listed if b.get("name") == name]
    obj = matches[-1] if matches else {}
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"created board '{name}' (id={obj.get('id')})"
    )


@app.command(
    "update",
    help=(
        "Update a board.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine board update 3 --name 'General (renamed)'\n"
        "redmine board update 3 --description 'New description'\n"
        "redmine board update 3 --position 1\n"
        "```"
    ),
)
def update_board(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric board ID."),
    name: Optional[str] = typer.Option(None, "--name"),
    description: Optional[str] = typer.Option(None, "--description"),
    parent_id: Optional[int] = typer.Option(None, "--parent-id"),
    position: Optional[int] = typer.Option(None, "--position"),
):
    c = _client(ctx)
    body: dict = {}
    if name is not None: body["name"] = name
    if description is not None: body["description"] = description
    if parent_id is not None: body["parent_id"] = parent_id
    if position is not None: body["position"] = position
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/boards/{id}.json", json={"board": body})
    typer.echo(f"updated board {id}")


@app.command(
    "delete",
    help=(
        "Delete a board (and all its messages). Prompts unless `-y`.\n\n"
        "**Example:**\n\n"
        "```\n"
        "redmine board delete 3 -y\n"
        "```"
    ),
)
def delete_board(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric board ID."),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete board {id}?", abort=True)
    c.delete(f"/boards/{id}.json")
    typer.echo(f"deleted board {id}")
