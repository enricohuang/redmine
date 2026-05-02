"""Sanity checks the rest of the suite depends on."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def test_binary_runs(cli):
    """`redmine --version` works and prints something sensible."""
    bin = Path(sys.executable).parent / "redmine"
    proc = subprocess.run([str(bin), "--version"], capture_output=True, text=True, timeout=10)
    assert proc.returncode == 0
    assert "redmine-cli" in proc.stdout


def test_help_lists_subcommands(cli):
    """Top-level --help advertises all v1 commands."""
    res = cli("--help")
    for sub in ("auth", "issue", "project", "wiki", "journal",
                "attachment", "label", "search", "user"):
        assert sub in res.stdout, f"{sub} missing from --help: {res.stdout}"


def test_project_fixture_resolves(project):
    """The session project fixture actually returns a usable record."""
    assert project["id"]
    assert project["identifier"].startswith("e2e-")
