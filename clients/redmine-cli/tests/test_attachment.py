"""Upload / attach / get / download for attachments."""

from __future__ import annotations

import pytest


@pytest.fixture
def issue_for_attach(cli, project, unique):
    obj = cli("issue", "create",
              "-p", project["identifier"],
              "-s", f"attach {unique}",
              "--description", "for attachment tests",
              "--json").json()
    yield obj
    cli("issue", "delete", str(obj["id"]), "-y", check=False)


def test_upload_returns_token(cli, tmp_path):
    p = tmp_path / "a.txt"
    p.write_text("hello attach")
    res = cli("attachment", "upload", str(p))
    token = res.stdout.strip()
    assert token  # non-empty
    assert len(token) >= 20  # Redmine tokens are long


def test_attach_to_issue_and_download(cli, issue_for_attach, tmp_path):
    iid = issue_for_attach["id"]
    src = tmp_path / "doc.txt"
    payload = b"binary-ish payload \x00\x01\x02 end"
    src.write_bytes(payload)
    cli("attachment", "attach", str(src), "-i", str(iid),
        "--description", "from e2e")

    issue = cli("issue", "get", str(iid), "--include", "attachments", "--json").json()
    atts = issue.get("attachments") or []
    assert len(atts) == 1
    att = atts[0]
    assert att["filename"] == "doc.txt"
    assert att["description"] == "from e2e"
    assert att["filesize"] == len(payload)

    out = tmp_path / "downloaded.bin"
    cli("attachment", "download", str(att["id"]), "-o", str(out))
    assert out.read_bytes() == payload


def test_attachment_get_metadata(cli, issue_for_attach, tmp_path):
    iid = issue_for_attach["id"]
    src = tmp_path / "meta.txt"
    src.write_text("meta only")
    cli("attachment", "attach", str(src), "-i", str(iid))
    issue = cli("issue", "get", str(iid), "--include", "attachments", "--json").json()
    aid = issue["attachments"][0]["id"]
    meta = cli("attachment", "get", str(aid), "--json").json()
    assert meta["id"] == aid
    assert meta["filename"] == "meta.txt"
