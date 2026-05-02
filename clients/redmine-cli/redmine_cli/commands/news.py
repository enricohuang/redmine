"""`redmine news ...` — project news / announcements."""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import typer

from ..output import emit_list, emit_object
from ._helpers import read_text_input

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Project news (announcements).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine news list -p mobile\n"
        "redmine news create -p mobile --title 'v2.0 shipped' --description-file announce.md\n"
        "redmine news delete 5 -y\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help=(
        "List news. Project-scoped if `-p` given, otherwise global.\n\n"
        "**Example:** `redmine news list -p mobile --json | jq '.[].title'`"
    ),
)
def list_news(
    ctx: typer.Context,
    project: Optional[str] = typer.Option(None, "-p", "--project"),
    limit: int = typer.Option(25, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    path = f"/projects/{project}/news.json" if project else "/news.json"
    if all_pages:
        items = list(c.paginate(path, key="news", page_size=limit))
    else:
        items = c.get(path, limit=limit).get("news", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Project", "project.name"),
                 ("Title", "title"), ("Author", "author.name"),
                 ("Created", "created_on")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help="Fetch a single news entry.\n\n**Example:** `redmine news get 5 --json`",
)
def get_news(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    include: Optional[str] = typer.Option("attachments,comments", "--include"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    params = {"include": include} if include else {}
    obj = c.get(f"/news/{id}.json", **params).get("news", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Post a news entry to a project.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine news create -p mobile --title 'v2.0 shipped' --description 'Big release!'\n"
        "redmine news create -p mobile --title 'Roadmap' --description-file roadmap.md\n"
        "```"
    ),
)
def create_news(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    title: str = typer.Option(..., "--title"),
    description: Optional[str] = typer.Option(None, "--description"),
    description_file: Optional[Path] = typer.Option(None, "--description-file"),
    summary: Optional[str] = typer.Option(None, "--summary"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    desc = read_text_input(description, description_file, name="description")
    if desc is None:
        typer.echo("error: provide --description or --description-file.", err=True)
        raise typer.Exit(code=2)
    body: dict = {"title": title, "description": desc}
    if summary: body["summary"] = summary
    # Redmine's POST /projects/:id/news.json returns 204 No Content, so we
    # can't read back the created object directly. Look it up afterwards by
    # listing the project's news and matching on title (newest wins).
    c.post(f"/projects/{project}/news.json", json={"news": body})
    listed = c.get(f"/projects/{project}/news.json", limit=10).get("news", [])
    obj = next((n for n in listed if n.get("title") == title), {})
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"created news '{title}' (id={obj.get('id')})"
    )


@app.command(
    "update",
    help="Update a news entry.\n\n**Example:** `redmine news update 5 --title 'Edited'`",
)
def update_news(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    title: Optional[str] = typer.Option(None, "--title"),
    description: Optional[str] = typer.Option(None, "--description"),
    description_file: Optional[Path] = typer.Option(None, "--description-file"),
    summary: Optional[str] = typer.Option(None, "--summary"),
):
    c = _client(ctx)
    desc = read_text_input(description, description_file, name="description")
    body: dict = {}
    if title is not None: body["title"] = title
    if desc is not None: body["description"] = desc
    if summary is not None: body["summary"] = summary
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/news/{id}.json", json={"news": body})
    typer.echo(f"updated news {id}")


@app.command(
    "delete",
    help="Delete a news entry. Prompts unless `-y`.",
)
def delete_news(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete news {id}?", abort=True)
    c.delete(f"/news/{id}.json")
    typer.echo(f"deleted news {id}")
