# Orca Agent Engine — Events & Steering

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
declare const session: { id: string };
declare const sessionId: string;
declare function streamEvents(sessionId: string): Promise<void>;
declare function sendMessage(sessionId: string, text: string): Promise<void>;
declare function resolvePendingAsks(eventIds: string[]): Promise<void>;
declare const text: string;
-->

## Events

### Sending Events

Send events to a session via `POST /v1/sessions/{id}/events`.

| Event Type                | When to Send                                        |
| ------------------------- | --------------------------------------------------- |
| `user.message`            | Send a user message |
| `user.interrupt`          | Interrupt the agent while it's running |
| `user.tool_confirmation`  | Approve/deny a tool call (when `always_ask` policy) — `{tool_use_id, result: "allow"\|"deny", deny_message?}` |
| `user.tool_result`        | Provide a result for a built-in tool call routed to you — `{tool_use_id, content?, is_error?}`. Accepted only on **self-hosted environments**; 400 elsewhere. |
| `user.custom_tool_result` | Provide result for a custom tool call — `{custom_tool_use_id, content?, is_error?}` |
| `user.define_outcome`     | Define an advisory outcome + rubric — see `shared/managed-agents-outcomes.md` |
| `system.message`          | Append privileged system-level context for this turn and every turn after it; see § Adding system context mid-session |

#### Adding system context mid-session (`system.message`)

The `system` field on the agent definition sets the top-level system prompt and is fixed for the session's lifetime. A `system.message` event **appends** to the session's system context — it does not replace that prompt. The content applies to the accompanying turn and all subsequent turns. Use it for a different persona, revised constraints, or runtime-fetched context that should shape behavior going forward:

<!-- ts-check: reset -->
```ts
await orca.sessions.events.send(session.id, {
  events: [
    {
      type: 'system.message',
      content: [{ type: 'text', text: "The user's current timezone is America/New_York." }],
    },
  ],
});
```

`content` is a non-empty array of text blocks. Because it lands in the privileged system channel rather than the user channel, prefer it for operator instructions the agent should not treat as user input.

### Receiving Events

Two methods:

1. **Streaming (SSE)**: `GET /v1/sessions/{id}/events/stream` — Server-Sent Events. **Long-lived** — the server sends periodic `:heartbeat` comments to keep the connection alive. An empty cursor starts at the transcript's **current head** and delivers only events appended after the stream opens. Pass `from_cursor=0` for a full replay. Any other explicit cursor is the numeric SSE frame cursor and replay starts **at that cursor (inclusive)**.
2. **Polling**: `GET /v1/sessions/{id}/events` — paginated event list (query params: `limit`, `page`, `order`, `types`, `created_at[gt|gte|lt|lte]`, `subpath`). **Returns immediately** — this is a plain paginated GET, not a long-poll.

All **persisted** events carry `id`, `type`, and `processed_at` (ISO 8601, `null` while the event is still queued behind earlier ones). The stream-only `event_start` / `event_delta` preview frames (see § Live previews) carry only the `id` of the event they preview.

An SSE frame has two different identifiers:

```text
id: 42
event: agent.message
data: {"id":"evt_...","type":"agent.message","content":[...]}
```

- Frame `id: 42` is the **resume cursor**. Treat it as opaque numeric transport metadata, persist it separately, and dedupe the first frame after reconnect because explicit replay is inclusive.
- `data.id: "evt_..."` is the **event identity** used for event deduplication, tool confirmations, and custom-tool results. Never pass it as `from_cursor`.

The core Registry accepts the standard `Last-Event-ID` header, but `from_cursor` is the portable spelling across current deployments. The `ork` CLI exposes frame metadata in its NDJSON wrapper. The default TypeScript SDK currently yields only `data` and discards frame `id`, so it cannot implement exact cursor resume from `SessionEvent.id`; use raw SSE/CLI when exact no-loss resume is required, or combine a fresh stream with `events.list()` catch-up and `event.id` deduplication.

> ⚠️ **Robust polling (raw HTTP).** If you bypass the SDK and roll your own poll loop, don't rely on per-read timeouts as wall-clock caps — they reset every time a byte arrives, so a trickling response (heartbeats, a wedged proxy) can keep the call blocked indefinitely. For a hard deadline: `curl --max-time`, an `AbortSignal.timeout(...)` on `fetch`, or an elapsed-time check at the loop level. The SDK is no exception: its `timeout` and retries cover opening a request, not a stream's lifetime, and its stream skips heartbeats and never reconnects. Give a long-lived `orca.sessions.events.stream()` your own idle watchdog — abort it through an `AbortSignal` — and reconnect with list catch-up (`shared/managed-agents-client-patterns.md`).

### Event Types (Received)

Event types use dot notation, grouped by namespace:

| Event Type | Description |
| --- | --- |
| `agent.message` | Agent text output (`content` block array) |
| `agent.thinking` | Progress signal that the agent is thinking — it does **not** carry the thinking content |
| `agent.tool_use` | Agent used a built-in tool (the agent toolset) |
| `agent.tool_result` | Result from a built-in tool |
| `agent.mcp_tool_use` | Agent used an MCP tool |
| `agent.mcp_tool_result` | Result from an MCP tool |
| `agent.custom_tool_use` | Agent invoked a custom tool — session goes idle, you respond with `user.custom_tool_result` |
| `agent.thread_context_compacted` | Conversation context was compacted |
| `agent.thread_message_sent` / `_received` | Cross-thread message, carries `to_session_thread_id` / `from_session_thread_id` (multiagent — see `shared/managed-agents-multiagent.md`) |
| `session.status_running` | Session has started running, and the agent is actively doing work. |
| `session.status_idle` | Agent finished the current task and awaits input — either a `user.message` to continue, or a pending `user.custom_tool_result` / `user.tool_confirmation`. Carries `stop_reason` (see § Event payloads). |
| `session.status_rescheduled` | Session is (re)scheduling after a retryable error, ready to be picked up again. |
| `session.status_terminated` | Reserved for protocol completeness — the harness does not currently emit it: failures leave the session idle (`stop_reason.type: "retries_exhausted"`), and genuine termination happens through archive/delete. |
| `session.updated` | A session update changed at least one field — carries only the changed fields |
| `session.deleted` | The session was deleted — terminates every stream on it |
| `session.error` | Error during processing — `{error: {type, message}, retry_status: {will_retry, next_attempt?}}` |
| `session.thread_created` | Subagent thread spawned (multiagent) — see `shared/managed-agents-multiagent.md` |
| `session.thread_status_running` / `_idle` / `_rescheduled` / `_terminated` | Thread status transitions (multiagent); `_idle` carries `stop_reason` |
| `span.model_request_start` | Model inference started |
| `span.model_request_end` | Model inference completed — carries `model_usage` token counts |
| `span.outcome_evaluation_start` / `_ongoing` / `_end` | Grader progress for sessions with a defined outcome — see `shared/managed-agents-outcomes.md` |

The stream also echoes back user-sent events (`user.message`, `user.interrupt`, `user.tool_confirmation`, `user.tool_result`, `user.custom_tool_result`, `user.define_outcome`) and `system.message`.

Stream-only delta preview frames (`event_start`, `event_delta`) are the one exception to the `{domain}.{action}` naming convention — see § Live previews below; they never appear in `GET /v1/sessions/{id}/events`.

---

## Live previews

By default, assistant text reaches the stream as buffered `agent.message` events — emitted only after the model request that produced them finishes. **Live previews** let you render that text incrementally while the model is still generating. The buffered `agent.message` is always the authoritative record; a client that ignores previews still receives a complete, correct stream. The wire format is **not** Messages-API streaming: the delta type is `content_delta`, not `content_block_delta`, so Messages-API accumulator code does not carry over unchanged.

**Opt in per stream connection** by adding the `event_deltas` query parameter (bracket form `event_deltas[]` also accepted), repeated once per event type to preview. Accepted values: `agent.message`, `agent.thinking` — any other value returns a 400. **Both stream endpoints accept it:** the session-level stream (`GET /v1/sessions/{id}/events/stream`) and each thread's own stream (`GET /v1/sessions/{sid}/threads/{tid}/stream`). In a shell, quote the URL — bare `[]` is a glob pattern.

<!-- ts-check: reset -->
```ts
const stream = await orca.sessions.events.stream(session.id, {
  event_deltas: ['agent.message'],
});
```

When a previewed event begins, the stream emits an `event_start` carrying the upcoming event's `type` and `id`; for `agent.message` it's followed by `event_delta` frames carrying incremental text:

```json
{"type": "event_start", "event": {"type": "agent.message", "id": "evt_01H8..."}}
{"type": "event_delta", "event_id": "evt_01H8...", "delta": {"type": "content_delta", "index": 0, "content": {"type": "text", "text": "Here is the summary"}}}
```

`event_start` and `event_delta` have no `id` or `processed_at` of their own — the only identifier they carry is the `id` of the event they preview. For `agent.thinking`, **only** the `event_start` is emitted (a "thinking has started" signal) — no deltas follow, and the buffered `agent.thinking` that concludes the preview carries no thinking content either.

**Accumulate-and-reconcile pattern.** Treat the preview as a scratch buffer keyed by `(event_id, index)`. On `event_start`, create an empty entry for the announced `id`. On each `event_delta`, append the delta text and render the running text. When the buffered `agent.message` arrives, match it by `id`, **discard the accumulated preview**, and render the message's content instead. A model request that ends early (error or interrupt) produces no final event — its terminal `span.model_request_end` closes the preview; drop any unreconciled buffer when you see it.

**Limitations:**
- **Best effort** — under load the server may shed deltas for an event; you receive a contiguous prefix and then no further deltas. The buffered `agent.message` still arrives complete. Never treat an accumulated preview as final.
- **Deltas are connection-scoped** — only connections that opted in receive them, and only for model requests that start while the connection is open. Persisted buffered events can be replayed with an explicit cursor (`0` for full history); missed *deltas* cannot be re-requested.
- **One thread, text only** — a connection previews only the thread it is reading; a child thread's previews are delivered on that child's stream only. Tool use and tool results are never previewed.
- **Never persisted** — `event_start` / `event_delta` exist only on the live SSE stream, never in `GET /v1/sessions/{id}/events`.

**Troubleshooting:**

| You see | What it means |
| --- | --- |
| Buffered events but no `event_start` / `event_delta` | This connection didn't opt in (`event_deltas` is per connection, not per session), or the turn ran on a different thread. List `GET /v1/sessions/{sid}/threads` to find which one ran. |
| 404 on the stream URL | Wrong path or ID. The thread path is `/threads/{tid}/stream`, **not** `/threads/{tid}/events/stream` (which doesn't exist; the non-stream event list *is* `/threads/{tid}/events`). |
| 400 naming `event_deltas` | Only `agent.message` and `agent.thinking` are accepted. |

---

## Steering Patterns

Practical patterns for driving a session via the events surface.

### Stream-first ordering

**Open the stream before sending and hold it.** Empty-cursor streams start from the current head, so send-then-stream can miss a fast turn. Establish the stream first (or concurrently with the send) to receive every new event in real time.

<!-- ts-check: reset -->
```ts
// One long-lived stream per session, opened alongside the first send
const [response] = await Promise.all([
  streamEvents(sessionId), // opens SSE connection
  sendMessage(sessionId, text),
]);
```

To attach to an existing session and replay its complete persisted transcript, open with `{from_cursor: '0'}`. Do not substitute an `evt_...` event ID.

### Reconnecting after a dropped stream

Raw SSE and CLI clients must persist the frame cursor (`id:` on SSE, outer `.id` in CLI NDJSON), reconnect with that value, and discard the repeated cursor frame before processing newer ones. `from_cursor=0` is the fallback when no cursor was persisted; dedupe replayed events by `data.id`.

The default TypeScript `Stream<SessionEvent>` does not expose frame cursors. **Never use the yielded event's `id` as `from_cursor`** — that is a payload UUID, not a transcript offset. For SDK-only recovery:

1. Open a new empty-cursor stream first so events produced after reconnection are captured.
2. List persisted events and dedupe them by `event.id` against IDs already processed by this consumer.
3. Continue the live stream. If exact cursor-based recovery is a hard requirement, use raw SSE/CLI until the SDK exposes frame metadata.

If an `agent.tool_use` / `agent.custom_tool_use` was pending when the connection dropped, inspect the latest `session.status_idle.stop_reason.event_ids` during catch-up and resolve only still-pending asks — the session stays parked until you do.

### Message queuing

**You don't have to wait for a response before sending the next message.** User events are queued server-side and processed in order. This is useful for chat bridges where the user sends rapid follow-ups:

<!-- ts-check: reset -->
```ts
// All three go into one session; agent processes them in order
await sendMessage(sessionId, 'Summarize the README');
await sendMessage(sessionId, 'Actually also check the CONTRIBUTING guide');
await sendMessage(sessionId, 'And compare the two');
// Stream once — agent responds to all three as a coherent turn
```

Events can be sent to the session at any time while it is `running` or `idle` — there is no need to wait on a specific session status to enqueue new events via `orca.sessions.events.send()`.

### Interrupt

A `user.interrupt` event asks the session to stop and go `idle`. Use this for "stop" / "nevermind" / "cancel" commands. Delivery is serialized like every other event — there is **no mid-turn preemption**: the in-flight model request completes and the turn winds down at a safe boundary before the interrupt takes effect, so expect a short tail of events after you send it.

<!-- ts-check: reset -->
```ts
await orca.sessions.events.send(sessionId, {
  events: [{ type: 'user.interrupt' }],
});
```

The agent does not see the interrupt as a message — the turn just ends. Send a follow-up `user.message` to explain what to do instead. If an outcome is active, the interrupt marks `span.outcome_evaluation_end.result: "interrupted"` (see `shared/managed-agents-outcomes.md`).

**In a multiagent session, `session_thread_id` targets one thread**; omitted, the interrupt applies session-wide. See `shared/managed-agents-multiagent.md`.

### Event payloads

Some events carry useful metadata beyond the status change itself:

`session.status_idle` — includes a `stop_reason` field which elaborates on why the session stopped and what further action is required. `type` is one of `end_turn` (finished normally), `requires_action` (blocked on a client reply; `event_ids` lists the pending events), or `retries_exhausted` (automatic processing can't continue; the session stays idle for further input):

```json
{
  "id": "evt_01H8...",
  "processed_at": "2026-04-07T04:27:43.197Z",
  "type": "session.status_idle",
  "stop_reason": {
    "type": "requires_action",
    "event_ids": ["evt_01H7..."]
  }
}
```

`span.model_request_end` contains a `model_usage` field for cost tracking and efficiency analysis (plus `is_error` and a `model_request_start_id` correlating the paired start event):

```json
{
  "type": "span.model_request_end",
  "id": "evt_01H8...",
  "is_error": false,
  "model_request_start_id": "evt_01H7...",
  "model_usage": {
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 6656,
    "input_tokens": 3571,
    "output_tokens": 727
  },
  "processed_at": "2026-04-07T04:11:32.189Z"
}
```

`session.error` — a typed error plus whether the harness will retry:

```json
{
  "type": "session.error",
  "id": "evt_01H8...",
  "error": { "type": "processing_error", "message": "..." },
  "retry_status": { "will_retry": true, "next_attempt": 2 }
}
```

### Archive

When done with a session, archive it to free resources:

<!-- ts-check: reset -->
```ts
await orca.sessions.archive(sessionId);
```

> Archiving a **session** is routine cleanup — sessions are per-run and disposable. **Do not generalize this to agents or environments**: those are persistent, reusable resources, and archiving them is permanent (no unarchive; new sessions cannot reference them). See `shared/managed-agents-overview.md` → Common Pitfalls.
