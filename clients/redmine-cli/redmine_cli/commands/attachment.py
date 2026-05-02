"""`redmine attachment ...` — upload, fetch metadata, download.

Redmine attachments are a two-step API:
  1. POST /uploads.json with the file body -> get a `token`.
  2. Use the token in `uploads:` array on issue/wiki/etc create/update calls.

This command exposes both a low-level `upload` (returns the token) and
high-level `attach` (uploads then attaches to an issue in one call).
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Optional

import typer

from ..output import emit_object

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Upload, fetch, and download attachments. The Redmine API is two-step "
        "(upload → token, then attach token to issue/wiki); this CLI exposes "
        "both the high-level `attach` and low-level `upload`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine attachment attach ./screenshot.png -i 1234 --description 'before'\n"
        "redmine attachment upload ./big.zip                # returns token\n"
        "redmine attachment download 42 -o ./downloaded.bin\n"
        "redmine attachment update 42 --description 'after'\n"
        "redmine attachment thumbnail 42 -o thumb.png --size 64\n"
        "redmine attachment delete 42 -y\n"
        "```\n\n"
        "Tutorial: `redmine help attachments`"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "upload",
    help=(
        "Upload a file and print the resulting upload token. The token can "
        "then be passed in `uploads:` arrays on issue/wiki create or update "
        "calls (useful for ad-hoc `curl` workflows).\n\n"
        "Most users want `redmine attachment attach` instead, which uploads "
        "**and** attaches in one shot.\n\n"
        "**Example:** `redmine attachment upload ./big.zip --json`"
    ),
)
def upload(
    ctx: typer.Context,
    file: Path = typer.Argument(..., exists=True, dir_okay=False, readable=True),
    filename: Optional[str] = typer.Option(None, "--filename", help="Override filename sent to server."),
    json_mode: bool = typer.Option(False, "--json"),
):
    """Upload a file and print the resulting upload token (for reuse)."""
    c = _client(ctx)
    data = file.read_bytes()
    fname = filename or file.name
    resp = c.request(
        "POST", f"/uploads.json?filename={fname}",
        data=data,
        headers={"Content-Type": "application/octet-stream"},
    )
    upload = resp.get("upload", resp)
    if json_mode:
        emit_object(upload, json_mode=True)
    else:
        typer.echo(upload.get("token", ""))


@app.command(
    "attach",
    help=(
        "Upload a file and attach it to an issue in one shot.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine attachment attach ./bug.png -i 1234\n"
        "redmine attachment attach ./bug.png -i 1234 --description 'before/after'\n"
        "redmine attachment attach ./fix.patch -i 1234 -n 'Patch attached'\n"
        "```"
    ),
)
def attach(
    ctx: typer.Context,
    file: Path = typer.Argument(..., exists=True, dir_okay=False, readable=True),
    issue: int = typer.Option(..., "-i", "--issue", help="Issue ID to attach to."),
    description: Optional[str] = typer.Option(None, "--description", help="Per-attachment description."),
    note: Optional[str] = typer.Option(None, "-n", "--note", help="Optional comment to add at the same time."),
    content_type: Optional[str] = typer.Option(None, "--content-type"),
):
    """Upload a file and attach it to an issue in one shot."""
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
    if description: upload_entry["description"] = description
    if content_type: upload_entry["content_type"] = content_type
    issue_body: dict = {"uploads": [upload_entry]}
    if note: issue_body["notes"] = note
    c.put(f"/issues/{issue}.json", json={"issue": issue_body})
    typer.echo(f"attached {fname} to #{issue}")


@app.command(
    "get",
    help=(
        "Fetch attachment metadata.\n\n"
        "**Example:** `redmine attachment get 42 --json`"
    ),
)
def get_attachment(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    """Fetch attachment metadata."""
    c = _client(ctx)
    data = c.get(f"/attachments/{id}.json")
    a = data.get("attachment", data)
    if json_mode:
        emit_object(a, json_mode=True)
        return
    emit_object(
        {k: a.get(k) for k in
         ("id", "filename", "filesize", "content_type", "description",
          "content_url", "author", "created_on")},
        json_mode=False,
    )


@app.command(
    "download",
    help=(
        "Download an attachment by ID. Defaults to the original filename in "
        "the current directory; pass `-o` for a custom path or `-o -` for stdout.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine attachment download 42                    # writes ./<original-name>\n"
        "redmine attachment download 42 -o ./out.bin\n"
        "redmine attachment download 42 -o - | sha256sum\n"
        "```"
    ),
)
def download(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    output: Optional[Path] = typer.Option(None, "-o", "--output", help="Output path. Defaults to original filename. Use '-' for stdout."),
):
    """Download an attachment by ID."""
    c = _client(ctx)
    meta = c.get(f"/attachments/{id}.json").get("attachment", {})
    url = meta.get("content_url")
    if not url:
        typer.echo("error: attachment has no content_url", err=True)
        raise typer.Exit(code=5)
    resp = c.request("GET", url, raw=True)
    if str(output) == "-":
        sys.stdout.buffer.write(resp.content)
        return
    out_path = output or Path(meta.get("filename", f"attachment-{id}"))
    out_path.write_bytes(resp.content)
    typer.echo(f"wrote {out_path} ({len(resp.content)} bytes)")


@app.command(
    "update",
    help=(
        "Update an attachment's filename and/or description. At least one of "
        "`--filename` or `--description` must be provided.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine attachment update 42 --description 'after fix'\n"
        "redmine attachment update 42 --filename screenshot-final.png\n"
        "```"
    ),
)
def update_attachment(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    filename: Optional[str] = typer.Option(None, "--filename", help="New filename for the attachment."),
    description: Optional[str] = typer.Option(None, "--description", help="New per-attachment description."),
):
    """Update an attachment's filename and/or description."""
    c = _client(ctx)
    body: dict = {}
    if filename is not None: body["filename"] = filename
    if description is not None: body["description"] = description
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.patch(f"/attachments/{id}.json", json={"attachment": body})
    typer.echo(f"updated attachment {id}")


@app.command(
    "delete",
    help=(
        "Delete an attachment by ID. Prompts unless `-y` is passed. No undo.\n\n"
        "**Example:** `redmine attachment delete 42 -y`"
    ),
)
def delete_attachment(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    """Delete an attachment by ID (irreversible)."""
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete attachment {id}?", abort=True)
    c.delete(f"/attachments/{id}.json")
    typer.echo(f"deleted attachment {id}")


@app.command(
    "thumbnail",
    help=(
        "Download a PNG thumbnail of an image attachment. Requires the server "
        "to have ImageMagick available; non-image attachments and servers "
        "without thumbnail support will return an error.\n\n"
        "Pass `-o PATH` to write to a file, or `-o -` for stdout. Optional "
        "`--size` selects the thumbnail edge in pixels (e.g. 32, 64, 100, 200).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine attachment thumbnail 42 -o thumb.png\n"
        "redmine attachment thumbnail 42 -o thumb-64.png --size 64\n"
        "redmine attachment thumbnail 42 -o - | feh -\n"
        "```"
    ),
)
def thumbnail(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    output: Path = typer.Option(..., "-o", "--output", help="Output path. Use '-' for stdout."),
    size: Optional[int] = typer.Option(None, "--size", help="Thumbnail edge in pixels (e.g. 32, 64, 100, 200)."),
):
    """Download a PNG thumbnail of an image attachment."""
    c = _client(ctx)
    # Redmine route: GET /attachments/thumbnail/:id(/:size)
    path = f"/attachments/thumbnail/{id}"
    if size is not None:
        path = f"{path}/{size}"
    resp = c.request("GET", path, raw=True)
    if str(output) == "-":
        sys.stdout.buffer.write(resp.content)
        return
    output.write_bytes(resp.content)
    typer.echo(f"wrote {output} ({len(resp.content)} bytes)")
