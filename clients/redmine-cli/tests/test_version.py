"""Project version CRUD."""

from __future__ import annotations


def test_version_lifecycle(cli, project, unique):
    name = f"v-{unique}"
    cli("version", "create", "-p", project["identifier"],
        "--name", name, "--due-date", "2026-12-31", "--json")
    listed = cli("version", "list", "-p", project["identifier"], "--json").json()
    target = next((v for v in listed if v["name"] == name), None)
    assert target is not None
    vid = target["id"]

    got = cli("version", "get", str(vid), "--json").json()
    assert got["name"] == name
    assert got.get("due_date") == "2026-12-31"

    cli("version", "update", str(vid), "--status", "closed")
    assert cli("version", "get", str(vid), "--json").json()["status"] == "closed"

    cli("version", "delete", str(vid), "-y")
    assert cli("version", "get", str(vid), check=False).returncode == 2
