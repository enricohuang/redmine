"""Read-only reference data: tracker, status, priority, enumeration,
custom-field, role."""

from __future__ import annotations


def test_tracker_list(cli):
    items = cli("tracker", "list", "--json").json()
    assert items, "trackers list should be non-empty on a default install"
    assert all("id" in t and "name" in t for t in items)


def test_status_list(cli):
    items = cli("status", "list", "--json").json()
    assert items
    # Closed statuses present too.
    assert any(s.get("is_closed") for s in items)


def test_priority_list(cli):
    items = cli("priority", "list", "--json").json()
    assert items
    assert any(p.get("is_default") for p in items)


def test_enumeration_arbitrary_kind(cli):
    items = cli("enumeration", "list", "time_entry_activities", "--json").json()
    assert items
    assert all("name" in e for e in items)


def test_role_list_and_get(cli):
    items = cli("role", "list", "--json").json()
    assert items
    rid = items[0]["id"]
    detail = cli("role", "get", str(rid), "--json").json()
    assert detail["id"] == rid
    # Detail typically includes a permissions list (may be empty for builtins).
    assert "permissions" in detail or "name" in detail


def test_custom_field_list(cli):
    """Stock install may have no custom fields — just verify the call works."""
    res = cli("custom-field", "list", "--json")
    assert isinstance(res.json(), list)
