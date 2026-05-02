"""Read and update the current user's own account (`/my/account`)."""

from __future__ import annotations


def test_myaccount_get_returns_current_user(cli):
    res = cli("myaccount", "get", "--json")
    obj = res.json()
    assert obj.get("login")
    assert obj.get("id")
    assert obj.get("mail")


def test_myaccount_get_table_has_login(cli):
    res = cli("myaccount", "get")
    assert "login" in res.stdout


def test_myaccount_update_requires_a_field(cli):
    res = cli("myaccount", "update", check=False)
    assert res.returncode == 2
    assert "nothing to update" in res.stderr


def test_myaccount_update_roundtrips_firstname(cli):
    """Update firstname to a benign value and put it back, to avoid disturbing state."""
    original = cli("myaccount", "get", "--json").json()
    orig_first = original.get("firstname") or "Redmine"

    cli("myaccount", "update", "--firstname", f"{orig_first}E2e")
    after = cli("myaccount", "get", "--json").json()
    assert after["firstname"] == f"{orig_first}E2e"

    # Restore.
    cli("myaccount", "update", "--firstname", orig_first)
    restored = cli("myaccount", "get", "--json").json()
    assert restored["firstname"] == orig_first
