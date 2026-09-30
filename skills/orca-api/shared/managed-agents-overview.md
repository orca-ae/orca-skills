# Orca Agent Engine — Overview

Orca Agent Engine provisions a container per session as the agent's workspace. The agent loop runs on Agent Engine's orchestration layer; the container is where the agent's *tools* execute — bash commands, file operations, code. You create a persisted **Agent** config (model, system prompt, tools, MCP servers, skills), then start **Sessions** that reference it. The session streams events back to you; you send user messages and tool results in.

Agent Engine's registry API is compatible with Anthropic's Managed Agents API: a Claude-style request works with the host swapped to your deployment. The differences that matter are collected in this skill; where Orca diverges, the Orca shape is documented and the upstream shape is called out.

## ⚠️ THE MANDATORY FLOW: Agent (once) → Session (every run)

**Why agents are separate objects: versioning.** An agent is a persisted, versioned config — every update creates a new immutable version, and sessions pin to a version at creation time. This lets you iterate on the agent (tweak the prompt, add a tool) without breaking sessions already running, roll back if a change regresses, and A/B test versions side-by-side. None of that works if you `agents.create()` fresh on every run.

Every session references a pre-created `/v1/agents` object. Create the agent once, store the ID, and reuse it across runs.

| Step | Call | Frequency |
|---|---|---|
| 1 | `POST /v1/agents` — `model`, `system`, `tools`, `mcp_servers`, `skills` live here | **ONCE.** Store `agent.id` **and** `agent.version`. |
| 2 | `POST /v1/sessions` — `environment_id` plus `agent: "agt_01H8..."` or `{type: "agent", id, version}` | **Every run.** String shorthand uses latest version. |

If you're about to write `sessions.create()` with `model`, `system`, or `tools` on the session body — **stop**. Those fields live on `agents.create()`. The session takes a *pointer* only (plus the `environment_id` it runs in).

**When generating code, separate setup from runtime.** `agents.create()` belongs in a setup script (or a guarded `if (!agentId)` block), not at the top of the hot path. If the user's code calls `agents.create()` on every invocation, they're accumulating orphaned agents and paying the create latency for nothing. The correct shape is: keep the agent definition in a version-controlled setup script that runs `ork agent create` (JSON payloads for tools and model can live in committed files — see `shared/orca-cli.md`), persist the returned ID (config file, env var, secrets manager), and have every run load the ID and call `sessions.create()`.

**To change the agent's behavior, use `POST /v1/agents/{id}` — don't create a new one.** Each update bumps the version; running sessions keep their pinned version, new sessions get the latest (or pin explicitly via `{type: "agent", id, version}`). See `shared/managed-agents-core.md` → Agents → Versioning. To change `tools`/`mcp_servers`/`model` on **one session** (while it is idle) without touching the agent object, use `sessions.update()` (`vault_ids` attaches at session create only) — see `shared/managed-agents-core.md` → Updating the agent configuration mid-session.

## Base URL, Auth, and Headers

<!-- orca-warn -->
**Base URL is the deployment host root.** Every path in this skill starts at `/v1/` directly under the host — `https://<your-deployment>/v1/agents`, never `/v1/registry/...` (a deprecated cloud-only dialect; the CLI and SDK strip that suffix with a warning). `/api/v1/*` is an accepted alias for `/v1/*`.
<!-- /orca-warn -->

**Two credential types, each with its own header.**

| Client | Endpoint env var | Workspace API key (`orca_…`) | OIDC access token |
|---|---|---|---|
| `ork` CLI | `ORCA_REGISTRY_URL` (host root) | `ORCA_API_KEY` → `x-api-key` | `ORCA_ACCESS_TOKEN` → `Authorization: Bearer ...` |
| TypeScript SDK | `ORCA_BASE_URL` (host root) | `apiKey: null` + `defaultHeaders: { 'x-api-key': ... }` | `apiKey` → `Authorization: Bearer ...` |
| Raw HTTP | — | `x-api-key: ...` | `Authorization: Bearer ...` |

The endpoint is the same host root under two names. A workspace API key authenticates only through `x-api-key` — sent as a Bearer token it is checked as an OIDC token and rejected with 401 — and a present `x-api-key` is authoritative: `Authorization` is not consulted. The SDK reads `ORCA_API_KEY` into `apiKey` by default and sends it as Bearer, so with a workspace key pass `apiKey: null` and the key in `x-api-key` (see `typescript/managed-agents/README.md`). Give the CLI exactly one credential: with both `ORCA_API_KEY` and `ORCA_ACCESS_TOKEN` exported, every call fails.

<!-- orca-warn -->
**No beta headers are needed.** Anthropic's `anthropic-beta` and `anthropic-version` headers are accepted for client compatibility and ignored — they enable nothing and are never required. Two headers Orca does read:
<!-- /orca-warn -->

| Header | What it does |
|---|---|
| `orca-beta: managed-agents-<version>` | Opts responses into Orca-native shapes (e.g. `agent_toolset` instead of the dated alias, `{provider, id}` model echo). Most clients should omit it and take the Claude-compatible shapes. |
| `idempotency-key: <key>` | Accepted on every write for safe retries. |

## Reading Guide

| User wants to...                       | Read these files                                        |
| -------------------------------------- | ------------------------------------------------------- |
| **Get started from scratch / "help me set up an agent"** | `shared/managed-agents-onboarding.md` — guided interview (describe → agent → environment → session), then emit code |
| Understand how the API works           | `shared/managed-agents-core.md`                         |
| See the full endpoint reference        | `shared/managed-agents-api-reference.md`                |
| **Create an agent** (required first step) | `shared/managed-agents-core.md` (Agents section) + `shared/orca-cli.md` or `typescript/managed-agents/README.md` |
| Update/version an agent                | `shared/managed-agents-core.md` (Agents → Versioning) — update, don't re-create |
| Create a session                       | `shared/managed-agents-core.md` + `typescript/managed-agents/README.md` (raw HTTP: `curl/managed-agents.md`) |
| Configure tools and permissions        | `shared/managed-agents-tools.md`                        |
| Set up MCP servers                     | `shared/managed-agents-tools.md` (MCP Servers section)  |
| Stream events / handle tool_use        | `shared/managed-agents-events.md` + `typescript/managed-agents/README.md` |
| Define an outcome / rubric-graded evaluation | `shared/managed-agents-outcomes.md` — `user.define_outcome` event, grader, `span.outcome_evaluation_*` events; verdicts are advisory |
| Coordinate multiple agents / subagents / threads | `shared/managed-agents-multiagent.md` — `multiagent: {type: "coordinator", agents: [...]}` on the agent, session threads, cross-posted tool confirmations |
| Set up environments                    | `shared/managed-agents-environments.md`                 |
| Run the agent loop and its tools on your own infrastructure | `shared/managed-agents-environments.md` (§ Self-hosted environments) — `config: {type: "self_hosted"}` |
| Upload files / attach repos            | `shared/managed-agents-environments.md` (Resources)     |
| Give agents persistent memory across sessions | `shared/managed-agents-memory.md` — memory stores, `memory_store` session resource, preconditions, versions/redact |
| Drive the API from the shell; version-controlled setup | `shared/orca-cli.md` — `ork agent create`, JSON flag payloads, `-o json` + jq |
| Store credentials (MCP auth, API keys for CLIs/SDKs) | `shared/managed-agents-tools.md` (Vaults section) — `mcp_oauth` / `static_bearer` / `environment_variable` |
| Call a non-MCP API / CLI that needs a secret | `shared/managed-agents-tools.md` (Vaults section) — `environment_variable` credential, substituted at egress. If that doesn't fit, `shared/managed-agents-client-patterns.md` Pattern 9 keeps the secret host-side via a custom tool |
| Run an agent on a schedule or on Pulsar/Kafka messages | `shared/managed-agents-triggers.md` — core cron Triggers, plus Pulsar/Kafka sources on hosted deployments (hosted only) |

## Common Pitfalls

- **Agent FIRST, then session — NO EXCEPTIONS** — the session's `agent` field takes a string ID, a pinned `{type: "agent", id, version}`, or `agent_with_overrides` for per-session changes (see `shared/managed-agents-core.md`). `model`, `system`, `tools`, `mcp_servers`, `skills` are **top-level fields on `POST /v1/agents`**, never on `sessions.create()`. If the user hasn't created an agent, that is step zero of every example.
- **Agent ONCE, not every run** — `agents.create()` is a setup step. Store the returned `agent_id` and reuse it; don't call `agents.create()` at the top of your hot path. If the agent's config needs to change, `POST /v1/agents/{id}` — each update creates a new version, and sessions can pin to a specific version for reproducibility.
- **Sessions need an environment** — `environment_id` is required on `sessions.create()`. Create an environment once (like the agent) and reuse it; see `shared/managed-agents-environments.md`.
- **MCP auth goes through vaults** — the agent's `mcp_servers` array declares `{name, type, url}` only (no auth). Credentials live in vaults (`orca.vaults.credentials.create`) and attach to sessions via `vault_ids`. Orca auto-refreshes OAuth tokens using the stored refresh token, and matches credentials to servers by URL. Vaults also hold `environment_variable` credentials for non-MCP services (CLIs, SDKs, direct API calls) — substituted at egress, never visible in the sandbox.
- **Reconcile resources before the first run** — a session with a clear ask but a missing tool, credential, data mount, or context will discover the gap mid-run, then flail and give up. Before creating the session, check that every action in the task maps to a configured tool/MCP server, every MCP server has a vault credential, and every referenced file/host is mounted/reachable. When helping a user set one up, run the reconciliation in `shared/managed-agents-onboarding.md` → §4 Silent viability gate.
- **Stream to get events** — `GET /v1/sessions/{id}/events/stream` is the primary way to receive agent output in real-time.
- **Stream first; cursor is transport metadata** — opening SSE without `from_cursor` follows from the transcript's current head and does **not** replay history. Open it before sending work. `from_cursor=0` requests full history; any other explicit cursor is the SSE frame's numeric `id:` and replay is inclusive, so dedupe the repeated frame. The CLI exposes that cursor as the outer NDJSON `.id`; the default TypeScript `Stream<SessionEvent>` exposes only frame `data`, not the cursor, so use list-and-dedupe catch-up (or raw SSE/CLI) after a dropped SDK stream. See `shared/managed-agents-events.md` → Receiving Events.
- **Don't trust HTTP-library timeouts as wall-clock caps** — per-read timeouts (curl without `--max-time`, fetch with no `AbortSignal`) reset on every received byte, so a trickling connection can block indefinitely. For a hard deadline on raw-HTTP polling, track elapsed time at the loop level and bail explicitly. The SDK's `timeout` and retries cover opening a request, not a stream's lifetime: give a long-lived `sessions.events.stream()` your own idle watchdog (an `AbortSignal`) and reconnect with catch-up. See `shared/managed-agents-events.md` → Receiving Events.
- **Messages queue** — you can send events while the session is `running` or `idle`; they're processed in order. No need to wait for a response before sending the next message.
- **Environment `config.type` is `"cloud"` or `"self_hosted"`** — `cloud` runs the container on the engine's operator-configured sandbox runtime; `self_hosted` runs the agent loop and its tools on a host you register, coordinated by the Registry over a tunnel (no `packages` allowed there). See `shared/managed-agents-environments.md` → Self-hosted environments.
- **Archive is permanent on every resource** — there is no unarchive for an agent, environment, session, vault, credential, or memory store. Archived agents, environments, and memory stores cannot be referenced by new sessions (existing sessions continue). Raw `DELETE /v1/agents/{id}` is an Orca extension that soft-deletes the agent and its versions; the TypeScript SDK and CLI expose archive only. Do not archive or delete a production agent, environment, or memory store as cleanup — **always confirm with the user first**.
