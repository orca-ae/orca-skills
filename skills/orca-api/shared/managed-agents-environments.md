# Orca Agent Engine — Environments & Resources

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
declare const agent: { id: string; version: number };
declare const envId: string;
declare const vaultId: string;
declare const session: { id: string };
-->

## Environments

Creating a session requires an `environment_id`. Environments are **reusable configuration templates** for spinning up containers — you might create different environments for different use cases (e.g. data visualization vs web development, with different package sets). The platform handles scaling and container lifecycle; the sandbox image itself is operator-configured on the deployment, not set per request.

**Environment names must be unique.** Creating an environment with an existing name returns 409.

### Networking

| Network Policy   | Description                                                   |
| ---------------- | ------------------------------------------------------------- |
| `unrestricted`   | Full egress                                                   |
| `limited`        | Deny-by-default; opt in via `allowed_hosts` / `allow_package_managers` / `allow_mcp_servers` |

```json
{
  "networking": {
    "type": "limited",
    "allow_package_managers": true,
    "allow_mcp_servers": true,
    "allowed_hosts": ["api.example.com"]
  }
}
```

All three `limited` fields are optional. `allow_package_managers` (default `false`) permits PyPI/npm/etc.; `allow_mcp_servers` (default `false`) permits the agent's configured MCP server endpoints without listing them in `allowed_hosts`.

**MCP caveat:** Under `limited` networking, either set `allow_mcp_servers: true` or add each MCP server domain to `allowed_hosts`. Otherwise the container can't reach them and tools fail.

### Packages

`config.packages` pre-installs packages into the container by manager: `apt`, `cargo`, `gem`, `go`, `npm`, `pip`. From the CLI, `--package-pip requests --package-npm typescript` etc. (repeatable per manager).

### Creating an environment

<!-- ts-check: reset -->
```ts
const env = await orca.environments.create({
  name: 'my_env',
  config: {
    type: 'cloud',
    networking: { type: 'unrestricted' },
    packages: { pip: ['requests'] },
  },
});
```

`config` is optional; `{ name }` creates a cloud environment with defaults. Use the `config` object shape — the older flat `packages`/`networking`/`image`/`target` top-level fields are legacy and the SDK no longer sends them.

### Self-hosted environments

`config: {type: "self_hosted"}` moves a session off the engine's sandbox runtime and onto infrastructure you operate: the agent loop and its tools run on your host, and the Registry coordinates the session over a tunnel. Two constraints differ from `cloud`: `packages` are rejected for self-hosted environments (you own the runtime image), and self-hosted environments additionally take a `scope` of `organization` or `account`. How the self-hosted runtime is registered and operated is deployment-specific — consult your deployment's operator documentation.

### Environment CRUD

| Operation        | Method   | Path                                       | Notes |
| ---------------- | -------- | ------------------------------------------ | ----- |
| Create           | `POST`   | `/v1/environments`                         | |
| List             | `GET`    | `/v1/environments`                         | Paginated (`limit`, `page`) |
| Get              | `GET`    | `/v1/environments/{id}`                    | |
| Update           | `POST`   | `/v1/environments/{id}`                    | Changes apply to containers provisioned after the update; running sessions keep the config they started with |
| Delete           | `DELETE` | `/v1/environments/{id}`                    | |
| Archive          | `POST`   | `/v1/environments/{id}/archive`            | Makes it **read-only**; existing sessions continue, new sessions cannot reference it. No unarchive — terminal state. |

---

## Resources

Attach files, GitHub repositories, and memory stores to a session. Resources are resolved during session creation, so a bad `file_id` or an invalid repo URL surfaces on the create call rather than mid-run. Creating a session does **not** by itself start work or provision the sandbox — without `initial_events` the session is only registered, and the sandbox comes up when the session first needs it (see `shared/managed-agents-core.md` → Seeding a session with `initial_events`).

Per-session caps: **100 resources total (and at most 100 `file` entries), 8 `github_repository`, 8 `memory_store`.** Mount paths must be unique across all resources. For `type: "memory_store"` resources (persistent cross-session memory), see `shared/managed-agents-memory.md`.

### File Uploads (input — host → agent)

Upload a file first via the Files API, then reference by `file_id` + `mount_path`:

<!-- ts-check: reset -->
```ts
import fs from 'fs';
import { toFile } from '@runorca/orca-sdk';

// 1. Upload
const file = await orca.files.upload({
  file: await toFile(fs.createReadStream('data.csv'), 'data.csv', { type: 'text/csv' }),
});

// 2. Attach as a session resource
const session = await orca.sessions.create({
  agent: agent.id,
  environment_id: envId,
  resources: [{ type: 'file', file_id: file.id, mount_path: '/workspace/data.csv' }],
});
```

`mount_path` must be absolute; omitted, it defaults to `/mnt/session/uploads/<file_id>`. Parent directories are created automatically. Agent working directory defaults to `/workspace`. Files are mounted read-only by default — the agent writes modified versions to new paths.

### Session outputs (output — agent → host)

The agent can write files to `/mnt/session/outputs/` during a session (the one always-writable output path). These are captured and exposed as **session files** — an Orca extension at `GET /v1/sessions/{id}/files`:

<!-- ts-check: reset -->
```ts
for await (const f of orca.sessions.files.list(session.id)) {
  console.log(f.filename, f.size_bytes);
  const resp = await orca.sessions.files.download(session.id, f.id);
  const text = await resp.text();
}
```

**Requirements and notes:**
- The `write` tool (or `bash`) must be enabled for the agent to create output files.
- Session files paginate with `after_id`/`before_id` ID cursors (the SDK's async iterator follows them for you). `delete` removes one output file.
- On raw HTTP, the account-wide Files API also accepts `GET /v1/files?scope_id=<session_id>` to filter for one session's outputs (an empty `scope_id` means "no filter").
- From the CLI: `ork agent sessions files list --session <id>` / `content <file-id> --output-file out.bin`.
- Allow a brief indexing lag between `session.status_idle` and output files appearing in the list. Retry once or twice if empty.

This gives you a bidirectional file bridge: upload reference data in, download agent artifacts out.

### GitHub Repositories

Clones a GitHub repository into the session container during initialization, before the agent begins execution. The agent can read, edit, commit, and push via `bash` (`git`). Multiple repositories per session are supported (max 8, unique URLs) — add one `resources` entry per repo.

Repositories are attached for the lifetime of the session — to change which repositories are mounted, create a new session. You **can** rotate a repository's `authorization_token` on a running session via `orca.sessions.resources.update(sessionId, resourceId, {...})`; the resource `id` is returned at session creation and by `resources.list()`.

**Fields:**

| Field | Required | Notes |
|---|---|---|
| `type` | ✅ | `"github_repository"` |
| `url` | ✅ | The repository URL — `https:` only, no userinfo/query/fragment, at least `owner/repo` path segments. Not restricted to github.com. |
| `authorization_token` | ✅ | Personal Access Token with repository access. **Never echoed in API responses.** Orca extension: `git_cred://<id>` references a pre-provisioned workspace git credential instead of an inline token. |
| `mount_path` | ❌ | Path where the repository will be cloned. Defaults to `/workspace/<repo-name>/`. |
| `access` | ❌ | `read_only` or `read_write` (default `read_write`) |
| `instructions` | ❌ | Guidance for the agent about this repo (≤4096 chars) |
| `checkout` | ❌ | `{type: "branch", name: "..."}` or `{type: "commit", sha: "..."}` — see the warning below |

<!-- orca-warn -->
> ⚠️ **`checkout` pins are currently not honored.** The API accepts and stores the field, but the clone step does not apply it: a branch pin clones the **default branch** anyway, and a commit pin only forces a full-history clone without checking out the sha. Until this is fixed, have the agent `git checkout <ref>` via `bash` as its first step if a specific ref matters.
<!-- /orca-warn -->

**Token permission levels** (fine-grained PATs):
- `Contents: Read` — clone only
- `Contents: Read and write` — push changes and create pull requests

**How auth works:** `authorization_token` never reaches the sandbox. The clone embeds it one-shot in the clone URL on the harness host and resets the remote to the bare URL before the working tree (including `.git/`) is streamed into the sandbox. In-sandbox `git push` / `git fetch` authenticate through a git **credential helper** that calls back to the platform per operation — the token is resolved per call and never persisted where agent code could read it. The clone is `--filter=blob:none --depth=1` (shallow).

> ‼️ **To generate pull requests** you also need GitHub **MCP server** access — the `github_repository` resource gives filesystem + git access only. See `shared/managed-agents-tools.md` → MCP Servers. The PR workflow is: edit files in the mounted repo → push branch via `bash` (authenticated via the credential helper) → create PR via the MCP `create_pull_request` tool (authenticated via the vault).

**TypeScript:**

<!-- ts-check: reset -->
```ts
// 1. Create the agent — declare GitHub MCP (no auth here)
const agent = await orca.agents.create({
  name: 'GitHub Agent',
  model: 'claude-sonnet-4-6',
  mcp_servers: [{ type: 'url', name: 'github', url: 'https://api.githubcopilot.com/mcp/' }],
  tools: [{ type: 'agent_toolset' }, { type: 'mcp_toolset', mcp_server_name: 'github' }],
});

// 2. Start a session — attach vault for MCP auth + mount the repo
const session = await orca.sessions.create({
  agent: agent.id,
  environment_id: envId,
  vault_ids: [vaultId], // vault contains the GitHub MCP OAuth credential
  resources: [
    {
      type: 'github_repository',
      url: 'https://github.com/owner/repo',
      authorization_token: process.env['GITHUB_TOKEN']!, // repo clone token (≠ MCP auth)
      checkout: { type: 'branch', name: 'main' },
    },
  ],
});
```

---

## Files API

Upload and manage files for use as session resources, and download files the agent wrote to `/mnt/session/outputs/`.

| Operation        | Method   | Path                                  | SDK |
| ---------------- | -------- | ------------------------------------- | --- |
| Upload           | `POST`   | `/v1/files`                           | `orca.files.upload({ file })` |
| List             | `GET`    | `/v1/files`                           | `orca.files.list({ limit, after_id, before_id })` |
| Get Metadata     | `GET`    | `/v1/files/{id}`                      | `orca.files.retrieve(id)` |
| Download         | `GET`    | `/v1/files/{id}/content`              | `orca.files.download(id)` → `Response` |
| Delete           | `DELETE` | `/v1/files/{id}`                      | `orca.files.delete(id)` |

Session outputs (Orca extension):

| Operation        | Method   | Path                                        | SDK |
| ---------------- | -------- | ------------------------------------------- | --- |
| List             | `GET`    | `/v1/sessions/{id}/files`                   | `orca.sessions.files.list(sessionId)` |
| Get Metadata     | `GET`    | `/v1/sessions/{id}/files/{file_id}`         | `orca.sessions.files.retrieve(sessionId, fileId)` |
| Download         | `GET`    | `/v1/sessions/{id}/files/{file_id}/content` | `orca.sessions.files.download(sessionId, fileId)` |
| Delete           | `DELETE` | `/v1/sessions/{id}/files/{file_id}`         | `orca.sessions.files.delete(sessionId, fileId)` |
