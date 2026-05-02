"""End-to-end tests for the `redmine fulltext` command (fork-only).

These exercise the attachment fulltext indexer API, which authenticates
with `X-Redmine-Indexer-Key` instead of the user API key. To stay
isolated from the rest of the suite (which uses the regular API key
via `REDMINE_URL`/`REDMINE_API_KEY`), we set `REDMINE_INDEXER_KEY` only
on the calls in this module — never globally — via the `cli` fixture's
`extra_env=` kwarg.

Server-side prerequisites are toggled on by an autouse fixture that
shells out to `bundle exec rails runner` to set:
    Setting.attachment_indexer_api_enabled = "1"
    Setting.attachment_indexer_api_key     = INDEXER_KEY

so that `curl -H "X-Redmine-Indexer-Key: $INDEXER_KEY" ...` works.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest


# Use a value distinct from any production secret. The autouse fixture
# below installs this on the running Rails server.
INDEXER_KEY = "test-indexer-key"

RAILS_ROOT = "/data/work/redmine/redmine"


# --------------------------------------------------------------------- setup

@pytest.fixture(scope="module", autouse=True)
def enable_fulltext_indexer():
    """Enable + key the fulltext indexer API on the test Redmine server.

    Runs once per module. We don't bother undoing it: leaving the setting
    on between test runs is harmless (no real client uses it), and
    teardown via Rails runner doubles the test cost.
    """
    code = (
        f'Setting.attachment_indexer_api_enabled = "1"\n'
        f'Setting.attachment_indexer_api_key = "{INDEXER_KEY}"\n'
        f'puts "ok"\n'
    )
    subprocess.run(
        ["bundle", "exec", "rails", "runner", code],
        cwd=RAILS_ROOT,
        env={**os.environ, "RAILS_ENV": "development"},
        check=True,
        timeout=120,
        capture_output=True,
    )


@pytest.fixture
def fulltext_env():
    """Extra env to pass to the `cli` fixture for indexer-authed calls."""
    return {"REDMINE_INDEXER_KEY": INDEXER_KEY}


@pytest.fixture
def attachment_id(cli, project, unique, tmp_path):
    """Create an issue with one text attachment; return the attachment id."""
    issue = cli("issue", "create",
                "-p", project["identifier"],
                "-s", f"fulltext {unique}",
                "--description", "for fulltext indexer tests",
                "--json").json()
    iid = issue["id"]
    src = tmp_path / f"ft-{unique}.txt"
    src.write_text(f"sample text {unique} for indexing")
    cli("attachment", "attach", str(src), "-i", str(iid))
    detail = cli("issue", "get", str(iid), "--include", "attachments", "--json").json()
    aid = detail["attachments"][0]["id"]
    yield aid
    # Best-effort cleanup of the parent issue (kills the attachment too).
    cli("issue", "delete", str(iid), "-y", check=False)


# --------------------------------------------------------------------- tests

def test_missing_indexer_key_errors_with_exit_code_4(cli, attachment_id):
    """Without REDMINE_INDEXER_KEY (and no host-stored key), exit 4."""
    res = cli("fulltext", "list", "--status", "pending", "--json",
              check=False)  # no extra_env -> no indexer key in scope
    assert res.returncode == 4, (
        f"expected EXIT_AUTH=4, got {res.returncode}\n"
        f"stdout={res.stdout!r}\nstderr={res.stderr!r}"
    )
    assert "indexer" in res.stderr.lower()


def test_list_includes_pending_attachment(cli, fulltext_env, attachment_id):
    """A freshly-attached file shows up in `list --status pending`."""
    res = cli("fulltext", "list", "--status", "pending", "--all", "--json",
              extra_env=fulltext_env)
    items = res.json()
    ids = [a["id"] for a in items]
    assert attachment_id in ids, f"attachment {attachment_id} missing from {ids}"
    me = next(a for a in items if a["id"] == attachment_id)
    assert me["fulltext"]["status"] == "pending"


def test_update_changes_status_and_get_reflects_it(cli, fulltext_env, attachment_id):
    """`update --status indexed --content ...` then `get` shows it."""
    cli("fulltext", "update", str(attachment_id),
        "--status", "indexed",
        "--content", f"extracted body for {attachment_id}",
        "--extractor-version", "test-extractor-1.0",
        extra_env=fulltext_env)

    res = cli("fulltext", "get", str(attachment_id), "--json",
              extra_env=fulltext_env)
    obj = res.json()
    assert obj["id"] == attachment_id
    assert obj["fulltext"]["status"] == "indexed"
    assert obj["fulltext"]["extractor_version"] == "test-extractor-1.0"
    # When indexed, the show endpoint includes the content too.
    assert obj["fulltext"]["content"] == f"extracted body for {attachment_id}"


def test_batch_update_marks_attachment_skipped(cli, fulltext_env, attachment_id, tmp_path):
    """`batch --file results.json` works for a one-element payload."""
    payload_file = tmp_path / "batch.json"
    payload_file.write_text(json.dumps({
        "attachments": [
            {"id": attachment_id, "status": "skipped",
             "error_message": "test batch skip"},
        ],
    }))

    res = cli("fulltext", "batch", "--file", str(payload_file), "--json",
              extra_env=fulltext_env)
    out = res.json()
    succ_ids = [s["id"] for s in out.get("success", [])]
    assert attachment_id in succ_ids, f"batch result: {out}"
    assert out.get("errors") == []

    # Confirm via `get`.
    obj = cli("fulltext", "get", str(attachment_id), "--json",
              extra_env=fulltext_env).json()
    assert obj["fulltext"]["status"] == "skipped"


def test_indexer_key_status_line(cli, tmp_path, fulltext_env):
    """`auth status` shows whether each host has an indexer key set.

    Done in a fresh XDG so we control the contents of hosts.yml. We log
    in twice — once to set the API key, once to add the indexer key —
    then assert the status line.
    """
    url = os.environ["REDMINE_URL"]
    key = os.environ["REDMINE_API_KEY"]
    fresh_xdg = {
        **os.environ,
        "XDG_CONFIG_HOME": str(tmp_path),
        "NO_COLOR": "1",
    }
    # Strip the env-bypass so resolve() actually reads hosts.yml.
    for var in ("REDMINE_URL", "REDMINE_API_KEY", "REDMINE_HOST",
                "REDMINE_USER", "REDMINE_INDEXER_KEY"):
        fresh_xdg.pop(var, None)

    bin_path = Path(os.path.dirname(__import__("sys").executable)) / "redmine"

    def run(args, check=True):
        proc = subprocess.run(
            [str(bin_path), *args], env=fresh_xdg,
            capture_output=True, text=True, timeout=30,
        )
        if check and proc.returncode != 0:
            raise AssertionError(
                f"redmine {' '.join(args)} exited {proc.returncode}\n"
                f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
            )
        return proc

    run(["auth", "login", "--url", url, "--api-key", key, "--label", "primary"])
    # Sanity: status before adding the indexer key reports "no".
    before = run(["auth", "status"]).stdout
    assert "indexer key: no" in before

    run(["auth", "login", "--url", url, "--indexer-key", INDEXER_KEY])
    after = run(["auth", "status"]).stdout
    assert "indexer key: yes" in after
    # Verify the key is NOT printed.
    assert INDEXER_KEY not in after
