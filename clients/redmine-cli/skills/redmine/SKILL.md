---
name: redmine
description: Use when the user asks to create, edit, comment on, search, or close Redmine issues; manage Redmine projects, wiki pages, attachments, or labels; or when a Redmine URL appears in scope. Drives the `redmine` CLI which wraps the REST API of this fork.
---

# Redmine CLI skill

The `redmine` CLI is a thin wrapper around the Redmine REST API of this fork (Issues, Projects, Wiki, Journals, Attachments, Labels, Search, Users, plus fork-specific endpoints). Use it instead of writing ad-hoc `curl` calls — it handles auth, pagination, error mapping, and JSON output for piping to `jq`.

## Discovery (when this skill isn't enough)

The CLI ships its own help system. Use it when you've forgotten a flag, hit an unfamiliar resource, or want to confirm exact syntax before acting:

```bash
redmine help                    # list topic tutorials
redmine help <topic>            # focused tutorial: auth, issues, wiki, attachments,
                                #   labels, journals, search, automation,
                                #   troubleshooting, getting-started, reference
redmine help all                # full --help for every command, in one bash call
                                # (preferred over many separate --help calls)
redmine <cmd> --help            # individual command, with examples
```

Reach for `redmine help all` when you need a CLI-wide refresher (one Bash call → full surface). Reach for `redmine help <topic>` when you know the workflow but not the commands. Reach for `--help` on a single command when you're picking flags.

## Setup check

Before any Redmine command, verify auth is configured:

```bash
redmine auth status
```

- If it prints `not authenticated`, ask the user for the URL and API key, then run:
  `redmine auth login --url <URL> --api-key <KEY> --label <name>`
- If multiple hosts are configured, use `--host` and/or `--user` to target a specific one, e.g. `redmine --host work.example.com issue list`.
- For one-off CI use, set `REDMINE_URL` and `REDMINE_API_KEY` env vars and skip the config file entirely.

## Output mode

Every list/get command supports `--json`. Use it whenever you need to extract fields with `jq` or compute on the result. Default output is a human-readable table.

Exit codes: `0` ok, `2` not found, `3` validation, `4` auth, `5` network. Treat non-zero as a hard failure unless you're explicitly probing existence.

## The 10 commands you'll actually use

```bash
# Issues
redmine issue list -p PROJECT [--status open|closed|*] [--assignee me|ID]
redmine issue get ID [--json]
redmine issue create -p PROJECT -s "subject" -t Bug --description-file body.md
redmine issue update ID --status Resolved --note "fix shipped"
redmine issue update ID --note-file comment.md       # long comments via file
redmine issue delete ID -y

# Wiki
redmine wiki list -p PROJECT
redmine wiki get -p PROJECT TITLE --text > page.md   # body only, for editing
redmine wiki update -p PROJECT TITLE --file page.md --comment "edit summary"

# Search (returns issues, wiki, news, etc.)
redmine search "query" -p PROJECT [--issues] [--wiki] [--json]
```

## Long markdown bodies

Always prefer `--description-file` / `--note-file` / `--file` (or `-` for stdin) over inline strings for anything longer than a sentence. Never cram multi-paragraph markdown into argv — it breaks shell quoting and pollutes shell history.

```bash
redmine issue create -p mobile -s "Crash" --description-file /tmp/bug.md
cat << 'MD' | redmine wiki update -p docs Setup --file - --comment "rewrite"
# Setup

Updated steps...
MD
```

## Multi-instance (gh-style)

```bash
redmine auth login                          # interactive, becomes default
redmine auth login --url ... --api-key ...  # script-friendly
redmine auth status                         # shows hosts and active user per host
redmine auth switch --host H --user U       # change active user on a host
redmine auth set-default HOST               # change which host is default
redmine --host H --user U issue list        # one-shot override
```

## Names vs. IDs

`--status`, `--tracker`, `--priority`, `--assignee`, `--category`, `--version` accept either a numeric ID or the human name (case-insensitive). The CLI resolves names against the small reference lists on demand — pass `Resolved` not `3`.

`--labels` and `--watchers` take **comma-separated numeric IDs only** (no name resolution yet — `redmine label list -p PROJECT --json | jq` for IDs).

To browse other reference data:

```bash
redmine project list --json | jq '.[] | {id, identifier, name}'
redmine label list -p mobile --json | jq '.[] | {id, name}'
redmine user list --name alice --json | jq '.[] | {id, login}'
```

## Fork-specific features worth knowing

These are *not* in vanilla Redmine — they are unique to this fork:

- **Direct journal/comment API** — `redmine journal {list,get,create,update}` lets you post and edit comments without touching the issue itself. Prefer this over `redmine issue update --note` when you only need to comment.
- **Wiki history / rename / protect** — `redmine wiki history|rename|protect`. Renames optionally leave a redirect (`--redirect`/`--no-redirect`). Use `--new-parent` to re-parent during rename.
- **Project labels** — `redmine label {list,create,update,delete}`. Issues take `--labels "1,2,3"` (numeric IDs only).
- **Reading labels back:** `issue get` includes assigned labels by default; `issue list --include labels` includes them per item.

## Confirmation before destructive actions

`issue delete`, `project delete`, `wiki delete`, `label delete` all prompt unless `-y` / `--yes` is passed. When acting on the user's behalf in unattended mode, only pass `-y` if the user explicitly authorized that specific deletion.

## When the CLI doesn't cover something

This skill targets v1 of the CLI (issues, projects, wiki, journals, attachments, labels, search, users). For features not covered — webhooks, time entries, bulk ops, attachment fulltext, news, versions, queries, memberships, boards, messages, documents, reactions, activities — fall back to direct `curl` calls using the API key from `redmine auth token`. The fork's REST endpoints are documented at: https://github.com/enricohuang/redmine/wiki

```bash
KEY=$(redmine auth token)
URL=$(redmine auth status | awk '/->/{print $3; exit}')
curl -H "X-Redmine-API-Key: $KEY" "$URL/time_entries.json?limit=5"
```

If the user asks for one of those uncovered resources repeatedly, suggest extending the CLI in `clients/redmine-cli/redmine_cli/commands/` rather than continuing with curl.

## Reference

- CLI source: `clients/redmine-cli/` in the redmine fork repo
- API docs: https://github.com/enricohuang/redmine/wiki (REST-API-* pages)
- Run `redmine <subcommand> --help` for full flag list on any command.
