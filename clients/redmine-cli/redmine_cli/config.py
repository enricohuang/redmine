"""Multi-host configuration storage, modeled on the `gh` CLI.

hosts.yml shape:

    redmine.example.com:
      url: https://redmine.example.com
      user: alice                  # active user for this host
      users:
        alice:
          api_key: <40-char>
          login: alice             # optional, redmine login name
        bob:
          api_key: <40-char>

config.yml shape:

    default_host: redmine.example.com
"""

from __future__ import annotations

import os
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


def config_dir() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "redmine"


def hosts_path() -> Path:
    return config_dir() / "hosts.yml"


def config_path() -> Path:
    return config_dir() / "config.yml"


def _load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a YAML mapping")
    return data


def _dump_yaml(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, sort_keys=True, default_flow_style=False)
    tmp.replace(path)
    try:
        path.chmod(stat.S_IRUSR | stat.S_IWUSR)
    except OSError:
        pass


def load_hosts() -> dict[str, Any]:
    return _load_yaml(hosts_path())


def save_hosts(hosts: dict[str, Any]) -> None:
    _dump_yaml(hosts_path(), hosts)


def load_config() -> dict[str, Any]:
    return _load_yaml(config_path())


def save_config(cfg: dict[str, Any]) -> None:
    _dump_yaml(config_path(), cfg)


@dataclass(frozen=True)
class Credential:
    """Resolved credential for a CLI invocation."""

    host: str       # e.g. "redmine.example.com" (display key)
    url: str        # e.g. "https://redmine.example.com"
    user: str       # local label for the account (e.g. "alice")
    api_key: str

    @property
    def headers(self) -> dict[str, str]:
        return {"X-Redmine-API-Key": self.api_key}


class AuthError(Exception):
    pass


def add_user(host: str, url: str, user: str, api_key: str, *, make_active: bool = True) -> None:
    """Add or replace a user under a host. Optionally set as active."""
    hosts = load_hosts()
    h = hosts.setdefault(host, {})
    h["url"] = url.rstrip("/")
    users = h.setdefault("users", {})
    users[user] = {"api_key": api_key}
    if make_active or "user" not in h:
        h["user"] = user
    save_hosts(hosts)

    cfg = load_config()
    cfg.setdefault("default_host", host)
    save_config(cfg)


def remove_user(host: str, user: str | None = None) -> None:
    """Remove a single user, or the entire host if user is None."""
    hosts = load_hosts()
    if host not in hosts:
        raise AuthError(f"no such host: {host}")
    if user is None:
        del hosts[host]
    else:
        users = hosts[host].get("users", {})
        if user not in users:
            raise AuthError(f"no such user '{user}' on host {host}")
        del users[user]
        if hosts[host].get("user") == user:
            hosts[host]["user"] = next(iter(users), None)
            if hosts[host]["user"] is None:
                del hosts[host]
    save_hosts(hosts)

    cfg = load_config()
    if cfg.get("default_host") == host and host not in hosts:
        cfg["default_host"] = next(iter(hosts), None)
        if cfg["default_host"] is None:
            cfg.pop("default_host", None)
        save_config(cfg)


def switch_user(host: str, user: str) -> None:
    hosts = load_hosts()
    if host not in hosts:
        raise AuthError(f"no such host: {host}")
    if user not in hosts[host].get("users", {}):
        raise AuthError(f"no such user '{user}' on host {host}")
    hosts[host]["user"] = user
    save_hosts(hosts)


def set_default_host(host: str) -> None:
    hosts = load_hosts()
    if host not in hosts:
        raise AuthError(f"no such host: {host}")
    cfg = load_config()
    cfg["default_host"] = host
    save_config(cfg)


def resolve(host_override: str | None = None, user_override: str | None = None) -> Credential:
    """Resolve which credential to use for this invocation.

    Priority:
      1. Raw env: REDMINE_URL + REDMINE_API_KEY
      2. CLI flags --host / --user
      3. Env: REDMINE_HOST / REDMINE_USER
      4. config.yml: default_host + that host's active user
    """
    raw_url = os.environ.get("REDMINE_URL")
    raw_key = os.environ.get("REDMINE_API_KEY")
    if raw_url and raw_key:
        host = raw_url.split("://", 1)[-1].split("/", 1)[0]
        return Credential(host=host, url=raw_url.rstrip("/"), user="(env)", api_key=raw_key)

    hosts = load_hosts()
    if not hosts:
        raise AuthError(
            "not authenticated. Run `redmine auth login` "
            "or set REDMINE_URL and REDMINE_API_KEY."
        )

    cfg = load_config()
    host = host_override or os.environ.get("REDMINE_HOST") or cfg.get("default_host")
    if not host:
        host = next(iter(hosts))
    if host not in hosts:
        raise AuthError(f"host '{host}' not configured. See `redmine auth status`.")

    h = hosts[host]
    user = user_override or os.environ.get("REDMINE_USER") or h.get("user")
    users = h.get("users", {})
    if not users:
        raise AuthError(f"host '{host}' has no users configured.")
    if not user:
        user = next(iter(users))
    if user not in users:
        raise AuthError(f"user '{user}' not configured for host '{host}'.")

    api_key = users[user].get("api_key")
    if not api_key:
        raise AuthError(f"no api_key stored for {user}@{host}.")

    return Credential(host=host, url=h["url"], user=user, api_key=api_key)
