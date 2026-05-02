"""`redmine help` — topic-based help and recursive --help dump.

Designed for AI agents:
- `redmine help`              lists topics and how to discover more
- `redmine help <topic>`      prints a focused tutorial
- `redmine help all`          recursively dumps --help for every (sub)command,
                              so an agent can read the full CLI surface in
                              one Bash call instead of N

Each topic is a self-contained reference. See `help_text.py` for content.
"""

from __future__ import annotations

import os
import sys
from typing import Optional

import typer

from ..help_text import SUMMARIES, TOPICS


def register(parent: typer.Typer) -> None:
    """Attach `help` as a single command on the parent app."""

    @parent.command(
        "help",
        help=("Topic-based help. `redmine help` lists topics; "
              "`redmine help <topic>` prints a tutorial; "
              "`redmine help all` dumps every command's --help."),
        epilog=(
            "Topics: " + " ".join(sorted(TOPICS)) + "\n\n"
            "Examples:\n"
            "  redmine help                 # list topics + discovery patterns\n"
            "  redmine help getting-started # a 1-screen orientation\n"
            "  redmine help wiki            # wiki workflows + fork endpoints\n"
            "  redmine help all             # full --help for every command"
        ),
    )
    def help_cmd(
        topic: Optional[str] = typer.Argument(
            None,
            help=("Topic name (e.g. 'wiki'), or 'all' to recursively dump "
                  "--help for every command. Omit to list topics."),
            metavar="[TOPIC]",
        ),
    ):
        if topic is None:
            _list_topics()
            return
        if topic == "all":
            _dump_all_help()
            return
        if topic not in TOPICS:
            typer.echo(f"unknown topic: {topic}", err=True)
            typer.echo(
                "Available: " + ", ".join(sorted(TOPICS)) + ", all",
                err=True,
            )
            raise typer.Exit(code=2)
        typer.echo(TOPICS[topic])


def _list_topics() -> None:
    typer.echo(
        "Topic-based help for the redmine CLI.\n\n"
        "Usage:\n"
        "  redmine help <topic>     focused tutorial\n"
        "  redmine help all         recursively dumps --help for every command\n"
        "  redmine <cmd> --help     individual command, with examples in epilog\n"
    )
    typer.echo("Topics:\n")
    for name in sorted(TOPICS):
        typer.echo(f"  {name:<18} {SUMMARIES.get(name, '')}")
    typer.echo(
        "\nNew here? Try: redmine help getting-started\n"
        "Working with an unfamiliar resource? Try: redmine help all"
    )


def _dump_all_help() -> None:
    """Walk the click command tree and print `--help` for every node.

    Renders in-process via click's get_help() (no subprocess per command).
    The CLI grew big enough — 32 top-level commands × ~6 subcommands each ≈
    200 nodes — that subprocess-per-node took >60s. In-process is ~150x
    faster and produces functionally equivalent output (same formatter,
    same panels), at the cost of using the current TTY width instead of
    re-resolving it for each child invocation.
    """
    import click
    from typer.main import get_command

    # Lazy-import to avoid a cycle with cli.py.
    from ..cli import app as root_app
    root = get_command(root_app)

    # Force consistent width and disable color so output is deterministic and
    # pipeable. Using a real terminal width here would make the dump depend on
    # the caller's window size, which is bad for `redmine help all > file`.
    os.environ.setdefault("NO_COLOR", "1")

    def render(cmd: click.Command, path: list[str]) -> None:
        header = "redmine " + " ".join(path) if path else "redmine"
        sys.stdout.write("=" * 78 + "\n")
        sys.stdout.write(f"$ {header} --help\n")
        sys.stdout.write("=" * 78 + "\n")
        info_name = "redmine" if not path else path[-1]
        with click.Context(cmd, info_name=info_name, parent=None,
                           terminal_width=78, max_content_width=78) as ctx:
            sys.stdout.write(cmd.get_help(ctx))
        sys.stdout.write("\n\n")

    def walk(cmd: click.Command, path: list[str]) -> None:
        if path:  # skip rendering root again; we did it first
            render(cmd, path)
        if isinstance(cmd, click.Group):
            for name, sub in sorted(cmd.commands.items()):
                # Don't recurse into 'help' itself (would re-emit this dump).
                if path == [] and name == "help":
                    render(sub, ["help"])
                    continue
                walk(sub, path + [name])

    render(root, [])
    walk(root, [])


