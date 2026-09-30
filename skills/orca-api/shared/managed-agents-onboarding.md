# Orca Agent Engine — Onboarding Flow

> **Invoked via `/orca-api managed-agents-onboard`?** You're in the right place. Run the interview below — don't summarize it back to the user, ask the questions.

Orca Agent Engine is an open-source managed-agents engine, run by you or by a hosted deployment: it runs the agent loop and provisions a sandboxed container per session where the agent's tools execute (or runs the loop and its tools on your own infrastructure with a `self_hosted` environment — see `shared/managed-agents-environments.md`). You supply an **agent config** (tools, skills, model, system prompt — reusable, versioned) and an **environment config** (the sandbox — reusable across agents). Each run is a **session**.

The flow is four beats — **describe → agent → environment → session** — with one philosophy: **value before credentials**. The user goes from idea to a runnable session before any auth ask; each credential is *flagged* at the moment the design makes it relevant (§2) and *collected* once, at session setup (§4), where it binds (`sessions.create()`) and gets exercised (smoke-test). Read `shared/managed-agents-core.md` alongside this — it has full detail for each knob; this doc is the interview script.

---

## 1. Describe the task

**Open with a one-breath signpost and a single open prompt — don't guess, don't questionnaire.** In your own words:

> Agent Engine runs the agent loop and the sandbox for you, server-side; you just define the agent. We'll do this in three moves: the agent, the environment it runs in, then a live test session. So: describe the agent you want — what should it do, and what kicks it off (a person, an event, a schedule)?

Let them answer in full before configuring anything.

## 2. Configure the agent — propose, don't interrogate

Their description does the interview's work. Draft the agent config from it and **present it as a proposal with your suggestions inline** — the user reacts to a concrete config instead of answering a question list. At most one batched follow-up for true gaps. Suggest where the description gives you an opening:

- **Tools** — enable the built-in toolset by default (`agent_toolset`: `bash`, `read`, `write`, `edit`, `glob`, `grep`, plus Orca's `list`/`delete`). **There is no built-in web access** — if the job needs to search or fetch the web, that reach comes through an MCP server; say so while proposing. **Suggest MCP servers** for any third-party service the job names (GitHub, Linear, Slack, …) — and flag the credential each one implies as you suggest it ("Linear MCP → you'll need its OAuth credential in a vault at kickoff"), so §4's auth step is a formality, not a surprise. Collection itself waits for §4. Custom tools only if the user's own app must answer calls (name, description, input schema — their handler code is theirs; don't generate it).
- **Skills** — suggest a **custom skill upload** when the job has house rules or a repeatable procedure worth packaging (`shared/managed-agents-tools.md` → Skills); reference by `skill_id` after upload. Don't propose Anthropic's pre-built document skills — stock deployments don't ship them.
- **Outcome** — if the description implies checkable "done" criteria (or you can elicit them in the follow-up: not "a good report" but "a CSV with a numeric `price` column per SKU"), **suggest an outcome kickoff** — a grader scores each turn against the rubric and your runtime reads the verdicts (`shared/managed-agents-outcomes.md`; verdicts are advisory — the client decides whether to push for revision).
- **On-hand resources** — repos to mount (`github_repository`: URL, optional `mount_path`; token comes in §4), files to seed (Files API upload → `{type: "file", file_id, mount_path}`; read-only), if the job references them.
- **Model** — default `claude-sonnet-4-6` (any model your deployment's catalog serves works; `effort`/`speed` are validated per model).

> ‼️ **PR creation needs the GitHub MCP server too** — a `github_repository` mount is filesystem-only. Edit in the mount → push branch via `bash` → open the PR via the MCP `create_pull_request` tool.

Full detail per knob: `shared/managed-agents-tools.md` (toolset, MCP, custom tools, skills), `shared/managed-agents-environments.md` (repos, files).

## 3. Environment

Usually zero or one question:

- **Reuse or create?** Environments are shared across agents — check for an existing one first.
- **Networking** — default unrestricted egress. Switch to `limited` only if the user wants egress control — then set `allow_mcp_servers: true` or list every MCP server domain in `allowed_hosts`, or those tools fail.
- **Suggest `self_hosted`** only when the signals are there: tools must run on their own infra, secrets can't leave it, or they need binaries/data the platform container won't have (`shared/managed-agents-environments.md` → Self-hosted environments; setup is deployment-specific). Otherwise `cloud` — don't raise it unprompted for simple jobs.

## 4. Session — auth, then test run

**No deployment to run against yet?** `ork local start` runs an engine on the user's machine with Docker and prints its URL and the path to its workspace key — see `shared/orca-cli.md` → A local engine.

**Auth happens here — collect the credentials flagged in §2, now that the config is settled:** a vault (existing or `vaults.create()`) + `vaults.credentials.create()` for each MCP server declared in §2, `environment_variable` credentials for API keys the job uses (substituted at egress; the sandbox sees a placeholder), and the `authorization_token` for each repo mount. Credentials are write-only; MCP credentials match servers by URL and auto-refresh. See `shared/managed-agents-tools.md` → Vaults.

**Silent viability gate — run this yourself before emitting anything; surface only the gaps.** Walk the job clause by clause: every verb maps to an enabled tool or MCP server ("open a PR" → GitHub MCP, not just the mount; "search the web" → an MCP server, not a built-in); every MCP server and repo mount has its credential from the auth step; every external host is reachable under the networking choice; every file/repo/dataset the job references is mounted; "done" is checkable. If something's missing, say so and resolve it — don't emit a config you already know is under-resourced.

**Kickoff — pick one, never both:**
- `user.message` — conversational.
- `user.define_outcome` + rubric — when §2 settled on an outcome; the grader scores each turn and the runtime reads the verdicts.
- **Scheduled or event-driven shape?** Skip per-session kickoff entirely — create an **Agent Trigger**. Core `/v1/triggers` supports cron on every deployment; hosted deployments widen the same resource with Pulsar/Kafka sources and additional session modes. Do not gate it on `GET /apis`; propose only capabilities the target deployment serves, and fall back to a client-side scheduler around `sessions.create` when it rejects the requested source. See `shared/managed-agents-triggers.md`.

Mechanics to bake into the runtime code: session creation resolves resources (a bad mount surfaces there, before tokens) but does not itself provision the sandbox; open the long-lived event stream before sending work because an empty cursor follows from the current head; break on `session.status_idle` with any non-`requires_action` `stop_reason` (`shared/managed-agents-client-patterns.md` Pattern 5); usage lands on `span.model_request_end`; artifacts land in `/mnt/session/outputs/` (`orca.sessions.files.list(session.id)`). For recovery, follow `shared/managed-agents-events.md` — replay uses the SSE frame cursor, not the event payload ID.

## 5. Integrate — emit the code

Go straight from the last answer to the code — no preamble, no lecture about setup-vs-runtime; the two-block structure shows it. Generate **two clearly-separated blocks**:

**Block 1 — Setup (run once, store the IDs).** A version-controlled shell script driving the **`ork` CLI**, with structured payloads in committed JSON files (there is no YAML apply — see `shared/orca-cli.md` → Version-controlled setup):

```sh
ENV_ID=$(ork agent environments create --name my-env -o json | jq -r .id)
AGENT_ID=$(ork agent create --name my-agent --model claude-sonnet-4-6 \
  --system "$(cat prompts/system.txt)" \
  --tool-json "$(cat agent/tools.json)" -o json | jq -r .id)
# CI sync: ork agent update "$AGENT_ID" --version N --system "$(cat prompts/system.txt)"
```

SDK fallback if the user asks: label it `// ONE-TIME SETUP — run once, save the IDs` and call `environments.create()` → `agents.create()`.

**Scheduled shape? The trigger is setup, not runtime.** Create it in Block 1, after the agent/environment IDs exist (`ork agent triggers create ...` or `orca.triggers.create(...)`). Block 2 is then **not** a session loop — there is no per-run kickoff to send. Emit instead a fetch helper: `orca.triggers.sessions.list(triggerId)` → latest session → stream its events and list its output files.

**Block 2 — Runtime (every invocation; conversational and outcome shapes).** TypeScript SDK code (raw HTTP callers: `curl/managed-agents.md`); don't emit shell loops here:

1. Load `agent_id` + `env_id` from config/env
2. `orca.sessions.create({agent: AGENT_ID, environment_id: ENV_ID, resources: [...], vault_ids: [...]})`
3. **Smoke-test when the job depends on MCP servers, credentials, or locked-down hosts** — those failures don't surface at `sessions.create()`, only on first use. One cheap probe turn ("Confirm you can reach <service> and list 1–2 items; don't start the task"), verify, then send the real kickoff. Skip when there are no external dependencies.
4. Open the stream → send the §4 kickoff → loop with the terminal gate from §4.

> ⚠️ **Never emit `agents.create()` and `sessions.create()` in the same unguarded block** — that teaches creating a new agent per run, the #1 anti-pattern. Single-script requests: wrap creation in `if (!process.env['ORCA_AGENT_ID']) { ... }`.

Pull exact syntax from `typescript/managed-agents/README.md` (SDK), `shared/orca-cli.md` (CLI), or `curl/managed-agents.md` (raw HTTP). Don't invent field names.
