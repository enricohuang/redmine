"""`redmine elasticsearch ...` — fork-only Elasticsearch-backed search.

The fork exposes a dedicated `/elasticsearch_search.json` endpoint distinct
from the standard `/search.json`. It supports field-targeted matching, per-
type filters, date ranges, sort modes, and returns ES relevance scores plus
match highlights. It only works when the Redmine fork has Elasticsearch
configured and the index built — otherwise the server returns 503.
"""

from __future__ import annotations

import re
from typing import List, Optional

import typer

from ..output import emit_list, emit_object


app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Elasticsearch-backed search (fork feature).\n\n"
        "Hits the fork's `/elasticsearch_search.json` route. Requires the fork "
        "to have Elasticsearch configured and indexes built; otherwise calls "
        "fail with 503.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine elasticsearch search 'login crash'\n"
        "redmine elasticsearch search 'release notes' -p mobile --type wiki_page --type news\n"
        "redmine elasticsearch search 'TODO' --search-in title --sort-by date_desc\n"
        "redmine elasticsearch search 'oom' --from-date 2025-01-01 --to-date 2025-06-30 --json\n"
        "redmine elasticsearch search 'oom' --include-closed --limit 50\n"
        "```"
    ),
)


_HIGHLIGHT_RE = re.compile(r"</?mark[^>]*>")


def _client(ctx: typer.Context):
    from ..cli import get_client
    return get_client(ctx)


def _strip_highlights(value):
    """Strip <mark> tags from highlighted snippets for table output."""
    if not isinstance(value, str):
        return value
    return _HIGHLIGHT_RE.sub("", value)


@app.command(
    "search",
    help=(
        "Run an Elasticsearch query and print the ranked hits.\n\n"
        "**Example:** `redmine elasticsearch search 'login crash' -p mobile --type issue --limit 10`"
    ),
)
def search(
    ctx: typer.Context,
    query: str = typer.Argument(..., help="Search query string."),
    project: Optional[str] = typer.Option(
        None, "-p", "--project",
        help="Restrict to a single project (identifier or numeric id).",
    ),
    types: Optional[List[str]] = typer.Option(
        None, "--type",
        help="Repeatable. One of: issue, wiki_page, news, message, document, "
             "changeset, project. Default: all.",
    ),
    search_in: str = typer.Option(
        "all", "--search-in",
        help="Field scope: all | title | content.",
    ),
    from_date: Optional[str] = typer.Option(
        None, "--from-date",
        help="ISO date (YYYY-MM-DD). Lower bound on created_on.",
    ),
    to_date: Optional[str] = typer.Option(
        None, "--to-date",
        help="ISO date (YYYY-MM-DD). Upper bound on created_on.",
    ),
    sort_by: str = typer.Option(
        "relevance", "--sort-by",
        help="relevance | date_desc | date_asc | updated_desc.",
    ),
    include_closed: bool = typer.Option(
        True, "--include-closed/--no-include-closed",
        help="Include closed issues. Default: include.",
    ),
    limit: int = typer.Option(25, "--limit", help="Max hits to return."),
    page: int = typer.Option(1, "--page", help="1-based page index."),
    json_mode: bool = typer.Option(False, "--json", help="Emit raw JSON."),
):
    c = _client(ctx)

    params: dict = {
        "q": query,
        "search_in": search_in,
        "sort_by": sort_by,
        "page": page,
        # Server reads include_closed as != '0' (truthy).
        "include_closed": "1" if include_closed else "0",
        # `per_page` controls @limit on the server via per_page_option.
        "per_page": limit,
    }
    if project:
        params["project_id"] = project
    if from_date:
        params["date_from"] = from_date
    if to_date:
        params["date_to"] = to_date
    # Use Rails-style repeated `types[]=` keys; the ES controller reads
    # `params[:types]` and only accepts the bracketed form as an array.
    if types:
        params["types[]"] = list(types)

    # Bypass the .get() kwargs path so that `types[]` (which isn't a valid
    # Python identifier) is preserved as a query-string key.
    data = c.request("GET", "/elasticsearch_search.json", params=params)

    if json_mode:
        from ..output import emit_json
        emit_json(data)
        return

    results = data.get("results", []) if isinstance(data, dict) else []
    # Strip <mark> highlight tags so the table stays readable.
    cleaned = [
        {**r,
         "title": _strip_highlights(r.get("title")),
         "content": _strip_highlights(r.get("content")),
         "score": (
             round(r["score"], 3) if isinstance(r.get("score"), (int, float)) else r.get("score")
         )}
        for r in results
    ]
    emit_list(
        cleaned,
        columns=[
            ("Type", "type"),
            ("ID", "id"),
            ("Title", "title"),
            ("Score", "score"),
            ("Project", "project_name"),
        ],
    )


@app.command(
    "stats",
    help=(
        "Print server-side aggregations (by type, by project, by date) for a query.\n\n"
        "Useful for getting a feel for where matches concentrate before drilling in.\n\n"
        "**Example:** `redmine elasticsearch stats 'oom'`"
    ),
)
def stats(
    ctx: typer.Context,
    query: str = typer.Argument(..., help="Search query string."),
    project: Optional[str] = typer.Option(None, "-p", "--project"),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    params: dict = {"q": query, "per_page": 1}
    if project:
        params["project_id"] = project
    data = c.get("/elasticsearch_search.json", **params)

    aggs = data.get("aggregations", {}) if isinstance(data, dict) else {}
    summary = {
        "query": query,
        "total_count": data.get("total_count", 0),
        "by_type": aggs.get("by_type", []),
        "by_project": aggs.get("by_project", []),
        "by_date": aggs.get("by_date", []),
    }
    emit_object(summary, json_mode=json_mode)
