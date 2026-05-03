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
    # Markdown mode lets us render fenced code blocks verbatim in `help=`
    # text — which is what we want for shell examples. (Note: typer's epilog
    # rendering still collapses newlines regardless of mode, so examples go
    # in `help=`, not `epilog=`. See `redmine help` for tutorial-grade docs.)
    rich_markup_mode="markdown",
    help=(
        "Command-line client for Redmine.\n\n"
        "**Get started:**\n\n"
        "```\n"
        "redmine auth login --url <URL> --api-key <KEY>\n"
        "redmine issue list -p PROJECT\n"
        "redmine issue create -p PROJECT -s 'subject' --description-file body.md\n"
        "redmine wiki get -p PROJECT TITLE --text > page.md\n"
        "```\n\n"
        "**Discover more:**\n\n"
        "```\n"
        "redmine help               # list topic tutorials\n"
        "redmine help getting-started\n"
        "redmine help all           # full --help for every command in one shot\n"
        "redmine <cmd> --help       # individual command flags + examples\n"
        "```\n"
    ),
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
    help_cmd,
    user as user_cmd,
    # v2
    time as time_cmd,
    version as version_cmd,
    news,
    relation,
    category,
    member,
    webhook,
    bulk,
    group,
    ref,
    # v3 — additional resource coverage
    myaccount,
    board,
    message,
    document,
    file as file_cmd,
    reaction,
    activity,
    query,
    fulltext,
    import_cmd,
    repository,
    elasticsearch as elasticsearch_cmd,
)

# NOTE: do not pass `help=` to add_typer — that overrides the rich `help=`
# (with examples) set on each sub-Typer. Without it, the root `--help`
# command list falls back to the first line of each sub-Typer's help,
# which is exactly the short description we want.
app.add_typer(auth.app, name="auth")
app.add_typer(issue.app, name="issue")
app.add_typer(project.app, name="project")
app.add_typer(wiki.app, name="wiki")
app.add_typer(journal.app, name="journal")
app.add_typer(attachment.app, name="attachment")
app.add_typer(label.app, name="label")
search.register(app)
app.add_typer(user_cmd.app, name="user")

# v2: workflow
app.add_typer(time_cmd.app, name="time")
app.add_typer(version_cmd.app, name="version")
app.add_typer(news.app, name="news")
app.add_typer(relation.app, name="relation")
app.add_typer(category.app, name="category")
app.add_typer(member.app, name="member")

# v2: admin / fork
app.add_typer(webhook.app, name="webhook")
app.add_typer(bulk.app, name="bulk")
app.add_typer(group.app, name="group")

# v2: read-only reference data (handy for name -> ID lookup)
app.add_typer(ref.tracker_app, name="tracker")
app.add_typer(ref.status_app, name="status")
app.add_typer(ref.priority_app, name="priority")
app.add_typer(ref.enum_app, name="enumeration")
app.add_typer(ref.cf_app, name="custom-field")
app.add_typer(ref.role_app, name="role")

# v3: additional workflow + fork-only commands
app.add_typer(myaccount.app, name="myaccount")
app.add_typer(board.app, name="board")
app.add_typer(message.app, name="message")
app.add_typer(document.app, name="document")
app.add_typer(file_cmd.app, name="file")
app.add_typer(reaction.app, name="reaction")
app.add_typer(activity.app, name="activity")
app.add_typer(query.app, name="query")
app.add_typer(fulltext.app, name="fulltext")
app.add_typer(import_cmd.app, name="import")
app.add_typer(repository.app, name="repository")
app.add_typer(elasticsearch_cmd.app, name="elasticsearch")

help_cmd.register(app)


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
