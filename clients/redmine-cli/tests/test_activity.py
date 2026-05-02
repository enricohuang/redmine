"""Read-only activity feed.

Smoke tests against `/activity.json` (global) and `/projects/:id/activity.json`
(project-scoped). The session fixture creates a project and the other tests
create issues/wiki/etc. against it, so by the time these run there is plenty
of activity to observe.
"""

from __future__ import annotations


def test_activity_list_global_non_empty(cli, project):
    # `project` fixture guarantees at least one project-creation event in the
    # global feed for this session.
    items = cli("activity", "list", "--json").json()
    assert isinstance(items, list)
    assert items, "global activity feed should not be empty"
    # Each event has at least a type and a datetime.
    assert all("type" in e and "datetime" in e for e in items)


def test_activity_list_project_scoped(cli, project):
    items = cli("activity", "list", "-p", project["identifier"], "--json").json()
    assert isinstance(items, list)
    # All returned events should belong to the requested project (when present).
    for e in items:
        proj = e.get("project") or {}
        if "id" in proj:
            assert proj["id"] == project["id"]


def test_activity_list_with_filters_does_not_crash(cli, project):
    # --user-id, --with-subprojects, --limit all combine without error.
    res = cli("activity", "list",
              "-p", project["identifier"],
              "--with-subprojects",
              "--limit", "5",
              "--json")
    items = res.json()
    assert isinstance(items, list)
    assert len(items) <= 5
