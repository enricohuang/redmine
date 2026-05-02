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


def test_search_no_match_returns_empty_array(cli, project):
    res = cli("search", "this-string-should-match-nothing-zzqq",
              "-p", project["identifier"], "--json")
    assert res.json() == []
