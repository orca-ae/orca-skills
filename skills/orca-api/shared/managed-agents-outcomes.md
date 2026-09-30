# Orca Agent Engine — Outcomes

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
declare const AGENT_ID: string;
declare const ENVIRONMENT_ID: string;
declare const RUBRIC_MD: string;
declare const session: { id: string };
-->

An **outcome** states what "done" looks like for a session's work, and a separate **grader** (independent context window) scores the conversation against your rubric after each successful agent turn, emitting a verdict on the event stream.

<!-- orca-warn -->
> ⚠️ **Verdicts are advisory.** The grader evaluates and reports — it does **not** re-drive the agent. A `needs_revision` verdict increments the iteration counter and surfaces the gaps; nothing automatically prompts the agent to revise. If you want revision loops, your client reads the verdict and sends the follow-up `user.message` itself. Do not promise "iterates until the outcome is met" behavior.
<!-- /orca-warn -->

---

## The `user.define_outcome` event

Outcomes are not a field on `sessions.create()`. You create a normal session, then send a `user.define_outcome` event. The agent starts working on receipt — **do not also send a `user.message`** to kick it off.

You can collapse both calls into one by passing a `user.define_outcome` in the session's `initial_events` array — same event, same rules, one round trip (see `shared/managed-agents-core.md` → Seeding a session with `initial_events`).

<!-- ts-check: reset -->
```ts
const session = await orca.sessions.create({
  agent: AGENT_ID,
  environment_id: ENVIRONMENT_ID,
  title: 'Financial analysis on Costco',
});

await orca.sessions.events.send(session.id, {
  events: [
    {
      type: 'user.define_outcome',
      description: 'Build a DCF model for Costco in .xlsx',
      rubric: { type: 'text', content: RUBRIC_MD },
      // or: rubric: { type: "file", file_id: rubricFile.id }
      max_iterations: 5, // optional; default 3, max 20
    },
  ],
});
```

| Field | Type | Notes |
|---|---|---|
| `type` | `"user.define_outcome"` | |
| `description` | string | The task. This is what the agent works toward — no separate `user.message` needed. |
| `rubric` | `{type: "text", content}` \| `{type: "file", file_id}` | **Required.** Markdown with explicit, independently gradeable criteria (text form ≤256K chars). Upload once via `orca.files.upload(...)` to reuse across sessions. |
| `max_iterations` | int | Optional. Default **3**, max **20** — a cap on grader evaluations, not a promise of retries. |

From the CLI, send it with `--event-json` (see `shared/orca-cli.md` — the typed `send outcome` subcommand currently sends a rubric shape the registry rejects).

> **Writing rubrics.** Use explicit, gradeable criteria ("CSV has a numeric `price` column"), not vibes ("data looks good") — the grader scores each criterion independently, so vague criteria produce noisy verdicts. If you don't have a rubric, have the model analyze a known-good artifact and turn that analysis into one.

Multiple outcomes may be defined on one session; the grader evaluates **every** defined outcome after each successful turn, each tracking its own iteration count.

---

## Outcome-specific events

These appear on the standard event stream (`sessions.events.stream` / `.list`) alongside the usual `agent.*` / `session.*` events. The trio is emitted **before** the terminal `session.status_idle`, so a stream consumer sees the verdict before treating the turn as complete. Evaluations run only after successful turns — an errored or interrupted turn is not graded, and a grader failure never breaks the turn.

| Event | Payload highlights | Meaning |
|---|---|---|
| `span.outcome_evaluation_start` | `outcome_id`, `iteration` (0-indexed) | Grader began scoring iteration *N*. |
| `span.outcome_evaluation_ongoing` | `outcome_id`, `iteration`, `outcome_evaluation_start_id` | Heartbeat while the grader runs. Grader reasoning is opaque — you see *that* it's working, not *what* it's thinking. |
| `span.outcome_evaluation_end` | `outcome_evaluation_start_id`, `outcome_id`, `iteration`, `result`, `explanation` | Grader finished one evaluation. `result` says where things stand (table below). |

`outcome_id` is a slug derived from the outcome's description (`outcome_<slugified-description>`).

### `span.outcome_evaluation_end.result`

| `result` | Meaning |
|---|---|
| `satisfied` | The rubric is met. Terminal for this outcome. |
| `needs_revision` | Gaps remain. The iteration counter advances; **the agent is not re-prompted** — send a follow-up `user.message` if you want another attempt. |
| `max_iterations_reached` | The evaluation cap was hit without satisfaction. No further grader cycles for this outcome. |
| `failed` | The rubric fundamentally doesn't match the task (e.g. description and rubric contradict). |
| `interrupted` | A `user.interrupt` arrived while the outcome was active — even if evaluation hadn't started, in which case `outcome_evaluation_start_id` is an empty string rather than an event ID, so don't use it as a lookup key without checking. |

---

## Checking status & retrieving deliverables

**Status** — watch the stream for `span.outcome_evaluation_end`, poll the session and read `outcome_evaluations`, or hit the dedicated Orca extension endpoint `GET /v1/sessions/{id}/outcome` (returns the latest outcome record, or `null` before any evaluation):

<!-- ts-check: reset -->
```ts
const current = await orca.sessions.retrieve(session.id);
for (const ev of current.outcome_evaluations) {
  console.log(`${ev.outcome_id}: ${ev.result} (iteration ${ev.iteration})`);
}
```

Each `outcome_evaluations` entry carries `outcome_id`, `description`, `result`, `explanation`, `iteration`, and `completed_at`. From the CLI: `ork agent sessions outcome <session-id> -o json`.

**Deliverables** — the agent writes to `/mnt/session/outputs/`. Once idle, fetch via the session-files endpoints (`orca.sessions.files.list/download`) — see `shared/managed-agents-environments.md` → Session outputs.

---

## Interaction rules & pitfalls

- **Steering is allowed.** You may send `user.message` events mid-outcome to nudge direction — and since verdicts don't re-drive the agent, a follow-up `user.message` after a `needs_revision` verdict is exactly how a revision loop happens.
- **`user.interrupt` marks the outcome `interrupted`** and leaves the session `idle`, ready for a new outcome or conversational turn.
- **The session stays reusable** — continue conversationally or define another outcome at any point.
- **Outcome ≠ session-create field.** Don't put `outcome`, `rubric`, or `description` on `sessions.create()` — outcomes are always sent as a `user.define_outcome` event (directly or via `initial_events`).
- **Idle-break gate is unchanged.** In your drain loop, keep using `event.type === 'session.status_idle' && event.stop_reason?.type !== 'requires_action'` — do **not** gate on `span.outcome_evaluation_end` (the verdict precedes the idle, and a turn can end with any verdict). See `shared/managed-agents-client-patterns.md` Pattern 5.
