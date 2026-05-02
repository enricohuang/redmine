"""Root Typer app — wires global options and registers subcommands."""

from __future__ import annotations

from typing import Optional

import typer

from . import __version__
from .client import APIError, Client, die
from .config import AuthError, Credential, resolve

app = typer.Typer(
    add_completion=False,
    no_args_is_help=True,
    help="Command-line client for Redmine. Use `redmine auth login` to start.",
)


def _version_callback(value: bool):
    if value:
        typer.echo(f"redmine-cli {__version__}")
        raise typer.Exit()


@app.callback()
def _root(
    ctx: typer.Context,
    host: Optional[str] = typer.Option(None, "--host", help="Override configured host (e.g. redmine.example.com)."),
    user: Optional[str] = typer.Option(None, "--user", help="Override configured user label for the host."),
    version: Optional[bool] = typer.Option(
        None, "--version", callback=_version_callback, is_eager=True, help="Show version and exit."
    ),
):
    """Stash credential resolution into the Click context for subcommands.

    Subcommands that need API access call `get_client(ctx)` — auth subcommands skip it.
    """
    ctx.ensure_object(dict)
    ctx.obj["host_override"] = host
    ctx.obj["user_override"] = user


def get_credential(ctx: typer.Context) -> Credential:
    try:
        return resolve(ctx.obj.get("host_override"), ctx.obj.get("user_override"))
    except AuthError as e:
        die(str(e), code=4)


def get_client(ctx: typer.Context) -> Client:
    return Client(get_credential(ctx))


# ---- Subcommand registration ---------------------------------------------------
from .commands import (  # noqa: E402  (registration must follow app definition)
    auth,
    issue,
    project,
    wiki,
    journal,
    attachment,
    label,
    search,
    user as user_cmd,
)

app.add_typer(auth.app, name="auth", help="Manage Redmine credentials (multi-host).")
app.add_typer(issue.app, name="issue", help="Create, list, update, delete issues.")
app.add_typer(project.app, name="project", help="Manage projects.")
app.add_typer(wiki.app, name="wiki", help="Manage wiki pages.")
app.add_typer(journal.app, name="journal", help="Read and post issue comments (journals).")
app.add_typer(attachment.app, name="attachment", help="Upload, fetch, and download attachments.")
app.add_typer(label.app, name="label", help="Manage issue labels (fork feature).")
search.register(app)
app.add_typer(user_cmd.app, name="user", help="Look up users.")


def main():
    try:
        app(standalone_mode=True)
    except APIError as e:
        die(str(e), code=e.exit_code)
    except SystemExit:
        raise
    except KeyboardInterrupt:
        raise SystemExit(130)


if __name__ == "__main__":
    main()
