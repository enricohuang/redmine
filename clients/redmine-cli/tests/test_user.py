"""User read commands."""

from __future__ import annotations


def test_user_get_current(cli):
    res = cli("user", "get", "current", "--json")
    user = res.json()
    assert user["id"] == 1 or user.get("login")  # admin is id=1 in fresh installs


def test_user_list_table(cli):
    """List in human format works without a crash; --json returns an array."""
    cli("user", "list", "--limit", "5")  # smoke
    res = cli("user", "list", "--limit", "5", "--json")
    assert isinstance(res.json(), list)
