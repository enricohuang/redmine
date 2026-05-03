"""Global search."""

from __future__ import annotations


def test_search_finds_freshly_created_issue(cli, project, unique):
    obj = cli("issue", "create",
              "-p", project["identifier"],
              "-s", f"searchneedle{unique}",
              "--description", f"unique-marker-{unique}",
              "--json").json()
    try:
        # Search by the unique subject token; project-scoped so we don't
        # depend on global noise being absent.
        res = cli("search", f"searchneedle{unique}",
                  "-p", project["identifier"], "--issues", "--json")
        items = res.json()
        assert any(r.get("id") == obj["id"] and r.get("type") == "issue"
                   for r in items)
    finally:
        cli("issue", "delete", str(obj["id"]), "-y")


def test_search_project_scope_excludes_other_projects(cli, project, unique):
    other_project = f"e2e-search-scope-{unique}"
    other_issue = None
    cli("project", "create",
        "--identifier", other_project,
        "--name", f"search scope {unique}",
        "--modules", "issue_tracking",
        "--json")
    try:
        needle = f"scopeonly{unique}"
        other_issue = cli("issue", "create",
                          "-p", other_project,
                          "-s", needle,
                          "--json").json()

        res = cli("search", needle,
                  "-p", project["identifier"], "--issues", "--json")
        items = res.json()
        assert all(r.get("id") != other_issue["id"] for r in items)
    finally:
        if other_issue:
            cli("issue", "delete", str(other_issue["id"]), "-y", check=False)
        cli("project", "delete", other_project, "-y", check=False)


def test_search_no_match_returns_empty_array(cli, project):
    res = cli("search", "this-string-should-match-nothing-zzqq",
              "-p", project["identifier"], "--json")
    assert res.json() == []
