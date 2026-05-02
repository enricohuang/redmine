"""Document CRUD + attach lifecycle."""

from __future__ import annotations

import pytest


@pytest.fixture(scope="module")
def doc_category(cli):
    """Pick the first available document category for the test run."""
    cats = cli("enumeration", "list", "document_categories", "--json").json()
    if not cats:
        pytest.skip("no document_categories configured on this Redmine")
    return cats[0]


def test_document_lifecycle(cli, project, unique, doc_category):
    title = f"doc-{unique}"
    res = cli("document", "create",
              "-p", project["identifier"],
              "--category", doc_category["name"],
              "--title", title,
              "--description", "initial body",
              "--json").json()
    did = res["id"]
    assert res["title"] == title
    assert res["category"]["id"] == doc_category["id"]

    listed = cli("document", "list", "-p", project["identifier"], "--json").json()
    assert any(d["id"] == did for d in listed)

    got = cli("document", "get", str(did), "--json").json()
    assert got["title"] == title
    assert got["description"] == "initial body"

    cli("document", "update", str(did), "--title", title + "-edit",
        "--description", "edited body")
    got = cli("document", "get", str(did), "--json").json()
    assert got["title"] == title + "-edit"
    assert got["description"] == "edited body"

    cli("document", "delete", str(did), "-y")
    assert cli("document", "get", str(did), check=False).returncode == 2


def test_document_create_with_file(cli, project, unique, doc_category, tmp_path):
    body_md = tmp_path / "body.md"
    body_md.write_text("# heading\n\nsome long markdown body text")
    title = f"docfile-{unique}"
    res = cli("document", "create",
              "-p", project["identifier"],
              "--category", str(doc_category["id"]),  # numeric id path
              "--title", title,
              "--description-file", str(body_md),
              "--json").json()
    assert "long markdown" in res["description"]
    cli("document", "delete", str(res["id"]), "-y")


def test_document_attach(cli, project, unique, doc_category, tmp_path):
    title = f"docatt-{unique}"
    res = cli("document", "create",
              "-p", project["identifier"],
              "--category", doc_category["name"],
              "--title", title,
              "--description", "with attachment",
              "--json").json()
    did = res["id"]

    payload = b"attachment payload \x00\x01 end"
    src = tmp_path / "note.bin"
    src.write_bytes(payload)
    cli("document", "attach", str(src), "--document", str(did),
        "--description", "test attachment")

    got = cli("document", "get", str(did), "--include", "attachments", "--json").json()
    atts = got.get("attachments") or []
    assert len(atts) == 1
    att = atts[0]
    assert att["filename"] == "note.bin"
    assert att["description"] == "test attachment"
    assert att["filesize"] == len(payload)

    cli("document", "delete", str(did), "-y")


def test_document_unknown_category_exits_3(cli, project, unique):
    res = cli("document", "create",
              "-p", project["identifier"],
              "--category", f"no-such-category-{unique}",
              "--title", f"bad-{unique}",
              "--description", "x",
              check=False)
    assert res.returncode == 3
    assert "unknown document category" in res.stderr
