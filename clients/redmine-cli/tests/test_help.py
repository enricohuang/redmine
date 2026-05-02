"""Tests for the help system: topics, dump, examples in --help."""

from __future__ import annotations

import pytest


# Help commands don't hit the Redmine API, but the conftest skip guard
# already required REDMINE_URL/REDMINE_API_KEY at import time, so we get the
# session env for free here too.

EXPECTED_TOPICS = {
    "getting-started", "auth", "issues", "wiki", "attachments",
    "labels", "journals", "search", "automation", "troubleshooting",
    "reference",
}


def test_help_lists_every_topic(cli):
    res = cli("help")
    for topic in EXPECTED_TOPICS:
        assert topic in res.stdout, f"topic '{topic}' missing from `redmine help` index"
    # Discovery hints also present.
    assert "redmine help all" in res.stdout
    assert "redmine help <topic>" in res.stdout


@pytest.mark.parametrize("topic", sorted(EXPECTED_TOPICS))
def test_each_topic_has_content(cli, topic):
    res = cli("help", topic)
    assert res.stdout.strip(), f"topic '{topic}' returned empty"
    # Topics start with a markdown heading.
    assert res.stdout.lstrip().startswith("#"), \
        f"topic '{topic}' should start with a heading"


def test_unknown_topic_exits_2_with_helpful_message(cli):
    res = cli("help", "nope-this-does-not-exist", check=False)
    assert res.returncode == 2
    assert "unknown topic" in res.stderr.lower()
    # Lists valid options so the agent can pick the right one.
    assert "Available:" in res.stderr


def test_help_all_dumps_every_command(cli):
    """`help all` should print --help for every (sub)command, header included."""
    res = cli("help", "all")
    out = res.stdout
    # Section headers are formatted as `$ redmine ... --help`.
    expected_headers = [
        "$ redmine --help",
        "$ redmine help --help",
        "$ redmine auth --help",
        "$ redmine auth login --help",
        "$ redmine auth status --help",
        "$ redmine auth switch --help",
        "$ redmine issue --help",
        "$ redmine issue list --help",
        "$ redmine issue create --help",
        "$ redmine issue update --help",
        "$ redmine issue delete --help",
        "$ redmine project --help",
        "$ redmine wiki --help",
        "$ redmine wiki rename --help",
        "$ redmine wiki protect --help",
        "$ redmine wiki history --help",
        "$ redmine journal --help",
        "$ redmine attachment --help",
        "$ redmine attachment attach --help",
        "$ redmine label --help",
        "$ redmine search --help",
        "$ redmine user --help",
    ]
    for header in expected_headers:
        assert header in out, f"`help all` missing section: {header}"


def test_individual_help_includes_examples(cli):
    """Spot-check that the example block we added appears in --help output."""
    res = cli("issue", "create", "--help")
    assert "Examples" in res.stdout, "issue create --help should show an Examples section"
    assert "redmine issue create" in res.stdout, "examples should reference the command"


def test_top_level_help_advertises_help_command(cli):
    res = cli("--help")
    assert "help" in res.stdout, "root --help should list the `help` subcommand"


def test_help_dump_is_self_contained(cli):
    """One bash call should yield the entire CLI surface — measure rough size."""
    res = cli("help", "all")
    # Should be substantial (every command's --help). Empirically ~10kB+.
    assert len(res.stdout) > 5000, \
        f"`help all` output is suspiciously small ({len(res.stdout)} bytes)"
