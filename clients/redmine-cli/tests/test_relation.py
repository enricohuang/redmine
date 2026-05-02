"""Issue relations."""

from __future__ import annotations

import pytest


@pytest.fixture
def two_issues(cli, project, unique):
    a = cli("issue", "create", "-p", project["identifier"],
            "-s", f"rel-from {unique}", "--json").json()
    b = cli("issue", "create", "-p", project["identifier"],
            "-s", f"rel-to {unique}", "--json").json()
    yield a, b
    for i in (a, b):
        cli("issue", "delete", str(i["id"]), "-y", check=False)


def test_create_list_delete_relation(cli, two_issues):
    a, b = two_issues
    res = cli("relation", "create", "-i", str(a["id"]),
              "--to", str(b["id"]), "--type", "blocks", "--json").json()
    rid = res["id"]
    assert res["relation_type"] == "blocks"
    assert res["issue_to_id"] == b["id"]

    listed = cli("relation", "list", "-i", str(a["id"]), "--json").json()
    assert any(r["id"] == rid for r in listed)

    got = cli("relation", "get", str(rid), "--json").json()
    assert got["id"] == rid

    cli("relation", "delete", str(rid), "-y")
    listed_after = cli("relation", "list", "-i", str(a["id"]), "--json").json()
    assert all(r["id"] != rid for r in listed_after)


def test_unknown_relation_type_exits_3(cli, two_issues):
    a, b = two_issues
    res = cli("relation", "create", "-i", str(a["id"]),
              "--to", str(b["id"]), "--type", "nonsense", check=False)
    assert res.returncode == 3
