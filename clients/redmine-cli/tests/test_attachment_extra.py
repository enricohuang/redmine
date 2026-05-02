"""Update / delete / thumbnail for attachments."""

from __future__ import annotations

import struct
import zlib

import pytest


@pytest.fixture
def issue_for_attach(cli, project, unique):
    obj = cli("issue", "create",
              "-p", project["identifier"],
              "-s", f"attach-extra {unique}",
              "--description", "for attachment extras tests",
              "--json").json()
    yield obj
    cli("issue", "delete", str(obj["id"]), "-y", check=False)


def _tiny_png_bytes() -> bytes:
    """Return a minimal valid 1x1 transparent PNG."""
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = b"IHDR" + struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    ihdr_chunk = struct.pack(">I", 13) + ihdr + struct.pack(">I", zlib.crc32(ihdr))
    idat_data = zlib.compress(b"\x00\x00\x00\x00\x00")
    idat = b"IDAT" + idat_data
    idat_chunk = struct.pack(">I", len(idat_data)) + idat + struct.pack(">I", zlib.crc32(idat))
    iend = b"IEND"
    iend_chunk = struct.pack(">I", 0) + iend + struct.pack(">I", zlib.crc32(iend))
    return sig + ihdr_chunk + idat_chunk + iend_chunk


def _attach_file_and_get_id(cli, issue_id: int, src_path) -> int:
    cli("attachment", "attach", str(src_path), "-i", str(issue_id))
    issue = cli("issue", "get", str(issue_id), "--include", "attachments", "--json").json()
    atts = issue.get("attachments") or []
    assert atts, "expected at least one attachment"
    return atts[-1]["id"]


def test_attachment_update_description(cli, issue_for_attach, tmp_path):
    iid = issue_for_attach["id"]
    src = tmp_path / "u.txt"
    src.write_text("update me")
    aid = _attach_file_and_get_id(cli, iid, src)

    cli("attachment", "update", str(aid), "--description", "edited via cli")
    meta = cli("attachment", "get", str(aid), "--json").json()
    assert meta["description"] == "edited via cli"


def test_attachment_update_filename(cli, issue_for_attach, tmp_path):
    iid = issue_for_attach["id"]
    src = tmp_path / "rename-me.txt"
    src.write_text("rename me")
    aid = _attach_file_and_get_id(cli, iid, src)

    cli("attachment", "update", str(aid), "--filename", "renamed.txt")
    meta = cli("attachment", "get", str(aid), "--json").json()
    assert meta["filename"] == "renamed.txt"


def test_attachment_update_requires_a_field(cli):
    res = cli("attachment", "update", "1", check=False)
    assert res.returncode == 2
    assert "nothing to update" in res.stderr


def test_attachment_delete(cli, issue_for_attach, tmp_path):
    iid = issue_for_attach["id"]
    src = tmp_path / "doomed.txt"
    src.write_text("doomed")
    aid = _attach_file_and_get_id(cli, iid, src)

    cli("attachment", "delete", str(aid), "-y")
    res = cli("attachment", "get", str(aid), "--json", check=False)
    assert res.returncode != 0  # 404 -> exit 2 (EXIT_NOT_FOUND)


def test_attachment_thumbnail(cli, issue_for_attach, tmp_path):
    """Server may not have ImageMagick — accept a clean failure as a skip."""
    iid = issue_for_attach["id"]
    src = tmp_path / "tiny.png"
    src.write_bytes(_tiny_png_bytes())
    aid = _attach_file_and_get_id(cli, iid, src)

    out = tmp_path / "thumb.png"
    res = cli("attachment", "thumbnail", str(aid), "-o", str(out), check=False)
    if res.returncode != 0:
        pytest.skip(f"thumbnail not available on this server: {res.stderr.strip()}")
    assert out.exists()
    # PNG magic bytes — Redmine always renders thumbnails as PNG
    assert out.read_bytes()[:4] == b"\x89PNG"
