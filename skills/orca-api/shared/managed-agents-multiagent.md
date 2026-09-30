# Orca Agent Engine — Multiagent Sessions

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
declare const env: { id: string };
declare const session: { id: string };
declare const reviewer: { id: string };
declare const testWriter: { id: string };
-->

A coordinator agent can delegate to other agents within one session. All agents **share the container and filesystem**; each runs in its own **thread** — a context-isolated event stream with its own conversation history, model, system prompt, tools, MCP servers, and skills (from that agent's own config). Delegation happens through the harness's built-in subagent mechanism — the coordinator sees each roster member's name and description and decides when to hand work off; there is no orchestration code to write, and your client still creates one session and reads one stream.

---

## When to use it — start with `self`, then add cheaper workers

**If the agent's work splits into independent pieces** — several sources to analyze, many files or records to process, anything shaped like "look into N things, then summarize" — or one piece would fill its context with reading, **use a multiagent session instead of one long single-threaded loop.** Each delegated piece runs in its own thread with a fresh context window, threads run in the same container, and only each subagent's report comes back, so the coordinator's context stays small.

**Step 1 — the smallest useful roster is the agent itself.** Add a `multiagent` block whose only entry is `{"type": "self"}`. The coordinator can then hand self-contained sub-tasks to copies of itself — same model, system prompt, and tools, minus the ability to delegate further — and combine what they report. Nothing else changes.

<!-- ts-check: reset -->
```ts
const agent = await orca.agents.create({
  name: 'Research assistant',
  description: 'Researches a question end to end. A copy can be spawned to own one well-scoped sub-question.',
  model: 'claude-sonnet-4-6',
  system:
    'You are a research assistant. When a request splits into independent sub-questions, delegate each to a copy of yourself, one self-contained task per copy, then verify and combine their reports.',
  tools: [{ type: 'agent_toolset' }],
  multiagent: { type: 'coordinator', agents: [{ type: 'self' }] }, // the only change vs. a single agent
});

const session = await orca.sessions.create({ agent: agent.id, environment_id: env.id }); // unchanged
```

**Step 2 — move the reading-heavy work to a cheaper model.** Delegated analysis work is mostly searching, reading, and extracting: many input tokens, little hard reasoning. Create a second agent on a smaller model with a narrow `system` prompt and only the tools it needs, and list it next to `self`. A roster entry is only a reference: the worker runs on its own `model`, `system`, and `tools`. The large model spends its tokens on planning, checking, and synthesis; the small model does the bulk reading.

<!-- ts-check: reset -->
```ts
const worker = await orca.agents.create({
  name: 'Repo researcher',
  description:
    'Fast, low-cost, read-only researcher. Give it one well-scoped question about the mounted files; it reads and reports findings with file paths.',
  model: 'claude-haiku-4-5',
  system:
    'Answer exactly the question you are given. Read as much as you need, then report concise findings with a file path for every claim.',
  tools: [
    {
      type: 'agent_toolset',
      default_config: { enabled: false },
      configs: [
        { name: 'read', enabled: true },
        { name: 'glob', enabled: true },
        { name: 'grep', enabled: true },
      ],
    },
  ],
});

const lead = await orca.agents.create({
  name: 'Research lead',
  description: 'Plans and synthesizes research. A copy can be spawned to own one large sub-analysis.',
  model: 'claude-sonnet-4-6',
  system:
    'Plan the work. Delegate each independent, reading-heavy question to Repo researcher, one self-contained task per spawn, several in parallel. Keep verification and the final synthesis for yourself; spawn a copy of yourself only for a sub-analysis that needs your full capability.',
  tools: [{ type: 'agent_toolset' }],
  multiagent: { type: 'coordinator', agents: [worker.id, { type: 'self' }] },
});
```

**Step 3 — add dedicated specialists.** When the sub-tasks call for different skills, give each its own agent — its own model, a narrow `system` prompt, and only the tools it needs — and roster them by ID next to `self`. A lead can make a change itself, send the same review brief to several read-only reviewer threads for independent passes (one rostered agent can be spawned many times), and hand a test writer a self-contained brief; it then de-duplicates the findings, checks each against the code, and keeps the fix and the summary for itself.

- **Good fits:** parallel analysis across sources; reading large amounts of material without filling the coordinator's context; specialists with narrow prompts and tool sets rather than one agent carrying every tool. **Poor fit:** a small single-step task — every delegation costs a round-trip and a re-briefing.
- **Write `name` and `description` for the coordinator to read.** The coordinator chooses whom to spawn from each roster entry's name and description (the `self` entry is listed under the coordinator's own name), so say what each agent is good at and what to hand it. Names must be unique across the roster.
- **Say how to delegate in the coordinator's `system` prompt** — what to hand off and to whom, how many at once, what to keep for itself, and what is too small to be worth delegating. Subagents see none of the coordinator's conversation, so each task must carry the paths, constraints, and report format it needs.
- **Limits:** 1–20 roster entries (at most one `self`; each rostered agent can be spawned many times), and **one level of delegation** — rostering an agent that itself carries a `multiagent` roster is rejected when the coordinator is created or updated.

---

## Declare the roster on the coordinator

`multiagent` is a **top-level field** on `agents.create()` / `agents.update()` — **not** a `tools[]` entry. `agents` lists 1–20 roster entries. Nothing changes on `sessions.create()` — the roster is resolved from the coordinator's config.

<!-- ts-check: reset -->
```ts
const orchestrator = await orca.agents.create({
  name: 'Engineering lead',
  model: 'claude-sonnet-4-6',
  system: 'You coordinate engineering work. Delegate code review to the reviewer and test writing to the test agent.',
  tools: [{ type: 'agent_toolset' }],
  multiagent: {
    type: 'coordinator',
    agents: [
      reviewer.id, //                                        bare string — latest version
      { type: 'agent', id: testWriter.id, version: 4 }, //   pinned version
      { type: 'self' }, //                                   the coordinator itself
    ],
  },
});

const session = await orca.sessions.create({ agent: orchestrator.id, environment_id: env.id });
```

| Roster entry | Shape | Notes |
|---|---|---|
| String shorthand | `"agt_01H8..."` | References the latest version of a stored agent. |
| Agent reference | `{type: "agent", id, version?}` | Omit `version` to use the latest. |
| Self | `{type: "self"}` | The coordinator can spawn copies of itself. |

If the session was created with `agent_with_overrides` (see `shared/managed-agents-core.md` → Override agent configuration for a session), those overrides apply to the **coordinator and its `self` copies**. Roster agents referenced by ID always use their own as-created configuration — overrides do not propagate to them.

---

## Threads

The session-level event stream is the **primary thread** — it shows the coordinator's trace plus a condensed view of subagent activity (thread status transitions and cross-thread messages, not every subagent tool call). Drill into a specific subagent via the per-thread endpoints:

| Operation | HTTP | SDK (`orca.sessions.threads.*`) |
|---|---|---|
| List threads | `GET /v1/sessions/{sid}/threads` | `.list(sessionId)` |
| Retrieve one | `GET /v1/sessions/{sid}/threads/{tid}` | `.retrieve(sessionId, threadId)` |
| Archive | `POST /v1/sessions/{sid}/threads/{tid}/archive` | `.archive(sessionId, threadId)` |
| List thread events | `GET /v1/sessions/{sid}/threads/{tid}/events` | `.events.list(sessionId, threadId)` |
| Stream thread events | `GET /v1/sessions/{sid}/threads/{tid}/stream` | `.events.stream(sessionId, threadId)` |

There is no thread *create* endpoint — the coordinator produces threads by delegating. Each `SessionThread` carries `id` (`sth_...`), `session_id`, `parent_thread_id` (null for the primary thread, which is included in the list), `agent` (a resolved snapshot of the member's config — `id`, `name`, `model`, `system`, `tools`, `mcp_servers`, `skills`, `version`), `status` (`running` | `idle` | `rescheduling` | `terminated`), `stats`, `usage` (per-thread token counts), and `archived_at`. The primary thread mirrors the session's status; read each subagent's own `status` from the thread list rather than inferring it from the session. When draining a per-thread stream, break on `session.thread_status_idle` (and check its `stop_reason` as you would for the session-level idle). From the CLI: `ork agent sessions threads list --session <id>` and `ork agent sessions threads events stream --session <id> --thread <id>`.

---

## Multiagent events (on the session stream)

| Event | Meaning |
|---|---|
| `session.thread_created` | A new thread was created for a delegation. |
| `session.thread_status_running` | Thread started activity. |
| `session.thread_status_idle` | Thread is awaiting input — inspect its `stop_reason` (same shape as `session.status_idle.stop_reason`). |
| `session.thread_status_rescheduled` | Thread is rescheduling after a retryable error. |
| `session.thread_status_terminated` | Thread ended — archived or hit a terminal error. |
| `agent.thread_message_sent` | *This* thread sent a message to another thread. On the primary stream: the coordinator sent a task or follow-up to a subagent. |
| `agent.thread_message_received` | A message arrived on *this* thread from another. On the primary stream: a subagent sent its report back to the coordinator. |

> **Direction is relative to the thread whose stream carries the event**, not to the coordinator. The same delegated task is an `agent.thread_message_sent` on the primary stream and an `agent.thread_message_received` on the child's own stream. Reading `_received` as "a subagent finished" is wrong once you're reading a child stream.

---

## Previewing a subagent's text

Each thread's stream accepts the same `event_deltas` parameter as the session-level stream, so you can watch a subagent's text as the model generates it:

```
GET /v1/sessions/{sid}/threads/{tid}/stream?event_deltas=agent.message
```

**Previews are thread-scoped.** A child's previews are delivered only on that child's stream and never cross-posted to the session-level stream, whose previews stay scoped to the primary thread. So watching a subagent live means opening its thread stream — the session stream will not show it. A worker's *reply to its coordinator* rides `agent.thread_message_sent` and is not assistant text, so a worker that does nothing but report back streams no deltas; to preview it live, its prompt has to make it write the answer as a plain assistant message first. Opt-in, accumulate, and reconcile details: `shared/managed-agents-events.md` → Live previews.

---

## Tool permissions and custom tools from subagent threads

When a subagent needs your client (an `always_ask` confirmation, or a custom tool result), the request surfaces on the **session stream** — so you only need to watch one stream. Reply as usual with `user.tool_confirmation` (carrying the `tool_use_id`) or `user.custom_tool_result` (carrying the `custom_tool_use_id`); the server routes the reply to the right thread by that ID. The event input contracts are strict — don't add extra routing fields to the reply.

---

## Interrupting threads

- **`user.interrupt` without `session_thread_id` interrupts the session as a whole.** Pass `session_thread_id` to target one thread.
- Archive finished threads (`threads.archive`) to keep long multiagent sessions tidy.

---

## Pitfalls

- **Don't put the roster on `sessions.create()` or in `tools[]`.** `multiagent` is a top-level agent field; update the coordinator, then start a session that references it.
- **Don't assume shared context.** Threads share the filesystem but not conversation history or tools. If the coordinator needs a subagent to act on something, it must say so in the delegated message (or write it to disk).
- **Depth > 1 is rejected.** Rostering an agent that itself has a `multiagent` roster fails the `agents.create`/`update` call — only the session's coordinator delegates.
- **Clear the roster with `multiagent: null`** on `agents.update()` to turn a coordinator back into a plain agent.
