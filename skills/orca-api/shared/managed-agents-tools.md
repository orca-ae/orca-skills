# Orca Agent Engine — Tools & Skills

<!-- ts-check-context
declare const orca: import('@runorca/orca-sdk').default;
-->

## Tools

### Server tools vs client tools

| Type | Who runs it | How it works |
|---|---|---|
| **Built-in agent toolset** (`agent_toolset`) | The platform, on the session's container | File ops, bash, search. Enable all at once or configure individually. |
| **MCP tools** (`mcp_toolset`) | The MCP server, reached through the platform's gateway | Capabilities exposed by connected MCP servers. Grant access per-server via the toolset. |
| **Custom tools** | **You** — your application handles the call and returns results | Agent emits a `agent.custom_tool_use` event, session goes `idle`, you send back a `user.custom_tool_result` event. |

The Anthropic dated alias `agent_toolset_20260401` is accepted everywhere `agent_toolset` is and is canonicalized on write; responses echo the dated form to Claude-compatible clients (the `orca-beta` header switches to the native name).

### Agent Toolset

The agent toolset provides these built-in tools:

| Tool                   | Description                              |
| ---------------------- | ---------------------------------------- |
| `bash` | Execute bash commands in a shell session |
| `read` | Read a file from the local filesystem |
| `write` | Write a file to the local filesystem |
| `edit` | Perform string replacement in a file |
| `glob` | Fast file pattern matching using glob patterns |
| `grep` | Text search using regex patterns |
| `list` | List directory contents — **Orca extension** |
| `delete` | Delete a file — **Orca extension** |

<!-- orca-warn -->
> ⚠️ **`web_fetch` and `web_search` do not run.** Both names validate in `configs[].name` (and are reserved as custom-tool names), but the platform never exposes them to the model — managed-agent sessions have no general-purpose web access by default. Give the agent web reach through an MCP server, or fetch content host-side via a custom tool. Note the asymmetry: `list`/`delete` run but are rejected in `configs[].name`.
<!-- /orca-warn -->

Enable the full toolset:

```json
{
  "tools": [
    { "type": "agent_toolset" }
  ]
}
```

### Per-Tool Configuration

Override defaults for individual tools. This example enables everything except bash:

```json
{
  "tools": [
    {
      "type": "agent_toolset",
      "default_config": { "enabled": true },
      "configs": [
        { "name": "bash", "enabled": false }
      ]
    }
  ]
}
```

| Field | Required | Description |
|---|---|---|
| `type` | ✅ | `"agent_toolset"` |
| `default_config` | ❌ | Applied to all tools. `{ "enabled": bool, "permission_policy": {...} }` |
| `configs` | ❌ | Per-tool overrides — an array `[{ "name": "...", "enabled": bool, "permission_policy": {...} }]` or a record keyed by tool name |

To enable only specific tools, flip the default off and opt-in per tool:

```json
{
  "tools": [
    {
      "type": "agent_toolset",
      "default_config": { "enabled": false },
      "configs": [
        { "name": "bash", "enabled": true },
        { "name": "read", "enabled": true }
      ]
    }
  ]
}
```

### Permission Policies

Control when server-executed tools (agent toolset + MCP) run automatically vs wait for approval. Does not apply to custom tools.

| Policy | Behavior |
|---|---|
| `always_allow` | Tool executes automatically (the default for the built-in toolset) |
| `always_ask` | Session emits `session.status_idle` (`stop_reason.type: "requires_action"`) and pauses until you send a `user.tool_confirmation` event. The default for MCP toolsets. |

<!-- orca-warn -->
These are the only two settable values — `always_deny` exists internally but the API rejects it with 400; to shut a tool off, set `enabled: false` instead.
<!-- /orca-warn -->

```json
{
  "type": "agent_toolset",
  "default_config": {
    "enabled": true,
    "permission_policy": { "type": "always_allow" }
  },
  "configs": [
    { "name": "bash", "permission_policy": { "type": "always_ask" } }
  ]
}
```

**Responding to `always_ask`:** Send a `user.tool_confirmation` event with `tool_use_id` from the triggering `agent.tool_use`/`agent.mcp_tool_use` event:

```json
{ "type": "user.tool_confirmation", "tool_use_id": "evt_01H8...", "result": "allow" }
{ "type": "user.tool_confirmation", "tool_use_id": "evt_01H8...", "result": "deny", "deny_message": "Read .env.example instead" }
```

The optional `deny_message` (valid only with `"deny"`) is delivered to the agent so it can adjust its approach.

**Resolution order** when the harness decides a tool call's policy: exact tool name → `mcp__<server>__*` wildcard → the toolset's default policy → unknown remote MCP server ⇒ deny → allow.

### Custom Tools (Client-Side)

Custom tools are executed by **your application**, not the platform. The flow:

1. Agent decides to use the tool → session emits a `agent.custom_tool_use` event with inputs
2. Session goes `idle` waiting for you
3. Your application executes the tool
4. You send back a `user.custom_tool_result` event (echoing the `agent.custom_tool_use` event's `id` as `custom_tool_use_id`)
5. Session resumes `running`

<!-- orca-warn -->
No permission policy needed — you're the one executing. Custom tool names must not collide with the built-in names (`bash`, `read`, `write`, `edit`, `list`, `delete`, `glob`, `grep`, `web_fetch`, `web_search` are reserved).
<!-- /orca-warn -->

```json
{
  "tools": [
    {
      "type": "custom",
      "name": "get_weather",
      "description": "Fetch current weather for a city.",
      "input_schema": {
        "type": "object",
        "properties": {
          "city": { "type": "string", "description": "City name" }
        },
        "required": ["city"]
      }
    }
  ]
}
```

`description` is required (1-4096 chars) and `input_schema` must be a JSON Schema object with `type: "object"`.

### MCP Servers

MCP (Model Context Protocol) servers expose standardized third-party capabilities (e.g. GitHub, Linear, Notion). **Configuration is split across agent and vault:**

1. **Agent creation** declares which servers to connect to (`type`, `name`, `url` — no auth). The agent's `mcp_servers` array has no auth field.
2. **Vault** stores the credentials. Attach via `vault_ids` on session create.

This keeps secrets out of reusable agent definitions. Each vault credential is tied to one MCP server URL; the platform matches credentials to servers by URL.

**Agent side — declare servers (no auth):**

| Field | Required | Description |
|---|---|---|
| `type` | ✅ | `"url"` — the only accepted value (optional on create, defaults to `url`). Transport is Streamable HTTP. |
| `name` | ✅ | Unique name (1-255 chars) — referenced by `mcp_toolset.mcp_server_name` |
| `url` | ✅ | The MCP server's endpoint URL |

```json
{
  "mcp_servers": [
    { "type": "url", "name": "linear", "url": "https://mcp.linear.app/mcp" }
  ],
  "tools": [
    { "type": "mcp_toolset", "mcp_server_name": "linear" }
  ]
}
```

**Every declared server must be referenced by an `mcp_toolset` tool**, or the create/update request is rejected with 400 — it is easy to write an example that declares a server and forgets the toolset entry. Max 20 servers per agent. `mcp_toolset` also accepts `default_config`/`configs` for enablement, so you can park a server (`default_config: {enabled: false}`) without removing it.

**Session side — attach vault:**

```json
{
  "agent": "agt_01H8...",
  "environment_id": "env_01H8...",
  "vault_ids": ["vlt_01H8..."]
}
```

> 💡 **Changing tools/MCP servers on an existing session:** `sessions.update()` can replace `agent.tools`, `agent.mcp_servers` and `agent.model` — a session-local override that doesn't touch the agent object. The session must be **idle** (a running session returns 409 `session must be idle to update agent configuration` — interrupt first). `vault_ids` is create-only. See `shared/managed-agents-core.md` → Updating the agent configuration mid-session.

**Large tool outputs.** `bash` and `grep` output over **100,000 characters** is cut in place — the agent receives the first 100,000 characters followed by a `…[truncated, total N chars]` marker. `read` returns a file in pages of a few KiB (4,096 bytes by default): pass `offset`/`limit` and follow `next_offset` while the result reports truncation. `edit` refuses files over 100,000 bytes. Large results from remote MCP servers may be written to a file on the harness host that the agent cannot open, so steer the agent toward narrow queries (`grep`, ranged `read`) when outputs may be large.

> ⚠️ **MCP auth tokens ≠ REST API tokens.** Hosted MCP servers (`mcp.notion.com`, `mcp.linear.app`, etc.) typically require **OAuth bearer tokens**, not the service's native API keys. A Notion integration token authenticates against Notion's REST API but will **not** work as a vault credential for the Notion MCP server. These are different auth systems.

### Vaults — the credential store

**Vaults** store credentials the platform manages on your behalf. Two credential categories:

- **MCP credentials** (`mcp_oauth`, `static_bearer`) — keyed by `mcp_server_url`. When the agent connects to a server at that URL, the token is injected automatically. **Matching is by canonical URL** — scheme and host case and a trailing slash don't break the match; a different path, subdomain, or port does. If two credentials in one vault match the same URL, that's an error; across multiple vaults, `vault_ids` order decides. If nothing matches, the connection is attempted unauthenticated. `mcp_oauth` tokens are auto-refreshed via the standard OAuth 2.0 `refresh_token` grant. This is the only way to authenticate MCP servers.
- **Environment variables** (`environment_variable`) — keyed by `secret_name` (the env var name). The sandbox sees only an **opaque placeholder**; the real secret is substituted into the outbound request **at egress**, by the platform's gateway. Use this for any service that authenticates through an environment variable: CLIs (`aws`, `gcloud`, `stripe`), SDKs, or direct `curl` calls from the `bash` tool.

Secret fields you supply (`token`, `access_token`, `refresh_token`, `client_secret`, `secret_value`) are write-only — never returned in API responses.

#### Credentials and the sandbox

Vaults store credentials; those credentials **never enter the sandbox**. This is a deliberate security boundary — code running in the sandbox (including anything the agent writes) cannot read or exfiltrate a vaulted credential, even under prompt injection. Credentials are injected after a request leaves the sandbox:

- **MCP tool calls** are routed through the platform's gateway, which fetches the credential from the vault and adds it to the outbound request.
- **Git operations on attached GitHub repositories** authenticate through a per-call credential helper — see `shared/managed-agents-environments.md` → GitHub Repositories.
- **Environment-variable credentials** appear in the sandbox as an opaque placeholder; the real value replaces the placeholder at egress, on requests to the credential's allowed hosts only.

**When vault credentials don't fit** (a secret the gateway can't substitute, or tool execution running on your own infrastructure), **register a custom tool:** the agent emits `agent.custom_tool_use`, your orchestrator (which already holds the credential) executes the call and returns `user.custom_tool_result` over the same authenticated event stream. No public endpoint is exposed; the sandbox never sees the secret. See `shared/managed-agents-client-patterns.md` → Pattern 9.

**Do not put API keys in the system prompt or user messages as a workaround** — they persist in the session's event history.

**Flow:**

1. Create a vault (`orca.vaults.create(...)`) — one per tenant/user, or one shared, depending on your model
2. Add credentials to it (`orca.vaults.credentials.create(...)`) — MCP credentials are keyed by MCP server URL; environment-variable credentials by `secret_name`
3. Reference the vault on session create via `vault_ids: ["vlt_..."]`
4. The platform auto-refreshes OAuth tokens before they expire and substitutes secrets at runtime

**MCP OAuth credential shape**:

```json
{
  "display_name": "Notion (workspace-foo)",
  "auth": {
    "type": "mcp_oauth",
    "mcp_server_url": "https://mcp.notion.com/mcp",
    "access_token": "<current access token>",
    "expires_at": "2026-04-02T14:00:00Z",
    "refresh": {
      "refresh_token": "<refresh token>",
      "client_id": "<your OAuth client_id>",
      "token_endpoint": "https://api.notion.com/v1/oauth/token",
      "token_endpoint_auth": { "type": "none" }
    }
  }
}
```

The `refresh` block is what enables auto-refresh — `token_endpoint` is where the platform posts the `refresh_token` grant. `token_endpoint_auth` is a discriminated union:

| `type` | Shape | Use when |
|---|---|---|
| `"none"` | `{type: "none"}` | Public OAuth client (no secret) |
| `"client_secret_basic"` | `{type: "client_secret_basic", client_secret: "..."}` | Confidential client, secret via HTTP Basic auth |
| `"client_secret_post"` | `{type: "client_secret_post", client_secret: "..."}` | Confidential client, secret in request body |

Omit `refresh` entirely if you only have an access token with no refresh capability — it'll work until it expires, then the agent loses access. A **`static_bearer`** credential (`{type: "static_bearer", token, mcp_server_url}`) is the simpler form for servers that take a long-lived bearer token.

`POST /v1/vaults/{vid}/credentials/{cid}/mcp_oauth_validate` (`orca.vaults.credentials.validate`, `ork agent vaults credentials validate`) is a diagnostic that exercises an `mcp_oauth` credential's refresh flow without waiting for a session to hit it.

**Getting an OAuth token.** The CLI can authorize an MCP server end to end — OAuth discovery, dynamic client registration, PKCE and a loopback browser callback — and store the result straight in the vault; the tokens are never saved locally:

```sh
ork agent vaults credentials create --vault "$VAULT_ID" --mcp-server-url https://mcp.example.com/mcp
```

Add `--no-browser` to print the authorization URL instead (for example over SSH, with `--callback-address` on a forwarded port). Otherwise, obtain the tokens as the MCP server's documentation describes and store them as `auth` JSON. Once stored, the platform auto-refreshes via `refresh.token_endpoint`.

**Environment-variable credential shape**:

```json
{
  "display_name": "Twilio API key for sandbox",
  "auth": {
    "type": "environment_variable",
    "secret_name": "TWILIO_API_KEY",
    "secret_value": "your-secret-here",
    "networking": {
      "type": "limited",
      "allowed_hosts": ["api.twilio.com", "*.twilio.com"]
    }
  }
}
```

`networking.allowed_hosts` controls which outbound hosts the secret can be substituted for — `{"type": "limited", "allowed_hosts": [...]}` or `{"type": "unrestricted"}` if you can't enumerate the domains in advance. Limiting is strongly recommended: it prevents the key from ever being sent to unauthorized hosts.

**`injection_location`** (optional, sibling of `networking`) controls **where** in the outbound request the secret is substituted — `{header: bool, body: bool}`. Most services read an API key from a request header, so header-only is the narrower configuration — request bodies are often assembled from content the agent is working with, making the body the broader exposure surface. At least one location must be enabled; the response echoes both resolved values.

> ⚠️ **Two networking layers, both required.** `networking.allowed_hosts` on the credential controls which requests *use the secret*, not which requests are *allowed*. The agent must also be able to reach the domain at the **environment level** (`unrestricted`, or the host listed in the environment's `allowed_hosts` — see `shared/managed-agents-environments.md`). A domain missing from either layer means the secret-substituted request fails.

> ⚠️ **Client-side validation caveat.** Substitution happens at egress, not inside the sandbox — clients that validate the credential *format* locally before making a network request (e.g. a CLI that checks the key's prefix) will see the opaque placeholder and may fail at startup. If a client rejects the credential before any network call, that's why.

> 💡 **Scope the key minimally.** The agent can do anything the key allows; a key with broader permissions than the task needs increases the blast radius if the agent behaves unexpectedly.

**Constraints (all credential types):**

- **Unique key per vault.** `mcp_server_url` (MCP credentials) and `secret_name` (environment-variable credentials) must be unique among active credentials in a vault; duplicates return a 409.
- **Keys are immutable.** Secret values, `display_name`, and (on environment-variable credentials) `injection_location` can be updated; to change `mcp_server_url`, `secret_name`, `token_endpoint`, or `client_id`, archive the credential and create a new one. Archiving purges the secret and frees the key for a replacement.
- **Maximum 20 active credentials per vault** (409 `credential limit exceeded`).
- Credentials are stored as provided and **not validated until session runtime** (or an explicit `mcp_oauth_validate` call) — an invalid credential surfaces as an auth error during the session rather than blocking session creation.

**Scoping:** Vaults are workspace-scoped. `vault_ids` can be set at session **create** time but not via session update — the update field exists on the wire and every attempt to set it is rejected.

---

## Skills

Skills are reusable, filesystem-based resources that provide your agent with domain-specific expertise: workflows, context, and best practices that transform general-purpose agents into specialists. Unlike prompts (conversation-level instructions for one-off tasks), skills load on-demand and eliminate the need to repeatedly provide the same guidance across multiple conversations.

**How the agent sees them (progressive disclosure):** skill files are mounted read-only in the sandbox, and the system prompt gains an `<available_skills>` catalog listing each skill's name, description, and `SKILL.md` path. The agent `read`s a skill's entrypoint when the task matches — skill instructions are **never concatenated into the system prompt wholesale**. Because loading happens through the `read` tool, an agent with skills must have `read` enabled.

### Creating skills

A skill is a directory whose root `SKILL.md` carries YAML frontmatter with string `name` and `description`, plus any reference files and scripts. Upload the bundle via the Skills API (multipart, ≤30 MiB) — from the CLI:

```bash
ork agent skills create -f SKILL.md -f reference.md --display-title "Financial Analysis"
```

Each upload creates a skill (`skill_...`) with monotonically numbered versions; `ork agent skills versions create <skill-id> -f ...` adds a version to an existing skill.

### Attaching skills to an agent

Skills are attached to the **agent** definition via `agents.create()` (max 500 refs):

<!-- ts-check: reset -->
```ts
const agent = await orca.agents.create({
  name: 'Financial Agent',
  model: 'claude-sonnet-4-6',
  system: 'You are a financial analysis agent.',
  skills: [{ type: 'custom', skill_id: 'skill_01H8...', version: 'latest' }],
});
```

**Skill reference fields:**

| Field | Notes |
|---|---|
| `type` | `"custom"` for skills you uploaded via the Skills API |
| `skill_id` | Skill ID from the Skills API (`skill_...`) |
| `version` | `"latest"` or a specific version ID |

<!-- orca-warn -->
> ⚠️ **`{"type": "anthropic", ...}` references resolve only if your deployment has seeded Anthropic-sourced skills.** The reference form is accepted for Claude compatibility, but a stock Agent Engine deployment does not ship Anthropic's pre-built document skills (`xlsx`, `docx`, `pptx`, `pdf`) — referencing them fails to resolve. Upload the capability you need as a custom skill instead.
<!-- /orca-warn -->

### Skills API

| Operation             | Method   | Path                                            |
| --------------------- | -------- | ----------------------------------------------- |
| Create Skill          | `POST`   | `/v1/skills` (multipart)                        |
| List Skills           | `GET`    | `/v1/skills`                                    |
| Get Skill             | `GET`    | `/v1/skills/{id}`                               |
| Delete Skill          | `DELETE` | `/v1/skills/{id}`                               |
| Create Version        | `POST`   | `/v1/skills/{id}/versions` (multipart)          |
| List Versions         | `GET`    | `/v1/skills/{id}/versions`                      |
| Get Version           | `GET`    | `/v1/skills/{id}/versions/{version}`            |
| Download Version      | `GET`    | `/v1/skills/{id}/versions/{version}/content`    |
| Delete Version        | `DELETE` | `/v1/skills/{id}/versions/{version}`            |

SDK: `orca.skills.{create, list, retrieve, delete}` and `orca.skills.versions.{create, list, retrieve, delete}` (no skill update — upload a new version instead). CLI: `ork agent skills ...` and `ork agent skills versions ...` (incl. `versions content --output-file bundle.zip`).
