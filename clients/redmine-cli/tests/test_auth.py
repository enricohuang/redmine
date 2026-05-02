"""Auth subcommand: env-bypass, login/status/switch/logout/token, multi-host."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest
import yaml


def _bin() -> str:
    return str(Path(sys.executable).parent / "redmine")


def _run(args, env, *, stdin=None, check=True):
    proc = subprocess.run(
        [_bin(), *args], env=env, capture_output=True, text=True,
        input=stdin, timeout=30,
    )
    if check and proc.returncode != 0:
        raise AssertionError(
            f"redmine {' '.join(args)} exited {proc.returncode}\n"
            f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
        )
    return proc


@pytest.fixture
def fresh_xdg(tmp_path):
    """A clean XDG_CONFIG_HOME for one test, with no leaking REDMINE_URL/KEY env."""
    base = {**os.environ, "XDG_CONFIG_HOME": str(tmp_path), "NO_COLOR": "1"}
    base.pop("REDMINE_URL", None)
    base.pop("REDMINE_API_KEY", None)
    base.pop("REDMINE_HOST", None)
    base.pop("REDMINE_USER", None)
    return base


def test_status_when_unauthenticated(fresh_xdg):
    proc = _run(["auth", "status"], env=fresh_xdg, check=False)
    assert proc.returncode != 0
    assert "not authenticated" in proc.stdout.lower()


def test_login_and_status(fresh_xdg):
    """`auth login` writes hosts.yml and `auth status` reflects it."""
    url = os.environ["REDMINE_URL"]
    key = os.environ["REDMINE_API_KEY"]
    _run(["auth", "login", "--url", url, "--api-key", key, "--label", "primary"],
         env=fresh_xdg)
    hosts_path = Path(fresh_xdg["XDG_CONFIG_HOME"]) / "redmine" / "hosts.yml"
    assert hosts_path.exists(), "hosts.yml was not created"
    data = yaml.safe_load(hosts_path.read_text())
    host = next(iter(data))
    assert data[host]["users"]["primary"]["api_key"] == key
    assert data[host]["user"] == "primary"

    status = _run(["auth", "status"], env=fresh_xdg)
    assert "primary" in status.stdout
    assert host in status.stdout


def test_login_rejects_bad_key(fresh_xdg):
    url = os.environ["REDMINE_URL"]
    proc = _run(["auth", "login", "--url", url, "--api-key", "x" * 40, "--label", "bad"],
                env=fresh_xdg, check=False)
    assert proc.returncode != 0
    # Should mention rejection somewhere, not crash with traceback.
    assert "Traceback" not in proc.stderr


def test_token_prints_active_key(fresh_xdg):
    url = os.environ["REDMINE_URL"]
    key = os.environ["REDMINE_API_KEY"]
    _run(["auth", "login", "--url", url, "--api-key", key, "--label", "primary"],
         env=fresh_xdg)
    proc = _run(["auth", "token"], env=fresh_xdg)
    assert proc.stdout.strip() == key


def test_switch_between_users(fresh_xdg):
    """Two profiles on the same host; switch toggles which one `token` returns."""
    url = os.environ["REDMINE_URL"]
    key = os.environ["REDMINE_API_KEY"]
    _run(["auth", "login", "--url", url, "--api-key", key, "--label", "alice"],
         env=fresh_xdg)
    _run(["auth", "login", "--url", url, "--api-key", key, "--label", "bob",
          "--no-set-default"], env=fresh_xdg)
    # Most-recently-added is now active per add_user(make_active=True).
    assert _run(["auth", "token"], env=fresh_xdg).stdout.strip() == key

    # Determine host from the config to drive switch.
    hosts = yaml.safe_load(
        (Path(fresh_xdg["XDG_CONFIG_HOME"]) / "redmine" / "hosts.yml").read_text())
    host = next(iter(hosts))

    _run(["auth", "switch", "--host", host, "--user", "alice"], env=fresh_xdg)
    status = _run(["auth", "status"], env=fresh_xdg)
    # The active marker '*' should now sit on alice.
    assert "* alice" in status.stdout


def test_logout_removes_user(fresh_xdg):
    url = os.environ["REDMINE_URL"]
    key = os.environ["REDMINE_API_KEY"]
    _run(["auth", "login", "--url", url, "--api-key", key, "--label", "alice"],
         env=fresh_xdg)
    hosts_path = Path(fresh_xdg["XDG_CONFIG_HOME"]) / "redmine" / "hosts.yml"
    host = next(iter(yaml.safe_load(hosts_path.read_text())))
    _run(["auth", "logout", "--host", host], env=fresh_xdg)
    # Whole host is gone -> hosts.yml is now empty mapping.
    data = yaml.safe_load(hosts_path.read_text()) or {}
    assert host not in data


def test_env_bypass(fresh_xdg, cli):
    """REDMINE_URL+REDMINE_API_KEY work even when no hosts.yml exists.

    Uses the session-scoped `cli` fixture (which always sets the env vars) to
    confirm the env path through `resolve()` succeeds without any login.
    """
    res = cli("user", "get", "current", "--json")
    assert res.json()["id"]  # non-zero
