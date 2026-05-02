"""`redmine wiki ...` — wiki page CRUD plus fork-only history/rename/protect."""

from __future__ import annotations

import sys
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
def list_pages(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project", help="Project ID or identifier."),
    limit: int = typer.Option(100, "--limit"),
    all_pages: bool = typer.Option(True, "--all/--no-all", help="Fetch all pages."),
    json_mode: bool = typer.Option(False, "--json"),
):
    """List wiki pages in a project."""
    c = _client(ctx)
    if all_pages:
        items = list(c.paginate(f"/projects/{project}/wiki/index.json",
                                key="wiki_pages", page_size=limit))
    else:
        items = c.get(f"/projects/{project}/wiki/index.json", limit=limit).get("wiki_pages", [])
    emit_list(
        items,
        columns=[("Title", "title"), ("Parent", "parent.title"),
                 ("Version", "version"), ("Updated", "updated_on")],
        json_mode=json_mode,
    )


@app.command("get")
def get_page(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    title: str = typer.Argument(..., help="Page title (URL-safe form expected by Redmine)."),
    version: Optional[int] = typer.Option(None, "--version", help="Fetch a specific historical version."),
    include: Optional[str] = typer.Option(None, "--include", help="e.g. attachments"),
    text_only: bool = typer.Option(False, "--text", help="Print only the page body to stdout."),
    json_mode: bool = typer.Option(False, "--json"),
):
    """Get a wiki page. Use --text to print the markdown body only (good for piping to a file)."""
    c = _client(ctx)
    path = f"/projects/{project}/wiki/{title}"
    if version is not None:
        path = f"{path}/{version}"
    path = path + ".json"
    params = {"include": include} if include else {}
    data = c.get(path, **params)
    page = data.get("wiki_page", data)
    if text_only:
        sys.stdout.write(page.get("text") or "")
        if not (page.get("text") or "").endswith("\n"):
            sys.stdout.write("\n")
        return
    if json_mode:
        emit_object(page, json_mode=True)
        return
    emit_object(
        {k: page.get(k) for k in
         ("title", "parent", "version", "author", "comments", "protected",
          "created_on", "updated_on", "text")},
        json_mode=False,
    )


@app.command("update")
def update_page(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    title: str = typer.Argument(...),
    text: Optional[str] = typer.Option(None, "--text", help="Inline body (or '-' for stdin)."),
    file: Optional[Path] = typer.Option(None, "--file", help="Path to body file."),
    parent_title: Optional[str] = typer.Option(None, "--parent-title"),
    comment: Optional[str] = typer.Option(None, "--comment", help="Edit comment."),
    expected_version: Optional[int] = typer.Option(
        None, "--expected-version", help="Optimistic locking — must match current version."),
):
    """Create or update a wiki page (PUT)."""
    c = _client(ctx)
    body_text = read_text_input(text, file, name="text")
    if body_text is None:
        typer.echo("error: provide --text or --file (use '-' for stdin).", err=True)
        raise typer.Exit(code=2)
    page: dict = {"text": body_text}
    if parent_title is not None: page["parent_title"] = parent_title
    if comment is not None: page["comments"] = comment
    if expected_version is not None: page["version"] = expected_version
    c.put(f"/projects/{project}/wiki/{title}.json", json={"wiki_page": page})
    typer.echo(f"saved {project}/{title}")


@app.command("delete")
def delete_page(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    title: str = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete wiki page {project}/{title}?", abort=True)
    c.delete(f"/projects/{project}/wiki/{title}.json")
    typer.echo(f"deleted {project}/{title}")


# ---- Fork-specific endpoints --------------------------------------------------

@app.command("history")
def history(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    title: str = typer.Argument(...),
    limit: int = typer.Option(25, "--limit"),
    json_mode: bool = typer.Option(False, "--json"),
):
    """List historical versions for a page (fork endpoint).

    Pagination is controlled server-side via limit/offset; the response is wrapped
    as `{"wiki_page": {"versions": [...], "total_count": N}}`.
    """
    c = _client(ctx)
    data = c.get(f"/projects/{project}/wiki/{title}/history.json", limit=limit)
    items = data.get("wiki_page", {}).get("versions", [])
    emit_list(
        items,
        columns=[("Version", "version_number"), ("Author", "author.name"),
                 ("Comments", "comments"), ("Updated", "updated_on")],
        json_mode=json_mode,
    )


@app.command("rename")
def rename(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    title: str = typer.Argument(..., help="Current title."),
    new_title: str = typer.Option(..., "--to", help="New title."),
    redirect: bool = typer.Option(True, "--redirect/--no-redirect",
                                  help="Leave a redirect at the old title."),
    new_parent: Optional[str] = typer.Option(None, "--new-parent",
                                             help="Optional new parent title."),
):
    """Rename a wiki page (fork endpoint)."""
    c = _client(ctx)
    page: dict = {"title": new_title, "redirect_existing_links": redirect}
    if new_parent is not None:
        page["parent_title"] = new_parent
    c.post(f"/projects/{project}/wiki/{title}/rename.json", json={"wiki_page": page})
    typer.echo(f"{project}/{title} -> {project}/{new_title}")


@app.command("protect")
def protect(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    title: str = typer.Argument(...),
    on: bool = typer.Option(True, "--on/--off", help="Toggle protection."),
):
    """Protect or unprotect a wiki page (fork endpoint)."""
    c = _client(ctx)
    c.post(f"/projects/{project}/wiki/{title}/protect.json",
           json={"protected": "1" if on else "0"})
    typer.echo(f"{project}/{title} protected={on}")
