# Orca Agent Engine — Common Client Patterns

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
declare const session: { id: string };
declare const stream: import('@runorca/orca-sdk').Stream<import('@runorca/orca-sdk').SessionEvent>;
declare function handle(event: unknown): void;
declare function resolvePendingAsks(eventIds: string[]): Promise<void>;
declare function onQueued(id: string): void;
declare function onProcessed(id: string, at: string): void;
declare const file: File;
declare const linear: { request(query: unknown, vars: unknown): Promise<unknown> };
-->

Patterns you'll write on the client side when driving an Agent Engine session. For complete programs that run end to end, see the public cookbooks at `https://github.com/orca-ae/orca-cookbooks`.

Code samples are TypeScript — the CLI and raw HTTP follow the same shapes; see `shared/orca-cli.md` and `curl/managed-agents.md`.

---

## 1. Stream consumption and recovery

An empty-cursor stream starts **from now**, not from the beginning. Open it before sending work. Raw SSE and CLI clients can resume with the frame cursor (`id:` on SSE, outer `.id` in CLI NDJSON); explicit replay is inclusive, so dedupe the repeated cursor frame. `from_cursor=0` requests full history.

The default TypeScript SDK yields only each frame's `data` payload and does not expose the SSE cursor. It therefore cannot implement exact cursor resume from `SessionEvent.id`. Keep one stream open for the turn and **fail closed** if it ends before terminal idle — a clean iterator EOF is still a dropped/incomplete turn unless you observed the terminal event:

<!-- ts-check: reset -->
```ts
const live = await orca.sessions.events.stream(session.id)
let terminal = false

for await (const event of live) {
  handle(event)
  if (event.type === 'session.status_idle') {
    const stop = event['stop_reason'] as { type: string; event_ids?: string[] } | undefined
    if (stop?.type === 'requires_action') {
      await resolvePendingAsks(stop.event_ids ?? [])
      continue
    }
    terminal = true
    break
  }
}

if (!terminal) {
  throw new Error('event stream ended before terminal idle; recover before reporting success')
}
```

After an SDK stream drop, open the replacement live stream first, then use `events.list({order: 'asc'})` to catch up and dedupe by persisted `event.id`. Reconstruct the **latest** lifecycle/pending state from the complete ordered catch-up before resolving asks or declaring completion — never execute every historical `session.status_idle` as a current instruction. For strict no-loss cursor recovery, consume raw SSE or CLI output until the TypeScript SDK exposes frame metadata.

---

## 2. `processed_at` — queued vs processed

Every persisted event carries `processed_at` (ISO 8601): `null` while the event is still queued behind earlier ones, populated once the agent has processed it. **The SSE stream is an immutable-frame contract** — each event appears once, as it was at append time, and is never re-sent with an updated `processed_at`. To observe the queued → processed transition, poll `events.list`:

<!-- ts-check: reset -->
```ts
const sent = await orca.sessions.events.send(session.id, {
  events: [{ type: 'user.message', content: [{ type: 'text', text: 'Continue.' }] }],
})
const myId = sent.data?.[0]?.id
if (myId) onQueued(myId)

// Later (or on an interval): read back the current state
for await (const event of orca.sessions.events.list(session.id, { types: 'user.message' })) {
  if (event.id === myId && event.processed_at != null) {
    onProcessed(event.id, event.processed_at)
    break
  }
}
```

Use this to drive pending → acknowledged UI state for anything you send — `events.send()` echoes the created events, so the server-assigned `id` is in its response. In practice most clients don't need per-message acknowledgment: the agent's replies arriving on the stream is the acknowledgment.

---

## 3. Interrupt a running session

Send `user.interrupt` as a normal event. The session keeps running until it reaches a safe boundary, then goes idle.

<!-- ts-check: reset -->
```ts
await orca.sessions.events.send(session.id, {
  events: [{ type: 'user.interrupt' }],
})

// Drain until the session is truly done — see Pattern 5 for the full gate.
for await (const event of stream) {
  if (event.type === 'session.status_idle') {
    const stop = event['stop_reason'] as { type: string } | undefined
    if (stop?.type !== 'requires_action') break
  }
}
```

---

## 4. `tool_confirmation` round-trip

When the agent has `permission_policy: { type: 'always_ask' }`, a call to that tool fires an `agent.tool_use` (or `agent.mcp_tool_use`) event and the session goes idle waiting for a decision — `session.status_idle` with `stop_reason.type: "requires_action"` and the pending event IDs in `stop_reason.event_ids`. **Gate on the idle event's `stop_reason.event_ids`** (the tool-use events themselves don't carry a reliable ask marker), then respond with one `user.tool_confirmation` per pending ID:

<!-- ts-check: reset -->
```ts
for await (const event of stream) {
  if (event.type === 'session.status_idle') {
    const stop = event['stop_reason'] as { type: string; event_ids?: string[] } | undefined
    if (stop?.type !== 'requires_action') break
    for (const toolUseId of stop.event_ids ?? []) {
      // A pending agent.custom_tool_use id takes user.custom_tool_result instead (Pattern 9)
      await orca.sessions.events.send(session.id, {
        events: [{
          type: 'user.tool_confirmation',
          tool_use_id: toolUseId, //         the asking event's own id — not a toolu_ id
          result: 'allow', //                or 'deny'
          // deny_message: '...', //         optional, only with result: 'deny'
        }],
      })
    }
  }
}
```

Key points:
- `tool_use_id` is the asking **event's `id`**, **not** a `toolu_...` ID. Keep a map of seen `agent.tool_use`/`agent.mcp_tool_use` events by `id` if you want to inspect `name`/`input` before deciding.
- `result` is `'allow' | 'deny'`. Use `deny_message` (valid only with `deny`) to tell the model *why* — it gets surfaced back to the agent.
- A `requires_action` idle can list several pending IDs at once — answer each. Custom tools park the session the same way, but their reply is `user.custom_tool_result` (Pattern 9).

---

## 5. Correct idle-break gate

Do not break on `session.status_idle` alone. The session goes idle transiently — e.g. while waiting for a `user.tool_confirmation` or a `user.custom_tool_result`. Break only when idle carries a non-`requires_action` `stop_reason`:

<!-- ts-check: reset -->
```ts
for await (const event of stream) {
  handle(event)
  if (event.type === 'session.status_idle') {
    const stop = event['stop_reason'] as { type: string } | undefined
    if (stop?.type === 'requires_action') continue // waiting on you — handle it
    break // end_turn or retries_exhausted
  }
}
```

`stop_reason.type` values on `session.status_idle`:
- `requires_action` — agent is waiting on a client-side event (tool confirmation, custom tool result); `event_ids` lists the pending events. Handle it, don't break.
- `retries_exhausted` — automatic processing can't continue. Break, then check `sessions.retrieve()` for the error state; the session stays idle and accepts further input.
- `end_turn` — normal completion.

---

## 6. Cleanup after idle

Archive and delete don't check whether a session is still running, so you can clean up as soon as you've seen the final `session.status_idle` — no polling loop. Decide from the event itself rather than from an immediate `sessions.retrieve()`, whose `status` can trail the stream by a moment.

---

## 7. Stream-first, then send

Open the stream **before** (or concurrently with) sending the kickoff event and hold it for the session's lifetime. Empty cursor means from-now, so opening after a fast turn can miss events rather than merely delay your reaction.

<!-- ts-check: reset -->
```ts
const stream = await orca.sessions.events.stream(session.id)
await orca.sessions.events.send(session.id, {
  events: [{ type: 'user.message', content: [{ type: 'text', text: 'Hello' }] }],
})
for await (const event of stream) {
  /* ... */
}
```

---

## 8. File-mount details

The attached resource is its own object: `session.resources[n].id` is a resource ID, with the referenced `file_id` alongside it — use the resource ID for `resources.retrieve/update/delete`, the file ID for the Files API.

<!-- ts-check: reset -->
```ts
const uploaded = await orca.files.upload({ file })
const session = await orca.sessions.create({
  agent: 'agt_01H8...',
  environment_id: 'env_01H8...',
  resources: [{ type: 'file', file_id: uploaded.id, mount_path: '/workspace/data.csv' }],
})
```

`mount_path` must be absolute; omitted, it defaults to `/mnt/session/uploads/<file_id>` — set it explicitly when the agent's prompt refers to the file by path. Files the agent should hand back come out through the session-outputs endpoints instead (`shared/managed-agents-environments.md` → Session outputs).

---

## 9. Secrets for non-MCP APIs and CLIs — keep them host-side via custom tools

**Problem:** you want the agent to call a third-party API or run a CLI that needs a secret (API key, token, service-account credential), but you can't or don't want to hand the secret to a vault.

**First check:** for cloud environments, the first-class answer is a vault `environment_variable` credential — the agent's shell sees an opaque placeholder and the real secret is substituted at egress. See `shared/managed-agents-tools.md` → Vaults. Use this pattern instead when that doesn't fit: clients that reject the placeholder via local format validation, secrets that must never leave your infrastructure, or calls that need host-side binaries.

**Solution:** move the authenticated call to your side. Declare a custom tool on the agent; when the agent emits `agent.custom_tool_use`, your orchestrator (the process reading the SSE stream) executes the call with its own credentials and responds with `user.custom_tool_result`. The container never sees the key.

<!-- ts-check: reset -->
```ts
// Orchestrator: handle the call with host-side creds
// (agent declares: tools: [{ type: 'custom', name: 'linear_graphql', description: ..., input_schema: ... }])
for await (const event of stream) {
  if (event.type === 'agent.custom_tool_use' && event['name'] === 'linear_graphql') {
    const input = event['input'] as { query: unknown; vars: unknown }
    const result = await linear.request(input.query, input.vars) // host's key
    await orca.sessions.events.send(session.id, {
      events: [{
        type: 'user.custom_tool_result',
        custom_tool_use_id: event.id,
        content: [{ type: 'text', text: JSON.stringify(result) }],
      }],
    })
  }
}
```

Same shape works for `gh` CLI, local eval scripts, or anything else that needs host-side auth or binaries.

**Security note:** this does not expose a public endpoint. `agent.custom_tool_use` arrives on the SSE stream your orchestrator already holds open with your workspace credential, and `user.custom_tool_result` goes back via `events.send()` under the same credential. Your orchestrator is a client, not a server — nothing unauthenticated is listening.

**Do not embed API keys in the system prompt or user messages as a workaround.** Prompts and messages are stored in the session's event history, returned by `events.list()`, and included in compaction summaries — a secret placed there is durably persisted and readable via the API for the life of the session.
