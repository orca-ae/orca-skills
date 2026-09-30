# Orca Agent Engine — Core Concepts

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
declare const agent: { id: string; version: number };
declare const agentId: string;
declare const environmentId: string;
declare const session: { id: string };
-->

## Architecture

Orca Agent Engine is built around four core concepts:

| Concept | Endpoint | What it is |
|---|---|---|
| **Agent** | `/v1/agents` | A persisted, versioned object defining the agent's capabilities and persona: model, system prompt, tools, MCP servers, skills. **Must be created before starting a session.** See the Agents section below. |
| **Session** | `/v1/sessions` | A stateful interaction with an agent. References a pre-created agent by ID + an environment + initial instructions. Produces an event stream. |
| **Environment** | `/v1/environments` | A template defining the configuration for container provisioning. |
| **Container** | N/A | An isolated compute instance where the agent's **tools** execute (bash, file ops, code). The agent loop does not run here — it runs on Agent Engine's harness and acts on the container via tool calls. |

```
                       ┌─────────────────────────────────────┐
                       │  Agent Engine harness               │
Agent (config) ───────▶│  (agent loop: model + tool calls)   │
                       └──────────────┬──────────────────────┘
                                      │ tool calls
                                      ▼
Environment (template) ──▶ Container (tool execution workspace)
                                 │
                         Session ─┤
                                 ├── Resources (files, repos, memory stores — attached at startup)
                                 ├── Vault IDs (MCP credential references)
                                 └── Conversation (event stream in/out)
```

> **Agent creation is a prerequisite.** Sessions reference a pre-created agent by ID — `model`/`system`/`tools` live on the agent object, never on the session. Every flow starts with `POST /v1/agents`.

---

## Session Lifecycle

```
rescheduling → running ↔ idle → terminated
```

| Status         | Description                                                        |
| -------------- | ------------------------------------------------------------------ |
| `idle` | Agent has finished the current task, and is awaiting input. It's either waiting for input to continue working via a `user.message`, or blocked awaiting a `user.custom_tool_result` or `user.tool_confirmation`. The `stop_reason` attached to `session.status_idle` says why the agent stopped (`end_turn`, `requires_action`, `retries_exhausted`). |
| `running` | Session has started running, and the agent is actively doing work. |
| `rescheduling` | Session is (re)scheduling after a retryable error has occurred, ready to be picked up by the harness. |
| `terminated` | Reserved terminal state. The harness does not currently emit it — completed work leaves the session `idle`, and genuine termination happens through archive/delete. |

- Events can be sent when the session is `running` or `idle`. Messages are queued and processed in order.
- The agent transitions `idle → running` when it receives a new event, then back to `idle` when done.
- Errors surface as `session.error` events in the stream, not as a status value.

### Built-in session features

- **Context compaction** — if the conversation approaches max context, the harness condenses session history to keep the interaction going (an `agent.thread_context_compacted` event marks it)
- **Extended thinking** — `agent.thinking` events signal thinking progress and carry no thinking content

### Session operations

| Operation | Notes |
|---|---|
| List / fetch | Paginated list or single resource by ID |
| Update | `title`, `metadata`, and the session-local `agent.tools`/`agent.mcp_servers`/`agent.model` can be overridden (see § Updating the agent configuration mid-session). `vault_ids` is create-only — the update field exists on the wire but every attempt to set it is rejected. |
| Archive | Session becomes **read-only**. Not reversible. |
| Delete | Soft delete: the session disappears from every read (404, no restore) and open streams end with `session.deleted`. The event history is retained on the server, so delete is not a purge. |

These are ops/inspection calls — typically made from a terminal, not application code. From the shell (see `shared/orca-cli.md`):

```sh
ork agent sessions list -o json | jq -r '.data[] | [.id, .title, .status] | @tsv'
ork agent sessions get "$SID"
ork agent sessions events stream --session "$SID"   # watch events live
ork agent sessions archive "$SID"
ork agent sessions delete "$SID"
```

---

## Sessions

A session is a running agent instance inside an environment.

### Session Object

Key fields returned by the API:

| Field           | Type     | Description                                         |
| --------------- | -------- | --------------------------------------------------- |
| `type` | string | Always `"session"` |
| `id` | string | Unique session ID (`ses_...`) |
| `title` | string | Human-readable title (nullable) |
| `status` | string | `idle`, `running`, `rescheduling`, `terminated` |
| `created_at` / `updated_at` | string | ISO 8601 timestamps |
| `archived_at` | string | ISO 8601 timestamp (nullable) |
| `environment_id` | string | Environment ID |
| `agent` | object | Agent reference with the session's effective configuration |
| `vault_ids` | array | Vaults attached at creation |
| `resources` | array | Attached files, repos, and memory stores |
| `metadata` | object | User-provided string key-value pairs |
| `usage` | object | Cumulative token usage: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation` |
| `stats` | object | Timing statistics (`active_seconds`, `duration_seconds`) |
| `timing` | object | Orca extension: wall-clock `started_at`, `last_active_at`, `active_seconds`, `duration_seconds` |
| `outcome_evaluations` | array | Latest advisory outcome verdicts, when the session defined outcomes — see `shared/managed-agents-outcomes.md` |

### Creating a session

**A session is meaningless without an agent.** Sessions reference a pre-created agent by ID. Create the agent first via `agents.create()`, then reference it:

<!-- ts-check: reset -->
```ts
// 1. Create the agent (reusable, versioned)
const agent = await orca.agents.create({
  name: 'Coding Assistant',
  model: 'claude-sonnet-4-6',
  system: 'You are a helpful coding agent.',
  tools: [{ type: 'agent_toolset' }],
});

// 2. Start a session that references it
const session = await orca.sessions.create({
  agent: agent.id, // string shorthand → latest version. Or: { type: "agent", id: agent.id, version: agent.version }
  environment_id: environmentId,
  title: 'Hello World Session',
});
```

**Session creation parameters:**

| Field           | Type     | Required | Description                                    |
| --------------- | -------- | -------- | ---------------------------------------------- |
| `agent`         | string or object | **Yes** (exactly one of `agent` / legacy `agent_id`) | Three forms: string shorthand `"agt_01H8..."` (latest version); pinned `{type: "agent", id, version}`; or `{type: "agent_with_overrides", id, version?, ...}` to override `model`/`system`/`tools`/`mcp_servers`/`skills` for this session only — see § Override agent configuration for a session |
| `environment_id`| string   | **Yes**  | Environment ID                                 |
| `title`         | string   | No       | Human-readable name, ≤1024 chars (appears in logs/dashboards) |
| `resources`     | array    | No       | Files, GitHub repos, or memory stores, attached to the container at startup (max 100 entries; per-type caps apply — see `shared/managed-agents-environments.md`) |
| `initial_events`| array    | No       | Events to send at creation, processed in order — collapses create + first send into one call. See § Seeding a session with `initial_events` below. |
| `vault_ids`     | array    | No       | Vault IDs (`vlt_...`) — MCP credentials with auto-refresh + `environment_variable` secrets substituted at egress. See `shared/managed-agents-tools.md` → Vaults. |
| `metadata`      | object   | No       | User-provided string key-value pairs           |

#### Seeding a session with `initial_events`

Creating a session without `initial_events` registers the session in `idle` and starts no work; the sandbox is provisioned when the session first needs it. Passing a non-empty `initial_events` array starts the agent loop in the same call — check `status` on the create response rather than waiting for an `idle → running` transition.

<!-- ts-check: reset -->
```ts
const session = await orca.sessions.create({
  agent: agentId,
  environment_id: environmentId,
  initial_events: [
    { type: 'user.message', content: [{ type: 'text', text: 'Review the auth module.' }] },
  ],
});
```

- **Only `user.message` and `user.define_outcome` are accepted**, max **50** events. The tool-result kinds (`user.tool_confirmation`, `user.tool_result`, `user.custom_tool_result`) are rejected because no agent turn exists yet, and `user.interrupt` because there is no turn to stop.
- Each event is validated and persisted in list order — exactly as if you had posted it to the send-events endpoint immediately after creation. If any event fails validation, the whole request is rejected and no session is created.
- **The events are not echoed on the create response.** Read them back with `sessions.events.list(session.id)` if you need their server-assigned IDs.

An outcome-driven session is therefore a single call — pass one `user.define_outcome` in `initial_events` instead of creating the session and then sending the event (see `shared/managed-agents-outcomes.md`).

**Agent configuration fields** (passed to `agents.create()`, not `sessions.create()`):

| Field         | Type     | Required | Description                                    |
| ------------- | -------- | -------- | ---------------------------------------------- |
| `name`        | string   | **Yes**  | Human-readable name (1-256 chars)              |
| `model`       | string or object | **Yes** | Model ID — bare string, or an object taking `id`, `speed`, `effort`. Anthropic model IDs by default (`provider` defaults to `anthropic`). See § Effort and speed on the agent model. |
| `system`      | string   | No       | System prompt — defines the agent's behavior   |
| `tools`       | array    | No       | Encompasses three kinds: (1) the built-in agent toolset (`agent_toolset`), (2) MCP tools (`mcp_toolset`), and (3) custom client-side tools. Max 128. |
| `mcp_servers` | array    | No       | MCP server connections — standardized third-party capabilities (e.g. GitHub, Linear). Max 20, unique names. See `shared/managed-agents-tools.md` → MCP Servers. |
| `skills`      | array    | No       | Customized "best-practices" context with progressive disclosure. Max 500 refs. See `shared/managed-agents-tools.md` → Skills. |
| `description` | string   | No       | Description of the agent (up to 2048 chars)    |
| `multiagent`  | object   | No       | `{type: "coordinator", agents: [...]}` — roster this agent may delegate to (1-20 entries). See `shared/managed-agents-multiagent.md`. |
| `metadata`    | object   | No       | User-provided string key-value pairs           |

---

## Agents

**This is where every Agent Engine flow begins.** The agent object is a persisted, versioned configuration — you create it once, then reference it by ID every time you start a session. No agent → no session.

### Agent Object

The API is **flat** — `model`, `system`, `tools` etc. are top-level fields, not wrapped in an `agent:{}` sub-object.

| Field              | Type     | Required | Description                                        |
| ------------------ | -------- | -------- | -------------------------------------------------- |
| `name`             | string   | Yes      | Human-readable name                                |
| `model`            | string or object | Yes | Model ID — bare string, or `{id, speed?, effort?}` |
| `system`           | string   | No       | System prompt                                      |
| `tools`            | array    | No       | Agent toolset / MCP toolset / custom tools         |
| `mcp_servers`      | array    | No       | MCP server connections                             |
| `skills`           | array    | No       | Skill references (max 500)                         |
| `description`      | string   | No       | Description of the agent                           |
| `multiagent`       | object   | No       | Coordinator roster — see `shared/managed-agents-multiagent.md` |
| `metadata`         | object   | No       | User-provided string key-value pairs               |

### Lifecycle: create once, run many, update in place

The agent is a **persistent resource**, not a per-run parameter. The intended pattern:

```
┌─ setup (once) ─────────┐     ┌─ runtime (every invocation) ─┐
│ agents.create()        │     │ sessions.create(             │
│   → store agent_id     │ ──→ │   agent={type:..., id: ID}   │
│     in config/env/db   │     │ )                            │
└────────────────────────┘     └──────────────────────────────┘
```

**Anti-pattern:** calling `agents.create()` at the top of every script run. This accumulates orphaned agent objects, pays create latency on every invocation, and defeats the versioning model. If you see `agents.create()` in a function that's called per-request or per-cron-tick, that's wrong — hoist it to one-time setup and persist the ID.

> **Recommended — provision with the `ork` CLI from a version-controlled setup script.** The split is **CLI for the control plane, SDK for the data plane**: agents and environments are relatively static resources you manage with `ork agent create`/`update` (JSON payloads committed to your repo, applied from CI); sessions are dynamic and driven by your application through the SDK. See `shared/orca-cli.md` → *Version-controlled setup*. The SDK `agents.create()` call shown elsewhere in this doc is the in-code equivalent — use it when you need to provision programmatically.

### Effort and speed on the agent model

Pass `model` as an object to set the effort level: `{"id": "claude-sonnet-4-6", "effort": "high"}`. `effort` accepts a level string (`low`, `medium`, `high`, `xhigh`, `max`) or an object such as `{"type": "high"}`. The create/update response echoes it in object form (`effort: {type: ...}`) and backfills the model's default level (`high`) when omitted.

Validation is model- and harness-aware. On the default Claude harness, `effort` and `speed` are accepted only for Anthropic models the deployment's harness catalog knows, each model supports a specific effort subset (e.g. `claude-sonnet-4-6` has no `xhigh`), and `speed: "fast"` is restricted to the fast-mode-capable models (`claude-opus-5`, `claude-opus-4-8`). Agents on the Codex and Pi harnesses (`codex_sdk`, `pi_sdk`, fixed when the agent is created) take their own models and effort levels, including `ultra`; `speed: "fast"` stays Claude-only. An unsupported combination is a 400 naming the supported levels. `GET /apis/runtime.runorca.ai/v1/harnesses` lists each harness with its models and effort levels, and `orca-agent-engine/docs/managed-agents/harness-modes.md` explains how an agent selects one.

### Guardrails: spend and token caps

There is no session `budget` field — the strict session contract rejects it. Caps are **Guardrails** from the policy extension (`/apis/policy.runorca.ai/v1/guardrails`; `orca.guardrails.*` in the SDK): a `cost_budget` caps a session's spend and a `token_budget` its total tokens. Attach guardrails with `guardrail_ids` on the agent, or inside `agent_with_overrides` for a single session. Shapes and enforcement: `orca-agent-engine/docs/managed-agents/guardrails.md`.

### Versioning

Each `POST /v1/agents/{id}` (update) creates a new immutable version — a sequential integer, starting at 1 and incrementing on each update. The agent's history is append-only — you can't edit a past version. `GET /v1/agents/{id}/versions` lists them, and `GET /v1/agents/{id}?version=N` fetches one.

**`version` on update is optional.** Supply it for optimistic concurrency, or omit it to apply the update unconditionally:

| `version` | Behavior | Fits |
|---|---|---|
| Supplied (must be ≥ 1) | **409 `version mismatch`** if it doesn't match the agent's current version — even when the fields you send already equal the stored values. Re-read and retry. | Interactive callers; the recommended default |
| Omitted | Applies unconditionally: if another writer lands between read and write, the patch is recomputed against the new current value — no synthetic conflict for either caller. | Declarative apply loops — e.g. a CI job syncing checked-in agent definitions, where the loop owns the agent |

**Update semantics.** Omitted fields are preserved. `system`, `description`, `tools`, `mcp_servers`, `skills`, `multiagent`, and `metadata` can be cleared with `null` (arrays also with `[]`; metadata clears per-key with `null` values); `model` and `name` cannot be cleared.

**Why version:**
- **Reproducibility** — pin a session to a known-good config: `{type: "agent", id, version: 3}`
- **Safe iteration** — update the agent without breaking sessions already running on the old version
- **Rollback** — if a new system prompt regresses, pin new sessions back to the prior version while you debug

**Getting the version to pin:** `agents.create()` and `agents.update()` both return `version` in the response. Store it alongside `agent_id`. To fetch the current latest for an existing agent: `GET /v1/agents/{id}` → `.version`.

**When to update vs create new:** Update (`POST /v1/agents/{id}`) when it's conceptually the same agent with tweaked behavior (better prompt, extra tool). Create a new agent when it's a different persona/purpose. Rule of thumb: if you'd give it the same `name`, update.

### Agent Endpoints

| Operation        | Method   | Path                                  |
| ---------------- | -------- | ------------------------------------- |
| Create           | `POST`   | `/v1/agents`                          |
| List             | `GET`    | `/v1/agents`                          |
| Get              | `GET`    | `/v1/agents/{id}` (`?version=N` for a historical version) |
| Update           | `POST`   | `/v1/agents/{id}`                     |
| Archive          | `POST`   | `/v1/agents/{id}/archive`             |
| List versions    | `GET`    | `/v1/agents/{id}/versions`            |
| Delete           | `DELETE` | `/v1/agents/{id}` — **Orca raw-HTTP extension**: soft-deletes the agent and all its versions (they disappear from reads; no restore). No SDK or CLI binding, and hosted deployments may not serve it |

> ⚠️ **Archive is permanent.** Archiving an agent stops **new sessions from referencing it** — existing sessions continue to run — and there is no unarchive. For portable cleanup use archive: `DELETE` is a raw-HTTP extension with no SDK or CLI binding. Never archive or delete a production agent as routine cleanup — confirm with the user first.

### Using an Agent in a Session

Reference the agent by string ID (latest version) or by object with an explicit version:

<!-- ts-check: reset -->
```ts
// String shorthand — uses the agent's latest version
const session = await orca.sessions.create({
  agent: agent.id,
  environment_id: environmentId,
});

// Or pin to a specific version (int)
const pinned = await orca.sessions.create({
  agent: { type: 'agent', id: agent.id, version: agent.version },
  environment_id: environmentId,
});
```

### Override agent configuration for a session

The third `agent` form, `agent_with_overrides`, replaces parts of the agent's configuration for **a single session** — try a different model or grant an extra tool without versioning the agent. Pass `id` (and optionally `version`; omitted = latest, same default as the other two forms) plus any of `model`, `system` (≤100K chars), `tools`, `mcp_servers`, `skills`:

<!-- ts-check: reset -->
```ts
const session = await orca.sessions.create({
  agent: {
    type: 'agent_with_overrides',
    id: agent.id,
    model: 'claude-sonnet-4-6', // replace the agent's model for this session
    system: null, // clear the system prompt for this session
  },
  environment_id: environmentId,
});
```

- **Omit** a field → the session inherits the value from the referenced agent version.
- **A value** → replaces the agent's value **in full**. Overrides never merge — a `tools` override must list every tool the session should have, and a `model` override replaces the whole model object: omitted `speed`/`effort` controls take the replacement model's defaults rather than inheriting the agent's.
- `system: null` runs the session with no system prompt; `model` is required on the agent and cannot be nulled.

Overrides are session-local: they do **not** modify the agent resource or create a new agent version. The response's `agent` object reflects the post-override configuration, while its `id` and `version` still identify the base agent — so you can trace a session back to its base.

### Updating the agent configuration mid-session

`sessions.update()` can change `agent.tools` and `agent.mcp_servers` (including permission policies), and `agent.model`, on an **existing** session. This is a **session-local override** — it does not create a new agent version and does not propagate back to the agent object. The provided arrays are **full replacements**; to append one tool, `GET` the session, modify, and `POST` back. The session must be **idle** — a running session returns 409 `session must be idle to update agent configuration`; send a `user.interrupt` and wait for the idle first. `vault_ids` is **create-only**: the update field exists on the wire but the endpoint rejects every attempt to set it — attach vaults when you create the session.

Among the agent-configuration fields, `tools`, `mcp_servers` and `model` can change after a session is created — replacing `model` is an Orca extension and takes the whole model object. To run with a `system` or `skills` other than the agent's values, use `agent_with_overrides` at create time (above). (`title` and `metadata` have their own session-update paths — see § Session operations.) You can still **append system-level context between turns** by sending a `system.message` event (see `shared/managed-agents-events.md` § Adding system context mid-session).

<!-- ts-check: reset -->
```ts
await orca.sessions.update(session.id, {
  agent: {
    tools: [{ type: 'agent_toolset' }, { type: 'mcp_toolset', mcp_server_name: 'linear' }],
    mcp_servers: [{ type: 'url', name: 'linear', url: 'https://mcp.linear.app/mcp' }],
  },
});
```
