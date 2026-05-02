"""Project board (forum) CRUD."""

from __future__ import annotations


def test_board_lifecycle(cli, project, unique):
    name = f"b-{unique}"
    res = cli("board", "create", "-p", project["identifier"],
              "--name", name, "--description", "auto", "--json").json()
    bid = res["id"]
    assert res["name"] == name
    assert res["description"] == "auto"

    listed = cli("board", "list", "-p", project["identifier"], "--json").json()
    assert any(b["id"] == bid for b in listed)

    got = cli("board", "get", str(bid), "--json").json()
    assert got["name"] == name

    cli("board", "update", str(bid), "--description", "edited")
    assert cli("board", "get", str(bid), "--json").json()["description"] == "edited"

    cli("board", "delete", str(bid), "-y")
    assert cli("board", "get", str(bid), check=False).returncode != 0


def test_board_create_with_parent(cli, project, unique):
    parent_name = f"bp-{unique}"
    parent = cli("board", "create", "-p", project["identifier"],
                 "--name", parent_name, "--description", "parent",
                 "--json").json()
    pid = parent["id"]

    child_name = f"bc-{unique}"
    child = cli("board", "create", "-p", project["identifier"],
                "--name", child_name, "--description", "child",
                "--parent-id", str(pid), "--json").json()
    cid = child["id"]
    assert child.get("parent", {}).get("id") == pid

    cli("board", "delete", str(cid), "-y")
    cli("board", "delete", str(pid), "-y")
