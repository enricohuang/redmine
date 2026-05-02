"""`redmine document ...` — project documents."""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import typer

from ..output import emit_list, emit_object
from ._helpers import read_text_input

app = typer.Typer(
    no_args_is_help=True,
    rich_markup_mode="markdown",
    help=(
        "Project documents (file-bearing knowledge base entries).\n\n"
        "Documents are scoped to a project and grouped by a category from the "
        "`document_categories` enumeration. Each document carries any number "
        "of attachments.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine document list -p mobile\n"
        "redmine document create -p mobile --category 'User documentation' \\\n"
        "    --title 'Onboarding guide' --description-file onboarding.md\n"
        "redmine document get 12 --include attachments\n"
        "redmine document attach ./diagram.png --document 12 --description 'arch overview'\n"
        "redmine document delete 12 -y\n"
        "```\n\n"
        "List available categories with `redmine enumeration list document_categories`."
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


def _resolve_category(c, value: Optional[str]):
    """Document-category id from name (case-insensitive); IDs pass through."""
    if value is None or str(value).isdigit():
        return value
    items = c.get("/enumerations/document_categories.json").get(
        "document_categories", []
    )
    for item in items:
        if item.get("name", "").lower() == value.lower():
            return int(item["id"])
    valid = ", ".join(repr(i.get("name")) for i in items)
    typer.echo(f"unknown document category '{value}'. Valid: {valid}", err=True)
    raise typer.Exit(code=3)


@app.command(
    "list",
    help=(
        "List documents in a project.\n\n"
        "**Example:** `redmine document list -p mobile --json | jq '.[].title'`"
    ),
)
def list_documents(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    limit: int = typer.Option(25, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    path = f"/projects/{project}/documents.json"
    if all_pages:
        items = list(c.paginate(path, key="documents", page_size=limit))
    else:
        items = c.get(path, limit=limit).get("documents", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Project", "project.name"),
                 ("Category", "category.name"), ("Title", "title"),
                 ("Created", "created_on")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help=(
        "Fetch a single document. Attachments are included automatically when "
        "the document has any.\n\n"
        "**Example:** `redmine document get 12 --include attachments --json`"
    ),
)
def get_document(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    include: Optional[str] = typer.Option("attachments", "--include"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    params = {"include": include} if include else {}
    obj = c.get(f"/documents/{id}.json", **params).get("document", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Create a new document in a project.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine document create -p mobile --category 'User documentation' \\\n"
        "    --title 'Onboarding guide' --description 'Quick setup notes.'\n"
        "redmine document create -p mobile --category 6 \\\n"
        "    --title 'Architecture' --description-file arch.md\n"
        "```\n\n"
        "`--category` accepts the category name (case-insensitive) or numeric id."
    ),
)
def create_document(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    category: str = typer.Option(..., "--category", help="Category name or numeric id."),
    title: str = typer.Option(..., "--title"),
    description: Optional[str] = typer.Option(None, "--description"),
    description_file: Optional[Path] = typer.Option(None, "--description-file"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    cat_id = _resolve_category(c, category)
    desc = read_text_input(description, description_file, name="description")
    body: dict = {"category_id": int(cat_id), "title": title}
    if desc is not None:
        body["description"] = desc
    # POST returns 204 No Content; re-fetch by listing and matching on title.
    c.post(f"/projects/{project}/documents.json", json={"document": body})
    listed = c.get(f"/projects/{project}/documents.json", limit=25).get("documents", [])
    obj = next((d for d in listed if d.get("title") == title), {})
    if json_mode:
        emit_object(obj, json_mode=True)
    else:
        typer.echo(f"created document '{title}' (id={obj.get('id')})")


@app.command(
    "update",
    help=(
        "Update a document's category, title, and/or description.\n\n"
        "**Example:** `redmine document update 12 --title 'New title'`"
    ),
)
def update_document(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    category: Optional[str] = typer.Option(None, "--category", help="Category name or numeric id."),
    title: Optional[str] = typer.Option(None, "--title"),
    description: Optional[str] = typer.Option(None, "--description"),
    description_file: Optional[Path] = typer.Option(None, "--description-file"),
):
    c = _client(ctx)
    desc = read_text_input(description, description_file, name="description")
    body: dict = {}
    if category is not None:
        body["category_id"] = int(_resolve_category(c, category))
    if title is not None:
        body["title"] = title
    if desc is not None:
        body["description"] = desc
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/documents/{id}.json", json={"document": body})
    typer.echo(f"updated document {id}")


@app.command(
    "delete",
    help="Delete a document. Prompts unless `-y`.",
)
def delete_document(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete document {id}?", abort=True)
    c.delete(f"/documents/{id}.json")
    typer.echo(f"deleted document {id}")


@app.command(
    "attach",
    help=(
        "Upload a file and attach it to an existing document.\n\n"
        "Two-step under the hood: POST `/uploads.json` to obtain a token, then "
        "PUT the document with the token in `uploads:`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine document attach ./diagram.png --document 12\n"
        "redmine document attach ./spec.pdf --document 12 --description 'v2 draft'\n"
        "```"
    ),
)
def attach_to_document(
    ctx: typer.Context,
    file: Path = typer.Argument(..., exists=True, dir_okay=False, readable=True),
    document: int = typer.Option(..., "--document", help="Document ID to attach to."),
    description: Optional[str] = typer.Option(None, "--description"),
    content_type: Optional[str] = typer.Option(None, "--content-type"),
):
    c = _client(ctx)
    fname = file.name
    body = file.read_bytes()
    upload_resp = c.request(
        "POST", f"/uploads.json?filename={fname}",
        data=body,
        headers={"Content-Type": "application/octet-stream"},
    )
    token = upload_resp["upload"]["token"]
    upload_entry: dict = {"token": token, "filename": fname}
    if description:
        upload_entry["description"] = description
    if content_type:
        upload_entry["content_type"] = content_type
    c.put(f"/documents/{document}.json",
          json={"document": {"uploads": [upload_entry]}})
    typer.echo(f"attached {fname} to document {document}")
