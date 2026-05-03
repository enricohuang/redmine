"""End-to-end tests for the fork's Elasticsearch-backed search.

These tests require BOTH:
  * The fork's dev server running (already required by the rest of the suite).
  * A reachable Elasticsearch instance the fork is configured against,
    with the index built (`rake redmine:elasticsearch:create_index` and
    `rake redmine:elasticsearch:reindex_all`).

If Elasticsearch isn't reachable, the whole module skips cleanly so devs
without ES still get a green suite. If ES is reachable but the fork's
endpoint isn't (e.g. server is up but the ES initializer didn't load), we
fail loudly — that means the fork is misconfigured rather than absent.
"""

from __future__ import annotations

import os
import time

import pytest
import requests


ES_URL = os.environ.get("ELASTICSEARCH_URL", "http://127.0.0.1:9200").rstrip("/")
REDMINE_URL = os.environ["REDMINE_URL"].rstrip("/")
REDMINE_API_KEY = os.environ["REDMINE_API_KEY"]


def _es_reachable() -> bool:
    try:
        r = requests.get(ES_URL + "/", timeout=2)
        return r.ok
    except requests.RequestException:
        return False


@pytest.fixture(scope="module", autouse=True)
def _require_elasticsearch():
    """Skip the module if ES is down; verify the fork endpoint if it's up."""
    if not _es_reachable():
        pytest.skip(
            f"Elasticsearch not reachable at {ES_URL} — skipping fork ES suite. "
            "Start ES (e.g. /opt/elasticsearch/bin/elasticsearch) to run these tests."
        )
    # ES is up. Confirm the fork's JSON endpoint is wired up. Anything other
    # than 2xx here means the fork's ES initializer didn't pick up the config
    # or the controller doesn't speak JSON — that's a fork bug, not a missing
    # dep, so fail rather than skip.
    r = requests.get(
        f"{REDMINE_URL}/elasticsearch_search.json",
        headers={"X-Redmine-API-Key": REDMINE_API_KEY,
                 "Accept": "application/json"},
        params={"q": "anything"},
        timeout=10,
    )
    if r.status_code == 503:
        pytest.fail(
            "Fork reports Elasticsearch unavailable (503). ES is up but the "
            "fork isn't using it. Check config/elasticsearch.yml and that the "
            "Rails server was restarted after the config landed."
        )
    if not r.ok:
        pytest.fail(
            f"Fork's /elasticsearch_search.json returned {r.status_code}: "
            f"{r.text[:300]}"
        )


def _trigger_reindex():
    """Best-effort: nudge the fork to re-index recent rows.

    Indexing of new rows is normally async (after_commit hook), but on a
    cold dev box it can lag behind the test creating an issue. We give the
    server a beat, then poll the search endpoint until the doc shows up.
    """
    time.sleep(0.5)


def _search_for(needle: str, project_id: str | None = None, limit: int = 25) -> list[dict]:
    params = {"q": needle, "per_page": limit}
    if project_id:
        params["project_ids[]"] = [project_id]
    r = requests.get(
        f"{REDMINE_URL}/elasticsearch_search.json",
        headers={"X-Redmine-API-Key": REDMINE_API_KEY,
                 "Accept": "application/json"},
        params=params,
        timeout=10,
    )
    r.raise_for_status()
    return r.json().get("results", [])


# ---- Tests -------------------------------------------------------------------

def test_search_command_returns_json(cli, project, unique):
    """`elasticsearch search` returns a JSON envelope with hits/aggregations."""
    subj = f"esneedle{unique}"
    obj = cli("issue", "create",
              "-p", project["identifier"],
              "-s", subj,
              "--description", f"unique-marker-{unique}-payload",
              "--json").json()
    try:
        # Poll: indexing is async via the after_commit hook.
        deadline = time.time() + 15
        result = None
        while time.time() < deadline:
            res = cli("elasticsearch", "search", subj,
                      "-p", project["identifier"], "--json")
            data = res.json()
            assert isinstance(data, dict)
            assert "results" in data
            assert "total_count" in data
            assert "aggregations" in data
            for r in data["results"]:
                if r.get("id") == obj["id"] and r.get("type") == "issue":
                    result = r
                    break
            if result:
                break
            time.sleep(1)
        assert result is not None, (
            f"issue {obj['id']} (subject {subj!r}) did not appear in ES "
            f"search within 15s — indexing pipeline broken?"
        )
        assert "score" in result and result["score"] > 0
        assert result["project_identifier"] == project["identifier"]
    finally:
        cli("issue", "delete", str(obj["id"]), "-y")


def test_search_table_output_renders(cli, project, unique):
    """Default (non-JSON) output renders without crashing and includes columns."""
    subj = f"estable{unique}"
    obj = cli("issue", "create",
              "-p", project["identifier"],
              "-s", subj, "--json").json()
    try:
        # Wait for index.
        deadline = time.time() + 15
        while time.time() < deadline:
            data = _search_for(subj, project["identifier"])
            if any(r.get("id") == obj["id"] for r in data):
                break
            time.sleep(1)
        res = cli("elasticsearch", "search", subj, "-p", project["identifier"])
        # Header columns from the command:
        for col in ("Type", "ID", "Title", "Score", "Project"):
            assert col in res.stdout, f"missing {col!r} in output:\n{res.stdout}"
    finally:
        cli("issue", "delete", str(obj["id"]), "-y")


def test_search_type_filter_excludes_other_types(cli, project, unique):
    """`--type wiki_page` should not return issue hits for the same query."""
    subj = f"estypef{unique}"
    obj = cli("issue", "create",
              "-p", project["identifier"], "-s", subj, "--json").json()
    try:
        # Make sure the issue is indexed first.
        deadline = time.time() + 15
        while time.time() < deadline:
            if any(r.get("id") == obj["id"]
                   for r in _search_for(subj, project["identifier"])):
                break
            time.sleep(1)
        res = cli("elasticsearch", "search", subj,
                  "-p", project["identifier"],
                  "--type", "wiki_page", "--json")
        data = res.json()
        # No issues should leak through the wiki_page-only filter.
        for r in data.get("results", []):
            assert r.get("type") == "wiki_page", (
                f"--type wiki_page returned a {r.get('type')!r}: {r}"
            )
    finally:
        cli("issue", "delete", str(obj["id"]), "-y")


def test_search_project_scope_excludes_other_projects(cli, project, unique):
    """`-p PROJECT` must not broaden to all visible projects."""
    other_project = f"e2e-es-scope-{unique}"
    other_issue = None
    cli("project", "create",
        "--identifier", other_project,
        "--name", f"es scope {unique}",
        "--modules", "issue_tracking",
        "--json")
    try:
        subj = f"esscopeonly{unique}"
        other_issue = cli("issue", "create",
                          "-p", other_project,
                          "-s", subj,
                          "--json").json()

        # Wait until the other project's issue is visible in the global ES
        # index; otherwise an empty scoped result would not prove filtering.
        deadline = time.time() + 15
        while time.time() < deadline:
            if any(r.get("id") == other_issue["id"] for r in _search_for(subj)):
                break
            time.sleep(1)
        else:
            pytest.fail(
                f"issue {other_issue['id']} did not appear in global ES search "
                "within 15s"
            )

        res = cli("elasticsearch", "search", subj,
                  "-p", project["identifier"], "--json")
        data = res.json()
        assert all(r.get("id") != other_issue["id"] for r in data.get("results", []))
    finally:
        if other_issue:
            cli("issue", "delete", str(other_issue["id"]), "-y", check=False)
        cli("project", "delete", other_project, "-y", check=False)


def test_search_no_match_returns_empty_results(cli, project):
    res = cli("elasticsearch", "search",
              "this-string-should-match-nothing-zzqq-99999",
              "-p", project["identifier"], "--json")
    data = res.json()
    assert data["results"] == []
    assert data["total_count"] == 0


def test_stats_command(cli, project, unique):
    """`elasticsearch stats` summarizes aggregations for a query."""
    subj = f"esstats{unique}"
    obj = cli("issue", "create",
              "-p", project["identifier"], "-s", subj, "--json").json()
    try:
        # Wait for index.
        deadline = time.time() + 15
        while time.time() < deadline:
            if any(r.get("id") == obj["id"]
                   for r in _search_for(subj, project["identifier"])):
                break
            time.sleep(1)
        res = cli("elasticsearch", "stats", subj,
                  "-p", project["identifier"], "--json")
        data = res.json()
        assert data["query"] == subj
        assert data["total_count"] >= 1
        assert any(b.get("key") == "issue" for b in data["by_type"])
    finally:
        cli("issue", "delete", str(obj["id"]), "-y")
