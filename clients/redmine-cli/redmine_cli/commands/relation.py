"""`redmine relation ...` — issue relations (links between issues)."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object

RELATION_TYPES = (
    "relates", "duplicates", "duplicated", "blocks", "blocked",
    "precedes", "follows", "copied_to", "copied_from",
)


app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Link related issues (blocks / duplicates / precedes / etc).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine relation list -i 1234\n"
        "redmine relation create -i 1234 --to 5678 --type blocks\n"
        "redmine relation delete 42 -y\n"
        "```\n\n"
        "Relation types: `relates, duplicates, duplicated, blocks, blocked, "
        "precedes, follows, copied_to, copied_from`."
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


@app.command(
    "list",
    help=(
        "List relations on an issue.\n\n"
        "**Example:** `redmine relation list -i 1234`"
    ),
)
def list_relations(
    ctx: typer.Context,
    issue: int = typer.Option(..., "-i", "--issue"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    items = c.get(f"/issues/{issue}/relations.json").get("relations", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("From", "issue_id"), ("To", "issue_to_id"),
                 ("Type", "relation_type"), ("Delay", "delay")],
        json_mode=json_mode,
    )


@app.command(
    "get",
    help="Fetch a single relation by ID.\n\n**Example:** `redmine relation get 42 --json`",
)
def get_relation(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    obj = c.get(f"/relations/{id}.json").get("relation", {})
    emit_object(obj, json_mode=json_mode)


@app.command(
    "create",
    help=(
        "Create a relation between two issues.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine relation create -i 1234 --to 5678 --type blocks\n"
        "redmine relation create -i 1234 --to 5678 --type precedes --delay 5\n"
        "```\n\n"
        "`--delay` only applies to `precedes` / `follows` and is in days."
    ),
)
def create_relation(
    ctx: typer.Context,
    issue: int = typer.Option(..., "-i", "--issue", help="Source issue ID."),
    to: int = typer.Option(..., "--to", help="Target issue ID."),
    rel_type: str = typer.Option("relates", "--type", help="Relation type."),
    delay: Optional[int] = typer.Option(None, "--delay", help="Days; precedes/follows only."),
    json_mode: bool = typer.Option(False, "--json"),
):
    if rel_type not in RELATION_TYPES:
        typer.echo(f"unknown relation type '{rel_type}'. "
                   f"Valid: {', '.join(RELATION_TYPES)}", err=True)
        raise typer.Exit(code=3)
    c = _client(ctx)
    body: dict = {"issue_to_id": to, "relation_type": rel_type}
    if delay is not None: body["delay"] = delay
    obj = c.post(f"/issues/{issue}/relations.json", json={"relation": body}).get("relation", {})
    emit_object(obj, json_mode=json_mode) if json_mode else typer.echo(
        f"linked #{issue} -[{rel_type}]-> #{to} (relation id={obj.get('id')})"
    )


@app.command(
    "delete",
    help="Delete a relation by ID.\n\n**Example:** `redmine relation delete 42 -y`",
)
def delete_relation(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    if not yes:
        typer.confirm(f"Really delete relation {id}?", abort=True)
    c.delete(f"/relations/{id}.json")
    typer.echo(f"deleted relation {id}")
