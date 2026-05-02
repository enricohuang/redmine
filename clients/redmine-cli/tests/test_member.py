"""Project membership lifecycle.

Admin users on a project they created via the API don't show up as
explicit memberships (admin bypasses membership entirely), so these
tests create a throwaway user and a throwaway project to exercise
add → get → update → remove.
"""

from __future__ import annotations

import os
import uuid

import pytest
import requests


def _api_session():
    s = requests.Session()
    s.headers.update({"X-Redmine-API-Key": os.environ["REDMINE_API_KEY"],
                      "Accept": "application/json"})
    return s


@pytest.fixture
def throwaway_user(api):
    suffix = uuid.uuid4().hex[:6]
    user = api.post("/users.json", json={"user": {
        "login": f"e2e-mem-{suffix}",
        "firstname": "E2E", "lastname": "Member",
        "mail": f"e2e-mem-{suffix}@example.com",
        "password": "Pass1234!"
    }})["user"]
    yield user
    try:
        api.delete(f"/users/{user['id']}.json")
    except Exception:
        pass


def test_member_full_lifecycle(cli, project, throwaway_user, api):
    """Add the throwaway user, list, get, update with two roles, remove."""
    roles = [r for r in api.get("/roles.json")["roles"] if not r.get("builtin")]
    assert len(roles) >= 2, "need >=2 non-builtin roles for this test"
    role_a, role_b = roles[0], roles[1]

    res = cli("member", "add", "-p", project["identifier"],
              "--user-id", str(throwaway_user["id"]),
              "--roles", str(role_a["id"]), "--json").json()
    mid = res["id"]
    assert mid

    listed = cli("member", "list", "-p", project["identifier"], "--json").json()
    assert any(m["id"] == mid for m in listed)

    got = cli("member", "get", str(mid), "--json").json()
    assert got["id"] == mid
    assert any(r["id"] == role_a["id"] for r in got.get("roles", []))

    cli("member", "update", str(mid),
        "--roles", f"{role_a['id']},{role_b['id']}")
    got2 = cli("member", "get", str(mid), "--json").json()
    role_ids = {r["id"] for r in got2.get("roles", [])}
    assert {role_a["id"], role_b["id"]} <= role_ids

    cli("member", "remove", str(mid), "-y")
    assert cli("member", "get", str(mid), check=False).returncode == 2
