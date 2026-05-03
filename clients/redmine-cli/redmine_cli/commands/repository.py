"""`redmine repository ...` - read repository entries and changesets."""

from __future__ import annotations

from typing import Optional

import typer

from ..client import die
from ..output import emit_list, emit_object


app = typer.Typer(
    no_args_is_help=True,
    rich_markup_mode="markdown",
    help=(
        "Read repository directory entries and changesets through bounded JSON "
        "endpoints. This intentionally does **not** expose raw file content or "
        "unbounded diffs.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine repository entries -p demo --repository 10 --path app/models --limit 50\n"
        "redmine repository revisions -p demo --repository 10 --limit 20\n"
        "redmine repository revision -p demo --repository 10 4 --json\n"
        "```"
    ),
)


def _client(ctx):
    from ..cli import get_client
    return get_client(ctx)


def _repository_path(project: str, repository: Optional[str], suffix: str = "") -> str:
    if repository:
        return f"/projects/{project}/repository/{repository}{suffix}.json"
    if suffix:
        die("--repository is required for this command", code=3)
    return f"/projects/{project}/repository.json"


@app.command(
    "entries",
    help=(
        "List repository directory entries. Use `--path` for a subdirectory, "
        "`--revision` for a specific revision, and `--limit/--offset` for "
        "bounded paging. If `--repository` is omitted, Redmine's default "
        "project repository is used.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine repository entries -p demo\n"
        "redmine repository entries -p demo --repository main --path lib --limit 25\n"
        "redmine repository entries -p demo --repository 10 --revision 4 --path trunk --json\n"
        "```"
    ),
)
def entries(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project", help="Project id or identifier."),
    repository: Optional[str] = typer.Option(None, "--repository", help="Repository id or identifier."),
    path: Optional[str] = typer.Option(None, "--path", help="Directory path inside the repository."),
    revision: Optional[str] = typer.Option(None, "--revision", help="Revision/branch/tag to browse."),
    limit: int = typer.Option(100, "--limit", help="Max entries to return; server caps the value."),
    offset: int = typer.Option(0, "--offset", help="Entry offset for paging."),
    json_mode: bool = typer.Option(False, "--json"),
):
    c = _client(ctx)
    params = {"limit": limit, "offset": offset}
    if path is not None:
        params["path"] = path
    if revision is not None:
        suffix = f"/revisions/{revision}/entries"
        url = _repository_path(project, repository, suffix)
    else:
        url = _repository_path(project, repository, "/entries" if repository else "")
    repo = c.get(url, **params).get("repository", {})
    if json_mode:
        emit_object(repo, json_mode=True)
        return
    emit_list(
        repo.get("entries", []),
        columns=[
            ("Name", "name"),
            ("Kind", "kind"),
            ("Path", "path"),
            ("Size", "size"),
            ("Revision", "changeset.revision"),
        ],
        json_mode=False,
        title=f"{project}:{repo.get('path', '') or '/'}",
    )


@app.command(
    "revisions",
    help=(
        "List changesets for a repository. This wraps "
        "`GET /projects/:project/repository/:repository/revisions.json`.\n\n"
        "**Example:** `redmine repository revisions -p demo --repository 10 --limit 20 --json`"
    ),
)
def revisions(
    ctx: typer.Context,
    project: str = typer.Option(..., "-p", "--project", help="Project id or identifier."),
    repository: str = typer.Option(..., "--repository", help="Repository id or identifier."),
    limit: int = typer.Option(25, "--limit", help="Rows per page."),
    page: int = typer.Option(1, "--page", help="1-based page number."),
    json_mode: bool = typer.Option(False, "--json"),
):
    data = _client(ctx).get(
        f"/projects/{project}/repository/{repository}/revisions.json",
        per_page=limit,
        page=page,
    )
    if json_mode:
        emit_object(data, json_mode=True)
        return
    emit_list(
        data.get("changesets", []),
        columns=[
            ("Revision", "revision"),
            ("Identifier", "identifier"),
            ("Author", "author"),
            ("Committed", "committed_on"),
            ("Comments", "comments"),
        ],
        json_mode=False,
        title=f"{project} revisions",
    )


@app.command(
    "revision",
    help=(
        "Show one changeset and its bounded file-change list. File changes are "
        "hidden by the server unless the user has `browse_repository`; the "
        "changeset metadata itself requires `view_changesets`.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine repository revision -p demo --repository 10 4\n"
        "redmine repository revision -p demo --repository 10 4 --limit 200 --json\n"
        "```"
    ),
)
def revision(
    ctx: typer.Context,
    rev: str = typer.Argument(..., help="Revision identifier."),
    project: str = typer.Option(..., "-p", "--project", help="Project id or identifier."),
    repository: str = typer.Option(..., "--repository", help="Repository id or identifier."),
    limit: int = typer.Option(1000, "--limit", help="Max file changes to return; server caps the value."),
    json_mode: bool = typer.Option(False, "--json"),
):
    changeset = _client(ctx).get(
        f"/projects/{project}/repository/{repository}/revisions/{rev}.json",
        limit=limit,
    ).get("changeset", {})
    if json_mode:
        emit_object(changeset, json_mode=True)
        return
    fields = [
        "id", "revision", "identifier", "scmid", "committed_on",
        "author", "committer", "comments", "filechanges_total_count",
    ]
    emit_object({f: changeset.get(f) for f in fields if f in changeset}, json_mode=False)
    filechanges = changeset.get("filechanges", [])
    if filechanges:
        emit_list(
            filechanges,
            columns=[
                ("Action", "action"),
                ("Path", "path"),
                ("From Path", "from_path"),
                ("From Rev", "from_revision"),
            ],
            json_mode=False,
            title="file changes",
        )
