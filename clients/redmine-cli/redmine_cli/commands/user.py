"""`redmine user ...` — read-only user lookup (v1)."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Look up and manage users. Listing and write operations require admin "
        "on stock Redmine.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine user get current               # the active credential\n"
        "redmine user list --name alice\n"
        "redmine user get 7 --json\n"
        "redmine user create --login alice --firstname Alice --lastname Smith \\\n"
        "                    --mail alice@example.com --generate-password --send-information\n"
        "redmine user update 7 --mail new@example.com\n"
        "redmine user delete 7 -y\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help=(
        "List users (admin only on stock Redmine).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine user list --name alice\n"
        "redmine user list --status 1 --all --json | jq '.[] | {id, login}'\n"
        "```\n\n"
        "Status: `1`=active, `2`=registered (pending), `3`=locked."
    ),
)
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


@app.command(
    "get",
    help=(
        "Get a user by ID, or pass `current` to look up the active credential.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine user get current               # who am I?\n"
        "redmine user get 7\n"
        "redmine user get 7 --include memberships,groups --json\n"
        "```"
    ),
)
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


@app.command(
    "create",
    help=(
        "Create a user account (admin only).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine user create --login alice --firstname Alice --lastname Smith \\\n"
        "                    --mail alice@example.com --password 'TempPa55!'\n"
        "redmine user create --login bob --firstname Bob --lastname Lee \\\n"
        "                    --mail bob@example.com --generate-password --send-information\n"
        "redmine user create --login svc --firstname Service --lastname Bot \\\n"
        "                    --mail svc@example.com --admin --no-mail-notification\n"
        "```\n\n"
        "`--mail-notification` accepts: `all`, `selected`, `only_my_events`, "
        "`only_assigned`, `only_owner`, `none`."
    ),
)
def create_user(
    ctx: typer.Context,
    login: str = typer.Option(..., "--login"),
    firstname: str = typer.Option(..., "--firstname"),
    lastname: str = typer.Option(..., "--lastname"),
    mail: str = typer.Option(..., "--mail"),
    password: Optional[str] = typer.Option(None, "--password", help="Initial password (omit to require generation)."),
    admin: bool = typer.Option(False, "--admin", help="Grant administrator privileges."),
    auth_source_id: Optional[int] = typer.Option(None, "--auth-source-id", help="External auth source ID."),
    mail_notification: Optional[str] = typer.Option(
        None, "--mail-notification",
        help="all, selected, only_my_events, only_assigned, only_owner, none.",
    ),
    must_change_passwd: Optional[bool] = typer.Option(
        None, "--must-change-passwd/--no-must-change-passwd",
        help="Force password change on first login.",
    ),
    generate_password: Optional[bool] = typer.Option(
        None, "--generate-password/--no-generate-password",
        help="Server generates a random password.",
    ),
    send_information: bool = typer.Option(
        False, "--send-information",
        help="Email the new user their account details (top-level form param).",
    ),
    json_mode: bool = typer.Option(False, "--json"),
):
    """Create a user account (admin only)."""
    c = _client(ctx)
    user_body: dict = {
        "login": login,
        "firstname": firstname,
        "lastname": lastname,
        "mail": mail,
    }
    if password is not None: user_body["password"] = password
    if admin: user_body["admin"] = True
    if auth_source_id is not None: user_body["auth_source_id"] = auth_source_id
    if mail_notification is not None: user_body["mail_notification"] = mail_notification
    if must_change_passwd is not None: user_body["must_change_passwd"] = must_change_passwd
    if generate_password is not None: user_body["generate_password"] = generate_password
    body: dict = {"user": user_body}
    if send_information: body["send_information"] = True
    data = c.post("/users.json", json=body)
    obj = data.get("user", data)
    if json_mode:
        emit_object(obj, json_mode=True)
    else:
        emit_object({k: obj.get(k) for k in ("id", "login", "firstname", "lastname", "mail")},
                    json_mode=False)


@app.command(
    "update",
    help=(
        "Update a user account (admin only). At least one field is required.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine user update 7 --mail new@example.com\n"
        "redmine user update 7 --firstname Alicia --lastname Smithe\n"
        "redmine user update 7 --admin --must-change-passwd\n"
        "```"
    ),
)
def update_user(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    login: Optional[str] = typer.Option(None, "--login"),
    firstname: Optional[str] = typer.Option(None, "--firstname"),
    lastname: Optional[str] = typer.Option(None, "--lastname"),
    mail: Optional[str] = typer.Option(None, "--mail"),
    password: Optional[str] = typer.Option(None, "--password"),
    admin: Optional[bool] = typer.Option(None, "--admin/--no-admin"),
    auth_source_id: Optional[int] = typer.Option(None, "--auth-source-id"),
    mail_notification: Optional[str] = typer.Option(None, "--mail-notification"),
    must_change_passwd: Optional[bool] = typer.Option(
        None, "--must-change-passwd/--no-must-change-passwd",
    ),
    generate_password: Optional[bool] = typer.Option(
        None, "--generate-password/--no-generate-password",
    ),
    send_information: bool = typer.Option(
        False, "--send-information",
        help="Email the user about the change (top-level form param).",
    ),
):
    """Update a user account (admin only)."""
    c = _client(ctx)
    user_body: dict = {}
    if login is not None: user_body["login"] = login
    if firstname is not None: user_body["firstname"] = firstname
    if lastname is not None: user_body["lastname"] = lastname
    if mail is not None: user_body["mail"] = mail
    if password is not None: user_body["password"] = password
    if admin is not None: user_body["admin"] = admin
    if auth_source_id is not None: user_body["auth_source_id"] = auth_source_id
    if mail_notification is not None: user_body["mail_notification"] = mail_notification
    if must_change_passwd is not None: user_body["must_change_passwd"] = must_change_passwd
    if generate_password is not None: user_body["generate_password"] = generate_password
    if not user_body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    body: dict = {"user": user_body}
    if send_information: body["send_information"] = True
    c.put(f"/users/{id}.json", json=body)
    typer.echo(f"updated user {id}")


@app.command(
    "delete",
    help=(
        "Delete a user account (admin only) — **irreversible**. The user's "
        "issues, comments, and time entries are reassigned to an anonymous "
        "user; their account is gone for good. Prompts unless `-y`.\n\n"
        "**Example:** `redmine user delete 7 -y`"
    ),
)
def delete_user(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    """Delete a user account (admin only, irreversible)."""
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete user {id}? This is permanent.", abort=True)
    c.delete(f"/users/{id}.json")
    typer.echo(f"deleted user {id}")
