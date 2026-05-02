"""Forum message (topic + reply) CRUD."""

from __future__ import annotations

import pytest


@pytest.fixture(scope="module")
def board(cli, project):
    """A module-scoped board to host all message tests."""
    res = cli("board", "create", "-p", project["identifier"],
              "--name", "msg-tests", "--description", "shared", "--json").json()
    yield res
    try:
        cli("board", "delete", str(res["id"]), "-y")
    except AssertionError:
        pass


def test_message_lifecycle(cli, board, unique):
    subj = f"topic-{unique}"
    res = cli("message", "create", "--board", str(board["id"]),
              "--subject", subj, "--content", "hello world", "--json").json()
    mid = res["id"]
    assert res["subject"] == subj
    assert res["content"] == "hello world"

    listed = cli("message", "list", "--board", str(board["id"]), "--json").json()
    assert any(m["id"] == mid for m in listed)

    got = cli("message", "get", str(mid), "--json").json()
    assert got["subject"] == subj

    cli("message", "update", str(mid), "--subject", subj + "-edit",
        "--content", "edited body")
    after = cli("message", "get", str(mid), "--json").json()
    assert after["subject"] == subj + "-edit"
    assert after["content"] == "edited body"

    cli("message", "delete", str(mid), "-y")
    assert cli("message", "get", str(mid), check=False).returncode != 0


def test_message_reply_and_include_replies(cli, board, unique):
    subj = f"thread-{unique}"
    topic = cli("message", "create", "--board", str(board["id"]),
                "--subject", subj, "--content", "starter", "--json").json()
    tid = topic["id"]

    reply = cli("message", "reply", str(tid),
                "--content", "first response", "--json").json()
    rid = reply["id"]
    assert reply["content"] == "first response"

    with_replies = cli("message", "get", str(tid),
                       "--include", "replies", "--json").json()
    assert with_replies["replies_count"] == 1
    assert any(r["id"] == rid for r in with_replies.get("replies", []))

    cli("message", "delete", str(tid), "-y")


def test_message_create_with_file(cli, board, unique, tmp_path):
    p = tmp_path / "topic.md"
    p.write_text("# Title\n\nbody from a file")
    subj = f"file-{unique}"
    res = cli("message", "create", "--board", str(board["id"]),
              "--subject", subj, "--content-file", str(p), "--json").json()
    assert "body from a file" in res["content"]
    cli("message", "delete", str(res["id"]), "-y")
