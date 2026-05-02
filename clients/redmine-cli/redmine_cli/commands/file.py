"""`redmine file ...` — project files (project- or version-scoped uploads)."""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import typer

from ..output import emit_list, emit_object

app = typer.Typer(
    no_args_is_help=True,
    rich_markup_mode="markdown",
    help=(
        "Project / version files. The `Files` project module must be enabled.\n\n"
        "Internally each file is an attachment metadata record bound to either "
        "the project root or to a specific version. `upload` is a two-step API: "
        "POST `/uploads.json` for a token, then POST the project's files endpoint "
        "with that token.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine file list -p mobile\n"
        "redmine file upload ./release.zip -p mobile --description 'v2.0 build'\n"
        "redmine file upload ./hotfix.zip -p mobile --version 7\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help=(
        "List files attached to a project (and its versions).\n\n"
        "**Example:** `redmine file list -p mobile --json | jq '.[].filename'`"
    ),
)
def list_files(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    items = c.get(f"/projects/{project}/files.json").get("files", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Filename", "filename"),
                 ("Size", "filesize"), ("Type", "content_type"),
                 ("Description", "description"), ("Version", "version.name"),
                 ("Created", "created_on")],
        json_mode=json_mode,
    )


@app.command(
    "upload",
    help=(
        "Upload a file to a project (or a project version). Two-step under the "
        "hood: POST `/uploads.json` for a token, then POST the project's files "
        "endpoint with the token, filename and optional metadata.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine file upload ./release.zip -p mobile --description 'v2.0 build'\n"
        "redmine file upload ./hotfix.zip -p mobile --version 7\n"
        "```"
    ),
)
def upload_file(
    ctx: typer.Context,
    file: Path = typer.Argument(..., exists=True, dir_okay=False, readable=True),
    project: str = typer.Option(..., "-p", "--project"),
    version: Optional[int] = typer.Option(None, "--version", help="Attach to this version ID instead of the project root."),
    description: Optional[str] = typer.Option(None, "--description"),
    content_type: Optional[str] = typer.Option(None, "--content-type"),
    json_mode: bool = typer.Option(False, "--json"),
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
    file_payload: dict = {"token": token, "filename": fname}
    if version is not None:
        file_payload["version_id"] = version
    if description:
        file_payload["description"] = description
    if content_type:
        file_payload["content_type"] = content_type
    # POST returns 204 No Content; re-fetch by listing and matching on filename.
    c.post(f"/projects/{project}/files.json", json={"file": file_payload})
    listed = c.get(f"/projects/{project}/files.json").get("files", [])
    obj = next((f for f in reversed(listed) if f.get("filename") == fname), {})
    if json_mode:
        emit_object(obj, json_mode=True)
    else:
        typer.echo(f"uploaded {fname} to project {project} (id={obj.get('id')})")
