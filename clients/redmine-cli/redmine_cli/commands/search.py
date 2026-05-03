"""`redmine search` — global search."""

from __future__ import annotations

from typing import Optional

import typer

from ..output import emit_list


def register(parent: typer.Typer) -> None:
    """Attach `search` as a single command on the parent app."""

    @parent.command(
        "search",
        help=(
            "Search issues, wiki, news, documents, etc. Default scope is "
            "all visible content; pass type flags to narrow.\n\n"
            "**Examples:**\n\n"
            "```\n"
            "redmine search 'login crash'\n"
            "redmine search 'login crash' -p mobile --issues\n"
            "redmine search 'release notes' --wiki --news\n"
            "redmine search 'TODO' --titles-only --json\n"
            "```\n\n"
            "Tutorial: `redmine help search`"
        ),
    )
    def search(
        ctx: typer.Context,
        query: str = typer.Argument(..., help="Search query."),
        project: Optional[str] = typer.Option(None, "-p", "--project"),
        scope: Optional[str] = typer.Option(None, "--scope", help="all / my_project / subprojects."),
        issues: bool = typer.Option(False, "--issues"),
        news: bool = typer.Option(False, "--news"),
        documents: bool = typer.Option(False, "--documents"),
        changesets: bool = typer.Option(False, "--changesets"),
        wiki_pages: bool = typer.Option(False, "--wiki"),
        messages: bool = typer.Option(False, "--messages"),
        projects: bool = typer.Option(False, "--projects"),
        titles_only: bool = typer.Option(False, "--titles-only"),
        open_issues: bool = typer.Option(False, "--open"),
        limit: int = typer.Option(25, "--limit"),
        all_pages: bool = typer.Option(False, "--all"),
        json_mode: bool = typer.Option(False, "--json"),
    ):
        from ..cli import get_client
        c = get_client(ctx)
        params: dict = {"q": query}
        path = f"/projects/{project}/search.json" if project else "/search.json"
        if scope: params["scope"] = scope
        for flag, key in [
            (issues, "issues"), (news, "news"), (documents, "documents"),
            (changesets, "changesets"), (wiki_pages, "wiki_pages"),
            (messages, "messages"), (projects, "projects"),
        ]:
            if flag:
                params[key] = 1
        if titles_only: params["titles_only"] = 1
        if open_issues: params["open_issues"] = 1

        if all_pages:
            items = list(c.paginate(path, key="results", page_size=limit, **params))
        else:
            params["limit"] = limit
            items = c.get(path, **params).get("results", [])

        emit_list(
            items,
            columns=[("Type", "type"), ("ID", "id"), ("Title", "title"),
                     ("Date", "datetime"), ("URL", "url")],
            json_mode=json_mode,
        )
