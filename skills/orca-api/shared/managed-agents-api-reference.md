# Orca Agent Engine — API Reference

Quick reference for the portable managed-agents surface and documented Orca extensions, with the TypeScript SDK method and `ork` CLI command beside each. Base URL is the deployment **host root**; paths start at `/v1/` (alias `/api/v1/`). Auth and headers: `shared/managed-agents-overview.md` → Base URL, Auth, and Headers. `idempotency-key` is accepted on every write.

> Most users should provision agents and environments from a version-controlled setup script with the `ork` CLI — see `shared/orca-cli.md`. The endpoints below are the underlying API that the CLI and SDK drive.

## Agents

| Method | Path | SDK (`orca.*`) | CLI (`ork agent ...`) |
|---|---|---|---|
| `POST` | `/v1/agents` | `agents.create(params)` | `create` |
| `GET` | `/v1/agents` | `agents.list(params?)` | `list` |
| `GET` | `/v1/agents/{id}` (`?version=N`) | `agents.retrieve(id, {version?})` | `get <id> [--version N]` |
| `POST` | `/v1/agents/{id}` | `agents.update(id, params)` | `update <id> [--version N]` |
| `POST` | `/v1/agents/{id}/archive` | `agents.archive(id)` | `archive <id>` |
| `GET` | `/v1/agents/{id}/versions` | `agents.versions.list(id)` | `versions <id>` |
| `DELETE` | `/v1/agents/{id}` — **Orca extension: soft-deletes the agent and its versions; hosted deployments may not serve it** | — | — |

## Sessions

| Method | Path | SDK | CLI (`ork agent sessions ...`) |
|---|---|---|---|
| `POST` | `/v1/sessions` | `sessions.create(params)` | `create --environment-id <id> [--agent <id>]` |
| `GET` | `/v1/sessions` | `sessions.list(params?)` | `list` |
| `GET` | `/v1/sessions/{id}` | `sessions.retrieve(id)` | `get <id>` |
| `POST` | `/v1/sessions/{id}` | `sessions.update(id, params)` | `update <id>` |
| `DELETE` | `/v1/sessions/{id}` | `sessions.delete(id)` | `delete <id>` |
| `POST` | `/v1/sessions/{id}/archive` | `sessions.archive(id)` | `archive <id>` |
| `GET` | `/v1/sessions/{id}/outcome` — **Orca extension** | — | `outcome <id>` |

## Events

| Method | Path | SDK | CLI (`ork agent sessions events ...`) |
|---|---|---|---|
| `GET` | `/v1/sessions/{id}/events` | `sessions.events.list(id, params?)` | `list --session <id>` |
| `POST` | `/v1/sessions/{id}/events` | `sessions.events.send(id, {events})` | `send --session <id>` (typed: `message`/`outcome`/`tool-confirmation`; raw: `--event-json`) |
| `GET` | `/v1/sessions/{id}/events/stream` (SSE) | `sessions.events.stream(id, params?)` | `stream --session <id>` |

## Session Threads

| Method | Path | SDK | CLI (`ork agent sessions threads ...`) |
|---|---|---|---|
| `GET` | `/v1/sessions/{sid}/threads` | `sessions.threads.list(sid)` | `list --session <id>` |
| `GET` | `/v1/sessions/{sid}/threads/{tid}` | `sessions.threads.retrieve(sid, tid)` | `get <tid> --session <id>` |
| `POST` | `/v1/sessions/{sid}/threads/{tid}/archive` | `sessions.threads.archive(sid, tid)` | `archive <tid> --session <id>` |
| `GET` | `/v1/sessions/{sid}/threads/{tid}/events` | `sessions.threads.events.list(sid, tid)` | `events list --session <id> --thread <tid>` |
| `GET` | `/v1/sessions/{sid}/threads/{tid}/stream` (SSE) | `sessions.threads.events.stream(sid, tid)` | `events stream --session <id> --thread <tid>` |
| `POST` | `/v1/sessions/{sid}/threads/{tid}/interrupt` — Orca extension, raw HTTP only | — | — |

## Session Resources

| Method | Path | SDK | CLI (`ork agent sessions resources ...`) |
|---|---|---|---|
| `GET` | `/v1/sessions/{sid}/resources` | `sessions.resources.list(sid)` | `list --session <id>` |
| `POST` | `/v1/sessions/{sid}/resources` | `sessions.resources.add(sid, params)` | `add --session <id>` |
| `GET` | `/v1/sessions/{sid}/resources/{rid}` | `sessions.resources.retrieve(sid, rid)` | `get <rid> --session <id>` |
| `POST` | `/v1/sessions/{sid}/resources/{rid}` | `sessions.resources.update(sid, rid, params)` — rotates a repo's `authorization_token` | `update <rid> --session <id>` |
| `DELETE` | `/v1/sessions/{sid}/resources/{rid}` | `sessions.resources.delete(sid, rid)` | `delete <rid> --session <id>` |

## Session Files (Orca extension — session outputs)

| Method | Path | SDK | CLI (`ork agent sessions files ...`) |
|---|---|---|---|
| `GET` | `/v1/sessions/{id}/files` | `sessions.files.list(id)` | `list --session <id>` |
| `GET` | `/v1/sessions/{id}/files/{fid}` | `sessions.files.retrieve(id, fid)` | `get <fid> --session <id>` |
| `GET` | `/v1/sessions/{id}/files/{fid}/content` | `sessions.files.download(id, fid)` | `content <fid> --session <id> [--output-file p]` |
| `DELETE` | `/v1/sessions/{id}/files/{fid}` | `sessions.files.delete(id, fid)` | `delete <fid> --session <id>` |

## Environments

| Method | Path | SDK | CLI (`ork agent environments ...`) |
|---|---|---|---|
| `POST` | `/v1/environments` | `environments.create(params)` | `create` |
| `GET` | `/v1/environments` | `environments.list(params?)` | `list` |
| `GET` | `/v1/environments/{id}` | `environments.retrieve(id)` | `get <id>` |
| `POST` | `/v1/environments/{id}` | `environments.update(id, params)` | `update <id>` |
| `DELETE` | `/v1/environments/{id}` | `environments.delete(id)` | `delete <id>` |
| `POST` | `/v1/environments/{id}/archive` | `environments.archive(id)` | `archive <id>` |

## Vaults & Credentials

| Method | Path | SDK | CLI (`ork agent vaults ...`) |
|---|---|---|---|
| `POST` | `/v1/vaults` | `vaults.create(params)` | `create` |
| `GET` | `/v1/vaults` | `vaults.list(params?)` | `list` |
| `GET` | `/v1/vaults/{id}` | `vaults.retrieve(id)` | `get <id>` |
| `POST` | `/v1/vaults/{id}` | `vaults.update(id, params)` | `update <id>` |
| `DELETE` | `/v1/vaults/{id}` | `vaults.delete(id)` | `delete <id>` |
| `POST` | `/v1/vaults/{id}/archive` | `vaults.archive(id)` | `archive <id>` |
| `POST` | `/v1/vaults/{vid}/credentials` | `vaults.credentials.create(vid, params)` | `credentials create --vault <vid>` |
| `GET` | `/v1/vaults/{vid}/credentials` | `vaults.credentials.list(vid)` | `credentials list --vault <vid>` |
| `GET` | `/v1/vaults/{vid}/credentials/{cid}` | `vaults.credentials.retrieve(vid, cid)` | `credentials get <cid> --vault <vid>` |
| `POST` | `/v1/vaults/{vid}/credentials/{cid}` | `vaults.credentials.update(vid, cid, params)` | `credentials update <cid> --vault <vid>` |
| `DELETE` | `/v1/vaults/{vid}/credentials/{cid}` | `vaults.credentials.delete(vid, cid)` | `credentials delete <cid> --vault <vid>` |
| `POST` | `/v1/vaults/{vid}/credentials/{cid}/archive` | `vaults.credentials.archive(vid, cid)` | `credentials archive <cid> --vault <vid>` |
| `POST` | `/v1/vaults/{vid}/credentials/{cid}/mcp_oauth_validate` | `vaults.credentials.validate(vid, cid)` | `credentials validate <cid> --vault <vid>` |

## Memory Stores, Memories, Memory Versions

| Method | Path | SDK | CLI |
|---|---|---|---|
| `POST` | `/v1/memory_stores` | `memoryStores.create(params)` | `ork agent memory-stores create` |
| `GET` | `/v1/memory_stores` | `memoryStores.list(params?)` | `... list` |
| `GET` | `/v1/memory_stores/{id}` | `memoryStores.retrieve(id)` | `... get <id>` |
| `POST` | `/v1/memory_stores/{id}` | `memoryStores.update(id, params)` | `... update <id>` |
| `DELETE` | `/v1/memory_stores/{id}` | `memoryStores.delete(id)` | `... delete <id>` |
| `POST` | `/v1/memory_stores/{id}/archive` | `memoryStores.archive(id)` | `... archive <id>` |
| `GET` | `/v1/memory_stores/{id}/memories` | `memoryStores.memories.list(id, params?)` | `... memories list --memory-store <id>` |
| `POST` | `/v1/memory_stores/{id}/memories` | `memoryStores.memories.create(id, {body})` | `... memories create --memory-store <id> --path p --content c` |
| `GET` | `/v1/memory_stores/{id}/memories/{mid}` | `memoryStores.memories.retrieve(id, mid)` | `... memories get <mid> --memory-store <id>` |
| `POST` | `/v1/memory_stores/{id}/memories/{mid}` | `memoryStores.memories.update(id, mid, {body})` | `... memories update <mid> --memory-store <id>` |
| `DELETE` | `/v1/memory_stores/{id}/memories/{mid}` | `memoryStores.memories.delete(id, mid, params?)` | `... memories delete <mid> --memory-store <id>` |
| `GET` | `/v1/memory_stores/{id}/memory_versions` | `memoryStores.memoryVersions.list(id, params?)` | `ork agent memory-versions list --memory-store <id>` |
| `GET` | `/v1/memory_stores/{id}/memory_versions/{vid}` | `memoryStores.memoryVersions.retrieve(id, vid)` | `... get <vid> --memory-store <id>` |
| `POST` | `/v1/memory_stores/{id}/memory_versions/{vid}/redact` | `memoryStores.memoryVersions.redact(id, vid)` | `... redact <vid> --memory-store <id>` |

## Files

| Method | Path | SDK | CLI (`ork agent files ...`) |
|---|---|---|---|
| `POST` | `/v1/files` (multipart) | `files.upload({file})` | `create -f <path>` |
| `GET` | `/v1/files` (`?scope_id=` filters to one session's outputs — raw HTTP on the engine; the SDK uses `sessions.files.list(sid)`) | `files.list(params?)` | `list` |
| `GET` | `/v1/files/{id}` | `files.retrieve(id)` | `get <id>` |
| `GET` | `/v1/files/{id}/content` | `files.download(id)` | `content <id> [--output-file p]` |
| `DELETE` | `/v1/files/{id}` | `files.delete(id)` | `delete <id>` |

## Skills

| Method | Path | SDK | CLI (`ork agent skills ...`) |
|---|---|---|---|
| `POST` | `/v1/skills` (multipart) | `skills.create({files, ...})` | `create -f <path> [-f ...]` |
| `GET` | `/v1/skills` | `skills.list(params?)` | `list` |
| `GET` | `/v1/skills/{id}` | `skills.retrieve(id)` | `get <id>` |
| `DELETE` | `/v1/skills/{id}` | `skills.delete(id)` | `delete <id>` |
| `POST` | `/v1/skills/{id}/versions` (multipart) | `skills.versions.create(id, {files, ...})` | `versions create <skill-id> -f <path> ...` |
| `GET` | `/v1/skills/{id}/versions` | `skills.versions.list(id)` | `versions list <skill-id>` |
| `GET` | `/v1/skills/{id}/versions/{v}` | `skills.versions.retrieve(id, v)` | `versions get <skill-id> <v>` |
| `GET` | `/v1/skills/{id}/versions/{v}/content` | — | `versions content <skill-id> <v> [--output-file p]` |
| `DELETE` | `/v1/skills/{id}/versions/{v}` | `skills.versions.delete(id, v)` | `versions delete <skill-id> <v>` |

## Agent Triggers

Triggers are core `/v1/triggers` operations. Open-source core supports cron + `SESSION_PER_EVENT` + one replica; hosted deployments widen the same request union with Pulsar/Kafka sources (hosted only), more session modes, and deployment-supported replica counts. Triggers are not part of the hosted extension group, so no discovery check applies.

| Method | Path | SDK (`orca.triggers.*`) | CLI (`ork agent triggers ...`) |
|---|---|---|---|
| `POST` | `/v1/triggers` | `create(params)` | `create` |
| `GET` | `/v1/triggers` | `list(params?)` | `list` |
| `GET` | `/v1/triggers/{id}` | `retrieve(id)` | `get <id>` |
| `POST` | `/v1/triggers/{id}` — partial update | `update(id, params)` | `update <id>` |
| `DELETE` | `/v1/triggers/{id}` — soft-delete Trigger, retain Session history | `delete(id)` | `delete <id>` |
| `POST` | `/v1/triggers/{id}/pause` | `pause(id)` | `pause <id>` |
| `POST` | `/v1/triggers/{id}/unpause` | `unpause(id)` | `unpause <id>` |
| `GET` | `/v1/triggers/{id}/sessions` | `sessions.list(id, params?)` | `sessions <id>` |

Full shape and portability rules: `shared/managed-agents-triggers.md`.

## Discovery & health (Orca extensions)

| Method | Path | SDK | Notes |
|---|---|---|---|
| `GET` | `/apis` | `discovery.groups()` | Extension groups this deployment serves. Every engine lists `runtime.runorca.ai`, `policy.runorca.ai` and `pricing.runorca.ai`; hosted deployments add the hosted extension group. Check for the group you need. Core Triggers do not use this gate. |
| `GET`/`POST` | `/apis/policy.runorca.ai/v1/guardrails` | `guardrails.list()` / `guardrails.create(params)` | Guardrails: spend and token caps, attached with `guardrail_ids` |
| `GET` | `/apis/pricing.runorca.ai/v1/modelprices` | `modelPrices.list()` | Per-model prices |
| `GET` | `/apis/runtime.runorca.ai/v1/harnesses` | — | Harnesses with their models and effort levels |
| `GET` | `/api` | — | Discovery root |
| `GET` | `/healthz`, `/readyz` | — | Unauthenticated probes (CLI: `ork healthz` / `ork readyz`). Raw callers should send `Accept: application/json` for gateway portability. |

## Request Schema Quick Reference

**CreateAgent** (`POST /v1/agents`) — strict; unknown keys rejected:

```json
{
  "name": "Research Agent",
  "model": "claude-sonnet-4-6",
  "system": "You are a research assistant.",
  "description": "Researches questions end to end.",
  "tools": [
    { "type": "agent_toolset" },
    { "type": "mcp_toolset", "mcp_server_name": "linear" },
    { "type": "custom", "name": "get_weather", "description": "...", "input_schema": { "type": "object" } }
  ],
  "mcp_servers": [{ "type": "url", "name": "linear", "url": "https://mcp.linear.app/mcp" }],
  "skills": [{ "type": "custom", "skill_id": "skill_01H8...", "version": "latest" }],
  "multiagent": { "type": "coordinator", "agents": [{ "type": "self" }] },
  "metadata": { "team": "research" }
}
```

**CreateSession** (`POST /v1/sessions`) — strict; exactly one of `agent` / `agent_id`:

```json
{
  "agent": { "type": "agent", "id": "agt_01H8...", "version": 3 },
  "environment_id": "env_01H8...",
  "title": "Nightly research",
  "vault_ids": ["vlt_01H8..."],
  "resources": [
    { "type": "file", "file_id": "file_01H8...", "mount_path": "/workspace/data.csv" },
    { "type": "github_repository", "url": "https://github.com/owner/repo", "authorization_token": "..." },
    { "type": "memory_store", "memory_store_id": "mems_01H8..." }
  ],
  "initial_events": [
    { "type": "user.message", "content": [{ "type": "text", "text": "Start with the README." }] }
  ],
  "metadata": { "run": "nightly" }
}
```

**CreateEnvironment** (`POST /v1/environments`):

```json
{
  "name": "research-env",
  "config": {
    "type": "cloud",
    "networking": { "type": "limited", "allow_mcp_servers": true, "allowed_hosts": ["api.example.com"] },
    "packages": { "pip": ["requests"] }
  }
}
```

**SendEvents** (`POST /v1/sessions/{id}/events`) — the seven input kinds:

```json
{ "events": [
  { "type": "user.message", "content": [{ "type": "text", "text": "..." }] },
  { "type": "user.interrupt", "session_thread_id": null },
  { "type": "user.tool_confirmation", "tool_use_id": "evt_...", "result": "deny", "deny_message": "..." },
  { "type": "user.tool_result", "tool_use_id": "evt_...", "content": [{ "type": "text", "text": "..." }] },
  { "type": "user.custom_tool_result", "custom_tool_use_id": "evt_...", "content": [{ "type": "text", "text": "..." }] },
  { "type": "user.define_outcome", "description": "...", "rubric": { "type": "text", "content": "..." }, "max_iterations": 3 },
  { "type": "system.message", "content": [{ "type": "text", "text": "..." }] }
] }
```

`user.tool_result` is accepted only on self-hosted environments (client-side tool execution); elsewhere it returns 400.

## Error Handling

The open-source Registry uses the Claude-style envelope on `/v1`, `/api`, and `/apis` (probe endpoints `/healthz`/`/readyz` excepted):

```json
{
  "type": "error",
  "error": { "type": "invalid_request_error", "message": "..." },
  "request_id": "..."
}
```

| Status | `error.type` |
|---|---|
| 400, other 4xx (default) | `invalid_request_error` |
| 401 | `authentication_error` |
| 402 | `billing_error` |
| 403 | `permission_error` |
| 404 | `not_found_error` |
| 408, 504 | `timeout_error` |
| 409 | `conflict_error` |
| 413 | `request_too_large` |
| 429 | `rate_limit_error` |
| 503, 529 | `overloaded_error` |
| 500, 502, other 5xx | `api_error` |

Domain errors keep their specific types inside that envelope (e.g. `memory_path_conflict_error`, `memory_precondition_failed_error`). Hosted deployments and provider adapters can still return transitional bodies such as `{"reason":"..."}` or plain text for some validation/provider failures. Portable clients must key behavior on HTTP status and treat the body as open; do not assume `error.type` is always present.

The SDK raises typed classes per status — `BadRequestError`, `AuthenticationError`, `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `UnprocessableEntityError`, `RateLimitError`, `InternalServerError` — all extending `APIError` (with `.status`, `.headers`, `.error`) under the root `OrcaError`. `APIConnectionError`, `APIConnectionTimeoutError` and `APIUserAbortError` extend `APIError` too, with `status` undefined. `ExtensionNotAvailableError` (an `OrcaError`, not an `APIError`) is thrown before any request when a deployment doesn't advertise the extension group a call needs: `orca.cloud.*`, `orca.guardrails.*`, `orca.modelPrices.*`, and creates or updates that carry `guardrail_ids`. Retries are automatic on network errors, 408, 409, 429, and 5xx (default 2, exponential backoff) — see Retries and idempotency below.

Catch most-specific-first:

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
-->
<!-- ts-check: reset -->
```ts
import { APIError, NotFoundError, RateLimitError } from '@runorca/orca-sdk';

try {
  await orca.agents.retrieve('agt_01H8...');
} catch (err) {
  if (err instanceof NotFoundError) {
    // create it, or surface a clean message
  } else if (err instanceof RateLimitError) {
    // back off and retry
  } else if (err instanceof APIError) {
    // status is undefined for connection errors, timeouts and aborts
    console.error(err.status, err.error);
    throw err;
  } else {
    throw err; // not from the API: e.g. ExtensionNotAvailableError
  }
}
```

### Retries and idempotency

The SDK retries POSTs as well as reads, and sends an `Idempotency-Key` only when you pass `idempotencyKey`. The engine honours the key on every write, so give each create or send that must not happen twice its own key. A 409 from an optimistic-concurrency write (a stale `version`, a memory precondition) won't change on retry; pass `maxRetries: 0` so it surfaces at once.

<!-- ts-check-context
declare const session: { id: string };
declare const agent: { id: string; version: number };
declare const turnId: string;
-->
<!-- ts-check: reset -->
```ts
await orca.sessions.events.send(
  session.id,
  { events: [{ type: 'user.message', content: [{ type: 'text', text: 'Next step' }] }] },
  { idempotencyKey: `turn-${turnId}` },
);

await orca.agents.update(
  agent.id,
  { version: agent.version, system: 'You are terse.' },
  { maxRetries: 0 },
);
```

## Pagination

Two cursor schemes, by route family:

| Route family | Envelope | Params |
|---|---|---|
| Agents, agent versions, environments, session resources, memory stores/memories/versions, vaults, credentials | `{ data, next_page }` | `limit`, `page` (opaque cursor from `next_page`) |
| Sessions | `{ data, next_page, prev_page }` | `limit`, `page`, `agent_id`, `include_archived`, and `metadata_<key>=<value>` (exact match, AND-combined, up to 16). On the engine over raw HTTP also `agent_version`, `created_at[...]`, `order` and status filters, which the SDK and hosted deployments don't offer. A cursor carries its sort order — conflicting explicit `order` on the next page is a 400 |
| Session events | `{ data, next_page }` | `limit`, `page`, `types`, `order`, `created_at[...]`, `subpath` |
| Skills | `{ data, has_more, next_page }` | `limit` (max 100; versions max 1000), `page`; `source` is raw HTTP on the engine only |
| Files, session files | `{ data, first_id, last_id, has_more }` | `limit`, `after_id`, `before_id` (Files also `scope_id`, raw HTTP on the engine only) — Anthropic's older Files cursor scheme |

In the SDK every list is async-iterable across pages (`for await (const x of orca.agents.list())`); one page at a time via `page.data` + the params above that the SDK exposes. Vault list `limit` caps at 100. `include_archived` defaults to false where supported.

## Response-shape notes

- Treat every resource ID as opaque. Open-source Registry commonly emits `agt_`, `ses_`, `sth_`, `env_`, `file_`, `skill_`, `vlt_`, `mems_`, `mem_`, `memver_`, and `evt_`; other deployments and adapters may emit forms such as `agent-`, `session-`, `env-`, and `skill-`. Never synthesize IDs or validate them with a deployment-specific prefix regex.
- `update` on core resources, including Triggers, is `POST` with per-resource partial/merge semantics. Read the resource section before deciding how omitted and null fields behave.
- With the `orca-beta` header, responses switch to Orca-native aliases (`agent_toolset`, `{provider, id}` model form, no `prev_page` on session lists). Omit it for Claude-compatible shapes.
