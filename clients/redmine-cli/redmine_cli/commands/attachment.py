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

app = typer.Typer(no_args_is_help=True)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command("upload")
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


@app.command("attach")
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


@app.command("get")
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


@app.command("download")
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
