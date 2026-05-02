"""Bulk update / delete (fork endpoint)."""

from __future__ import annotations

import pytest


@pytest.fixture
def three_issues(cli, project, unique):
    objs = []
    for i in range(3):
        objs.append(cli("issue", "create", "-p", project["identifier"],
                        "-s", f"bulk {unique} #{i}", "--json").json())
    yield objs
    # Bulk delete tests already remove these; cleanup anything left.
    for o in objs:
        cli("issue", "delete", str(o["id"]), "-y", check=False)


def test_bulk_update_status(cli, three_issues, api):
    ids = [str(o["id"]) for o in three_issues]
    cli("bulk", "update", "--ids", ",".join(ids),
        "--status", "Resolved", "--note", "bulk close", "-y")
    for i in three_issues:
        j = api.get(f"/issues/{i['id']}.json", include="journals")["issue"]
        assert j["status"]["name"] == "Resolved"
        notes = [x.get("notes") for x in j.get("journals", [])]
        assert any("bulk close" in (n or "") for n in notes)


def test_bulk_update_from_ids_file(cli, three_issues, tmp_path):
    p = tmp_path / "ids.txt"
    p.write_text("\n".join(str(o["id"]) for o in three_issues) + "\n")
    cli("bulk", "update", "--ids-file", str(p),
        "--priority", "High", "-y")
    for o in three_issues:
        got = cli("issue", "get", str(o["id"]), "--json").json()
        assert got["priority"]["name"] == "High"


def test_bulk_update_requires_field(cli, three_issues):
    res = cli("bulk", "update",
              "--ids", ",".join(str(o["id"]) for o in three_issues),
              check=False, stdin="")
    assert res.returncode != 0


def test_bulk_delete(cli, project, unique):
    """Standalone — does its own creates so it can fully delete them."""
    ids = []
    for i in range(2):
        obj = cli("issue", "create", "-p", project["identifier"],
                  "-s", f"to-bulk-delete {unique} #{i}", "--json").json()
        ids.append(str(obj["id"]))

    cli("bulk", "delete", "--ids", ",".join(ids), "-y")
    for i in ids:
        assert cli("issue", "get", i, check=False).returncode == 2
