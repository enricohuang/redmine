"""Read-only reference-data list commands.

These small commands exist primarily so an agent (or human) can look up
the numeric IDs and canonical names that other commands need:
trackers, statuses, priorities, time-entry activities, document categories,
custom fields, and roles.

Each is a simple `list` (and where useful, `get`) that wraps a stock GET.
"""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list, emit_object


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


# ---- tracker -----------------------------------------------------------------
tracker_app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Read-only: list issue trackers (Bug, Feature, Support, ...).\n\n"
        "**Example:** `redmine tracker list --json | jq '.[] | {id, name}'`"
    ),
)


@tracker_app.command("list", help="List all trackers.")
def tracker_list(
    ctx: typer.Context,
    json_mode: bool = typer.Option(False, "--json"),
):
    items = _client(ctx).get("/trackers.json").get("trackers", [])
    emit_list(items,
              columns=[("ID", "id"), ("Name", "name"),
                       ("Default Status", "default_status.name"),
                       ("Description", "description")],
              json_mode=json_mode)


# ---- status ------------------------------------------------------------------
status_app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Read-only: list issue statuses (New, In Progress, Closed, ...).\n\n"
        "**Example:** `redmine status list --json`"
    ),
)


@status_app.command("list", help="List all issue statuses.")
def status_list(
    ctx: typer.Context,
    json_mode: bool = typer.Option(False, "--json"),
):
    items = _client(ctx).get("/issue_statuses.json").get("issue_statuses", [])
    emit_list(items,
              columns=[("ID", "id"), ("Name", "name"),
                       ("Closed", "is_closed"), ("Description", "description")],
              json_mode=json_mode)


# ---- priority ----------------------------------------------------------------
priority_app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Read-only: list issue priorities (Low, Normal, High, Urgent, ...).\n\n"
        "**Example:** `redmine priority list`"
    ),
)


@priority_app.command("list", help="List all issue priorities.")
def priority_list(
    ctx: typer.Context,
    json_mode: bool = typer.Option(False, "--json"),
):
    items = _client(ctx).get(
        "/enumerations/issue_priorities.json"
    ).get("issue_priorities", [])
    emit_list(items,
              columns=[("ID", "id"), ("Name", "name"),
                       ("Default", "is_default"), ("Active", "active")],
              json_mode=json_mode)


# ---- enumeration (any kind) --------------------------------------------------
enum_app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Read-only: list any Redmine enumeration kind.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine enumeration list issue_priorities\n"
        "redmine enumeration list time_entry_activities\n"
        "redmine enumeration list document_categories\n"
        "```\n\n"
        "Kind is a path segment under `/enumerations/` "
        "(snake_case, e.g. `issue_priorities`)."
    ),
)


@enum_app.command(
    "list",
    help="List items of a specific enumeration kind.",
)
def enum_list(
    ctx: typer.Context,
    kind: str = typer.Argument(..., help="e.g. issue_priorities, time_entry_activities."),
    json_mode: bool = typer.Option(False, "--json"),
):
    data = _client(ctx).get(f"/enumerations/{kind}.json")
    items = data.get(kind, [])
    emit_list(items,
              columns=[("ID", "id"), ("Name", "name"),
                       ("Default", "is_default"), ("Active", "active")],
              json_mode=json_mode)


# ---- custom-field ------------------------------------------------------------
cf_app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Read-only: list custom field definitions (admin-only on stock Redmine).\n\n"
        "**Example:** `redmine custom-field list --json | jq '.[] | {id, name, customized_type}'`"
    ),
)


@cf_app.command("list", help="List all custom field definitions.")
def cf_list(
    ctx: typer.Context,
    json_mode: bool = typer.Option(False, "--json"),
):
    items = _client(ctx).get("/custom_fields.json").get("custom_fields", [])
    emit_list(items,
              columns=[("ID", "id"), ("Name", "name"),
                       ("Customized", "customized_type"),
                       ("Field Format", "field_format"),
                       ("Required", "is_required")],
              json_mode=json_mode)


# ---- role --------------------------------------------------------------------
role_app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Read-only: list roles, optionally with their permissions.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine role list\n"
        "redmine role get 3            # permissions, etc.\n"
        "```"
    ),
)


@role_app.command("list", help="List all roles.")
def role_list(
    ctx: typer.Context,
    json_mode: bool = typer.Option(False, "--json"),
):
    items = _client(ctx).get("/roles.json").get("roles", [])
    emit_list(items,
              columns=[("ID", "id"), ("Name", "name"),
                       ("Builtin", "builtin")],
              json_mode=json_mode)


@role_app.command(
    "get",
    help=(
        "Get a role by ID, including its permission list.\n\n"
        "**Example:** `redmine role get 3 --json`"
    ),
)
def role_get(
    ctx: typer.Context,
    id: int = typer.Argument(...),
    json_mode: bool = typer.Option(False, "--json"),
):
    obj = _client(ctx).get(f"/roles/{id}.json").get("role", {})
    emit_object(obj, json_mode=json_mode)
