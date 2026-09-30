# Orca Agent Skills

Agent Skills for building on [Orca Agent Engine](https://github.com/orca-ae/orca-agent-engine), the open-source runtime for managed AI agents. The engine's registry API is compatible with Anthropic's Managed Agents API.

## Skills

| Skill | Description |
|---|---|
| [`orca-api`](./skills/orca-api/SKILL.md) | Teaches an AI coding agent how to work with the Agent Engine registry API, the `ork` CLI, and the `@runorca/orca-sdk` TypeScript SDK: the resource model (agents, sessions, environments, files, skills, vaults, memory stores, triggers), authentication, events and streaming, pagination, and the error model. |

## Quick start

In Claude Code, add this repository as a plugin marketplace and install the skill:

```
/plugin marketplace add orca-ae/orca-skills
/plugin install orca-api@orca-skills
```

For a local checkout, use the path form instead:

```
/plugin marketplace add /path/to/orca-skills
```

Then describe what you want to build, for example "set up an Orca agent that triages new GitHub issues". The skill loads when a prompt or project mentions Orca, Agent Engine, `ork`, `@runorca/orca-sdk`, or the `ORCA_*` variables. Other agents that read the Agent Skills format can load [`skills/orca-api`](./skills/orca-api) directly.

What the skill's code needs at run time:

- **An Agent Engine deployment.** `ork local start` runs one on your machine with Docker. Export your model provider's key before you start it — `ANTHROPIC_API_KEY` for the Claude models the skill defaults to, `OPENAI_API_KEY` for OpenAI models — or the first session fails to authenticate. The engine's [quick start](https://github.com/orca-ae/orca-agent-engine#quick-start) covers the other ways to run it, or use a hosted deployment.
- **The `ork` CLI** for setup scripts and CI: `brew install orca-ae/tap/ork`.
- **The TypeScript SDK** for application code: `npm install @runorca/orca-sdk`.

## Documentation

- [Engine documentation](https://github.com/orca-ae/orca-agent-engine/tree/main/docs), including [which engine, `ork`, and SDK versions work together](https://github.com/orca-ae/orca-agent-engine/blob/main/docs/compatibility.md)
- [Cookbooks](https://github.com/orca-ae/orca-cookbooks): complete programs that run end to end
- [runorca.ai](https://runorca.ai)

## Where to talk

- **Questions and ideas:** [Discussions](https://github.com/orca-ae/orca-skills/discussions) in this repository.
- **The skill says something the engine doesn't do:** open an [issue](https://github.com/orca-ae/orca-skills/issues) here.
- **Bugs in the engine, `ork`, or the TypeScript SDK:** open an issue on the [engine repository](https://github.com/orca-ae/orca-agent-engine/issues).
- **Security problems:** report them privately, as [SECURITY.md](SECURITY.md) describes, never in a public issue.

## Development

[CONTRIBUTING.md](CONTRIBUTING.md) covers the workflow: DCO sign-off, no CLA, and how to disclose AI assistance under the [AI policy](AI_POLICY.md). The verification gates run against published artifacts only:

```bash
npm ci --prefix scripts    # the pinned SDK, TypeScript and Node types
brew install orca-ae/tap/ork    # or set ORK_BIN to an ork binary
scripts/check-all.sh            # every gate; run it before each commit
```

| Gate | What it checks |
|---|---|
| `scripts/check-hygiene.sh` | names and links across the whole tree: renamed tools, private repositories, personal paths |
| `scripts/check-skill.sh` | skill claims that don't match Orca: upstream-only surfaces, absent endpoints, wrong CLI shapes |
| `scripts/check-ts-snippets.sh` | typechecks every TypeScript example against the published `@runorca/orca-sdk` |
| `scripts/check-cli-commands.sh` | every documented `ork` command and flag against `ork --help`, and the stream output shape |
| `scripts/check-xrefs.sh` | cross-references, frontmatter, the manifest, and the engine and SDK paths the skill cites |
| `scripts/check-license-headers.mjs` | the license header on every script and workflow (`--fix` adds it) |

The gates need Node.js 20 or newer with npm, `ork`, `python3` (for a local SSE fixture server), and `jq`. To check the engine paths the skill cites, point `ORCA_ENGINE_DIR` at a clone of `orca-ae/orca-agent-engine`; `ORCA_REQUIRE_LIVE_SOURCES=1` turns a missing clone or SDK install into a failure.

## License and attribution

Apache License 2.0 — see [LICENSE](./LICENSE) and [NOTICE](./NOTICE).

The `orca-api` skill is a derivative of the `claude-api` skill from [anthropics/skills](https://github.com/anthropics/skills), Copyright 2026 Anthropic, PBC, used under the Apache License 2.0 (retained at [`skills/orca-api/LICENSE.txt`](./skills/orca-api/LICENSE.txt)). The files have been modified to target Orca Agent Engine, the `ork` CLI, and the `@runorca/orca-sdk` TypeScript SDK.
