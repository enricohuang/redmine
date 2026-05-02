"""Shared fixtures for the redmine-cli e2e suite.

The suite shells out to the installed `redmine` binary (via the same Python the
tests run under, so installs in `pip install -e .` are picked up automatically)
and talks to a real Redmine. It does not mock anything.

Required environment for the suite to run:
- REDMINE_URL: base URL of a writable Redmine instance
- REDMINE_API_KEY: an admin (or sufficiently permissioned) API key

Without those, the entire suite is skipped with a clear message — so CI without
a Redmine still passes cleanly.

Each pytest *session* gets its own freshly-created project; resources created by
tests are scoped under that project and torn down at session end. We use a
unique identifier per session run so concurrent runs against the same Redmine
do not collide.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

import pytest
import requests


# ---- Module-level skip if the env is not configured --------------------------

REDMINE_URL = os.environ.get("REDMINE_URL", "").rstrip("/")
REDMINE_API_KEY = os.environ.get("REDMINE_API_KEY", "")

if not REDMINE_URL or not REDMINE_API_KEY:
    pytest.skip(
        "REDMINE_URL and REDMINE_API_KEY must be set to run the e2e suite.",
        allow_module_level=True,
    )


# ---- Helpers ----------------------------------------------------------------

@dataclass
class CLIResult:
    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str

    def json(self):
        return json.loads(self.stdout)


def _resolve_binary() -> str:
    """Find the `redmine` console script from the active Python."""
    bin_dir = Path(sys.executable).parent
    candidate = bin_dir / "redmine"
    if candidate.exists():
        return str(candidate)
    found = shutil.which("redmine")
    if not found:
        pytest.fail(
            "could not find the `redmine` binary on PATH or alongside the test interpreter; "
            "did you `pip install -e .[test]` ?"
        )
    return found


REDMINE_BIN = _resolve_binary()


@pytest.fixture(scope="session")
def isolated_config(tmp_path_factory) -> Path:
    """Direct the CLI's config to a session-scoped tmp dir via XDG_CONFIG_HOME.

    Auth subcommands write here; resolve() reads from here. This keeps the
    user's real ~/.config/redmine untouched.
    """
    cfg = tmp_path_factory.mktemp("xdg-config")
    return cfg


@pytest.fixture(scope="session")
def cli(isolated_config: Path):
    """Invoker fixture. Use as `result = cli('issue', 'list', '-p', 'demo')`.

    Always passes REDMINE_URL/REDMINE_API_KEY through so the bypass-env path of
    `resolve()` is exercised — we don't depend on an `auth login` having run
    (auth-specific tests do their own logins into the isolated config).
    """
    def _run(*args: str, check: bool = True, stdin: str | None = None,
             extra_env: dict | None = None) -> CLIResult:
        env = {
            **os.environ,
            "XDG_CONFIG_HOME": str(isolated_config),
            "REDMINE_URL": REDMINE_URL,
            "REDMINE_API_KEY": REDMINE_API_KEY,
            # disable rich's color/markup so output is stable
            "NO_COLOR": "1",
            "TERM": "dumb",
        }
        if extra_env:
            env.update(extra_env)
        proc = subprocess.run(
            [REDMINE_BIN, *args],
            input=stdin,
            capture_output=True,
            text=True,
            env=env,
            timeout=60,
        )
        result = CLIResult(args=tuple(args), returncode=proc.returncode,
                           stdout=proc.stdout, stderr=proc.stderr)
        if check and proc.returncode != 0:
            raise AssertionError(
                f"redmine {' '.join(args)} exited {proc.returncode}\n"
                f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
            )
        return result

    return _run


@pytest.fixture(scope="session")
def session_id() -> str:
    """Short unique tag used to scope created resources to this run."""
    return uuid.uuid4().hex[:8]


@pytest.fixture(scope="session")
def project(cli, session_id) -> dict:
    """Create a project at session start, delete at session end.

    Returns the project dict (id, identifier, name).
    """
    identifier = f"e2e-{session_id}"
    name = f"e2e {session_id}"
    cli("project", "create",
        "--identifier", identifier,
        "--name", name,
        "--description", "auto-created by redmine-cli e2e suite",
        # Enable every module the suite touches; new tests should reuse this
        # session project rather than creating one of their own.
        "--modules", "issue_tracking,wiki,news,time_tracking,boards,documents",
        "--json")
    # Fetch by identifier to capture the assigned numeric id.
    res = cli("project", "get", identifier, "--include", "", "--json")
    proj = res.json()
    yield proj
    # Teardown: best-effort delete (failures don't blow up the suite).
    try:
        cli("project", "delete", identifier, "-y")
    except AssertionError:
        pass


# ---- Direct API helper for assertions that bypass the CLI -------------------

@pytest.fixture(scope="session")
def api():
    """Plain requests session for assertions about server-side state.

    Useful when validating that the CLI did the right thing — or for setup that
    isn't worth a CLI call (e.g. enabling a project module the CLI doesn't expose).
    """
    s = requests.Session()
    s.headers.update({
        "X-Redmine-API-Key": REDMINE_API_KEY,
        "Accept": "application/json",
    })
    return _APIClient(s)


class _APIClient:
    def __init__(self, session: requests.Session):
        self.s = session

    def get(self, path: str, **params):
        r = self.s.get(f"{REDMINE_URL}{path}", params=params, timeout=15)
        r.raise_for_status()
        return r.json() if r.content else None

    def post(self, path: str, json=None):
        r = self.s.post(f"{REDMINE_URL}{path}", json=json, timeout=15)
        r.raise_for_status()
        return r.json() if r.content else None

    def delete(self, path: str):
        r = self.s.delete(f"{REDMINE_URL}{path}", timeout=15)
        r.raise_for_status()


# ---- Per-test helpers --------------------------------------------------------

@pytest.fixture
def unique() -> str:
    """A short unique tag for naming test-scoped resources."""
    return f"{int(time.time() * 1000) % 10_000_000:07d}"
