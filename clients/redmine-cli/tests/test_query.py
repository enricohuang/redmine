"""Read-only saved-query listing.

A stock dev DB ships with a handful of public default queries
("Issues assigned to me", etc.) — but we don't *require* any to exist;
the only contract is that the call succeeds and returns a JSON list.
"""

from __future__ import annotations


def test_query_list(cli):
    res = cli("query", "list", "--json")
    items = res.json()
    assert isinstance(items, list)
    for q in items:
        assert "id" in q and "name" in q
        # `project_id` is always present in the API response (may be null).
        assert "project_id" in q


def test_query_list_project_filter_does_not_crash(cli, project):
    # Newly-created project has no project-scoped queries, so we expect [].
    res = cli("query", "list", "--project", project["identifier"], "--json")
    items = res.json()
    assert isinstance(items, list)
    # If anything came back, it really is scoped to this project.
    for q in items:
        assert q.get("project_id") == project["id"]
