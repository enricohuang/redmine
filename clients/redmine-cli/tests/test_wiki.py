"""Wiki CRUD plus fork endpoints (history, rename, protect)."""

from __future__ import annotations

import pytest


# Each test gets its own unique page name so they don't trample one another
# inside the shared session project.
@pytest.fixture
def page_title(unique):
    # Capitalize so Redmine accepts it as a wiki page id (no spaces).
    return f"Page{unique}"


def test_update_then_get(cli, project, page_title):
    body = "# hello\n\nfrom wiki test\n"
    cli("wiki", "update", "-p", project["identifier"], page_title,
        "--text", body, "--comment", "initial")
    res = cli("wiki", "get", "-p", project["identifier"], page_title, "--json")
    page = res.json()
    assert page["title"] == page_title
    assert page["text"] == body
    assert page["version"] == 1


def test_get_text_only_strips_metadata(cli, project, page_title):
    body = "raw\nbody\nlines\n"
    cli("wiki", "update", "-p", project["identifier"], page_title,
        "--text", body)
    res = cli("wiki", "get", "-p", project["identifier"], page_title, "--text")
    assert res.stdout == body


def test_update_via_file_and_stdin(cli, project, page_title, tmp_path):
    f = tmp_path / "page.md"
    f.write_text("from file\n")
    cli("wiki", "update", "-p", project["identifier"], page_title,
        "--file", str(f))
    assert "from file" in cli("wiki", "get", "-p", project["identifier"],
                              page_title, "--text").stdout

    cli("wiki", "update", "-p", project["identifier"], page_title,
        "--file", "-", stdin="from stdin\n")
    assert "from stdin" in cli("wiki", "get", "-p", project["identifier"],
                               page_title, "--text").stdout


def test_history_after_two_versions(cli, project, page_title):
    cli("wiki", "update", "-p", project["identifier"], page_title,
        "--text", "v1", "--comment", "one")
    cli("wiki", "update", "-p", project["identifier"], page_title,
        "--text", "v2", "--comment", "two")
    res = cli("wiki", "history", "-p", project["identifier"], page_title, "--json")
    versions = res.json()
    assert len(versions) >= 2
    assert {v["version_number"] for v in versions} >= {1, 2}


def test_rename(cli, project, unique):
    src = f"Old{unique}"
    dst = f"New{unique}"
    cli("wiki", "update", "-p", project["identifier"], src, "--text", "x")
    cli("wiki", "rename", "-p", project["identifier"], src, "--to", dst,
        "--no-redirect")
    # Old title 404s, new one resolves.
    res = cli("wiki", "get", "-p", project["identifier"], dst, "--json")
    assert res.json()["title"] == dst


def test_protect_toggle(cli, project, page_title, api):
    cli("wiki", "update", "-p", project["identifier"], page_title, "--text", "x")
    cli("wiki", "protect", "-p", project["identifier"], page_title, "--on")
    page = api.get(f"/projects/{project['identifier']}/wiki/{page_title}.json")
    assert page["wiki_page"]["protected"] is True
    cli("wiki", "protect", "-p", project["identifier"], page_title, "--off")
    page = api.get(f"/projects/{project['identifier']}/wiki/{page_title}.json")
    assert page["wiki_page"]["protected"] is False


def test_list_includes_page(cli, project, page_title):
    cli("wiki", "update", "-p", project["identifier"], page_title, "--text", "x")
    res = cli("wiki", "list", "-p", project["identifier"], "--json")
    titles = [p["title"] for p in res.json()]
    assert page_title in titles


def test_delete_page(cli, project, unique):
    title = f"Dead{unique}"
    cli("wiki", "update", "-p", project["identifier"], title, "--text", "x")
    cli("wiki", "delete", "-p", project["identifier"], title, "-y")
    res = cli("wiki", "get", "-p", project["identifier"], title, check=False)
    assert res.returncode == 2
