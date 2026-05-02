"""News CRUD."""

from __future__ import annotations


def test_news_lifecycle(cli, project, unique):
    title = f"n-{unique}"
    res = cli("news", "create", "-p", project["identifier"],
              "--title", title, "--description", "body text", "--json").json()
    nid = res["id"]
    assert res["title"] == title

    listed = cli("news", "list", "-p", project["identifier"], "--json").json()
    assert any(n["id"] == nid for n in listed)

    got = cli("news", "get", str(nid), "--json").json()
    assert got["title"] == title

    cli("news", "update", str(nid), "--title", title + "-edit")
    assert cli("news", "get", str(nid), "--json").json()["title"] == title + "-edit"

    cli("news", "delete", str(nid), "-y")
    assert cli("news", "get", str(nid), check=False).returncode == 2


def test_news_create_with_file(cli, project, unique, tmp_path):
    p = tmp_path / "body.md"
    p.write_text("# header\n\nlong body content")
    res = cli("news", "create", "-p", project["identifier"],
              "--title", f"file-{unique}",
              "--description-file", str(p), "--json").json()
    assert "long body" in res["description"]
    cli("news", "delete", str(res["id"]), "-y")
