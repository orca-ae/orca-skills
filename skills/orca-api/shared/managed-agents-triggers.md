# Orca Agent Engine — Agent Triggers

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
declare const agent: { id: string; version: number };
declare const env: { id: string };
-->

Agent Triggers run an agent without a client driving each invocation. Every firing creates an ordinary Session from a stored Agent reference plus a Session template. Triggers are a **core `/v1/triggers` resource**, not part of the hosted extension group, so no discovery check applies; hosted deployments widen the same resource with Pulsar/Kafka sources and additional routing modes (hosted only).

<!-- orca-warn -->
Orca does not serve `/v1/deployments` or `/v1/deployment_runs`. Use Triggers for scheduled or message-driven invocation and list the Sessions a Trigger created for run history.
<!-- /orca-warn -->

## Open-source core vs hosted deployments

| Capability | Open-source core | Hosted deployments (hosted only beyond core) |
|---|---|---|
| Endpoint / SDK | `/v1/triggers` / `orca.triggers` | Same |
| Sources | `cron` | `cron`, `pulsar`, `kafka` |
| Session modes | `SESSION_PER_EVENT` | `SESSION_PER_EVENT`, `SESSION_PER_TOPIC`, `SESSION_PER_KEY`, `SHARED` (`cron` supports per-event/shared) |
| Replicas | Exactly `1` | Positive deployment-supported count |

**On an engine you run yourself**, the Pulsar/Kafka sources are not available: consume the topic in your own worker and call `sessions.create` per message (or per key), or use a `cron` trigger when polling is enough.

The SDK exposes the widened union and does not preflight which backend is serving the request. Use only core values when code must run on every deployment; otherwise let the target deployment validate the requested source and mode. **Do not gate Triggers on `GET /apis`** — discovery covers the extension groups (the hosted extension group, policy, pricing, runtime), and Triggers are core.

## Trigger shape

| Field | What it is |
|---|---|
| `name` | Trigger name |
| `agent` | Agent ID string or `{type: "agent", id, version?}`. Create resolves and pins a concrete version. |
| `source` | `cron`; `pulsar` / `kafka` on hosted deployments only |
| `session` | `{environment_id, title_template?, metadata?, vault_ids?}` |
| `session_mode` | How source events map to Sessions |
| `replicas` | Runner count; defaults to `1` |
| `paused` | Create without accepting future firings |
| `status` | Read-only: `active`, `paused`, or `archived` |
| `next_fire_at`, `last_fired_at`, `error` | Read-only scheduler/runner state |

Session resources are not part of the portable Trigger template. Pre-provision durable inputs through supported Session-template fields rather than storing raw repository credentials in a Trigger.

### Source fields

- **`cron`** — `schedule` (five fields), optional `timezone` (defaults to `Etc/UTC`), and `payload` (the `user.message` text delivered to each Session).
- **`pulsar` / `kafka`** — `connection`, exactly one of `topics` / `topic_pattern`, optional `subscription_name`, and schema settings. Kafka additionally supports `consumer_additional_config` and `input_schema_configs`.

Use an explicit IANA timezone. Prefer `Etc/UTC` for schedules that must not depend on daylight-saving transitions.

## Creating a Trigger

TypeScript:

<!-- ts-check: reset -->
```ts
const trigger = await orca.triggers.create({
  name: 'nightly-digest',
  agent: { type: 'agent', id: agent.id, version: agent.version },
  session_mode: 'SESSION_PER_EVENT',
  source: {
    type: 'cron',
    schedule: '0 6 * * *',
    timezone: 'Etc/UTC',
    payload: 'Compile the nightly digest from /workspace/inbox.',
  },
  session: {
    environment_id: env.id,
    title_template: 'Nightly digest',
    vault_ids: [],
  },
});
console.log(trigger.id, trigger.status);
```

CLI — portable cron, then a Pulsar example (hosted only):

```bash
ork agent triggers create --name nightly-digest \
  --agent "$ORCA_AGENT_ID" --session-mode SESSION_PER_EVENT \
  --source-type cron --schedule "0 6 * * *" --timezone Etc/UTC \
  --payload "Compile the nightly digest from /workspace/inbox." \
  --environment-id "$ORCA_ENV_ID" --title-template "Nightly digest"

ork agent triggers create --name support-intake \
  --agent "$ORCA_AGENT_ID" --session-mode SESSION_PER_KEY \
  --source-type pulsar --connection my-pulsar --topic persistent://public/default/tickets \
  --subscription-name agent-intake \
  --environment-id "$ORCA_ENV_ID" --vault-id "$ORCA_VAULT_ID"
```

`ork agent triggers create -f trigger.json` (or `--config-json`) takes the full Trigger object from a version-controlled JSON file.

## Lifecycle

| Operation | SDK (`orca.triggers.*`) | CLI (`ork agent triggers ...`) | Wire |
|---|---|---|---|
| Create | `.create(params)` | `create` | `POST /v1/triggers` |
| List | `.list(params?)` | `list` | `GET /v1/triggers` |
| Get | `.retrieve(id)` | `get <id>` | `GET /v1/triggers/{id}` |
| Partial update | `.update(id, params)` | `update <id>` | `POST /v1/triggers/{id}` |
| Pause / resume | `.pause(id)` / `.unpause(id)` | `pause <id>` / `unpause <id>` | `POST .../pause`, `POST .../unpause` |
| Delete | `.delete(id)` | `delete <id>` | `DELETE /v1/triggers/{id}` |
| Sessions it fired | `.sessions.list(triggerId)` | `sessions <trigger-id>` | `GET .../sessions` |

Update is a **partial POST**: omitted fields remain unchanged. Pause fences future firings; unpause resumes from the next future slot. Delete soft-deletes the Trigger configuration and returns a tombstone; Sessions already created by it retain their own lifecycle and history.

## Observing fired Sessions

Each firing produces an ordinary Session. `orca.triggers.sessions.list(triggerId)` (CLI: `ork agent triggers sessions <trigger-id>`) returns those Sessions, newest first. Poll their events or open a stream using the cursor rules in `shared/managed-agents-events.md`; Session archive/delete controls whether historical Sessions remain visible.

## Mapping from scheduled deployments

<!-- orca-warn -->
| Scheduled-deployment concept | Agent Engine equivalent |
|---|---|
| Deployment with cron | Trigger with `source.type: "cron"` |
| Deployment run record | Session returned by `triggers.sessions.list` |
| Pause / unpause | `pause` / `unpause` |
| Deployment Session template | Trigger `agent` + `session` fields |
| Message-driven invocation | Trigger with a Pulsar/Kafka source (hosted only) |
<!-- /orca-warn -->
