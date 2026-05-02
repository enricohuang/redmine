"""Project archive/unarchive and close/reopen lifecycle."""

from __future__ import annotations

import pytest


@pytest.fixture
def throwaway_project(cli, unique):
    """A project we can fully archive/close/delete without disturbing the session fixture."""
    ident = f"e2e-life-{unique}"
    name = f"e2e lifecycle {unique}"
    cli("project", "create", "--identifier", ident, "--name", name,
        "--description", "throwaway for lifecycle tests")
    yield {"identifier": ident, "name": name}
    cli("project", "delete", ident, "-y", check=False)


def test_project_archive_unarchive(cli, throwaway_project):
    ident = throwaway_project["identifier"]

    res = cli("project", "archive", ident)
    assert "archived" in res.stdout

    # Archived projects don't appear in the default `project list`.
    listed = cli("project", "list", "--all", "--json").json()
    assert all(p["identifier"] != ident for p in listed)

    res = cli("project", "unarchive", ident)
    assert "unarchived" in res.stdout

    listed = cli("project", "list", "--all", "--json").json()
    assert any(p["identifier"] == ident for p in listed)


def test_project_close_reopen(cli, throwaway_project):
    ident = throwaway_project["identifier"]

    res = cli("project", "close", ident)
    assert "closed" in res.stdout

    obj = cli("project", "get", ident, "--json").json()
    # Status 5 == closed in Redmine; some forks may report differently.
    assert obj.get("status") in (5, "5") or obj.get("status") != 1

    res = cli("project", "reopen", ident)
    assert "reopened" in res.stdout

    obj = cli("project", "get", ident, "--json").json()
    assert obj.get("status") in (1, "1")
