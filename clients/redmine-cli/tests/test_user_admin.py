"""User create/update/delete (admin endpoints)."""

from __future__ import annotations

import pytest


@pytest.fixture
def throwaway_user(cli, unique):
    """Create a user, yield it, best-effort delete on teardown."""
    login = f"e2eu{unique}"
    res = cli("user", "create",
              "--login", login,
              "--firstname", "E2e",
              "--lastname", "User",
              "--mail", f"{login}@example.com",
              "--password", "Pa55word!1",
              "--mail-notification", "only_my_events",
              "--json")
    user = res.json()
    yield user
    cli("user", "delete", str(user["id"]), "-y", check=False)


def test_user_create_appears_in_list(cli, throwaway_user):
    listed = cli("user", "list", "--name", throwaway_user["login"], "--json").json()
    logins = [u["login"] for u in listed]
    assert throwaway_user["login"] in logins


def test_user_update_changes_firstname(cli, throwaway_user):
    uid = throwaway_user["id"]
    cli("user", "update", str(uid), "--firstname", "Renamed")
    fetched = cli("user", "get", str(uid), "--json").json()
    assert fetched["firstname"] == "Renamed"


def test_user_update_requires_a_field(cli, throwaway_user):
    uid = throwaway_user["id"]
    res = cli("user", "update", str(uid), check=False)
    assert res.returncode == 2
    assert "nothing to update" in res.stderr


def test_user_delete_then_gone(cli, unique):
    """Full create -> delete cycle without the throwaway fixture (so we can assert delete)."""
    login = f"e2ed{unique}"
    user = cli("user", "create",
               "--login", login,
               "--firstname", "Del",
               "--lastname", "Me",
               "--mail", f"{login}@example.com",
               "--password", "Pa55word!1",
               "--json").json()
    cli("user", "delete", str(user["id"]), "-y")
    res = cli("user", "get", str(user["id"]), "--json", check=False)
    assert res.returncode != 0  # 404 -> exit 2
