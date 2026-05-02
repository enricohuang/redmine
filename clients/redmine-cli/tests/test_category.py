"""Issue category CRUD."""

from __future__ import annotations


def test_category_lifecycle(cli, project, unique):
    name = f"cat-{unique}"
    res = cli("category", "create", "-p", project["identifier"],
              "--name", name, "--json").json()
    cid = res["id"]
    assert res["name"] == name

    listed = cli("category", "list", "-p", project["identifier"], "--json").json()
    assert any(c["id"] == cid for c in listed)

    cli("category", "update", str(cid), "--name", name + "-edit")
    got = cli("category", "get", str(cid), "--json").json()
    assert got["name"] == name + "-edit"

    cli("category", "delete", str(cid), "-y")
    assert cli("category", "get", str(cid), check=False).returncode == 2
