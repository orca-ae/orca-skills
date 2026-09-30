# Orca Agent Engine — TypeScript

> **Bindings not shown here:** This README covers the most common Agent Engine flows for TypeScript. If you need a class, method, or field that isn't shown, read the package's type definitions (`node_modules/@runorca/orca-sdk/**/*.d.ts`, mapped in `shared/live-sources.md`) rather than guess. Do not extrapolate from cURL shapes.

> **Agents are persistent — create once, reference by ID.** Store the agent ID returned by `agents.create` and pass it to every subsequent `sessions.create`; do not call `agents.create` in the request path. **Recommended:** provision agents and environments from a version-controlled setup script with the `ork` CLI — see `shared/orca-cli.md`. The CLI owns the control plane (create/update); your code owns the data plane (sessions with the stored ID). The examples below show in-code creation for when you must provision programmatically; in production the create call belongs in setup, not in the request path.

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
declare const environment: { id: string };
declare const agent: { id: string; version: number };
declare const session: { id: string; status?: string };
declare const vault: { id: string };
declare const toolUseEvent: import('@runorca/orca-sdk').SessionEvent;
-->

## Installation

The package is published to npm; no registry configuration or token is needed:

```bash
npm install @runorca/orca-sdk
```

Node 20+. The SDK has zero runtime dependencies and ships CJS + ESM.

## Client Initialization

```typescript
import Orca from '@runorca/orca-sdk';

// baseURL is REQUIRED (the constructor throws without it): the deployment
// host root, e.g. https://host.example.com — no /v1 suffix.
// A workspace API key (orca_…) authenticates only in the x-api-key header:
// apiKey: null stops the SDK sending it as a Bearer token.
const orca = new Orca({
  baseURL: process.env['ORCA_BASE_URL'],
  apiKey: null,
  defaultHeaders: { 'x-api-key': process.env['ORCA_API_KEY'] },
});
```

`apiKey` is sent as `Authorization: Bearer ...`, which the engine checks as an **OIDC access token** — use it for OIDC tokens: a string, or an async function called per request for rotation. Left unset it defaults to `ORCA_API_KEY` and sends that as Bearer, which the engine rejects (401) for a workspace key, so keep `apiKey: null` when the credential is a workspace key. Useful options: `timeout` (default 600 s; it covers opening a request, not a stream's lifetime), `maxRetries` (default 2, on network errors and 408/409/429/5xx), `logLevel` (`ORCA_LOG` env var).

---

## Create an Environment

<!-- ts-check: reset -->
```typescript
const environment = await orca.environments.create({
  name: 'my-dev-env',
  config: {
    type: 'cloud',
    networking: { type: 'unrestricted' },
  },
});
console.log(environment.id); // env_...
```

`config` is optional — `{ name }` alone creates a cloud environment with defaults. See `shared/managed-agents-environments.md` for networking and packages.

---

## Create an Agent (required first step)

> ⚠️ **There is no inline agent config.** `model`/`system`/`tools` live on the agent object, not the session. Always start with `agents.create()` — the session only takes a pointer (`agent`) plus its `environment_id`.

### Minimal

<!-- ts-check: reset -->
```typescript
// 1. Create the agent (reusable, versioned)
const agent = await orca.agents.create({
  name: 'Coding Assistant',
  model: 'claude-sonnet-4-6',
  tools: [{ type: 'agent_toolset' }],
});

// 2. Start a session
const session = await orca.sessions.create({
  agent: { type: 'agent', id: agent.id, version: agent.version },
  environment_id: environment.id as string,
});
console.log(session.id, session.status);
```

`agent` also accepts a bare string (`agent: agent.id` — shorthand for latest version) or an `agent_with_overrides` object (see `shared/managed-agents-core.md`). The tool type `agent_toolset` is Orca's canonical name; the Anthropic dated alias `agent_toolset_20260401` is accepted on write and echoed back to Claude-compatible clients.

### With system prompt and custom tools

<!-- ts-check: reset -->
```typescript
const agent = await orca.agents.create({
  name: 'Code Reviewer',
  model: 'claude-sonnet-4-6',
  system: 'You are a senior code reviewer.',
  tools: [
    { type: 'agent_toolset' },
    {
      type: 'custom',
      name: 'run_tests',
      description: 'Run the test suite',
      input_schema: {
        type: 'object',
        properties: {
          test_path: { type: 'string', description: 'Path to test file' },
        },
        required: ['test_path'],
      },
    },
  ],
});

const session = await orca.sessions.create({
  agent: { type: 'agent', id: agent.id, version: agent.version },
  environment_id: environment.id as string,
  title: 'Code review session',
  resources: [
    {
      type: 'github_repository',
      url: 'https://github.com/owner/repo',
      mount_path: '/workspace/repo',
      authorization_token: process.env['GITHUB_TOKEN']!,
      checkout: { type: 'branch', name: 'main' },
    },
  ],
});
```

<!-- orca-warn -->
> ⚠️ **`checkout` pins are currently not honored at clone time** — the field is accepted and stored, but the default branch is cloned regardless. If a specific ref matters, have the agent `git checkout <ref>` via `bash` as its first step. See `shared/managed-agents-environments.md` → GitHub Repositories.
<!-- /orca-warn -->

---

## Send a User Message

<!-- ts-check: reset -->
```typescript
await orca.sessions.events.send(session.id, {
  events: [
    {
      type: 'user.message',
      content: [{ type: 'text', text: 'Review the auth module' }],
    },
  ],
});
```

> ⚠️ Open the stream before sending when you need live delivery. An empty cursor starts from the transcript's current head; send-then-stream can miss a fast response. Use `{from_cursor: '0'}` only when you intentionally want full persisted history. See `shared/managed-agents-events.md`.

---

## Stream Events (SSE)

`events.stream()` returns an async-iterable `Stream<SessionEvent>`. Received events are **loosely typed** — `SessionEvent` is `{ id, type, processed_at }` plus open fields — so pull payload fields with an assertion:

<!-- ts-check: reset -->
```typescript
import type { TextContentBlock } from '@runorca/orca-sdk';

const stream = await orca.sessions.events.stream(session.id);

for await (const event of stream) {
  switch (event.type) {
    case 'agent.message': {
      const blocks = event['content'] as TextContentBlock[];
      for (const block of blocks) {
        if (block.type === 'text') process.stdout.write(block.text);
      }
      break;
    }
    case 'agent.custom_tool_use':
      // Custom tool invocation — the session parks until you reply
      console.log(`\nCustom tool call: ${String(event['name'])}`);
      console.log(`Input: ${JSON.stringify(event['input'])}`);
      break;
    case 'session.status_idle':
      console.log('\n--- Agent idle ---');
      break;
  }
}
```

For an intentional full replay, open a separate stream with `{ from_cursor: '0' }`. Any nonzero cursor is transport metadata from the SSE `id:` field and replay is inclusive.

`from_cursor` takes the numeric SSE frame cursor, **not** `event.id`. The default SDK stream yields only frame `data` and does not expose that cursor, so do not build a reconnect loop from `SessionEvent.id`. Use `events.list()` plus `event.id` deduplication for SDK catch-up, or raw SSE/CLI for exact cursor resume. Token-level previews: `{ event_deltas: ['agent.message'] }` — see `shared/managed-agents-events.md` → Live previews.

---

## Provide Custom Tool Result

Reply with the `agent.custom_tool_use` **event's own `id`** as `custom_tool_use_id`:

<!-- ts-check: reset -->
```typescript
await orca.sessions.events.send(session.id, {
  events: [
    {
      type: 'user.custom_tool_result',
      custom_tool_use_id: toolUseEvent.id,
      content: [{ type: 'text', text: 'All 42 tests passed.' }],
    },
  ],
});
```

---

## Poll Events

Every list method is both awaitable (one page) and async-iterable (all pages):

<!-- ts-check: reset -->
```typescript
const page = await orca.sessions.events.list(session.id, { limit: 50 });
for (const event of page.data) {
  console.log(`${event.type}: ${event.id}`);
}

// Or walk every page:
for await (const event of orca.sessions.events.list(session.id, { types: 'agent.message' })) {
  console.log(event.id);
}
```

---

## Stream-First Loop with Custom Tools

<!-- ts-check: reset -->
```typescript
import Orca from '@runorca/orca-sdk';
import type { SessionEvent, SessionEventInput } from '@runorca/orca-sdk';

function runCustomTool(toolName: string, toolInput: unknown): string {
  if (toolName === 'run_tests') {
    // Your tool implementation here
    return 'All tests passed.';
  }
  return `Unknown tool: ${toolName}`;
}

async function runSession(orca: Orca, sessionId: string, kickoff: string): Promise<void> {
  // Empty cursor = from-now. Establish the stream before the kickoff so a fast
  // turn cannot finish before the client starts listening.
  const stream = await orca.sessions.events.stream(sessionId);
  try {
    await orca.sessions.events.send(sessionId, {
      events: [{ type: 'user.message', content: [{ type: 'text', text: kickoff }] }],
    });
  } catch (error) {
    stream.controller.abort();
    throw error;
  }

  const pendingCustomTools = new Map<string, SessionEvent>();
  let terminal = false;

  for await (const event of stream) {
    if (event.type === 'agent.message') {
      const blocks = event['content'] as { type: string; text?: string }[];
      for (const block of blocks) {
        if (block.type === 'text' && block.text) process.stdout.write(block.text);
      }
    } else if (event.type === 'agent.custom_tool_use') {
      pendingCustomTools.set(event.id, event);
    } else if (event.type === 'session.status_idle') {
      const stop = event['stop_reason'] as { type: string; event_ids?: string[] } | undefined;
      if (stop?.type !== 'requires_action') {
        terminal = true; // end_turn or retries_exhausted
        break;
      }

      const results: SessionEventInput[] = [];
      const resolvedCustomToolIds: string[] = [];
      const unresolved: string[] = [];
      for (const eventId of stop.event_ids ?? []) {
        const call = pendingCustomTools.get(eventId);
        if (!call) {
          unresolved.push(eventId); // built-in/MCP confirmation follows a different flow
          continue;
        }
        results.push({
          type: 'user.custom_tool_result',
          custom_tool_use_id: call.id,
          content: [{
            type: 'text',
            text: runCustomTool(String(call['name']), call['input']),
          }],
        });
        resolvedCustomToolIds.push(eventId);
      }
      if (results.length > 0) {
        await orca.sessions.events.send(sessionId, { events: results });
        for (const eventId of resolvedCustomToolIds) pendingCustomTools.delete(eventId);
      }
      if (unresolved.length > 0) {
        throw new Error(`unhandled pending tool confirmations: ${unresolved.join(', ')}`);
      }
    }
  }

  if (!terminal) {
    throw new Error('event stream ended before terminal idle; recover before reporting success');
  }
}
```

If this connection drops, `SessionEvent.id` is not a resume cursor. Open a new live stream first, then use `events.list({order: 'asc'})` to catch up and dedupe by event ID. Use raw SSE or CLI when exact frame-cursor recovery is mandatory.

---

## Upload a File

<!-- ts-check: reset -->
```typescript
import fs from 'fs';
import { toFile } from '@runorca/orca-sdk';

const file = await orca.files.upload({
  file: await toFile(fs.createReadStream('data.csv'), 'data.csv', { type: 'text/csv' }),
});

// Use in a session
const session = await orca.sessions.create({
  agent: { type: 'agent', id: agent.id, version: agent.version },
  environment_id: environment.id as string,
  resources: [{ type: 'file', file_id: file.id, mount_path: '/workspace/data.csv' }],
});
```

`upload` takes only the `file` part — set the MIME type on the `File`/`toFile` value itself. `orca.files.list()` pages with `after_id`/`before_id` ID cursors (not `page` tokens).

---

## List and Download Session Files

Files the agent wrote to the session's outputs directory are an Orca extension, exposed at `orca.sessions.files`:

<!-- ts-check: reset -->
```typescript
import fs from 'fs';

for await (const f of orca.sessions.files.list(session.id)) {
  console.log(f.filename, f.size_bytes);

  // Download and save to disk
  const resp = await orca.sessions.files.download(session.id, f.id);
  const buffer = Buffer.from(await resp.arrayBuffer());
  fs.writeFileSync(String(f.filename), buffer);
}
```

---

## Session Management

<!-- ts-check: reset -->
```typescript
// Get session details
const session = await orca.sessions.retrieve('ses_01H8...');
console.log(session.status);

// List sessions (async-iterable across pages)
const sessions = await orca.sessions.list({ limit: 20 });

// Delete a session
await orca.sessions.delete('ses_01H8...');

// Archive a session
await orca.sessions.archive('ses_01H8...');
```

For repeated calls on one session, `orca.session(id)` returns a `SessionHandle` with `.events`, `.resources`, `.files`, and `.threads` pre-bound to the ID:

```typescript
const handle = orca.session('ses_01H8...');
await handle.events.send({ events: [{ type: 'user.message', content: [{ type: 'text', text: 'Continue.' }] }] });
for await (const event of await handle.events.stream()) {
  if (event.type === 'session.status_idle') break;
}
```

---

## MCP Server Integration

<!-- ts-check: reset -->
```typescript
// Agent declares MCP server (no auth here — auth goes in a vault)
const agent = await orca.agents.create({
  name: 'MCP Agent',
  model: 'claude-sonnet-4-6',
  mcp_servers: [
    { type: 'url', name: 'my-tools', url: 'https://my-mcp-server.example.com/mcp' },
  ],
  tools: [
    { type: 'agent_toolset' },
    { type: 'mcp_toolset', mcp_server_name: 'my-tools' },
  ],
});

// Session attaches vault(s) containing credentials for those MCP server URLs
const session = await orca.sessions.create({
  agent: agent.id,
  environment_id: environment.id as string,
  vault_ids: [vault.id],
});
```

Every declared MCP server must be referenced by an `mcp_toolset` tool, or the create request is rejected. See `shared/managed-agents-tools.md` §Vaults for creating vaults and adding credentials.
