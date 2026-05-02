"""Issue CRUD, including update with --note and delete confirmation."""

from __future__ import annotations

import pytest


@pytest.fixture
def issue(cli, project, unique):
    """Create a per-test issue and return its dict."""
    res = cli("issue", "create",
              "-p", project["identifier"],
              "-s", f"e2e issue {unique}",
              "--description", "body",
              "--json")
    obj = res.json()
    yield obj
    # Best-effort delete (tests may have already deleted it).
    cli("issue", "delete", str(obj["id"]), "-y", check=False)


def test_create_with_inline_description(cli, project, unique):
    res = cli("issue", "create",
              "-p", project["identifier"],
              "-s", f"inline {unique}",
              "--description", "from inline arg",
              "--json")
    obj = res.json()
    assert obj["subject"] == f"inline {unique}"
    assert obj["description"] == "from inline arg"
    cli("issue", "delete", str(obj["id"]), "-y")


def _norm(s: str | None) -> str:
    """Redmine normalizes text bodies to CRLF on save; compare in LF."""
    return (s or "").replace("\r\n", "\n").replace("\r", "\n")


def test_create_with_description_file(cli, project, unique, tmp_path):
    body = "# heading\n\nparagraph text " + unique
    p = tmp_path / "body.md"
    p.write_text(body)
    res = cli("issue", "create",
              "-p", project["identifier"],
              "-s", f"file body {unique}",
              "--description-file", str(p),
              "--json")
    obj = res.json()
    assert _norm(obj["description"]) == body
    cli("issue", "delete", str(obj["id"]), "-y")


def test_create_with_stdin_description(cli, project, unique):
    body = "stdin content " + unique
    res = cli("issue", "create",
              "-p", project["identifier"],
              "-s", f"stdin body {unique}",
              "--description", "-",
              "--json",
              stdin=body)
    obj = res.json()
    assert _norm(obj["description"]) == body
    cli("issue", "delete", str(obj["id"]), "-y")


def test_get_returns_full_issue(cli, issue):
    res = cli("issue", "get", str(issue["id"]), "--json")
    got = res.json()
    assert got["id"] == issue["id"]
    assert got["subject"] == issue["subject"]


def test_list_filters_by_project(cli, project, issue):
    res = cli("issue", "list", "-p", project["identifier"], "--json")
    items = res.json()
    assert any(i["id"] == issue["id"] for i in items)


def test_update_status_and_note(cli, issue, api):
    cli("issue", "update", str(issue["id"]),
        "--status", "Resolved",
        "--note", "fixing in PR #1")
    j = api.get(f"/issues/{issue['id']}.json", include="journals")
    assert j["issue"]["status"]["name"] == "Resolved"
    notes = [x.get("notes") for x in j["issue"].get("journals", [])]
    assert any("fixing in PR #1" in (n or "") for n in notes)


def test_update_with_no_changes_errors(cli, issue):
    res = cli("issue", "update", str(issue["id"]), check=False)
    assert res.returncode != 0
    assert "nothing to update" in res.stderr.lower() or "nothing to update" in res.stdout.lower()


def test_delete_requires_yes_or_confirms(cli, project, unique):
    """Without -y the prompt reads stdin; an empty stdin should abort, not delete."""
    obj = cli("issue", "create",
              "-p", project["identifier"], "-s", f"to-delete {unique}",
              "--json").json()
    # No -y, no stdin -> click prompt aborts on EOF.
    res = cli("issue", "delete", str(obj["id"]), check=False, stdin="")
    assert res.returncode != 0
    # Issue should still exist.
    cli("issue", "get", str(obj["id"]), "--json")
    # Now actually delete.
    cli("issue", "delete", str(obj["id"]), "-y")
    res2 = cli("issue", "get", str(obj["id"]), check=False)
    assert res2.returncode == 2  # not found


def test_get_unknown_issue_exits_2(cli):
    res = cli("issue", "get", "99999999", check=False)
    assert res.returncode == 2
    assert "Traceback" not in res.stderr
