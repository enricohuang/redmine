"""Journals (fork-specific direct comment API)."""

from __future__ import annotations

import pytest


@pytest.fixture
def issue_for_comments(cli, project, unique):
    obj = cli("issue", "create",
              "-p", project["identifier"],
              "-s", f"comments {unique}",
              "--description", "for comment tests",
              "--json").json()
    yield obj
    cli("issue", "delete", str(obj["id"]), "-y", check=False)


def test_create_and_list_journal(cli, issue_for_comments):
    iid = issue_for_comments["id"]
    cli("journal", "create", "-i", str(iid), "-n", "first comment")
    cli("journal", "create", "-i", str(iid), "-n", "second comment")
    items = cli("journal", "list", "-i", str(iid), "--json").json()
    notes = [j.get("notes") for j in items]
    assert "first comment" in notes
    assert "second comment" in notes


def test_create_from_stdin(cli, issue_for_comments):
    body = "multi\nline\ncomment"
    cli("journal", "create", "-i", str(issue_for_comments["id"]),
        "-n", "-", stdin=body)
    items = cli("journal", "list", "-i", str(issue_for_comments["id"]),
                "--json").json()
    assert any(j.get("notes") == body for j in items)


def test_update_journal(cli, issue_for_comments):
    iid = issue_for_comments["id"]
    res = cli("journal", "create", "-i", str(iid), "-n", "original", "--json")
    jid = res.json()["id"]
    cli("journal", "update", str(jid), "-n", "edited")
    got = cli("journal", "get", str(jid), "--json").json()
    assert got["notes"] == "edited"


def test_create_private_note(cli, issue_for_comments):
    iid = issue_for_comments["id"]
    res = cli("journal", "create", "-i", str(iid),
              "-n", "private detail", "--private", "--json")
    j = res.json()
    assert j.get("private_notes") is True
