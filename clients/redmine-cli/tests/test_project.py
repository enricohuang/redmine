"""Project CRUD."""

from __future__ import annotations


def test_project_get_by_identifier(cli, project):
    res = cli("project", "get", project["identifier"], "--json")
    obj = res.json()
    assert obj["id"] == project["id"]
    assert obj["identifier"] == project["identifier"]


def test_project_appears_in_list(cli, project):
    res = cli("project", "list", "--all", "--json")
    ids = [p["id"] for p in res.json()]
    assert project["id"] in ids


def test_project_update_description(cli, project):
    cli("project", "update", project["identifier"],
        "--description", "updated by e2e")
    res = cli("project", "get", project["identifier"], "--json")
    assert res.json().get("description") == "updated by e2e"


def test_project_create_delete_lifecycle(cli, unique):
    """Standalone project create + delete (not the session fixture)."""
    ident = f"e2e-tmp-{unique}"
    cli("project", "create",
        "--identifier", ident,
        "--name", f"e2e tmp {unique}",
        "--description", "throwaway")
    listed = cli("project", "list", "--all", "--json").json()
    assert any(p["identifier"] == ident for p in listed)
    cli("project", "delete", ident, "-y")
    listed = cli("project", "list", "--all", "--json").json()
    assert all(p["identifier"] != ident for p in listed)
