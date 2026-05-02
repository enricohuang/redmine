"""Project file upload + list."""

from __future__ import annotations


def test_file_upload_and_list(cli, project, unique, tmp_path):
    payload = b"release artifact " + unique.encode() + b" \x00\x01"
    src = tmp_path / f"release-{unique}.bin"
    src.write_bytes(payload)

    res = cli("file", "upload", str(src),
              "-p", project["identifier"],
              "--description", f"build {unique}",
              "--json").json()
    assert res["filename"] == src.name
    assert res["filesize"] == len(payload)
    assert res["description"] == f"build {unique}"

    listed = cli("file", "list", "-p", project["identifier"], "--json").json()
    match = next((f for f in listed if f["filename"] == src.name), None)
    assert match is not None
    assert match["filesize"] == len(payload)
    assert match["id"] == res["id"]


def test_file_upload_text_table_output(cli, project, unique, tmp_path):
    src = tmp_path / f"notes-{unique}.txt"
    src.write_text("plain text notes")

    res = cli("file", "upload", str(src), "-p", project["identifier"])
    assert res.returncode == 0
    assert src.name in res.stdout
