# Orca Agent Engine — Memory Stores

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
declare const agent: { id: string };
declare const environment: { id: string };
declare const store: { id: string };
declare const mem: { id: string; content_sha256: string };
declare const memoryId: string;
declare const versionId: string;
-->

Sessions are ephemeral by default — when one ends, anything the agent learned is gone. A **memory store** is a workspace-scoped collection of small text documents that persists across sessions. When a store is attached to a session (via `resources[]`), it is mounted into the container as a filesystem directory; the agent reads and writes it with the ordinary file tools, and a system-prompt note tells it the mount is there.

Every mutation to a memory produces an immutable **memory version** (`memver_...`), giving you an audit trail and point-in-time rollback/redact.

> ⚠️ **Never store credentials, API keys, or tokens in memory stores.** Memories persist across sessions and are returned verbatim into future contexts — a key written once is replayed into every later session that mounts the store. Use vault `environment_variable` credentials instead (`shared/managed-agents-tools.md` → Vaults). If a secret has already been written, delete the memory and redact the affected versions (see "Redact a version" below).

> 💡 Memory endpoints are registered only on deployments configured with a memory backend — a 404 on `/v1/memory_stores` across the board means the deployment doesn't have one, not that your request is wrong.

## Object model

| Object | ID prefix | Scope | Notes |
| --- | --- | --- | --- |
| Memory store | `mems_...` | Workspace | Attach to sessions via `resources[]` |
| Memory | `mem_...` | Store | One text file, addressed by `path` — prefer many small files |
| Memory version | `memver_...` | Memory | Immutable snapshot per mutation; `operation` ∈ `created` / `modified` / `deleted` |

## Create a store

`description` is passed to the agent so it knows what the store contains — write it for the model, not for humans. (`name` ≤255 chars, `description` ≤1024.)

<!-- ts-check: reset -->
```ts
const store = await orca.memoryStores.create({
  name: 'User Preferences',
  description: 'Per-user preferences and project context.',
});
console.log(store.id); // mems_01H8...
```

Stores support `retrieve` / `update` / `list` (with `include_archived`; a `created_at` filter is raw HTTP on the engine only) / `delete` / **`archive`**. Archive makes the store read-only — existing session attachments continue, new sessions cannot reference it; no unarchive. From the CLI: `ork agent memory-stores ...`.

### Seed with content (optional)

Pre-load reference material before any session runs. `memories.create` creates a memory at the given `path`; if a memory already exists there the call returns `409` (`memory_path_conflict_error`). The store ID is the first positional argument.

<!-- ts-check: reset -->
```ts
await orca.memoryStores.memories.create(store.id, {
  body: {
    path: '/formatting_standards.md',
    content: 'All reports use GAAP formatting. Dates are ISO-8601...',
  },
});
```

## Attach to a session

Memory stores go in the session's `resources[]` array alongside `file` and `github_repository` resources (see `shared/managed-agents-environments.md` → Resources). They can also be attached to an existing session via `sessions.resources.add` — the 8-per-session cap is enforced at create and attach time alike.

<!-- ts-check: reset -->
```ts
const session = await orca.sessions.create({
  agent: agent.id,
  environment_id: environment.id,
  resources: [
    {
      type: 'memory_store',
      memory_store_id: store.id,
      access: 'read_write', // or "read_only"; default is "read_write"
      instructions: 'User preferences and project context. Check before starting any task.',
    },
  ],
});
```

| Field | Required | Notes |
| --- | --- | --- |
| `type` | ✅ | `"memory_store"` |
| `memory_store_id` | ✅ | `mems_...` |
| `access` | — | `"read_write"` (default) or `"read_only"` — enforced at the filesystem level on the mount |
| `instructions` | — | Session-specific guidance for this store, in addition to the store's `name`/`description` |

**Max 8 memory stores per session.** Attach multiple when different slices of memory have different owners or lifecycles — e.g. one read-only shared-reference store plus one read-write per-user store, or one store per end-user/team/project sharing a single agent config.

### How the agent sees it (mounted directory)

Each attached store is mounted in the session container at `/mnt/memory/<store-name>/` — the mount path is server-derived and is **not settable** on the resource (the strict attach contract rejects a `mount_path` key; the resolved path is echoed on the resource output). The agent interacts with it using the standard file tools (`bash`, `read`, `write`, `edit`, `glob`, `grep`) — there are no dedicated memory tools. `access: "read_only"` makes the mount read-only at the filesystem level; `"read_write"` allows the agent to create, edit, and delete files under it. A short description of each mount (name, path, `instructions`, access) is injected into the system prompt so the agent knows the store exists without you having to mention it.

Writes the agent makes under the mount are persisted back to the store and produce memory versions just like host-side `memories.update` calls.

## Manage memories directly (host-side)

Use these for review workflows, correcting bad memories, or seeding stores out-of-band.

### List

Returns `memory | memory_prefix` entries — a `memory_prefix` (just a `path`) is a directory-like node when listing hierarchically. Use `path_prefix` to scope (include a trailing slash: `"/notes/"` matches `/notes/a.md` but not `/notes_backup/old.md`) and `depth` (0 or 1) to bound the tree walk. Pass `view: "full"` to include `content` in each item; the default `"basic"` returns metadata only.

<!-- ts-check: reset -->
```ts
for await (const m of orca.memoryStores.memories.list(store.id, { path_prefix: '/' })) {
  if (m.type === 'memory') {
    console.log(`${m.path}  (${m.content_size_bytes} bytes)`);
  } else {
    console.log(`${m.path}/`);
  }
}
```

### Read

<!-- ts-check: reset -->
```ts
const memory = await orca.memoryStores.memories.retrieve(store.id, memoryId);
console.log(memory.content);
```

### Create vs. update

| Operation | Addressed by | Semantics |
| --- | --- | --- |
| `memories.create(storeId, {body: {path, content}})` | **Path** | Create at `path`. `409` (`memory_path_conflict_error`) if the path is already occupied. |
| `memories.update(storeId, memoryId, {body: {...}})` | **`mem_...` ID** | Mutate existing memory. Change `content`, `path` (rename), or both. Renaming onto an occupied path returns the same `409 memory_path_conflict_error`. |

<!-- ts-check: reset -->
```ts
const mem = await orca.memoryStores.memories.create(store.id, {
  body: {
    path: '/preferences/formatting.md',
    content: 'Always use tabs, not spaces.',
  },
});

await orca.memoryStores.memories.update(store.id, mem.id, {
  body: { path: '/archive/2026_q1_formatting.md' }, // rename
});
```

### Optimistic concurrency (precondition on `update`)

`memories.update` accepts a `precondition` so you can read → modify → write back without clobbering a concurrent writer. The only supported type is `content_sha256`. On mismatch the API returns `409` (`memory_precondition_failed_error`) — re-read and retry against fresh state.

<!-- ts-check: reset -->
```ts
await orca.memoryStores.memories.update(store.id, mem.id, {
  body: {
    content: 'CORRECTED: Always use 2-space indentation.',
    precondition: { type: 'content_sha256', content_sha256: mem.content_sha256 },
  },
});
```

### Delete

<!-- ts-check: reset -->
```ts
await orca.memoryStores.memories.delete(store.id, mem.id);
```

## Audit and rollback — memory versions

Every mutation creates an immutable `memver_...` snapshot. Versions accumulate for the lifetime of the parent memory; `memories.retrieve` always returns the current head, the version endpoints give you history.

| Operation that triggers it | `operation` field on the version |
| --- | --- |
| `memories.create` at a new path | `"created"` |
| `memories.update` changing `content`, `path`, or both (or an agent-side write to the mount) | `"modified"` |
| `memories.delete` | `"deleted"` |

Each version also records `created_by` — an actor object with `type` ∈ `session_actor` / `api_actor` / `user_actor` — and, after redaction, `redacted_at` + `redacted_by`.

### List versions

Newest-first, paginated. Filter by `memory_id`, `operation`, `api_key_id`, or `created_at[gte]` / `created_at[lte]`. Pass `view: "full"` to include `content`; default is metadata-only.

<!-- ts-check: reset -->
```ts
for await (const v of orca.memoryStores.memoryVersions.list(store.id, { memory_id: mem.id })) {
  console.log(`${v.id}: ${v.operation}`);
}
```

### Retrieve a version

<!-- ts-check: reset -->
```ts
const version = await orca.memoryStores.memoryVersions.retrieve(store.id, versionId);
console.log(version.content);
```

### Redact a version

Scrubs content from a historical version while preserving the audit trail (actor + timestamps). Clears `content`, `content_sha256`, `content_size_bytes`, and `path`; everything else stays. Use for leaked secrets, PII, or user-deletion requests.

<!-- ts-check: reset -->
```ts
await orca.memoryStores.memoryVersions.redact(store.id, versionId);
```

From the CLI: `ork agent memory-versions list --memory-store <id>` / `get` / `redact <version-id>`.

## Endpoint reference

See `shared/managed-agents-api-reference.md` → Memory Stores / Memories / Memory Versions for the full HTTP method/path tables. Note for raw HTTP: **memory updates are `POST`**, not PATCH:

```
POST   /v1/memory_stores
POST   /v1/memory_stores/{memory_store_id}/archive
GET    /v1/memory_stores/{memory_store_id}/memories
POST   /v1/memory_stores/{memory_store_id}/memories/{memory_id}
GET    /v1/memory_stores/{memory_store_id}/memory_versions
POST   /v1/memory_stores/{memory_store_id}/memory_versions/{version_id}/redact
```
