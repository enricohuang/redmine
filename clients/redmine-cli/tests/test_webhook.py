"""Webhook CRUD (fork feature). Requires Setting.webhooks_enabled = 1."""

from __future__ import annotations

import pytest


@pytest.fixture(scope="module", autouse=True)
def _enable_webhooks(api):
    """Best-effort enable; if we can't toggle the setting we skip the suite.

    Settings can only be modified via the admin UI / Rails runner, not via
    the REST API, so we probe instead and skip if disabled.
    """
    r = api.s.get(f"{__import__('os').environ['REDMINE_URL']}/webhooks.json")
    if r.status_code in (401, 403):
        pytest.skip("webhooks setting not enabled on the server "
                    "(needs `Setting.webhooks_enabled = 1`)")


def test_webhook_lifecycle(cli, unique):
    url = f"https://example.com/hook-{unique}"
    res = cli("webhook", "create",
              "--url", url, "--secret", "deadbeef",
              "--events", "issue.created,issue.updated",
              "--active", "--json").json()
    wid = res["id"]
    assert res["url"] == url
    assert "issue.created" in res["events"]

    listed = cli("webhook", "list", "--all", "--json").json()
    assert any(w["id"] == wid for w in listed)

    got = cli("webhook", "get", str(wid), "--json").json()
    assert got["url"] == url

    # Update: change events
    cli("webhook", "update", str(wid),
        "--events", "issue.created", "--inactive")
    got2 = cli("webhook", "get", str(wid), "--json").json()
    assert got2["events"] == ["issue.created"]
    assert got2["active"] is False

    cli("webhook", "delete", str(wid), "-y")
    assert cli("webhook", "get", str(wid), check=False).returncode == 2
