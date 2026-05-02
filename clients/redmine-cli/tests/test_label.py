"""Project label CRUD and assignment to issues.

Labels are returned in issue API responses since the templates were patched
in this fork (issues/show.api.rsb + issues/index.api.rsb with include=labels).
"""

from __future__ import annotations

import pytest


def test_label_lifecycle(cli, project, unique):
    # Create
    cli("label", "create", "-p", project["identifier"],
        "--name", f"l-{unique}", "--color", "#9b59b6", "--json")
    items = cli("label", "list", "-p", project["identifier"], "--json").json()
    created = next((l for l in items if l["name"] == f"l-{unique}"), None)
    assert created is not None
    assert created["color"] == "#9b59b6"

    # Update
    cli("label", "update", str(created["id"]),
        "--name", f"l-{unique}-renamed", "--color", "#000000")
    listed = cli("label", "list", "-p", project["identifier"], "--json").json()
    found = next((l for l in listed if l["id"] == created["id"]), None)
    assert found is not None
    assert found["name"] == f"l-{unique}-renamed"
    assert found["color"] == "#000000"

    # Get
    got = cli("label", "get", str(created["id"]), "--json").json()
    assert got["name"] == f"l-{unique}-renamed"

    # Delete
    cli("label", "delete", str(created["id"]), "-y")
    listed = cli("label", "list", "-p", project["identifier"], "--json").json()
    assert all(l["id"] != created["id"] for l in listed)


def test_label_assignment_visible_in_issue_show(cli, project, unique):
    """Validate the API patch: labels are in show.api.rsb output."""
    # Two labels.
    cli("label", "create", "-p", project["identifier"],
        "--name", f"a-{unique}", "--color", "#ff0000", "--json")
    cli("label", "create", "-p", project["identifier"],
        "--name", f"b-{unique}", "--color", "#00ff00", "--json")
    labels = cli("label", "list", "-p", project["identifier"], "--json").json()
    a = next(l for l in labels if l["name"] == f"a-{unique}")
    b = next(l for l in labels if l["name"] == f"b-{unique}")

    # Issue with both.
    obj = cli("issue", "create",
              "-p", project["identifier"], "-s", f"labelled {unique}",
              "--labels", f"{a['id']},{b['id']}",
              "--json").json()

    got = cli("issue", "get", str(obj["id"]), "--json").json()
    returned_ids = {l["id"] for l in got.get("labels", [])}
    assert returned_ids == {a["id"], b["id"]}
    # Color round-trips too.
    by_id = {l["id"]: l for l in got["labels"]}
    assert by_id[a["id"]]["color"] == "#ff0000"

    cli("issue", "delete", str(obj["id"]), "-y")
    cli("label", "delete", str(a["id"]), "-y")
    cli("label", "delete", str(b["id"]), "-y")


def test_index_with_include_labels(cli, project, unique):
    """list with --include labels should also surface the labels array."""
    cli("label", "create", "-p", project["identifier"],
        "--name", f"i-{unique}", "--color", "#abcdef", "--json")
    label_id = next(l["id"] for l in
                    cli("label", "list", "-p", project["identifier"], "--json").json()
                    if l["name"] == f"i-{unique}")
    obj = cli("issue", "create",
              "-p", project["identifier"], "-s", f"il {unique}",
              "--labels", str(label_id), "--json").json()
    listed = cli("issue", "list", "-p", project["identifier"],
                 "--include", "labels", "--json").json()
    target = next(i for i in listed if i["id"] == obj["id"])
    assert any(l["id"] == label_id for l in (target.get("labels") or []))
    cli("issue", "delete", str(obj["id"]), "-y")
    cli("label", "delete", str(label_id), "-y")
