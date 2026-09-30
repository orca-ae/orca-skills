# Orca CLI (`ork`)

The `ork` CLI exposes every Orca Agent Engine registry resource as a shell subcommand. Compared to `curl`: request bodies are built from typed flags (structured fields take JSON via repeatable `--*-json` flags), the credential header is set for you, output switches between human text and machine `json`/`yaml` with `-o`, and content endpoints download to a file with `--output-file`. There is no built-in field extractor — pipe `-o json` to `jq`.

## When to use the CLI vs the SDK

**CLI for the control plane, SDK for the data plane.** Agents and environments are relatively static resources you define, configure, and debug with `ork` — keep the setup script and its JSON payloads in your repo, apply from CI, inspect from a terminal. Sessions are dynamic and driven by your application through the SDK — create per task, stream events, react to tool calls, integrate into your product. Both hit the same API; the split is about where the call lives, not what's possible.

| | Control plane → `ork` | Data plane → SDK |
|---|---|---|
| Resources | agents, environments, skills, vaults, files | sessions, events |
| Cadence | Once per deploy / ad-hoc | Every task / every turn |
| Lives in | Setup script + `*.json` payloads in your repo + CI + terminal | Application code |
| Typical calls | `create`, `update --version N`, `list`, `get`, `archive` | `sessions.create()`, `events.stream()`, `events.send()` |

## Install and configure

```sh
# Homebrew (macOS and Linux)
brew install orca-ae/tap/ork

# Or a release archive with checksums: https://github.com/orca-ae/homebrew-tap/releases

# Or the container image (amd64 + arm64; its entrypoint is the CLI)
docker run --rm \
  -e ORCA_REGISTRY_URL -e ORCA_API_KEY \
  ghcr.io/orca-ae/orca-cli:latest agent list
```

<!-- orca-warn -->
**Configuration is an endpoint plus one credential — there is no `ork login`, no profiles, and no config file.** The CLI reads these env vars, or the matching global flags:
<!-- /orca-warn -->

<!-- orca-warn -->
| Env var | Flag | Value |
|---|---|---|
| `ORCA_REGISTRY_URL` | `--registry-url` | Deployment **host root**, e.g. `https://host.example.com` — no `/v1` or `/v1/registry` suffix (a legacy suffix is stripped with a deprecation warning on stderr) |
| `ORCA_API_KEY` | `--api-key` | Workspace API key (`orca_…`), sent as `x-api-key` — the credential for an engine you run yourself, including `ork local` |
| `ORCA_ACCESS_TOKEN` | `--access-token` | OIDC access token, sent as `Authorization: Bearer ...` |
<!-- /orca-warn -->

**Set exactly one credential.** `--api-key` and `--access-token` are mutually exclusive, and the check covers env vars too: with both `ORCA_API_KEY` and `ORCA_ACCESS_TOKEN` exported, every call fails with `--access-token and --api-key cannot be used together`, even when you pass one of them as a flag. Missing values fail fast: `--registry-url is required` / `one of --access-token or --api-key is required`. Where the credential comes from is deployment-specific (a hosted deployment's console, or the operator of an engine you run yourself). The SDK names the endpoint `ORCA_BASE_URL` — document both names when a project uses both clients.

### A local engine: `ork local`

`ork local start` runs an engine on your machine with Docker Compose v2: Postgres, S3-compatible object storage, the Registry, and the harness. The first start creates a workspace, writes its API key to `<data-dir>/secrets/workspace-api-key`, and prints the Registry URL. Set the model provider's API key in the shell first, or the first session fails to authenticate: for the default Claude models, the variable Anthropic's own SDK reads; for OpenAI models, `OPENAI_API_KEY`. The README's quick start names both.

```sh
ork local start        # --with-gateway also runs the AI gateway, which MCP servers need
export ORCA_REGISTRY_URL=http://127.0.0.1:8080
export ORCA_API_KEY="$(cat "<data-dir>/secrets/workspace-api-key")"
ork local status
ork local stop         # keeps the data and the workspace key
```

`ork local --help` shows the default `--data-dir`. The local sandbox is not isolated, so run only agents and code you trust, and its vault values live in memory: they don't survive a Registry restart.

`ork healthz` and `ork readyz` need only the URL — use them to check connectivity before debugging auth.

## Command structure

```
ork agent <group> <action> [flags]
```

<!-- orca-warn -->
Everything managed-agents lives under `ork agent` (alias `ork agents`); there are no top-level `ork sessions` / `ork vaults` commands. The groups:
<!-- /orca-warn -->

| Group | Actions |
|---|---|
| *(agent itself)* | `list`, `get [agent-id]`, `create`, `update [agent-id]`, `archive`, `versions [agent-id]` |
| `sessions` | `list`, `get`, `create`, `update`, `delete`, `archive`, `outcome [session-id]` |
| `sessions events` | `list`, `send` (+ typed `send message` / `send outcome` / `send tool-confirmation`), `stream` |
| `sessions threads` | `list`, `get [thread-id]`, `archive [thread-id]`, plus `events` (`list`, `stream`) |
| `sessions resources` | `list`, `get`, `add`, `update`, `delete` |
| `sessions files` | `list`, `get`, `content [file-id]`, `delete` |
| `environments` | `list`, `get`, `create`, `update`, `delete`, `archive` |
| `files` | `list`, `get`, `create -f <path>`, `content [file-id]`, `delete` |
| `skills` | `list`, `get`, `create -f <path>...`, `delete`, plus `versions` (`list`, `get`, `content`, `create`, `delete`) |
| `vaults` | `list`, `get`, `create`, `update`, `delete`, `archive`, plus `credentials` (incl. `validate`) |
| `memory-stores` | `list`, `get`, `create`, `update`, `delete`, `archive`, plus `memories` |
| `memory-versions` | `list`, `get`, `redact [version-id]` |
| `triggers` | `list`, `get`, `create`, `update`, `delete`, `pause`, `unpause`, `sessions`; core cron support, plus the Pulsar/Kafka sources and session modes of hosted deployments |

`ork agent --help` lists the groups; append `--help` to any subcommand for its flags — that help output is the authoritative flag reference.

## Output — `-o` + `jq`

`-o` / `--output` takes `text` (default), `json`, or `yaml`. For scripting, use `-o json` and extract with `jq`:

```sh
# One bare ID per line from a list endpoint
ork agent list -o json | jq -r '.data[].id'

# Capture a scalar for shell use
AGENT_ID=$(ork agent create --name "My Agent" --model claude-sonnet-4-6 -o json | jq -r .id)
```

List endpoints take `--limit` and `--page` (the cursor from the previous response's `next_page`); `files list` and `sessions files list` page with `--after-id` / `--before-id` instead. `--include-archived` exists on the agent, session, environment, vault, and memory-store lists, and session lists also filter with `--agent`. Content endpoints (`files content`, `sessions files content`, `skills versions content`) write to stdout or `--output-file <path>`.

## Input — typed flags + JSON payload flags

Scalar fields map to flags directly. Structured fields take JSON strings, one element per repeated flag; `key=value` flags build simple maps:

```sh
ork agent create \
  --name "Research Agent" \
  --model claude-sonnet-4-6 \
  --system "You are a research assistant. Cite sources for every claim." \
  --tool-json '{"type": "agent_toolset"}' \
  --tool-json '{"type": "custom", "name": "search_docs", "description": "Search the docs index", "input_schema": {"type": "object", "properties": {"query": {"type": "string"}}}}' \
  --mcp-server name=linear,type=url,url=https://mcp.linear.app/mcp \
  --metadata team=research
```

There is no stdin body and no YAML manifest apply — keep JSON payloads in version-controlled files and inline them with command substitution:

```sh
ork agent create --name "Research Agent" --model claude-sonnet-4-6 \
  --system "$(cat prompts/researcher.txt)" \
  --tool-json "$(cat agent/tools/search-docs.json)"
```

Sessions compose the same way: `--resource-json` and `--initial-event-json` are repeatable JSON flags, `--vault-id` repeats into `vault_ids`:

```sh
ork agent sessions create --environment-id env_01H8... --agent "$AGENT_ID" \
  --vault-id vlt_01H8... --title "Nightly research" \
  --resource-json '{"type": "file", "file_id": "file_01H8...", "access": "read_only"}' \
  --initial-event-json '{"type": "user.message", "content": [{"type": "text", "text": "Start with the README."}]}'
```

## Version-controlled setup

The recommended flow for agents and environments: a setup script in your repo that creates (first run) or updates (thereafter), with the JSON payloads as committed files. See `shared/managed-agents-core.md` for the field reference.

```sh
#!/usr/bin/env bash
# setup-agent.sh — run once per config change; IDs land in .orca-ids.env
set -euo pipefail

ENV_ID=$(ork agent environments create --name research-env \
  --networking-type unrestricted --package-pip requests -o json | jq -r .id)

AGENT_ID=$(ork agent create --name Summarizer --model claude-sonnet-4-6 \
  --system "$(cat prompts/summarizer.txt)" \
  --tool-json '{"type": "agent_toolset"}' -o json | jq -r .id)

printf 'ORCA_ENV_ID=%s\nORCA_AGENT_ID=%s\n' "$ENV_ID" "$AGENT_ID" > .orca-ids.env
```

Updating needs the ID. `--version` is optional: pass the current version to make the update conditional, and a stale one fails with 409 `version mismatch`:

```sh
ork agent update "$AGENT_ID" --version 3 --system "$(cat prompts/summarizer.txt)"
```

Every run then loads the IDs and creates sessions — from this script via the CLI, or (more commonly) from application code via the SDK:

```sh
ork agent sessions create --environment-id "$ORCA_ENV_ID" --agent "$ORCA_AGENT_ID" --title "Task"
```

## Interactive session loop

`ork agent sessions events stream` opens the session's SSE stream and prints **NDJSON — one JSON object per line**. Registry frames carry SSE `id`, `event`, and `data`, so the CLI preserves all three:

```json
{"id":"42","event":"agent.message","data":{"id":"evt_...","type":"agent.message","content":[]}}
```

Outer `.id` is the numeric resume cursor; `.data.id` is the event's `evt_…` ID. No cursor follows from the current head; a non-numeric cursor isn't rejected and silently does the same. `--from-cursor 0` requests full history; any other explicit cursor replays inclusively, so dedupe the first repeated frame. `--event-delta agent.message` opts into token-level preview frames. `--timeout 2m` bounds the wait: it counts from when the stream opens and ends it with exit status 0, so a script can only tell a finished turn from a timeout by checking for the idle event itself.

```bash
SID=$(ork agent sessions create --environment-id "$ORCA_ENV_ID" --agent "$ORCA_AGENT_ID" -o json | jq -r .id)

ork agent sessions events send message --session "$SID" --text "Summarize the repo README"

# Replay this new session from cursor 0 and print agent text until the turn ends.
jq -r 'if .data.type == "session.status_idle" and .data.stop_reason.type != "requires_action" then halt
       else (select(.data.type == "agent.message") .data.content[]? | select(.type == "text") .text)
       end' < <(ork agent sessions events stream --session "$SID" --from-cursor 0 --timeout 30m) 2>/dev/null
```

**Read the stream through process substitution (`< <(ork …)`, which needs bash or zsh), not a pipe.** The server keeps the stream open after the turn ends, and its heartbeats never reach stdout, so with `ork … | jq` or `ork … | while read` the shell keeps waiting for `ork` after the consumer has stopped — until `--timeout`. With process substitution the script moves on as soon as the consumer stops; the leftover `ork` exits when its `--timeout` expires.

A watch loop that prints every event type, stops on idle, and reports whether the turn actually ended:

```bash
seen_idle=
while IFS= read -r line; do
  type=$(printf '%s' "$line" | jq -r '.data.type? // empty')
  stop=$(printf '%s' "$line" | jq -r '.data.stop_reason.type? // empty')
  printf '%s\n' "$type"
  if [ "$type" = "session.status_idle" ] && [ "$stop" != "requires_action" ]; then seen_idle=1; break; fi
done < <(ork agent sessions events stream --session "$SID" --from-cursor 0 --timeout 30m)
[ -n "$seen_idle" ] || echo "stream ended before the turn finished (timeout or disconnect)" >&2
```

When the agent pauses for a permission (`always_ask` tools emit `agent.tool_use` and the session idles with `stop_reason.type: "requires_action"`), answer from the shell:

```sh
ork agent sessions events send tool-confirmation --session "$SID" \
  --tool-use-id evt_01H8... --decision allow      # or --decision deny --deny-message "not that host"
```

This works for interactive exploration and demos. Persist outer `.id` when exact reconnect matters. The default TypeScript SDK does not expose that frame cursor; see `shared/managed-agents-client-patterns.md` for its stream-first + list-catch-up pattern.

## Scripting patterns

The typed `events send` subcommands cover `message`, `outcome`, and `tool-confirmation`; every other sendable kind (`user.interrupt`, `user.custom_tool_result`, `user.tool_result`, `system.message`) goes through the raw `--event-json` flag:

```sh
ork agent sessions events send --session "$SID" \
  --event-json '{"type": "user.interrupt"}'

ork agent sessions events send --session "$SID" \
  --event-json '{"type": "user.custom_tool_result", "custom_tool_use_id": "evt_01H8...", "content": [{"type": "text", "text": "42 rows"}]}'
```

<!-- orca-warn -->
> ⚠️ **Define outcomes with `--event-json`, not `send outcome`.** The typed `send outcome --rubric` subcommand currently sends `rubric` as a plain string, but the registry requires `{"type": "text", "content": ...}` (or `{"type": "file", "file_id": ...}`) and rejects the string form. Until that's fixed, send the event raw:
<!-- /orca-warn -->

```sh
ork agent sessions events send --session "$SID" --event-json '{
  "type": "user.define_outcome",
  "description": "Produce a summary of the repository README",
  "rubric": {"type": "text", "content": "The summary covers purpose, install, and usage in under 200 words."},
  "max_iterations": 3
}'
```

Poll instead of stream when a cron job just needs the transcript so far:

```sh
ork agent sessions events list --session "$SID" --event-type agent.message -o json \
  | jq -r '.data[].content[]? | select(.type == "text") .text'
```

For anything this file doesn't cover, `--help` on the exact subcommand is the reference; the underlying endpoints are in `shared/managed-agents-api-reference.md`.
