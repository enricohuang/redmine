"""`redmine group ...` — user groups (admin-only)."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object
from ._helpers import parse_id_list

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Manage user groups (admin-only on stock Redmine).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine group list\n"
        "redmine group create --name backend-team --user-ids 7,8,9\n"
        "redmine group add-user 3 --user-id 12\n"
        "redmine group remove-user 3 --user-id 12\n"
        "redmine group delete 3 -y\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help="List user groups.\n\n**Example:** `redmine group list --json`",
)
def list_groups(
    ctx: typer.Context,
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    items = c.get("/groups.json").get("groups", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Name", "name")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help=(
        "Get a group by ID. Default `--include` covers users and memberships.\n\n"
        "**Example:** `redmine group get 3 --json`"
    ),
)
def get_group(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    include: Optional[str] = typer.Option("users,memberships", "--include"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    params = {"include": include} if include else {}
    obj = c.get(f"/groups/{id}.json", **params).get("group", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Create a group, optionally with initial users.\n\n"
        "**Example:** `redmine group create --name backend --user-ids 7,8,9`"
    ),
)
def create_group(
    ctx: typer.Context,
    name: str = typer.Option(..., "--name"),
    user_ids: Optional[str] = typer.Option(None, "--user-ids", help="Comma-separated."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    body: dict = {"name": name}
    if user_ids:
        body["user_ids"] = parse_id_list(user_ids)
    obj = c.post("/groups.json", json={"group": body}).get("group", {})
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"created group {name} (id={obj.get('id')})"
    )


@app.command(
    "update",
    help="Rename a group.\n\n**Example:** `redmine group update 3 --name new-name`",
)
def update_group(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    name: str = typer.Option(..., "--name"),
):
    c = _client(ctx)
    c.put(f"/groups/{id}.json", json={"group": {"name": name}})
    typer.echo(f"updated group {id}")


@app.command(
    "delete",
    help="Delete a group. Prompts unless `-y`.\n\n**Example:** `redmine group delete 3 -y`",
)
def delete_group(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete group {id}?", abort=True)
    c.delete(f"/groups/{id}.json")
    typer.echo(f"deleted group {id}")


@app.command(
    "add-user",
    help=(
        "Add a user to a group.\n\n"
        "**Example:** `redmine group add-user 3 --user-id 12`"
    ),
)
def add_user(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Group ID."),
    user_id: int = typer.Option(..., "--user-id"),
):
    c = _client(ctx)
    c.post(f"/groups/{id}/users.json", json={"user_id": user_id})
    typer.echo(f"added user {user_id} to group {id}")


@app.command(
    "remove-user",
    help=(
        "Remove a user from a group.\n\n"
        "**Example:** `redmine group remove-user 3 --user-id 12`"
    ),
)
def remove_user(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    user_id: int = typer.Option(..., "--user-id"),
):
    c = _client(ctx)
    c.delete(f"/groups/{id}/users/{user_id}.json")
    typer.echo(f"removed user {user_id} from group {id}")
