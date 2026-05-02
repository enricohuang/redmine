"""`redmine message ...` — board topics, replies and edits."""

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
        "Manage forum messages (topics and replies) on a board.\n\n"
        "Top-level messages are *topics*; messages with a parent are *replies*. "
        "List boards first with `redmine board list -p PROJECT` to find a "
        "board ID.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine message list --board 3\n"
        "redmine message create --board 3 --subject 'Hi' --content 'first post'\n"
        "redmine message reply 12 --content 'thanks!'\n"
        "redmine message get 12 --include replies --json\n"
        "redmine message delete 12 -y\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help=(
        "List topics in a board.\n\n"
        "**Example:**\n\n"
        "```\n"
        "redmine message list --board 3 --json | jq '.[].subject'\n"
        "```"
    ),
)
def list_messages(
    ctx: typer.Context,
    board: int = typer.Option(..., "--board", help="Board ID."),
    limit: int = typer.Option(25, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    path = f"/boards/{board}/messages.json"
    if all_pages:
        items = list(c.paginate(path, key="messages", page_size=limit))
    else:
        items = c.get(path, limit=limit).get("messages", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("Subject", "subject"), ("Author", "author.name"),
                 ("Replies", "replies_count"), ("Sticky", "sticky"),
                 ("Locked", "locked"), ("Created", "created_on")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help=(
        "Fetch a single message. Pass `--include replies` to inline children.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine message get 12 --json\n"
        "redmine message get 12 --include replies --json\n"
        "```"
    ),
)
def get_message(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric message ID."),
    include: Optional[str] = typer.Option(None, "--include",
                                          help="Comma-separated includes (e.g. `replies`)."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    params = {"include": include} if include else {}
    obj = c.get(f"/messages/{id}.json", **params).get("message", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Create a new top-level topic on a board. Body comes from `--content`, "
        "`--content-file`, or `-` (stdin). The endpoint returns 204 No Content; "
        "we re-fetch by subject (newest match wins).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine message create --board 3 --subject 'Hello' --content 'first post'\n"
        "redmine message create --board 3 --subject 'RFC' --content-file rfc.md\n"
        "echo 'piped' | redmine message create --board 3 --subject 'Pipe' --content -\n"
        "```"
    ),
)
def create_message(
    ctx: typer.Context,
    board: int = typer.Option(..., "--board", help="Board ID."),
    subject: str = typer.Option(..., "--subject"),
    content: Optional[str] = typer.Option(None, "--content",
                                          help="Inline body (or '-' for stdin)."),
    content_file: Optional[Path] = typer.Option(None, "--content-file",
                                                help="Path to body file."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    body_text = read_text_input(content, content_file, name="content")
    if not body_text:
        typer.echo("error: provide --content or --content-file.", err=True)
        raise typer.Exit(code=2)
    body = {"subject": subject, "content": body_text}
    # POST /boards/:board_id/messages.json returns 204 No Content; re-fetch.
    c.post(f"/boards/{board}/messages.json", json={"message": body})
    listed = c.get(f"/boards/{board}/messages.json", limit=100).get("messages", [])
    matches = [m for m in listed if m.get("subject") == subject]
    # Topics are returned newest-first (`reorder(:sticky => :desc, :id => :desc)`).
    obj = matches[0] if matches else {}
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"created topic '{subject}' (id={obj.get('id')})"
    )


@app.command(
    "reply",
    help=(
        "Reply to an existing message. Body via `--content`, `--content-file`, "
        "or `-` (stdin). The reply subject defaults to `RE: <parent subject>`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine message reply 12 --content 'thanks!'\n"
        "redmine message reply 12 --content-file followup.md\n"
        "```"
    ),
)
def reply_message(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Parent message ID."),
    content: Optional[str] = typer.Option(None, "--content",
                                          help="Inline body (or '-' for stdin)."),
    content_file: Optional[Path] = typer.Option(None, "--content-file"),
    subject: Optional[str] = typer.Option(None, "--subject",
                                          help="Override default `RE: ...` subject."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    body_text = read_text_input(content, content_file, name="content")
    if not body_text:
        typer.echo("error: provide --content or --content-file.", err=True)
        raise typer.Exit(code=2)
    parent = c.get(f"/messages/{id}.json").get("message", {})
    reply_subject = subject or f"RE: {parent.get('subject', '')}"
    payload = {"reply": {"subject": reply_subject, "content": body_text}}
    # POST /messages/:id/replies.json returns 204 No Content; locate the new
    # reply by re-fetching the topic with replies included and matching content.
    c.post(f"/messages/{id}/replies.json", json=payload)
    refreshed = c.get(f"/messages/{id}.json", include="replies").get("message", {})
    replies = refreshed.get("replies") or []
    matches = [r for r in replies if r.get("content") == body_text]
    obj = matches[-1] if matches else {}
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"replied to message {id} (reply id={obj.get('id')})"
    )


@app.command(
    "update",
    help=(
        "Edit a message's subject and/or content.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine message update 12 --subject 'Hello (edited)'\n"
        "redmine message update 12 --content-file revised.md\n"
        "```"
    ),
)
def update_message(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric message ID."),
    subject: Optional[str] = typer.Option(None, "--subject"),
    content: Optional[str] = typer.Option(None, "--content",
                                          help="Inline body (or '-' for stdin)."),
    content_file: Optional[Path] = typer.Option(None, "--content-file"),
):
    c = _client(ctx)
    body_text = read_text_input(content, content_file, name="content")
    body: dict = {}
    if subject is not None: body["subject"] = subject
    if body_text is not None: body["content"] = body_text
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/messages/{id}.json", json={"message": body})
    typer.echo(f"updated message {id}")


@app.command(
    "delete",
    help=(
        "Delete a message (and any replies, if it's a topic root). "
        "Prompts unless `-y`.\n\n"
        "**Example:**\n\n"
        "```\n"
        "redmine message delete 12 -y\n"
        "```"
    ),
)
def delete_message(
    ctx: typer.Context,
    id: int = typer.Argument(..., help="Numeric message ID."),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete message {id}?", abort=True)
    c.delete(f"/messages/{id}.json")
    typer.echo(f"deleted message {id}")
