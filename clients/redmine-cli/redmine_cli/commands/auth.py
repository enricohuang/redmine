"""`redmine auth ...` — gh-style credential management."""

from __future__ import annotations

import getpass
from typing import Optional
from urllib.parse import urlparse

import requests
import typer

from ..client import die
from ..config import (
    AuthError,
    add_user,
    load_config,
    load_hosts,
    remove_user,
    resolve,
    set_default_host,
    switch_user,
)

app = typer.Typer(
    no_args_is_help=True,
    help=(
        "Manage Redmine credentials (gh-style multi-host).\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine auth login --url https://redmine.example.com --api-key <KEY>\n"
        "redmine auth status\n"
        "redmine auth switch --host redmine.example.com --user readonly\n"
        "redmine auth token                  # print active key\n"
        "redmine auth logout --host redmine.example.com\n"
        "```\n\n"
        "Tutorial: `redmine help auth`"
    ),
)


def _host_from_url(url: str) -> str:
    parsed = urlparse(url)
    if not parsed.scheme:
        parsed = urlparse("https://" + url)
    if not parsed.hostname:
        raise typer.BadParameter(f"could not parse host from URL: {url}")
    return parsed.hostname


def _verify(url: str, api_key: str) -> dict:
    """Hit /users/current.json to confirm the key works; return user dict."""
    r = requests.get(
        url.rstrip("/") + "/users/current.json",
        headers={"X-Redmine-API-Key": api_key, "Accept": "application/json"},
        timeout=15,
    )
    if r.status_code in (401, 403):
        raise typer.BadParameter("the API key was rejected by the server.")
    if r.status_code >= 400:
        raise typer.BadParameter(f"server returned HTTP {r.status_code}: {r.text[:200]}")
    return r.json().get("user", {})


@app.command(
    "login",
    help=(
        "Add a credential. Interactive if `--url` or `--api-key` is missing.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine auth login                                    # interactive prompts\n"
        "redmine auth login --url https://x.com --api-key K   # script-friendly\n"
        "redmine auth login --url https://x.com --api-key K2 \\\n"
        "                   --label readonly --no-set-default  # second account\n"
        "```"
    ),
)
def login(
    url: Optional[str] = typer.Option(None, "--url", help="Redmine base URL (e.g. https://redmine.example.com)."),
    api_key: Optional[str] = typer.Option(None, "--api-key", help="API key. If omitted, you'll be prompted."),
    label: Optional[str] = typer.Option(None, "--label", help="Local label to identify this account (defaults to Redmine login)."),
    set_default: bool = typer.Option(True, "--set-default/--no-set-default", help="Make this the default host."),
    no_verify: bool = typer.Option(False, "--no-verify", help="Skip the /users/current.json verification step."),
):
    """Add a credential. Interactive if --url or --api-key is missing."""
    if not url:
        url = typer.prompt("Redmine URL").strip()
    url = url.rstrip("/")
    if not api_key:
        api_key = getpass.getpass("API key (input hidden): ").strip()
    if not api_key:
        die("API key is required.", code=2)

    if not no_verify:
        user = _verify(url, api_key)
        login_name = user.get("login") or "user"
    else:
        login_name = "user"

    host = _host_from_url(url)
    final_label = label or login_name

    add_user(host, url, final_label, api_key, make_active=True)
    if set_default:
        set_default_host(host)
    typer.echo(f"saved {final_label}@{host} (default={set_default})")


@app.command(
    "status",
    help=(
        "List configured hosts and their users. Active user is marked with `*`.\n\n"
        "Exits non-zero if no hosts are configured."
    ),
)
def status():
    """List configured hosts and their users."""
    hosts = load_hosts()
    cfg = load_config()
    if not hosts:
        typer.echo("not authenticated. Run `redmine auth login`.")
        raise typer.Exit(code=1)
    default = cfg.get("default_host")
    for host, h in hosts.items():
        marker = " (default)" if host == default else ""
        typer.echo(f"{host}{marker}  -> {h.get('url')}")
        active = h.get("user")
        for u in h.get("users", {}):
            tag = " *" if u == active else "  "
            typer.echo(f"   {tag} {u}")


@app.command(
    "switch",
    help=(
        "Change the active user for a host.\n\n"
        "**Example:** `redmine auth switch --host redmine.example.com --user bob`"
    ),
)
def switch(
    host: Optional[str] = typer.Option(None, "--host"),
    user: str = typer.Option(..., "--user", help="User label to make active."),
):
    """Change the active user for a host."""
    if not host:
        cfg = load_config()
        host = cfg.get("default_host")
        if not host:
            die("--host is required (no default set).", code=2)
    try:
        switch_user(host, user)
    except AuthError as e:
        die(str(e), code=2)
    typer.echo(f"active user for {host} is now {user}")


@app.command(
    "logout",
    help=(
        "Remove a user — or an entire host — from the credential store.\n\n"
        "**Examples:**\n\n"
        "```\n"
        "redmine auth logout --host redmine.example.com               # whole host\n"
        "redmine auth logout --host redmine.example.com --user bob    # one user\n"
        "```"
    ),
)
def logout(
    host: str = typer.Option(..., "--host"),
    user: Optional[str] = typer.Option(None, "--user", help="If omitted, removes the entire host."),
):
    """Remove a user (or an entire host) from the credential store."""
    try:
        remove_user(host, user)
    except AuthError as e:
        die(str(e), code=2)
    typer.echo(f"removed {user + '@' if user else ''}{host}")


@app.command(
    "token",
    help=(
        "Print the active API key. Useful for piping into `curl`:\n\n"
        "```\n"
        "curl -H \"X-Redmine-API-Key: $(redmine auth token)\" $URL/foo.json\n"
        "```"
    ),
)
def token(
    host: Optional[str] = typer.Option(None, "--host"),
    user: Optional[str] = typer.Option(None, "--user"),
):
    """Print the active API key (useful for piping into curl)."""
    try:
        cred = resolve(host, user)
    except AuthError as e:
        die(str(e), code=4)
    typer.echo(cred.api_key)


@app.command(
    "set-default",
    help=(
        "Set the default host (used when neither `--host` nor "
        "`REDMINE_HOST` is given).\n\n"
        "**Example:** `redmine auth set-default redmine.example.com`"
    ),
)
def cmd_set_default(host: str = typer.Argument(...)):
    """Set the default host used when --host / REDMINE_HOST are not given."""
    try:
        set_default_host(host)
    except AuthError as e:
        die(str(e), code=2)
    typer.echo(f"default host: {host}")
