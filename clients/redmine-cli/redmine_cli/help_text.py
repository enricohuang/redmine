"""Topic-based help content rendered by `redmine help`.

Each topic is a self-contained reference for one workflow. Keep them concise —
this is what an agent reads in a single Bash call when it needs a refresher,
and a wall of prose burns its context budget. Examples beat exposition.
"""

from __future__ import annotations

import textwrap

TOPICS: dict[str, str] = {}
SUMMARIES: dict[str, str] = {}


def topic(name: str, summary: str):
    def deco(fn):
        # textwrap.dedent strips the common leading whitespace from the
        # triple-quoted docstring so it renders flush-left.
        TOPICS[name] = textwrap.dedent(fn.__doc__ or "").strip("\n")
        SUMMARIES[name] = summary
        return fn
    return deco


@topic("getting-started", "First-time orientation: auth, output, discovery.")
def _getting_started():
    """
    # Getting started

    `redmine` wraps the REST API of this Redmine fork (issues, projects, wiki,
    journals, attachments, labels, search, users) for use by humans and agents.

    First, configure auth (gh-style):

        redmine auth login --url https://redmine.example.com --api-key <KEY>
        redmine auth status

    For unattended/CI use, set REDMINE_URL + REDMINE_API_KEY env vars and skip
    the config file:

        export REDMINE_URL=https://...
        export REDMINE_API_KEY=...
        redmine user get current

    Every read command supports `--json` for piping into `jq`. Default output
    is a human-readable table.

    Exit codes: 0 ok, 2 not found, 3 validation, 4 auth, 5 network.

    Discover more:
        redmine help              # list topics
        redmine help <topic>      # focused tutorial
        redmine help all          # full CLI reference (single bash call)
        redmine <cmd> --help      # individual command flags + examples
    """


@topic("auth", "Multi-host credentials, env-bypass for CI.")
def _auth():
    """
    # Authentication and multi-host

    Modeled on `gh`. Multiple hosts, multiple users per host, one active user
    per host, one default host overall.

    ## Common flows

        # First login (becomes default)
        redmine auth login --url https://redmine.example.com --api-key <KEY>

        # Add a second account on the same host
        redmine auth login --url https://redmine.example.com --api-key <KEY2> \\
                           --label readonly --no-set-default

        # Switch the active user on a host
        redmine auth switch --host redmine.example.com --user readonly

        # One-shot override (does not change saved state)
        redmine --host redmine.example.com --user readonly issue list

        # Print the active key (for piping into curl)
        redmine auth token

        # Inspect / forget
        redmine auth status
        redmine auth logout --host redmine.example.com [--user <label>]
        redmine auth set-default redmine.example.com

    ## Files

    Storage lives at `~/.config/redmine/`:

        hosts.yml      one entry per host: url, users, active user
        config.yml     default_host

    File mode is 0600. Never commit these.

    ## Env-bypass (CI)

    If REDMINE_URL **and** REDMINE_API_KEY are set, they take priority over
    everything in the config files. Useful in CI where you don't want to
    `auth login` first.
    """


@topic("issues", "Issue lifecycle: create, list, update, status changes.")
def _issues():
    """
    # Issues

    ## Lifecycle

        # Create
        redmine issue create -p mobile -t Bug -s "Crash on login" \\
            --description-file bug.md \\
            --priority High --assignee me

        # Read
        redmine issue list -p mobile --status open --assignee me
        redmine issue get 1234
        redmine issue get 1234 --json | jq '.subject'

        # Update (status + comment in one call)
        redmine issue update 1234 --status Resolved --note "Fixed in v2.3"
        redmine issue update 1234 --note-file long_comment.md

        # Move to another project (existing labels are remapped by name)
        redmine issue update 1234 --project other-project

        # Watch / unwatch
        redmine issue watch 1234   --user-id 7
        redmine issue unwatch 1234 --user-id 7

        # Delete (irreversible)
        redmine issue delete 1234 -y

    ## Names vs IDs

    `--status`, `--tracker`, `--priority`, `--assignee`, `--category`,
    `--version` accept either a numeric ID or the human name (case-insensitive).
    Pass `Resolved` not `3`. Unknown name fails with exit code 3 + the valid
    list.

    `--labels`, `--watchers` take **comma-separated numeric IDs only**.
    Resolve via `redmine label list -p PROJECT --json`.

    ## Filtering on list

    Default `--status open`. Pass `--status '*'` for all, `--status closed`
    for only closed, or a specific status name/ID. `--assignee me` is a
    shorthand the server understands.

    Combine `--include` to fetch related data: `journals`, `attachments`,
    `relations`, `watchers`, `children`, `allowed_statuses`, `labels`.
    """


@topic("wiki", "Wiki read/write loop and fork-only history/rename/protect.")
def _wiki():
    """
    # Wiki pages

    ## Read / write

        # Read body to a file (round-trippable)
        redmine wiki get -p docs Home --text > home.md

        # Edit then write back (creates a new version with a comment)
        $EDITOR home.md
        redmine wiki update -p docs Home --file home.md --comment "typo fix"

        # New page
        redmine wiki update -p docs OnboardingGuide --text "# Welcome..."

        # New page from stdin
        cat << 'MD' | redmine wiki update -p docs Setup --file - --comment "init"
        # Setup
        Steps...
        MD

    ## Optimistic concurrency

    Pass `--expected-version N` on update to fail with a 409 if someone else
    has saved a newer version since you last read.

    ## Fork-only operations

        # History
        redmine wiki history -p docs Home --json

        # Rename (optionally leave a redirect at the old title)
        redmine wiki rename -p docs Home --to OnboardingGuide
        redmine wiki rename -p docs Home --to OnboardingGuide --no-redirect
        redmine wiki rename -p docs Home --to OnboardingGuide --new-parent Index

        # Protect / unprotect
        redmine wiki protect -p docs Home --on
        redmine wiki protect -p docs Home --off

    ## Title gotcha

    Wiki page titles in URLs are *Pascal/CamelCase* (no spaces). Redmine
    normalizes "On boarding" to "On_boarding" or similar — when in doubt,
    `redmine wiki list -p PROJECT --json | jq '.[].title'` to see exact
    titles in your project.
    """


@topic("attachments", "Two-step upload/attach + download.")
def _attachments():
    """
    # Attachments

    The Redmine API is two-step (POST /uploads → token, then attach token to
    issue/wiki). The CLI wraps both.

    ## Most common: attach to an issue

        redmine attachment attach ./screenshot.png -i 1234 \\
            --description "before/after"

        # With a comment in the same call
        redmine attachment attach ./fix.patch -i 1234 \\
            --note "Patch attached"

    ## Low-level: upload only (returns a token)

        redmine attachment upload ./big.zip
        # → 8a72f9...   (use as `uploads:` token in custom POSTs)

    ## Read / download

        redmine attachment get 42 --json
        redmine attachment download 42 -o ./downloaded.bin
        redmine attachment download 42 -o -            # to stdout
    """


@topic("labels", "Per-project colored tags (fork feature) and how to assign.")
def _labels():
    """
    # Labels (fork feature)

    Labels are per-project colored tags. CLI covers full CRUD.

    ## Manage labels

        redmine label list -p mobile
        redmine label create -p mobile --name "v1-bug" --color "#e74c3c"
        redmine label update 7 --name "v1-bug-critical"
        redmine label delete 7 -y

    ## Assign to issues

    Issue commands take comma-separated numeric label IDs (no name resolution
    yet — discover IDs via `label list --json`):

        LBL=$(redmine label list -p mobile --json | jq '.[]|select(.name=="v1-bug").id')
        redmine issue create -p mobile -s "Crash" --labels "$LBL"
        redmine issue update 1234 --labels "1,2,3"

    Read back via `issue get` (always included) or `issue list --include labels`.

    ## Cross-project move

    When an issue moves to a new project (`issue update --project other`),
    Redmine reassigns labels by *name* — labels with no same-named twin in the
    target project are dropped. This is server-side behavior.
    """


@topic("journals", "Direct comment API (fork-only) — comment without state changes.")
def _journals():
    """
    # Journals (fork-only direct comment API)

    Stock Redmine only lets you comment via `issue update --note`. The fork
    adds a direct journals API so you can list/create/update/delete comments
    independently.

    ## Common usage

        # List comments on an issue
        redmine journal list -i 1234

        # Add a comment without changing anything else
        redmine journal create -i 1234 -n "Looking into this now"

        # Long comment from a file
        redmine journal create -i 1234 --file analysis.md

        # Edit your own comment
        redmine journal update 88 -n "edited: corrected typo"

        # Make it private (visible only to members with view_private_notes)
        redmine journal create -i 1234 -n "internal context" --private

    ## When to use which

        # Comment-only:        redmine journal create -i ID -n "..."
        # Comment + state:     redmine issue update ID --status X --note "..."
    """


@topic("search", "Global search across issues/wiki/news/etc.")
def _search():
    """
    # Search

    Wraps Redmine's built-in search (or the fork's Elasticsearch backend if
    enabled server-side; the API is the same).

    ## Common queries

        # Default: all visible content
        redmine search "login crash"

        # Restrict to one project + only issues
        redmine search "login crash" -p mobile --issues

        # Multiple types
        redmine search "release notes" --wiki --news --documents

        # Titles only (faster)
        redmine search "v2.3" --titles-only

        # Open issues only
        redmine search "regression" --issues --open

        # Pipe-friendly
        redmine search "TODO" --json | jq '.[] | {type, id, title}'

    Available type flags: `--issues --news --documents --changesets --wiki
    --messages --projects`.
    """


@topic("imports", "CSV import state machine: upload, settings, mapping, run.")
def _imports():
    """
    # Imports

    The fork exposes Redmine's CSV import wizard as a JSON state machine. The
    CLI keeps the same stages but avoids browser redirects.

    ## Issue import flow

        redmine import create --type issues --file issues.csv --project 1
        redmine import settings 42 --separator ';' --encoding ISO-8859-1
        redmine import auto-map 42 --json
        redmine import mapping 42 --map project_id=1 --map subject=1 --map tracker=13
        redmine import run 42
        redmine import status 42 --json

    `create` returns a stable numeric import ID. Use that ID for the rest of
    the workflow. `run` may process a chunk; repeat until `state` is `finished`.

    ## Mapping values

    Mapping values are server import values:

        --map subject=1          # use CSV column index 1
        --map tracker=13         # use CSV column index 13
        --map tracker=value:2    # constant tracker ID 2
        --map project_id=1       # target project ID

    For complex mappings, use a JSON file:

        redmine import mapping 42 --mapping-file mapping.json
    """


@topic("repository", "Bounded repository browsing and changeset reads.")
def _repository():
    """
    # Repository

    Repository commands are read-only and bounded. They expose directory
    entries and changeset metadata/file-change lists, but intentionally do not
    expose raw file content or unbounded diffs.

    ## Browse entries

        redmine repository entries -p demo --repository 10
        redmine repository entries -p demo --repository 10 --path app/models --limit 50
        redmine repository entries -p demo --repository 10 --revision 4 --json

    If `--repository` is omitted for `entries`, Redmine's default project
    repository is used.

    ## Changesets

        redmine repository revisions -p demo --repository 10 --limit 20
        redmine repository revision -p demo --repository 10 4 --json

    File changes are returned only when the API user has `browse_repository`.
    Changeset metadata requires `view_changesets`.
    """


@topic("automation", "Piping, IDs from names, batch jobs, CI patterns.")
def _automation():
    """
    # Automation patterns

    The CLI is built for piping; here are common chains.

    ## Find IDs by name

        # Project ID from identifier
        redmine project get mobile --json | jq -r '.id'

        # All open bug IDs assigned to me
        redmine issue list -p mobile --tracker Bug --assignee me --json \\
            | jq -r '.[].id'

        # User ID from login
        redmine user list --name alice --json \\
            | jq -r '.[] | select(.login=="alice") | .id'

        # Label ID from name
        redmine label list -p mobile --json \\
            | jq -r '.[] | select(.name=="needs-info") | .id'

    ## Bulk update via xargs

        # Close all in-progress issues older than a query result
        redmine issue list -p mobile --status "In Progress" --json \\
            | jq -r '.[].id' \\
            | xargs -I{} redmine issue update {} --status Closed --note "swept"

    ## Batch wiki sync

        # Pull all wiki pages to disk
        for t in $(redmine wiki list -p docs --json | jq -r '.[].title'); do
            redmine wiki get -p docs "$t" --text > "$t.md"
        done

    ## CI-friendly auth

        export REDMINE_URL=https://redmine.example.com
        export REDMINE_API_KEY=$REDMINE_TOKEN_FROM_SECRETS
        redmine issue list --status open --json
    """


@topic("troubleshooting", "Exit codes, common errors, post-upgrade gotchas.")
def _troubleshooting():
    """
    # Troubleshooting

    ## Exit codes

    The CLI never throws Python tracebacks; it exits with one of:

        0  success
        2  not found (HTTP 404) — wrong ID, wrong project identifier
        3  validation (HTTP 422) — invalid field; server-side error message
                                  is printed to stderr
        4  auth (HTTP 401/403)  — bad/missing key, or insufficient permissions
        5  network/server error — connection refused, 5xx, etc.

    ## "not authenticated"

    No host is configured *and* no env vars. Either:
        redmine auth login
    or
        export REDMINE_URL=...; export REDMINE_API_KEY=...

    ## "unknown <field> 'X'. Valid: ..."

    You passed a name to `--status`/`--tracker`/`--priority`/`--assignee`/
    `--category`/`--version` that doesn't exist on the server. Either fix the
    spelling or pass the numeric ID. The valid list is in the error message.

    ## Permission errors after upgrading from upstream Redmine

    Some fork-added permissions (`manage_labels`) require a data migration to
    grant them to existing roles. If non-admin users get 403 on label
    operations, run `bundle exec rake db:migrate` on the server.

    ## "API disabled" on attachment fulltext / webhooks

    Settings, not migration:
      Administration → Settings → API → enable webhooks /
      attachment fulltext indexer API + set its key.

    ## Multi-host: "host not configured"

    `--host` was passed (or REDMINE_HOST) but doesn't appear in `auth status`.
    Run `redmine auth login --url <that-host> ...` first.
    """


@topic("reference", "Quick reference: commands, conventions, discovery.")
def _reference():
    """
    # Quick reference

    ## Top-level commands

        auth         multi-host credential management
        issue        create / list / get / update / delete / watch
        project      create / list / get / update / delete
        wiki         get / update / delete + history / rename / protect (fork)
        journal      list / get / create / update (fork direct API)
        attachment   upload / attach (issue) / get / download
        import       CSV import create / settings / mapping / run / status
        repository   bounded repository entries / revisions / revision
        label        list / get / create / update / delete (fork)
        search       global search across types
        user         list / get  (admin-only on stock Redmine)
        help         topic-based help (this command)

    ## Conventions

    - `--json`         on every read → pipe-friendly
    - `--all`          on list → fetch every page (else default page size)
    - `--description-file`, `--note-file`, `--file` → read body from file
      (or `-` for stdin); never cram multi-paragraph markdown into argv
    - `-y` / `--yes`   skip the confirmation prompt on delete commands
    - `-p` / `--project`  takes ID or identifier (e.g. 1 or "mobile")

    ## Discovery

    Per-command flags + examples:
        redmine <cmd> --help
        redmine <cmd> <subcmd> --help

    All commands' --help in one shot (full CLI surface):
        redmine help all

    Topic tutorials:
        redmine help <topic>

    Topics:  getting-started auth issues wiki attachments labels journals
             search imports repository automation troubleshooting reference
    """
