# Live Ground-Truth Sources

When this skill doesn't cover a binding, field, or behavior — or a claim here seems stale — read the source of truth instead of guessing. Orca Agent Engine's authorities are its public repository and its published tools, all readable without credentials:

- **The engine** — `https://github.com/orca-ae/orca-agent-engine`: the docs, the registry contracts, and the harness source.
- **The CLI** — `ork`: `ork <command> --help` prints every command and flag.
- **The TypeScript SDK** — `@runorca/orca-sdk` on npm: its type definitions ship inside the package.

## Authority order

Check in this order. Later entries override earlier ones about *behavior*; earlier entries win about *what the API accepts*.

| # | Source | What it answers |
|---|---|---|
| 1 | `orca-agent-engine/docs/managed-agents/conformance-matrix.md` | Which operations exist, per-operation deviations from Anthropic's Managed Agents spec (generated, CI-gated) |
| 2 | `orca-agent-engine/docs/managed-agents/orca-extensions.md` + `orca-agent-engine/docs/managed-agents/api-groups-and-extensions.md` | The Claude-compatible vs Orca-only line; headers; URL model |
| 3 | `orca-agent-engine/services/registry-service-ts/src/contracts/` | Exactly what the API accepts (zod schemas; enums and literals are closed sets) |
| 4 | `orca-agent-engine/services/registry-service-ts/src/api/` | Cross-field validation; the source of most 400 messages |
| 5 | `orca-agent-engine/services/harness-server/src/` | What actually runs — where accepted can diverge from effective (`harness/event-kinds.ts` is the event vocabulary) |
| 6 | `ork <command> --help` (start at `ork agent --help`) | Every agent-related CLI command and flag |
| 7 | `@runorca/orca-sdk/index.d.ts` + `@runorca/orca-sdk/resources/` | Which resources/methods the SDK exposes, exact TS signatures |

Paths that start with `orca-agent-engine/` are relative to a clone of `https://github.com/orca-ae/orca-agent-engine`; without a clone, open the same path on GitHub under `blob/main/`. Paths that start with `@runorca/orca-sdk/` are inside the installed package, `node_modules/@runorca/orca-sdk/`.

## Useful deep links per topic

| Topic | Read |
|---|---|
| Event kinds & payloads | `orca-agent-engine/services/harness-server/src/harness/event-kinds.ts` |
| Session/event input shapes | `orca-agent-engine/services/registry-service-ts/src/contracts/sessions.contract.ts` |
| Agent/tool/MCP/skill shapes | `orca-agent-engine/services/registry-service-ts/src/contracts/agents.contract.ts` |
| Vault credential shapes | `orca-agent-engine/services/registry-service-ts/src/contracts/vaults.contract.ts` |
| Model id/effort/speed rules | `orca-agent-engine/services/registry-service-ts/src/contracts/model-wire.ts` + `orca-agent-engine/packages/harness-catalog/src/model-controls.ts` |
| Pagination envelopes & filters | `orca-agent-engine/docs/managed-agents/pagination-and-filters.md` |
| Skills behavior | `orca-agent-engine/docs/managed-agents/skills.md` |
| SSE cursor semantics | `orca-agent-engine/packages/transcript-store-types/src/store.ts` + `orca-agent-engine/services/registry-service-ts/src/streaming/sse.ts` |
| SDK event union & streaming | `@runorca/orca-sdk/resources/sessions/events.d.ts` + `@runorca/orca-sdk/core/streaming.d.ts` |
| Trigger shapes | `orca-agent-engine/services/registry-service-ts/src/contracts/triggers.contract.ts` + `@runorca/orca-sdk/resources/triggers/triggers.d.ts` |
| Guardrails: spend and token caps, policies | `orca-agent-engine/docs/managed-agents/guardrails.md` |
| Harnesses, their models and modes | `orca-agent-engine/docs/managed-agents/harness-modes.md` |
| CLI usage | `ork agent --help`, then `ork agent <group> --help` |
| Runnable end-to-end examples | `https://github.com/orca-ae/orca-cookbooks` |
| Engine, CLI, and SDK versions that work together | `orca-agent-engine/docs/compatibility.md` |

**Never treat the SDK's open-ended types (`[key: string]: unknown`) as proof a field exists** — they accept anything. The registry contracts (row 3) are the acceptance authority; the harness (row 5) is the behavior authority.

**Trust this skill's stream-cursor rules over the SDK's doc comments.** The JSDoc example for `events.stream` passes an event ID (`evt_...`) as `from_cursor`; the cursor is the SSE frame's numeric `id`, and `0` replays full history (`shared/managed-agents-events.md`).
