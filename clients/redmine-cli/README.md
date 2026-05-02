# redmine-cli

A command-line client for Redmine, designed for use by humans and AI agents. Wraps the Redmine REST API (including the fork-specific endpoints in this repository) with a `gh`-style multi-host auth model and JSON output mode for shell composition.

## Install

```bash
pipx install ./clients/redmine-cli           # recommended
# or
pip install ./clients/redmine-cli            # in a venv
```

After install, `redmine --help` should work.

## Auth (gh-style)

```bash
redmine auth login                           # interactive: host URL, API key, user label
redmine auth status                          # list configured hosts and active user per host
redmine auth switch --host redmine.example.com --user bob
redmine auth logout --host redmine.example.com [--user bob]
redmine auth token                           # print active API key (for piping)
```

Configuration:
- `~/.config/redmine/hosts.yml` — host → users → api_key, plus active user per host
- `~/.config/redmine/config.yml` — `default_host`, ui prefs

Environment overrides (CI-friendly):
- `REDMINE_HOST=host.example.com` and/or `REDMINE_USER=alice` — pick from configured hosts
- `REDMINE_URL=https://...` and `REDMINE_API_KEY=...` — bypass config entirely

## Common usage

```bash
redmine issue list --project mobile --status open --assignee me
redmine issue create -p mobile -t Bug -s "Crash on login" --description-file bug.md
redmine issue update 1234 --status Resolved --note "Fixed in v2.3"
redmine issue get 1234 --json | jq '.subject'

redmine wiki get -p mobile Home > home.md
redmine wiki update -p mobile Home --file home.md --comment "typo fix"

redmine search "login crash" --project mobile
```

Every read command supports `--json` for machine-readable output.

## Claude Code skill

A pre-written Claude Code skill ships with the CLI at [`skills/redmine/SKILL.md`](skills/redmine/SKILL.md). Once the agent has it, it will pick `redmine` over ad-hoc `curl` calls, follow the multi-host auth model, and use file/stdin input for long markdown.

Install it into your Claude config:

```bash
mkdir -p ~/.claude/skills/redmine
cp clients/redmine-cli/skills/redmine/SKILL.md ~/.claude/skills/redmine/
```

For project-scoped use (only active when working in this repo), put the file under `.claude/skills/redmine/SKILL.md` in the repo instead.

The skill is reloaded at the start of each Claude Code session — restart the session after installing it.

## Tests

```bash
pip install -e '.[test]'
REDMINE_URL=http://127.0.0.1:3000 REDMINE_API_KEY=... pytest
```

The pytest suite is end-to-end — it shells out to the installed `redmine` binary against a real Redmine. Without `REDMINE_URL` and `REDMINE_API_KEY` set, the suite is skipped cleanly. Each session creates and deletes its own scratch project; resources are scoped under it so concurrent runs don't collide.

## Output and exit codes

- Default output: human-readable (rich table for lists, formatted for single objects).
- `--json` flag: prints raw JSON from the API.
- Exit codes: `0` ok, `2` not found (HTTP 404), `3` validation (HTTP 422), `4` auth (HTTP 401/403), `5` network/server error.
