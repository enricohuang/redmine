"""Reactions (fork-only). One thumbs-up-style reaction per (user, object).

These tests cover two reactable types — Issue and Journal — exercising the
unusual routing where `object_type` and `object_id` are query parameters even
on `DELETE /reactions/{id}.json`.

Notes:
- `create` is idempotent server-side (find_or_create_by!) so a second call
  returns the same row, not a new one.
- `delete` accepts either an explicit id argument or, with id omitted, finds
  the current user's own reaction on the target.
"""

from __future__ import annotations

import pytest


@pytest.fixture
def issue_for_reactions(cli, project, unique):
    obj = cli("issue", "create",
              "-p", project["identifier"],
              "-s", f"reactable {unique}",
              "--description", "for reaction tests",
              "--json").json()
    yield obj
    cli("issue", "delete", str(obj["id"]), "-y", check=False)


def test_reaction_lifecycle_on_issue(cli, issue_for_reactions):
    iid = issue_for_reactions["id"]
    target = f"issue:{iid}"

    # Create.
    created = cli("reaction", "create", "--on", target, "--json").json()
    assert created.get("id")
    assert created.get("object_type") == "Issue"
    assert created.get("object_id") == iid
    rid = created["id"]

    # Idempotent: same id.
    again = cli("reaction", "create", "--on", target, "--json").json()
    assert again["id"] == rid

    # List shows it.
    listed = cli("reaction", "list", "--on", target, "--json").json()
    assert any(r["id"] == rid for r in listed)

    # Delete by explicit id.
    cli("reaction", "delete", str(rid), "--on", target, "-y")
    listed = cli("reaction", "list", "--on", target, "--json").json()
    assert all(r["id"] != rid for r in listed)


def test_reaction_delete_without_id_uses_current_user(cli, issue_for_reactions):
    iid = issue_for_reactions["id"]
    target = f"issue:{iid}"

    created = cli("reaction", "create", "--on", target, "--json").json()
    rid = created["id"]

    # No id arg — should still find and delete the caller's own reaction.
    cli("reaction", "delete", "--on", target, "-y")
    listed = cli("reaction", "list", "--on", target, "--json").json()
    assert all(r["id"] != rid for r in listed)


def test_reaction_on_journal(cli, issue_for_reactions):
    iid = issue_for_reactions["id"]

    # Need a journal first — create a comment on the issue.
    cli("journal", "create", "-i", str(iid), "-n", "comment to react to")
    journals = cli("journal", "list", "-i", str(iid), "--json").json()
    # Pick a journal that has notes (skip the issue-creation journal, which has none).
    jid = next(j["id"] for j in journals if j.get("notes") == "comment to react to")

    target = f"journal:{jid}"
    created = cli("reaction", "create", "--on", target, "--json").json()
    assert created.get("object_type") == "Journal"
    assert created.get("object_id") == jid
    rid = created["id"]

    listed = cli("reaction", "list", "--on", target, "--json").json()
    assert any(r["id"] == rid for r in listed)

    cli("reaction", "delete", str(rid), "--on", target, "-y")
    listed = cli("reaction", "list", "--on", target, "--json").json()
    assert all(r["id"] != rid for r in listed)


def test_reaction_on_invalid_type_exits_3(cli, issue_for_reactions):
    iid = issue_for_reactions["id"]
    res = cli("reaction", "list", "--on", f"banana:{iid}", check=False)
    assert res.returncode == 3
    # Error message should list valid types.
    err = res.stderr.lower()
    for t in ("issue", "journal", "message", "news", "comment"):
        assert t in err


def test_reaction_on_malformed_target_exits_3(cli):
    res = cli("reaction", "list", "--on", "issue-1234", check=False)
    assert res.returncode == 3
    res = cli("reaction", "list", "--on", "issue:notanint", check=False)
    assert res.returncode == 3
