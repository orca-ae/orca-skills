---
name: orca-api
description: |-
  Reference for Orca Agent Engine — the managed-agents registry API (Anthropic Managed Agents-compatible), the ork CLI, and the @runorca/orca-sdk TypeScript SDK: agents, sessions, environments, events and streaming, tools, MCP, vaults, skills, files, memory stores, triggers.
  TRIGGER — read BEFORE opening the target file — whenever: the prompt names Orca or Agent Engine in any form (Orca, orca-ae, Agent Engine, `@runorca/orca-sdk`, the `ork` CLI, `ORCA_*` env vars, runorca.ai); the task builds on or debugs an Agent Engine deployment (agents/sessions/environments against an Orca registry endpoint); OR the project imports `@runorca/orca-sdk` or scripts `ork agent` commands (`grep -rE '@runorca/orca-sdk|(^|[^[:alnum:]_-])ork agent |ORCA_(REGISTRY_URL|BASE_URL|ACCESS_TOKEN|API_KEY)'` hits).
  SKIP when the work targets Anthropic's own platform (api.anthropic.com, `@anthropic-ai/sdk`, `ANTHROPIC_API_KEY`, the `ant` CLI) with no Orca deployment in sight — that is the claude-api skill's domain.
license: Complete terms in LICENSE.txt
---

# Building on Orca Agent Engine

This skill teaches the Orca Agent Engine managed-agents surface: an open-source engine that runs agents server-side — on an engine you run yourself or on a hosted deployment — and whose registry API is compatible with Anthropic's Managed Agents API. You create a persisted **Agent** config (`POST /v1/agents`), then start **Sessions** that reference it; each session provisions a container where the agent's tools execute, and streams events you read and answer.

## Before You Start

<!-- orca-warn -->
Scan the target file (or, if no target file, the prompt and project) for signs the user is actually targeting Anthropic's own platform — `api.anthropic.com`, `@anthropic-ai/sdk`, `ANTHROPIC_API_KEY`, `ant beta:` commands — with no Orca deployment involved. If that's the case, stop and say this skill produces Agent Engine code; the claude-api skill covers Anthropic's platform. A Claude-compatible integration being *pointed at* an Orca deployment is squarely in scope — that's the platform's design.
<!-- /orca-warn -->

## Output Requirement

When the user asks you to add, modify, or implement something against Agent Engine, your code must go through one of:

1. **The TypeScript SDK** (`@runorca/orca-sdk`) — the default for application code, and the only SDK this skill documents. Orca also publishes a Python SDK (`runorca` on PyPI) and a Go SDK (`github.com/orca-ae/orca-sdk-go`); this skill doesn't cover them, so take their bindings from their own READMEs and the shapes from this skill's API reference.
2. **The `ork` CLI** — the default for setup scripts, CI, and terminal inspection.
3. **Raw HTTP** (`curl`, `fetch`, ...) — when the user asks for it, or for languages without an SDK.

**Never guess bindings.** Method names, flags, field names, and event shapes must come from this skill's files or the ground-truth sources in `shared/live-sources.md`. Do not extrapolate from Anthropic SDK shapes — the surface is compatible, not identical, and this skill documents exactly where they differ.

## Client Selection

| Situation | Surface | Read |
|---|---|---|
| TypeScript/JavaScript application code | `@runorca/orca-sdk` | `typescript/managed-agents/README.md` |
| Setup scripts, CI, ad-hoc terminal work | `ork` CLI | `shared/orca-cli.md` |
| Python or Go application code | the Python (`runorca`) or Go (`github.com/orca-ae/orca-sdk-go`) SDK — not covered here; use its README for bindings | `shared/managed-agents-api-reference.md` for shapes |
| Any other language; debugging on the wire | raw HTTP | `curl/managed-agents.md` + `shared/managed-agents-api-reference.md` |

**Endpoint + one credential, spelled differently per client** (both URLs are the deployment **host root** — no `/v1` suffix). A workspace API key (`orca_…`) is only ever accepted in `x-api-key`; `Authorization: Bearer` carries an OIDC access token, never a workspace key:

| Client | Endpoint | Workspace API key | OIDC access token |
|---|---|---|---|
| `ork` CLI | `ORCA_REGISTRY_URL` | `ORCA_API_KEY` → `x-api-key` | `ORCA_ACCESS_TOKEN` → `Authorization: Bearer` (set one, never both) |
| TS SDK | `ORCA_BASE_URL` | `apiKey: null` + `defaultHeaders: { 'x-api-key': … }` | `apiKey` → `Authorization: Bearer` |
| Raw HTTP | — | `x-api-key: …` | `Authorization: Bearer …` |

<!-- orca-warn -->
No `anthropic-version` or `anthropic-beta` header is ever required — they're accepted for compatibility and ignored. `orca-beta` opts into Orca-native response shapes; omit it unless you know you want that.
<!-- /orca-warn -->

---

## The Mandatory Flow

**Agent (once) → Session (every run).** `model`/`system`/`tools`/`mcp_servers`/`skills` live on the agent object, never the session; the session takes an agent pointer plus a required `environment_id`. Create agents and environments from a version-controlled setup script (CLI), store the IDs, and have runtime code only create sessions. Full rules and pitfalls: `shared/managed-agents-overview.md` — **read it first for any managed-agents task**; its reading guide adds per-topic depth beyond the map below.

| Topic | File |
|---|---|
| Overview, auth, pitfalls, reading guide | `shared/managed-agents-overview.md` |
| Core concepts: agents, sessions, versioning, overrides | `shared/managed-agents-core.md` |
| Environments, files, GitHub repos, session outputs | `shared/managed-agents-environments.md` |
| Tools, permissions, MCP servers, vaults, skills | `shared/managed-agents-tools.md` |
| Events, streaming, live previews, steering | `shared/managed-agents-events.md` |
| Outcomes (advisory grading) | `shared/managed-agents-outcomes.md` |
| Multiagent sessions and threads | `shared/managed-agents-multiagent.md` |
| Memory stores | `shared/managed-agents-memory.md` |
| Agent Triggers (core cron; Pulsar/Kafka sources on hosted deployments) | `shared/managed-agents-triggers.md` |
| Client-side patterns (reconnect, confirmations, gates) | `shared/managed-agents-client-patterns.md` |
| Guided setup interview | `shared/managed-agents-onboarding.md` |
| Endpoint/SDK/CLI reference, errors, pagination | `shared/managed-agents-api-reference.md` |
| Ground-truth repositories | `shared/live-sources.md` |

## Subcommands

If the User Request at the bottom of this prompt is a bare subcommand string (no prose), match it here and follow the Action column directly. This lets users invoke specific flows via `/orca-api <subcommand>`. If nothing matches, treat the request as normal prose.

| Subcommand | Action |
|---|---|
| `managed-agents-onboard` | Walk the user through setting up an agent from scratch. **Read `shared/managed-agents-onboarding.md` immediately** and follow its interview script: describe → configure the agent (propose, don't interrogate) → environment → session — defaults and inline suggestions do the work, with a silent viability gate before any code is emitted. Do not summarize — run the interview. |

**When the user wants to set up an agent from scratch** (e.g. "how do I get started", "walk me through creating one", "set up a new agent"): same flow — read `shared/managed-agents-onboarding.md` and run its interview.

---

## ⚠️ Where Orca Differs from Anthropic's Managed Agents

Your training prior (and Anthropic's docs) will suggest features and shapes this platform does not have. The load-bearing deltas — each detailed in the file cited:

<!-- orca-warn -->
| You might expect | Agent Engine reality | See |
|---|---|---|
| `web_fetch` / `web_search` built-in tools | Accepted names, never run — web reach comes via MCP servers. Orca adds `list`/`delete` built-ins instead. | `shared/managed-agents-tools.md` |
| Session `budget` / `budget_reached` | No `budget` field — the strict session contract rejects it. Spend and token caps are Guardrails (`cost_budget`, `token_budget`) from the policy extension, attached with `guardrail_ids`. | `shared/managed-agents-core.md` |
| `/v1/deployments` cron scheduling | Absent — core `/v1/triggers` covers cron; hosted deployments widen it with Pulsar/Kafka. | `shared/managed-agents-triggers.md` |
| Webhooks | Absent — stream or poll events. | `shared/managed-agents-events.md` |
| Outcome loop that "iterates until met" | Grading is advisory: verdicts stream, nothing re-drives the agent. | `shared/managed-agents-outcomes.md` |
| `{type: "advisor"}` roster entries | No advisor type — roster is string / agent-ref / `self`. | `shared/managed-agents-multiagent.md` |
| "SSE always replays" | Empty cursor follows from now. Use `from_cursor=0` for full history; explicit cursors are SSE frame offsets and inclusive. | `shared/managed-agents-events.md` |
| `{type: "anthropic"}` pre-built skills (`xlsx`, `docx`, ...) | Not shipped on stock deployments — upload custom skills. | `shared/managed-agents-tools.md` |
| `checkout: {type: "branch", ...}` honored at clone | Accepted but currently not applied — have the agent `git checkout` via bash. | `shared/managed-agents-environments.md` |
| `inference_geo`, model/pricing tables, Console URLs | No `inference_geo` and no Console URLs. Models come from the deployment's catalog (`claude-sonnet-4-6` is a safe default); the runtime extension lists harnesses with their models, and the pricing extension serves per-model prices. | `shared/managed-agents-core.md` |
| `/v1/registry/...` paths | Deprecated cloud dialect — every path is `/v1/...` at the host root. | `shared/managed-agents-overview.md` |
| `/v1/messages` on the same host | Agent Engine is a control plane only — there is no inference API on this surface. | `shared/managed-agents-api-reference.md` |
<!-- /orca-warn -->

## Common Pitfalls

- **Agent Skills ≠ managed-agents skills-on-agents.** "Skills" in this skill means the `/v1/skills` resource attached to agent configs. A `.claude/skills` directory in a repo is a Claude Code concept — Agent Engine does not scan mounted repos for skills.
- **`agents.create()` in the hot path** is the #1 anti-pattern — create once, store the ID, version via update. See `shared/managed-agents-overview.md` → THE MANDATORY FLOW.
- **Breaking on the first `session.status_idle`** loses tool asks — gate on `stop_reason.type !== 'requires_action'` (`shared/managed-agents-client-patterns.md` Pattern 5).
- **Declaring an MCP server without an `mcp_toolset` referencing it** is a 400; and MCP servers need vault credentials matched by URL, attached via `vault_ids` at session create only.
- **Secrets never go in prompts or messages** — they persist in the event history. Vault `environment_variable` credentials or host-side custom tools (`shared/managed-agents-client-patterns.md` Pattern 9).
