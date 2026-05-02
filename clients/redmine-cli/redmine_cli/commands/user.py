"""`redmine user ...` — read-only user lookup (v1)."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object

app = typer.Typer(no_args_is_help=True)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command("list")
def list_users(
    ctx: typer.Context,
    name: Optional[str] = typer.Option(None, "--name", help="Substring filter on name/login/email."),
    status: Optional[int] = typer.Option(None, "--status", help="1 active, 2 registered, 3 locked."),
    group_id: Optional[int] = typer.Option(None, "--group-id"),
    limit: int = typer.Option(25, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    """List users (admin only on stock Redmine)."""
    c = _client(ctx)
    params: dict = {}
    if name: params["name"] = name
    if status: params["status"] = status
    if group_id: params["group_id"] = group_id
    if all_pages:
        items = list(c.paginate("/users.json", key="users", page_size=limit, **params))
    else:
        params["limit"] = limit
        items = c.get("/users.json", **params).get("users", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Login", "login"), ("Name", "firstname"),
                 ("Last", "lastname"), ("Mail", "mail")],
        json_mode=json_mode,
    )


@app.command("get")
def get_user(
    ctx: typer.Context,
    id: str = typer.Argument(..., help="User ID, or 'current' for the active credential."),
    include: Optional[str] = typer.Option("memberships,groups", "--include"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    params = {"include": include} if include else {}
    data = c.get(f"/users/{id}.json", **params).get("user", {})
    if json_mode:
        emit_object(data, json_mode=True)
        return
    fields = ["id", "login", "firstname", "lastname", "mail", "admin",
              "created_on", "last_login_on", "memberships", "groups"]
    emit_object({f: data.get(f) for f in fields if f in data}, json_mode=False)
