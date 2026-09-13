---
name: jira-cli
description: Use this skill when creating, reading, updating, deleting, linking, transitioning, labeling, or searching Jira issues via the `jira` CLI. Covers installation, authentication, Markdown<->ADF conversion, custom-field discovery (`jira fields`), and safe patterns for setting required fields on create/edit/transition. Trigger on any task that says "create a Jira ticket", "update this issue", "add a comment to DAST-123", "transition this issue", "find required fields for X", or similar.
---

# jira-cli: Jira issue management via CLI

`jira` is a Go CLI for scripting Jira Cloud issue management
(source: `github.intuit.com/mpowers5/jira-cli`).

**Strengths vs. typical Jira MCPs:**
- Bidirectional Markdown ↔ ADF conversion — panels, status lozenges, dates,
  emoji, mentions, task lists, decision lists, tables, and media all render
  to/from real Markdown, not raw ADF JSON or flattened text.
- `jira fields` / `jira transition list --format json` dump required fields
  and allowed values in one call.
- Block-card smart-links (e.g. a pasted filtered-issue-list link) resolve
  live — the embedded JQL is re-run and rendered as a real table.
- HTTP 429s retry automatically with backoff + `Retry-After`.
- `label add`/`label remove` handle Jira's async bulk API directly:
  auto-batching at 1,000 issues/request and polling to completion.

## Setup

Don't assume `jira` is installed — just run the command you need. If it
fails with `command not found`, install it:

```bash
go install github.intuit.com/mpowers5/jira-cli/cmd/jira@latest
command -v jira   # confirm $GOPATH/bin or $GOBIN is on PATH
```

If Go isn't available, stop and tell the user `jira` needs to be installed —
don't fabricate a workaround.

## Authentication

Requires `JIRA_EMAIL` and `JIRA_TOKEN` env vars (`JIRA_URL` optional, defaults
to `https://intuit-prod.atlassian.net`). **Assume these are already set.** Do
not search the filesystem, shell history, config files, or secret stores for
credentials, and do not ask the user to paste a token into the conversation.
If a command fails with `email and token are required`, or you otherwise have
concrete reason to believe they're unset, **stop and tell the user** —
don't attempt to locate or supply credentials yourself.

Other global flags: `--debug` (writes `jira-cli-debug.log`), `--har FILE`
(records HTTP traffic for troubleshooting).

## Priority / Severity — never guess high

Setting Priority (or a project's Severity/Impact field) to a high value
(Highest/P0/P1, "Blocker", "S1", etc.) commonly triggers Jira SLA/paging
automations. **Do not infer a high priority or severity from issue content**
(e.g. words like "urgent," "prod down," "critical"). If the user doesn't
explicitly state the priority/severity:
- ask them, or
- default to Medium/Low (whatever the project's mid-to-low allowed value is).

Never set Highest/P0/Blocker-tier values without an explicit, unambiguous
instruction from the user to do so.

## Core workflow: discover fields, then act

Required custom fields vary per project/issue-type/transition. Discover
before calling `create-issue`, `edit-issue`, or `transition apply` with
anything beyond the built-in flags:

```bash
jira fields --project ACAP --type Bug                       # all create fields
jira fields --project ACAP --type Bug --required --format json  # required only
jira fields --custom                                         # global custom fields

jira transition list --issue DAST-123                        # transition fields (state-dependent)
jira transition list --issue DAST-123 --required --format json
```

`--format json` exposes `allowedValues` — use it instead of guessing display
names for select/cascading-select fields.

If a create/edit/transition call errors with "missing required ... fields",
the message names them — re-run discovery, find allowed values, retry with
`--field 'Name=Value'`.

## `--field NAME=VALUE` semantics (create-issue, edit-issue, transition apply)

- `NAME` matches a display name, field key, or `customfield_XXXXX` ID,
  case-insensitively. Ambiguous matches error with candidate field IDs.
- Repeat `--field` for the same name to set a multi-select/array field.
- Select/radio/checkbox values match case-insensitively by name or ID.
- Numbers parse as floats; ADF-textarea fields convert from Markdown
  automatically.
- For shapes that can't be a plain string (cascading selects, nested JSON),
  use `--field-json NAME=JSON` with Jira's exact wire shape (see
  `--format json` discovery output).
- A field can't be set by both a dedicated flag and `--field`/`--field-json`
  — errors as duplicate.

## Commands

### `create-issue`

```bash
jira create-issue --project DAST --title "Fix login bug" [flags]
```

Required: `--project`/`-p`, `--title`/`-T`. `--type`/`-t` defaults to `Story`.

| Flag | Notes |
|---|---|
| `--description`/`-d` | Markdown → ADF |
| `--acceptance-criteria` | Markdown → ADF; must exist on the create screen |
| `--attachment PATH` | local file uploaded after creation; repeatable |
| `--assignee`/`-a`, `--reporter` | account ID, or `me` |
| `--priority` | Highest/High/Medium/Low/Lowest — see priority/severity warning above |
| `--labels`/`-l`, `--components` | repeatable or comma-separated |
| `--due-date` | `YYYY-MM-DD` |
| `--story-points`/`-s` | float; applied via follow-up edit after creation |
| `--epic`/`-e` | epic key, e.g. `DAST-100` |
| `--sprint` | numeric sprint ID (see `list-sprints`) |
| `--field NAME=VALUE` | any other create field; repeatable |
| `--format` | `human` (default) or `json` |

Validation happens before creation — missing/invalid fields are rejected
client-side.

```bash
jira create-issue --project DAST --type Bug \
  --title "Login fails on iOS 17" --priority High --assignee me

jira create-issue --project ACAP --type Bug --title "Startup failure" \
  --field 'Impact=High' --field 'Severity=S2-Major' \
  --field 'Environments=Production'

jira create-issue --project DAST --title "Add dark mode" \
  --acceptance-criteria $'- [ ] Follows the system theme\n- [ ] Has tests'

jira create-issue --project DAST --type Bug --title "Login failure" \
  --attachment screenshot.png --attachment logs.txt
```

### `edit-issue`

```bash
jira edit-issue --issue DAST-123 [flags]
```

Same fields as `create-issue` minus project/type (that's a Jira move, not
supported). Omitted flags leave fields unchanged; pass an explicit empty
value to clear:

```bash
jira edit-issue --issue DAST-123 --description ""       # clear description
jira edit-issue --issue DAST-123 --labels ""             # clear all labels
jira edit-issue --issue DAST-123 --assignee unassigned   # unassign
jira edit-issue --issue DAST-123 --epic ""               # unlink epic
jira edit-issue --issue DAST-123 --sprint 0              # remove from sprint
```

Dynamic fields resolve against the issue's own edit metadata, not create
metadata — a field may be creatable but not editable, or vice versa.

Upload an attachment before referencing it in a Markdown field. Copy the
returned link, which uses the authenticated `content` URL rather than the
attachment metadata `self` URL. Prefix it with `!` to embed an image inline.

```bash
jira add-attachment --issue DAST-123 --file report.pdf
jira edit-issue --issue DAST-123 \
  --description 'See [report.pdf](ATTACHMENT_CONTENT_URL)'

jira add-attachment --issue DAST-123 --file screenshot.png
jira edit-issue --issue DAST-123 \
  --description '![Screenshot](ATTACHMENT_CONTENT_URL)'
```

### `comment`

```bash
jira comment --issue DAST-123 --comment "**Root cause**: nil pointer in auth middleware."
```

Markdown → ADF. Prints the new comment ID.

Edit an existing comment by ID:

```bash
jira comment edit --issue DAST-123 --comment-id 10001 \
  --comment "Updated **root cause** and verification notes."
```

### `transition list` / `transition apply`

Required fields are state-dependent — always run `list` fresh for the
issue's current status.

```bash
jira transition list --issue DAST-123
jira transition list --issue DAST-123 --required --format json

jira transition apply --issue DAST-123 --to "In Progress"
jira transition apply --issue DAST-123 --to Done \
  --field 'Resolution=Done' --field 'Root Cause=Code defect' \
  --comment '**Verified** in production'

# Cascading-select or other complex field:
jira transition apply --issue DAST-123 --to 31 \
  --field-json 'customfield_12345={"id":"10001","child":{"id":"10002"}}'
```

`--to` accepts a transition name, destination status, or transition ID.
Ambiguous matches list `Name (ID)` pairs. `--comment` is Markdown → ADF.

Transition metadata does not expose every workflow validator. A field may
appear optional in `transition list` while the transition still requires a
value already stored on the issue. Some validators also run before Jira
applies fields supplied with the transition. For example, if an In Progress
transition returns `Please enter assignee/owner for the task`, passing
`--field 'Assignee=me'` to `transition apply` may not satisfy it. Persist the
assignee first, then retry:

```bash
jira edit-issue --issue ACAP-123 --assignee me
jira transition apply --issue ACAP-123 --to "In Progress"
```

Only use `me` when assigning the authenticated user matches the requested
ownership. Otherwise, get the intended assignee from the user before editing
the issue.

### `link`

```bash
# DAST-101 blocks DAST-102
jira link --type Blocks --outward DAST-101 --inward DAST-102
```

Link types are directional and site-configured (`Blocks`, `Duplicate`,
`Cloners`, `Relates`, ...).

### `label add` / `label remove`

```bash
jira label add --issue DAST-101,DAST-102 --label triaged --label backend
jira label remove --issue DAST-101 --issue DAST-102 --label needs-review
```

Async bulk API; auto-batches at 1,000 issues/request. Requires the **Bulk
change** global permission plus Browse/Edit on every affected project.
`--wait=false` submits without waiting; `--format json` gives task IDs and
per-issue failures.

### `get-issue`

```bash
jira get-issue --issue DAST-123                 # rendered Markdown (default)
jira get-issue --issue DAST-123 --format json    # raw API response
jira get-issue --issue DAST-123 --history        # include full change history
```

`--history`/`--changelog` appends the complete, paginated changelog.
`--format json` exposes fields not shown in Markdown (raw custom field IDs).

The Markdown "Attachments" section links each filename to its authenticated
download URL. Attachments embedded inline in descriptions or comments use the
same URL. `--format json` also exposes it as `fields.attachment[].content`.

### `get-attachment`

```bash
jira get-attachment --url "https://<site>.atlassian.net/rest/api/3/attachment/content/10001" --file screenshot.png
jira get-attachment --url "https://<site>.atlassian.net/rest/api/3/attachment/content/10002" | less
```

Downloads bytes for an attachment content URL. `--file PATH` saves to disk
(atomic write); without it, bytes go to stdout.

### `add-attachment`

```bash
jira add-attachment --issue DAST-123 --file screenshot.png
jira add-attachment --issue DAST-123 --file report.pdf --file logs.txt
jira add-attachment --issue DAST-123 --file report.pdf --format json
```

Uploads one or more local files to an existing issue. Repeat `--file` for
multiple attachments. Human output contains ready-to-copy Markdown links;
JSON output contains the attachment response objects, including `content` URLs.

### `search`

```bash
jira search --jql "project = DAST AND assignee = currentUser()" [flags]
```

| Flag | Notes |
|---|---|
| `--max-results` (default 50), `--start-at` | server-side pagination |
| `--fields` | `*all` (default), `*navigable`, or specific names |
| `--expand` | e.g. `renderedFields`; for readable change history use `get-issue --history` instead |
| `--validate-query` | strict JQL validation |
| `--format` | `human` (default), `json`, `jsonl` |

```bash
jira search --jql "sprint in openSprints() AND project = DAST" \
  --format jsonl | jq -r '.issues[].key'
```

### `fields` — see "core workflow" above

### `list-sprints` / `list-epics`

```bash
jira list-sprints --project DAST --format json \
  | jq '[.[].sprints[] | select(.state=="active") | {id,name}]'

jira list-epics --project DAST --jql "AND status != Done" --format json
```

Use to resolve sprint IDs / epic keys before `--sprint`/`--epic`.

## Markdown → ADF notes

Supported: paragraphs, headings (1–6), blockquotes, fenced/indented code
blocks, bullet/ordered/task lists, tables (GFM), thematic breaks, hard
breaks, and inline `**bold**`, `*em*`, `` `code` ``, `~~strike~~`,
`[link](url)`.

- `code` cannot combine with bold/italic/strike (Jira ADF rejects it as
  `INVALID_INPUT`) — the converter keeps `code` and drops the conflicting
  mark automatically. Avoid relying on `**bold `code`**` producing bold code.
- Empty/whitespace Markdown converts to an empty ADF doc — this is how
  `edit-issue --description ""` clears a field, not an error.

`get-issue`/`search` do the reverse (ADF → Markdown) automatically.

## Output formats

Every structured command supports `--format json`; `search` also supports
`jsonl` for `jq` pipelines. Prefer `--format json` whenever chaining output
into another command or into your own reasoning.

## Playbook

**Create an issue with project-specific requirements**
1. `jira fields --project PROJECT --type TYPE --required --format json`
2. Build `create-issue` with built-in flags, then `--field` for the rest.
3. On a "missing required fields" error, re-check allowed values and retry.

**Update a field on an issue**
- Dedicated flag if one exists; otherwise
  `edit-issue --issue KEY --field 'X=value'`. Unknown/ambiguous names error
  with candidate field IDs.

**Transition an issue**
1. `jira transition list --issue KEY` (always fresh — state-dependent).
2. Supply required fields via `--field`/`--field-json`, plus `--comment` if
   a resolution note is expected.

**Search**
- `jira search --jql "sprint in openSprints() AND assignee = currentUser()" --format json`
