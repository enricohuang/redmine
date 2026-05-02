"""Name → ID resolvers for reference data passed to write commands.

Redmine's write API requires numeric IDs for status_id, tracker_id, priority_id,
category_id, fixed_version_id, etc. Agents (and humans) overwhelmingly know
these by name. These resolvers fetch the small reference lists once per process
and translate names case-insensitively.

A value that already looks like an integer is returned as-is — names and IDs
are interchangeable on the CLI surface.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Any

from .client import APIError, Client


def _is_int(value: str) -> bool:
    return value.isdigit() or (value.startswith("-") and value[1:].isdigit())


def _norm(name: str) -> str:
    return name.strip().lower()


def _resolve_by_name(items: list[dict], value: str, *, kind: str) -> int:
    target = _norm(value)
    for item in items:
        if _norm(item.get("name", "")) == target:
            return int(item["id"])
    valid = ", ".join(repr(i.get("name")) for i in items)
    raise APIError(f"unknown {kind} '{value}'. Valid: {valid}", exit_code=3)


@lru_cache(maxsize=None)
def _list(client_key: tuple[str, str], path: str, list_key: str) -> tuple[dict, ...]:
    """Cache reference lists per (host, api_key) so repeated calls are free.

    Note: lru_cache requires hashable args, hence the tuple key.
    """
    # The cache key encodes the credential — but we still need a Client instance.
    # We re-derive it lazily; in practice resolvers are always called from a
    # CLI command that has a Client at hand, so we accept it as the public API.
    raise RuntimeError("internal use: call resolve_*() helpers, not _list directly")


_REF_CACHE: dict[tuple[str, str, str], list[dict]] = {}


def _fetch(c: Client, path: str, list_key: str) -> list[dict]:
    cache_key = (c.cred.url, c.cred.api_key, path)
    if cache_key not in _REF_CACHE:
        data = c.get(path)
        _REF_CACHE[cache_key] = data.get(list_key, [])
    return _REF_CACHE[cache_key]


def resolve_status(c: Client, value: str | None) -> Any:
    if value is None or _is_int(value):
        return value
    return _resolve_by_name(_fetch(c, "/issue_statuses.json", "issue_statuses"),
                            value, kind="status")


def resolve_tracker(c: Client, value: str | None) -> Any:
    if value is None or _is_int(value):
        return value
    return _resolve_by_name(_fetch(c, "/trackers.json", "trackers"),
                            value, kind="tracker")


def resolve_priority(c: Client, value: str | None) -> Any:
    if value is None or _is_int(value):
        return value
    items = _fetch(c, "/enumerations/issue_priorities.json", "issue_priorities")
    return _resolve_by_name(items, value, kind="priority")


def resolve_assignee(c: Client, value: str | None) -> Any:
    """Special: 'me' / numeric ID / login name."""
    if value is None or value == "me" or _is_int(value):
        return value
    # Look up by login. /users.json supports `name=` substring; we want exact login.
    data = c.get("/users.json", name=value, limit=100)
    for u in data.get("users", []):
        if u.get("login", "").lower() == value.lower():
            return int(u["id"])
    raise APIError(f"no user with login '{value}'", exit_code=3)


def resolve_category(c: Client, project: str, value: str | None) -> Any:
    if value is None or _is_int(value):
        return value
    items = _fetch(c, f"/projects/{project}/issue_categories.json",
                   "issue_categories")
    return _resolve_by_name(items, value, kind="category")


def resolve_version(c: Client, project: str, value: str | None) -> Any:
    if value is None or _is_int(value):
        return value
    items = _fetch(c, f"/projects/{project}/versions.json", "versions")
    return _resolve_by_name(items, value, kind="version")
