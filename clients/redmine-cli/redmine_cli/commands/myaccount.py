"""`redmine myaccount ...` — view and update the active user's own account.

Wraps `/my/account.json`. Unlike `redmine user get current`, this also exposes
the writable side of the endpoint — handy for fixing your own email or display
name without needing admin on `/users/:id`.
"""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_object

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "View and update the active user's own account (`/my/account.json`).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine myaccount get\n"
        "redmine myaccount get --json | jq '.api_key'\n"
        "redmine myaccount update --mail me@new-domain.com\n"
        "redmine myaccount update --firstname Alice --lastname Smithe\n"
        "```\n\n"
        "Unlike `redmine user update`, this does not require admin — every "
        "user can edit their own account."
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "get",
    help=(
        "Show the current user's account settings (including api_key).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine myaccount get\n"
        "redmine myaccount get --json | jq '{login, mail, api_key}'\n"
        "```"
    ),
)
def get_account(
    ctx: typer.Context,
    json_mode: bool = typer.Option(False, "--json"),
):
    """Show the current user's account settings."""
    c = _client(ctx)
    data = c.get("/my/account.json").get("user", {})
    if json_mode:
        emit_object(data, json_mode=True)
        return
    fields = ["id", "login", "firstname", "lastname", "mail", "admin",
              "language", "mail_notification", "created_on", "last_login_on",
              "api_key"]
    emit_object({f: data.get(f) for f in fields if f in data}, json_mode=False)


@app.command(
    "update",
    help=(
        "Update the current user's account. At least one field is required.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine myaccount update --mail me@new-domain.com\n"
        "redmine myaccount update --firstname Alice --lastname Smithe\n"
        "redmine myaccount update --language fr\n"
        "redmine myaccount update --mail-notification only_my_events\n"
        "```\n\n"
        "`--mail-notification` accepts: `all`, `selected`, `only_my_events`, "
        "`only_assigned`, `only_owner`, `none`."
    ),
)
def update_account(
    ctx: typer.Context,
    firstname: Optional[str] = typer.Option(None, "--firstname"),
    lastname: Optional[str] = typer.Option(None, "--lastname"),
    mail: Optional[str] = typer.Option(None, "--mail"),
    language: Optional[str] = typer.Option(None, "--language", help="Language code (e.g. en, fr, ja)."),
    mail_notification: Optional[str] = typer.Option(
        None, "--mail-notification",
        help="all, selected, only_my_events, only_assigned, only_owner, none.",
    ),
):
    """Update the current user's account."""
    c = _client(ctx)
    body: dict = {}
    if firstname is not None: body["firstname"] = firstname
    if lastname is not None: body["lastname"] = lastname
    if mail is not None: body["mail"] = mail
    if language is not None: body["language"] = language
    if mail_notification is not None: body["mail_notification"] = mail_notification
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put("/my/account.json", json={"user": body})
    typer.echo("updated my account")
