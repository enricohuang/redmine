"""`redmine member ...` — project memberships."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object
from ._helpers import parse_id_list

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Manage project memberships (which users/groups have which roles "
        "in a project).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine member list -p mobile\n"
        "redmine member add -p mobile --user-id 7 --roles 3,4\n"
        "redmine member update 12 --roles 3\n"
        "redmine member remove 12 -y\n"
        "```\n\n"
        "Role IDs from `redmine role list`. User IDs from `redmine user list`. "
        "For groups, use `--group-id` instead of `--user-id`."
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help="List memberships in a project.\n\n**Example:** `redmine member list -p mobile`",
)
def list_members(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    limit: int = typer.Option(25, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    path = f"/projects/{project}/memberships.json"
    if all_pages:
        items = list(c.paginate(path, key="memberships", page_size=limit))
    else:
        items = c.get(path, limit=limit).get("memberships", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Project", "project.name"),
                 ("User/Group", "user.name"), ("Group", "group.name"),
                 ("Roles", "roles")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help="Get a single membership by ID.\n\n**Example:** `redmine member get 12 --json`",
)
def get_member(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    obj = c.get(f"/memberships/{id}.json").get("membership", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "add",
    help=(
        "Add a user (or group) to a project with one or more roles.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine member add -p mobile --user-id 7 --roles 3,4\n"
        "redmine member add -p mobile --group-id 2 --roles 3\n"
        "```"
    ),
)
def add_member(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    user_id: Optional[int] = typer.Option(None, "--user-id"),
    group_id: Optional[int] = typer.Option(None, "--group-id"),
    roles: str = typer.Option(..., "--roles", help="Comma-separated role IDs."),
    json_mode: bool = typer.Option(False, "--json"),
):
    if (user_id is None) == (group_id is None):
        typer.echo("error: pass exactly one of --user-id or --group-id.", err=True)
        raise typer.Exit(code=2)
    c = _client(ctx)
    body: dict = {"role_ids": parse_id_list(roles)}
    body["user_id"] = user_id if user_id is not None else group_id
    obj = c.post(f"/projects/{project}/memberships.json",
                 json={"membership": body}).get("membership", {})
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"added membership (id={obj.get('id')})"
    )


@app.command(
    "update",
    help=(
        "Update an existing membership (replace roles).\n\n"
        "**Example:** `redmine member update 12 --roles 3,5`"
    ),
)
def update_member(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    roles: str = typer.Option(..., "--roles", help="Comma-separated role IDs."),
):
    c = _client(ctx)
    c.put(f"/memberships/{id}.json",
          json={"membership": {"role_ids": parse_id_list(roles)}})
    typer.echo(f"updated membership {id}")


@app.command(
    "remove",
    help="Remove a membership by ID.\n\n**Example:** `redmine member remove 12 -y`",
)
def remove_member(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really remove membership {id}?", abort=True)
    c.delete(f"/memberships/{id}.json")
    typer.echo(f"removed membership {id}")
