# Orca Agent Engine — cURL / Raw HTTP

<!-- orca-warn -->
Use these examples when the user needs raw HTTP requests or is working without an SDK. All paths sit at `/v1/` directly under the deployment host root. Auth is a workspace API key in `x-api-key`, or an OIDC access token as `Authorization: Bearer` — a workspace key sent as Bearer is rejected. No `anthropic-version` or beta headers are needed — see `shared/managed-agents-overview.md`.
<!-- /orca-warn -->

## Setup

```bash
export ORCA_REGISTRY_URL="https://host.example.com"   # host root — no /v1 suffix
export ORCA_API_KEY="orca_..."                        # workspace API key

# Common headers. With an OIDC access token instead of a workspace key,
# send -H "Authorization: Bearer $ORCA_ACCESS_TOKEN" in place of x-api-key.
HEADERS=(
  -H "Content-Type: application/json"
  -H "x-api-key: $ORCA_API_KEY"
)
```

---

## Create an Environment

```bash
curl -X POST "$ORCA_REGISTRY_URL/v1/environments" \
  "${HEADERS[@]}" \
  -d '{
    "name": "my-dev-env",
    "config": {
      "type": "cloud",
      "networking": { "type": "unrestricted" }
    }
  }'
```

### With restricted networking

```bash
curl -X POST "$ORCA_REGISTRY_URL/v1/environments" \
  "${HEADERS[@]}" \
  -d '{
    "name": "restricted-env",
    "config": {
      "type": "cloud",
      "networking": {
        "type": "limited",
        "allow_package_managers": true,
        "allow_mcp_servers": true,
        "allowed_hosts": ["api.example.com"]
      }
    }
  }'
```

---

## Create an Agent (required first step)

> ⚠️ **There is no inline agent config.** `model`/`system`/`tools` are top-level fields on `POST /v1/agents`, not on the session. Always create the agent first — the session only takes `"agent": {"type": "agent", "id": "..."}` (plus its `environment_id`).

### Minimal

```bash
# 1. Create the agent
curl -X POST "$ORCA_REGISTRY_URL/v1/agents" \
  "${HEADERS[@]}" \
  -d '{
    "name": "Coding Assistant",
    "model": "claude-sonnet-4-6",
    "tools": [{ "type": "agent_toolset" }]
  }'
# → { "id": "agt_01H8...", "version": 1, ... }

# 2. Start a session
curl -X POST "$ORCA_REGISTRY_URL/v1/sessions" \
  "${HEADERS[@]}" \
  -d '{
    "agent": { "type": "agent", "id": "agt_01H8...", "version": 1 },
    "environment_id": "env_01H8..."
  }'
# → { "id": "ses_01H8...", "status": "idle", ... }
```

### With system prompt, custom tools, and GitHub repo

```bash
# 1. Create the agent
curl -X POST "$ORCA_REGISTRY_URL/v1/agents" \
  "${HEADERS[@]}" \
  -d '{
    "name": "Code Reviewer",
    "model": "claude-sonnet-4-6",
    "system": "You are a senior code reviewer. Be thorough and constructive.",
    "tools": [
      { "type": "agent_toolset" },
      {
        "type": "custom",
        "name": "run_linter",
        "description": "Run the project linter on a file",
        "input_schema": {
          "type": "object",
          "properties": {
            "file_path": { "type": "string", "description": "Path to lint" }
          },
          "required": ["file_path"]
        }
      }
    ]
  }'

# 2. Start a session with the repo mounted
curl -X POST "$ORCA_REGISTRY_URL/v1/sessions" \
  "${HEADERS[@]}" \
  -d '{
    "agent": { "type": "agent", "id": "agt_01H8...", "version": 1 },
    "environment_id": "env_01H8...",
    "title": "Code review session",
    "resources": [
      {
        "type": "github_repository",
        "url": "https://github.com/owner/repo",
        "mount_path": "/workspace/repo",
        "authorization_token": "<fine-grained PAT>",
        "checkout": { "type": "branch", "name": "feature-branch" }
      }
    ]
  }'
```

<!-- orca-warn -->
> ⚠️ `checkout` pins are accepted but currently not applied at clone time — see `shared/managed-agents-environments.md` → GitHub Repositories.
<!-- /orca-warn -->

---

## Send a User Message

```bash
curl -X POST "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID/events" \
  "${HEADERS[@]}" \
  -d '{
    "events": [
      {
        "type": "user.message",
        "content": [{ "type": "text", "text": "Review the auth module for security issues" }]
      }
    ]
  }'
```

---

## Stream Events (SSE)

```bash
# Empty cursor follows from the current transcript head. Open before sending
# work when you need every new event in real time.
curl -N "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID/events/stream" \
  -H "Accept: text/event-stream" \
  "${HEADERS[@]}"

# Full persisted replay, then follow live:
curl -N "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID/events/stream?from_cursor=0" \
  -H "Accept: text/event-stream" \
  "${HEADERS[@]}"

# Resume at a saved SSE frame cursor. Replay is inclusive: discard/dedupe the
# first frame when its cursor equals LAST_SSE_CURSOR.
curl -N "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID/events/stream?from_cursor=$LAST_SSE_CURSOR" \
  -H "Accept: text/event-stream" \
  "${HEADERS[@]}"
```

Persist the value from the SSE `id:` line, not the `evt_...` ID inside `data`. The core Registry also accepts `Last-Event-ID`, but the query parameter is more portable across hosted deployments.

Response format:

```
id: 2
event: session.status_running
data: {"type":"session.status_running","id":"evt_...","processed_at":"..."}

id: 14
event: agent.message
data: {"type":"agent.message","id":"evt_...","content":[{"type":"text","text":"I'll review..."}],"processed_at":"..."}

id: 16
event: session.status_idle
data: {"type":"session.status_idle","id":"evt_...","stop_reason":{"type":"end_turn"},"processed_at":"..."}
```

---

## Poll Events

```bash
# Get events (paginated envelope: { data, next_page })
curl "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID/events" \
  "${HEADERS[@]}"

# Next page
curl "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID/events?page=$NEXT_PAGE" \
  "${HEADERS[@]}"
```

---

## Provide Custom Tool Result

When the agent calls a custom tool, send the result back (echo the `agent.custom_tool_use` event's `id`):

```bash
curl -X POST "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID/events" \
  "${HEADERS[@]}" \
  -d '{
    "events": [
      {
        "type": "user.custom_tool_result",
        "custom_tool_use_id": "evt_01H8...",
        "content": [{ "type": "text", "text": "No linting errors found." }]
      }
    ]
  }'
```

---

## Interrupt a Running Session

```bash
curl -X POST "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID/events" \
  "${HEADERS[@]}" \
  -d '{
    "events": [
      {
        "type": "user.interrupt"
      }
    ]
  }'
```

---

## Get Session Details

```bash
curl "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID" \
  "${HEADERS[@]}"
```

---

## List Sessions

```bash
curl "$ORCA_REGISTRY_URL/v1/sessions" \
  "${HEADERS[@]}"
```

---

## Delete a Session

```bash
curl -X DELETE "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID" \
  "${HEADERS[@]}"
```

---

## Upload a File

```bash
curl -X POST "$ORCA_REGISTRY_URL/v1/files" \
  -H "x-api-key: $ORCA_API_KEY" \
  -F "file=@path/to/file.txt"
```

---

## List and Download Session Files

List files the agent wrote to `/mnt/session/outputs/` during a session, then download them. The session-scoped path is an Orca extension; the account-wide Files list also takes `?scope_id=`.

```bash
# List a session's output files ({ data, first_id, last_id, has_more })
curl "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID/files" \
  "${HEADERS[@]}"

# Download one
curl "$ORCA_REGISTRY_URL/v1/sessions/$SESSION_ID/files/$FILE_ID/content" \
  "${HEADERS[@]}" \
  -o downloaded_file.txt

# Equivalent filter on the account-wide Files API
curl "$ORCA_REGISTRY_URL/v1/files?scope_id=$SESSION_ID" \
  "${HEADERS[@]}"
```

---

## List Agents

```bash
curl "$ORCA_REGISTRY_URL/v1/agents" \
  "${HEADERS[@]}"
```

---

## MCP Server Integration

```bash
# 1. Agent declares MCP server (no auth here — auth goes in a vault).
#    Every declared server must be referenced by an mcp_toolset tool.
curl -X POST "$ORCA_REGISTRY_URL/v1/agents" \
  "${HEADERS[@]}" \
  -d '{
    "name": "MCP Agent",
    "model": "claude-sonnet-4-6",
    "mcp_servers": [
      { "type": "url", "name": "my-tools", "url": "https://my-mcp-server.example.com/mcp" }
    ],
    "tools": [
      { "type": "agent_toolset" },
      { "type": "mcp_toolset", "mcp_server_name": "my-tools" }
    ]
  }'

# 2. Session attaches vault containing credentials for that MCP server URL
curl -X POST "$ORCA_REGISTRY_URL/v1/sessions" \
  "${HEADERS[@]}" \
  -d '{
    "agent": "agt_01H8...",
    "environment_id": "env_01H8...",
    "vault_ids": ["vlt_01H8..."]
  }'
```

See `shared/managed-agents-tools.md` §Vaults for creating vaults and adding credentials.

---

## Tool Configuration

```bash
curl -X POST "$ORCA_REGISTRY_URL/v1/agents" \
  "${HEADERS[@]}" \
  -d '{
    "name": "Restricted Agent",
    "model": "claude-sonnet-4-6",
    "tools": [
      {
        "type": "agent_toolset",
        "default_config": { "enabled": true },
        "configs": [
          { "name": "bash", "enabled": false }
        ]
      }
    ]
  }'
```
