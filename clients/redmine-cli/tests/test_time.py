"""Time entry CRUD."""

from __future__ import annotations

import pytest


@pytest.fixture
def issue_for_time(cli, project, unique):
    obj = cli("issue", "create", "-p", project["identifier"],
              "-s", f"time {unique}", "--description", "for time tests",
              "--json").json()
    yield obj
    cli("issue", "delete", str(obj["id"]), "-y", check=False)


def test_create_list_get_delete(cli, issue_for_time):
    iid = issue_for_time["id"]
    res = cli("time", "create", "-i", str(iid),
              "--hours", "1.5", "--activity", "Development",
              "--comment", "investigating", "--json").json()
    teid = res["id"]
    assert res["hours"] == 1.5

    listed = cli("time", "list", "-i", str(iid), "--json").json()
    assert any(t["id"] == teid for t in listed)

    got = cli("time", "get", str(teid), "--json").json()
    assert got["id"] == teid
    assert got.get("activity", {}).get("name") == "Development"

    cli("time", "delete", str(teid), "-y")
    res = cli("time", "get", str(teid), check=False)
    assert res.returncode == 2


def test_update_hours(cli, issue_for_time):
    iid = issue_for_time["id"]
    res = cli("time", "create", "-i", str(iid),
              "--hours", "1", "--activity", "Development", "--json").json()
    cli("time", "update", str(res["id"]), "--hours", "2.5",
        "--comment", "corrected")
    got = cli("time", "get", str(res["id"]), "--json").json()
    assert got["hours"] == 2.5
    cli("time", "delete", str(res["id"]), "-y")


def test_unknown_activity_exits_3(cli, issue_for_time):
    res = cli("time", "create", "-i", str(issue_for_time["id"]),
              "--hours", "1", "--activity", "NotAnActivity", check=False)
    assert res.returncode == 3
