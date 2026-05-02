"""`redmine webhook ...` — outbound webhook management (fork feature)."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object

# Common event names — not enforced client-side, just shown in help.
SAMPLE_EVENTS = (
    "issue.created", "issue.updated", "issue.deleted",
    "wiki_page.created", "wiki_page.updated", "wiki_page.deleted",
    "time_entry.created", "time_entry.updated",
    "news.created", "version.created",
)


app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Manage outbound webhooks (fork feature). Webhooks fire HTTP POSTs "
        "with HMAC-SHA256-signed payloads on selected events.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine webhook list\n"
        "redmine webhook create --url https://example.com/hook \\\n"
        "                       --secret <hex> \\\n"
        "                       --events issue.created,issue.updated\n"
        "redmine webhook update 7 --active --events issue.created\n"
        "redmine webhook delete 7 -y\n"
        "```\n\n"
        "Server-side requirement: `Setting.webhooks_enabled = '1'` "
        "(Administration → Settings → API)."
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help="List configured webhooks.\n\n**Example:** `redmine webhook list --json`",
)
def list_webhooks(
    ctx: typer.Context,
    limit: int = typer.Option(25, "--limit"),
    all_pages: bool = typer.Option(False, "--all"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    if all_pages:
        items = list(c.paginate("/webhooks.json", key="webhooks", page_size=limit))
    else:
        items = c.get("/webhooks.json", limit=limit).get("webhooks", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("URL", "url"), ("Active", "active"),
                 ("Events", "events"), ("Updated", "updated_at")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help="Get a webhook by ID.\n\n**Example:** `redmine webhook get 7 --json`",
)
def get_webhook(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    obj = c.get(f"/webhooks/{id}.json").get("webhook", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Create a webhook. Events must be a comma-separated list.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine webhook create --url https://ci.example.com/hook \\\n"
        "                       --secret deadbeef --events issue.created\n"
        "redmine webhook create --url https://x.com/hook \\\n"
        "                       --events issue.created,issue.updated --active\n"
        "```\n\n"
        "Common events: " + ", ".join(SAMPLE_EVENTS)
    ),
)
def create_webhook(
    ctx: typer.Context,
    url: str = typer.Option(..., "--url"),
    events: str = typer.Option(..., "--events", help="Comma-separated event names."),
    secret: Optional[str] = typer.Option(None, "--secret",
                                         help="HMAC-SHA256 signing secret."),
    active: bool = typer.Option(False, "--active/--inactive"),
    description: Optional[str] = typer.Option(None, "--description"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    body: dict = {
        "url": url,
        "events": [e.strip() for e in events.split(",") if e.strip()],
        "active": active,
    }
    if secret is not None: body["secret"] = secret
    if description is not None: body["description"] = description
    obj = c.post("/webhooks.json", json={"webhook": body}).get("webhook", {})
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"created webhook {obj.get('id')} for {url}"
    )


@app.command(
    "update",
    help=(
        "Update a webhook.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine webhook update 7 --active\n"
        "redmine webhook update 7 --events issue.created,issue.updated\n"
        "redmine webhook update 7 --url https://new.example.com/hook --secret new\n"
        "```"
    ),
)
def update_webhook(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    url: Optional[str] = typer.Option(None, "--url"),
    events: Optional[str] = typer.Option(None, "--events"),
    secret: Optional[str] = typer.Option(None, "--secret"),
    active: Optional[bool] = typer.Option(None, "--active/--inactive"),
    description: Optional[str] = typer.Option(None, "--description"),
):
    c = _client(ctx)
    body: dict = {}
    if url is not None: body["url"] = url
    if events is not None:
        body["events"] = [e.strip() for e in events.split(",") if e.strip()]
    if secret is not None: body["secret"] = secret
    if active is not None: body["active"] = active
    if description is not None: body["description"] = description
    if not body:
        typer.echo("nothing to update", err=True)
        raise typer.Exit(code=2)
    c.put(f"/webhooks/{id}.json", json={"webhook": body})
    typer.echo(f"updated webhook {id}")


@app.command(
    "delete",
    help="Delete a webhook. Prompts unless `-y`.\n\n**Example:** `redmine webhook delete 7 -y`",
)
def delete_webhook(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete webhook {id}?", abort=True)
    c.delete(f"/webhooks/{id}.json")
    typer.echo(f"deleted webhook {id}")
