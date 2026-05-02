"""User group CRUD (admin-only)."""

from __future__ import annotations

import uuid


def test_group_lifecycle(cli):
    name = f"g-{uuid.uuid4().hex[:8]}"
    res = cli("group", "create", "--name", name, "--json").json()
    gid = res["id"]
    assert res["name"] == name

    listed = cli("group", "list", "--json").json()
    assert any(g["id"] == gid for g in listed)

    got = cli("group", "get", str(gid), "--json").json()
    assert got["name"] == name

    cli("group", "update", str(gid), "--name", name + "-edit")
    assert cli("group", "get", str(gid), "--json").json()["name"] == name + "-edit"

    cli("group", "delete", str(gid), "-y")
    assert cli("group", "get", str(gid), check=False).returncode == 2


def test_group_add_remove_user(cli, api):
    """Create a group + a user, add the user, remove, clean up."""
    user = api.post("/users.json", json={"user": {
        "login": f"gtest-{uuid.uuid4().hex[:6]}",
        "firstname": "G", "lastname": "Test",
        "mail": f"g-{uuid.uuid4().hex[:6]}@example.com",
        "password": "Pass1234!"
    }})["user"]
    try:
        gid = cli("group", "create", "--name", f"members-{uuid.uuid4().hex[:6]}",
                  "--json").json()["id"]
        try:
            cli("group", "add-user", str(gid), "--user-id", str(user["id"]))
            got = cli("group", "get", str(gid), "--include", "users", "--json").json()
            assert any(u["id"] == user["id"] for u in got.get("users", []))

            cli("group", "remove-user", str(gid), "--user-id", str(user["id"]))
            got2 = cli("group", "get", str(gid), "--include", "users", "--json").json()
            assert all(u["id"] != user["id"] for u in got2.get("users", []))
        finally:
            cli("group", "delete", str(gid), "-y")
    finally:
        api.delete(f"/users/{user['id']}.json")
