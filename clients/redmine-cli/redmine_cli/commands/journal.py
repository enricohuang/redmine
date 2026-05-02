"""`redmine journal ...` — issue comments via the fork's Journals API."""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import typer

from ..output import emit_list, emit_object
from ._helpers import read_text_input

app = typer.Typer(no_args_is_help=True)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command("list")
def list_journals(
    ctx: typer.Context,
    issue: int = typer.Option(..., "-i", "--issue"),
    limit: int = typer.Option(50, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    """List comments/journals for an issue."""
    c = _client(ctx)
    path = f"/issues/{issue}/journals.json"
    if all_pages:
        items = list(c.paginate(path, key="journals", page_size=limit))
    else:
        items = c.get(path, limit=limit).get("journals", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("User", "user.name"),
                 ("Created", "created_on"), ("Notes", "notes"),
                 ("Private", "private_notes")],
        json_mode=json_mode,
    )


@app.command("get")
def get_journal(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    """Get a single journal."""
    c = _client(ctx)
    data = c.get(f"/journals/{id}.json")
    j = data.get("journal", data)
    if json_mode:
        emit_object(j, json_mode=True)
        return
    emit_object(
        {k: j.get(k) for k in ("id", "user", "created_on", "private_notes", "notes", "details")},
        json_mode=False,
    )


@app.command("create")
def create_journal(
    ctx: typer.Context,
    issue: int = typer.Option(..., "-i", "--issue"),
    note: Optional[str] = typer.Option(None, "-n", "--note", help="Comment text (or '-' for stdin)."),
    file: Optional[Path] = typer.Option(None, "--file"),
    private: bool = typer.Option(False, "--private", help="Mark as private notes."),
    json_mode: bool = typer.Option(False, "--json"),
):
    """Add a comment to an issue (uses fork journal endpoint)."""
    c = _client(ctx)
    body_text = read_text_input(note, file, name="note")
    if not body_text:
        typer.echo("error: provide --note or --file.", err=True)
        raise typer.Exit(code=2)
    body = {"notes": body_text, "private_notes": private}
    data = c.post(f"/issues/{issue}/journals.json", json={"journal": body})
    j = data.get("journal", data)
    if json_mode:
        emit_object(j, json_mode=True)
    else:
        typer.echo(f"comment added to #{issue} (journal id={j.get('id')})")


@app.command("update")
def update_journal(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    note: Optional[str] = typer.Option(None, "-n", "--note"),
    file: Optional[Path] = typer.Option(None, "--file"),
    private: Optional[bool] = typer.Option(None, "--private/--public"),
):
    """Edit an existing comment."""
    c = _client(ctx)
    body_text = read_text_input(note, file, name="note")
    body: dict = {}
    if body_text is not None: body["notes"] = body_text
    if private is not None: body["private_notes"] = private
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/journals/{id}.json", json={"journal": body})
    typer.echo(f"updated journal {id}")
