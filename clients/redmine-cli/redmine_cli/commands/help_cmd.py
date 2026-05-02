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
import subprocess
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

    Done by spawning subprocesses (`<argv0> ... --help`) so each node renders
    exactly as a user would see it. The alternative (rendering programmatically
    via click) drops the rich formatting and epilog.
    """
    argv0 = sys.argv[0]
    if not argv0 or not os.path.exists(argv0):
        # Shouldn't happen — typer entry points always set argv[0]
        argv0 = "redmine"

    # Lazy-import to avoid a cycle with cli.py.
    from ..cli import app as root_app

    paths = list(_iter_command_paths(root_app))
    for path in paths:
        header = "redmine " + " ".join(path) if path else "redmine"
        typer.echo("=" * 78)
        typer.echo(f"$ {header} --help")
        typer.echo("=" * 78)
        try:
            result = subprocess.run(
                [argv0, *path, "--help"],
                capture_output=True, text=True, timeout=20,
                env={**os.environ, "NO_COLOR": "1", "TERM": "dumb"},
            )
            sys.stdout.write(result.stdout)
            if result.stderr:
                sys.stderr.write(result.stderr)
        except Exception as e:  # pragma: no cover
            typer.echo(f"  (failed to invoke: {e})", err=True)
        typer.echo("")


def _iter_command_paths(app):
    """Yield ['issue'], ['issue','list'], ['issue','create'], ... for the whole tree.

    Uses click's reflection on the underlying app. Skips the dump command itself
    (no point) and the auth subtree's destructive forms aren't filtered — we
    want them visible in --help.
    """
    import click

    # Convert the typer.Typer to a click.Group via typer's machinery.
    from typer.main import get_command
    root = get_command(app)

    def walk(cmd: click.Command, path: list[str]):
        # Skip the root itself — we already print it explicitly first.
        if path:
            yield list(path)
        if isinstance(cmd, click.Group):
            for name, sub in sorted(cmd.commands.items()):
                # Skip recursing into 'help' itself to avoid the dump being included.
                if path == [] and name == "help":
                    yield ["help"]
                    continue
                yield from walk(sub, path + [name])

    # First yield the root --help
    yield []
    yield from walk(root, [])
