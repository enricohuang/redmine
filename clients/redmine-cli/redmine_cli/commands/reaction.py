"""`redmine reaction ...` — emoji-style reactions on objects (fork feature).

Despite the conventional "emoji reaction" name, the fork's API actually
implements a single thumbs-up-style reaction per (user, object) pair: every
authenticated user can react at most once to a given reactable. There is no
emoji or kind to pick. The controller's `create` does
`@object.reactions.find_or_create_by!(user: User.current)`, so calling
`create` twice as the same user is idempotent and returns the existing row.

Endpoints (note the unusual routing — `object_type`/`object_id` are query
params on a flat `/reactions` resource, even on destroy):

    GET    /reactions.json?object_type=Issue&object_id=1234
    POST   /reactions.json?object_type=Issue&object_id=1234
    DELETE /reactions/{id}.json?object_type=Issue&object_id=1234

Reactable types: Journal, Issue, Message, News, Comment.
"""

from __future__ import annotations

import typer

from ..output import emit_list, emit_object


# Map user-facing lowercase aliases → canonical Rails class names.
_REACTABLE_TYPES: dict[str, str] = {
    "issue": "Issue",
    "journal": "Journal",
    "message": "Message",
    "news": "News",
    "comment": "Comment",
}


app = typer.Typer(
    no_args_is_help=True,
    rich_markup_mode="markdown",
    help=(
        "React to issues, journal comments, board messages, news posts, "
        "and news comments (fork feature). One reaction per user per object — "
        "creating again is a no-op.\n\n"
        "Targets are addressed as `TYPE:ID`, where TYPE is one of "
        "`issue`, `journal`, `message`, `news`, `comment`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine reaction list   --on issue:1234\n"
        "redmine reaction create --on issue:1234\n"
        "redmine reaction list   --on journal:88\n"
        "redmine reaction delete --on issue:1234 -y\n"
        "redmine reaction delete 17 --on issue:1234 -y\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


def _parse_on(value: str) -> tuple[str, int]:
    """Parse `TYPE:ID` into (canonical_type, id). Exits 3 on bad input."""
    valid = ", ".join(sorted(_REACTABLE_TYPES))
    if value is None or ":" not in value:
        typer.echo(
            f"error: --on must be 'TYPE:ID' (TYPE is one of: {valid})",
            err=True,
        )
        raise typer.Exit(code=3)
    raw_type, _, raw_id = value.partition(":")
    canonical = _REACTABLE_TYPES.get(raw_type.strip().lower())
    if canonical is None:
        typer.echo(
            f"error: invalid type {raw_type!r}; expected one of: {valid}",
            err=True,
        )
        raise typer.Exit(code=3)
    try:
        oid = int(raw_id.strip())
    except ValueError:
        typer.echo(
            f"error: object id in --on must be an integer, got {raw_id!r}",
            err=True,
        )
        raise typer.Exit(code=3)
    return canonical, oid


def _on_params(value: str) -> dict:
    obj_type, obj_id = _parse_on(value)
    return {"object_type": obj_type, "object_id": obj_id}


@app.command(
    "list",
    help=(
        "List reactions on an object.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine reaction list --on issue:1234\n"
        "redmine reaction list --on journal:88 --json | jq '.[].user.name'\n"
        "```"
    ),
)
def list_reactions(
    ctx: typer.Context,
    on: str = typer.Option(..., "--on", help="Target object as TYPE:ID, e.g. issue:1234."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    items = c.get("/reactions.json", **_on_params(on)).get("reactions", [])
    emit_list(
        items,
        columns=[("ID", "id"), ("User", "user.name"), ("Created", "created_on")],
        json_mode=json_mode,
    )


@app.command(
    "create",
    help=(
        "React to an object as the current API user. Idempotent: if you have "
        "already reacted, the existing reaction is returned unchanged.\n\n"
        "**Example:** `redmine reaction create --on issue:1234`"
    ),
)
def create_reaction(
    ctx: typer.Context,
    on: str = typer.Option(..., "--on", help="Target object as TYPE:ID, e.g. issue:1234."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    params = _on_params(on)
    data = c.post("/reactions.json", params=params)
    obj = data.get("reaction", data) if isinstance(data, dict) else {}
    if json_mode:
        emit_object(obj, json_mode=True)
    else:
        typer.echo(
            f"reacted to {params['object_type']}#{params['object_id']} "
            f"(reaction id={obj.get('id')})"
        )


@app.command(
    "delete",
    help=(
        "Remove your reaction from an object. The reaction id can be passed "
        "explicitly as the argument; if omitted, your own reaction on the "
        "given target is looked up and deleted.\n\n"
        "Server-side authorization only allows you to delete your own "
        "reaction (`@object.reactions.by(User.current).find_by(id: ...)`), "
        "so the id-less form is the convenient default.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine reaction delete --on issue:1234 -y\n"
        "redmine reaction delete 17 --on issue:1234 -y\n"
        "```"
    ),
)
def delete_reaction(
    ctx: typer.Context,
    id: int = typer.Argument(None, help="Reaction id. Optional — defaults to your own."),
    on: str = typer.Option(..., "--on", help="Target object as TYPE:ID, e.g. issue:1234."),
    yes: bool = typer.Option(False, "-y", "--yes"),
):
    c = _client(ctx)
    params = _on_params(on)
    if id is None:
        # Find the caller's own reaction on this object.
        items = c.get("/reactions.json", **params).get("reactions", [])
        me = c.get("/users/current.json").get("user", {})
        my_id = me.get("id")
        mine = next(
            (r for r in items if (r.get("user") or {}).get("id") == my_id),
            None,
        )
        if mine is None:
            typer.echo(
                f"no reaction by current user on "
                f"{params['object_type']}#{params['object_id']}",
                err=True,
            )
            raise typer.Exit(code=2)
        id = mine["id"]

    if not yes:
        typer.confirm(
            f"Really delete reaction {id} on "
            f"{params['object_type']}#{params['object_id']}?",
            abort=True,
        )
    c.delete(f"/reactions/{id}.json", params=params)
    typer.echo(f"deleted reaction {id}")
