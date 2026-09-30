# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` is a symlink to this file.

## What this repository is

Agent Skills that teach AI coding agents to build on
[Orca Agent Engine](https://github.com/orca-ae/orca-agent-engine), published as a Claude Code plugin
marketplace. Today it holds one skill, `orca-api`.

| Path | What it is |
| --- | --- |
| `skills/orca-api/SKILL.md` | The skill's router: frontmatter (name, description with TRIGGER/SKIP), then the map of topic files |
| `skills/orca-api/shared/` | Topic files: API, events, tools, environments, the `ork` CLI, ground-truth sources |
| `skills/orca-api/typescript/`, `skills/orca-api/curl/` | Client-specific guides for the TypeScript SDK and raw HTTP |
| `scripts/` | The verification gates; `scripts/check-all.sh` runs them all |
| `.claude-plugin/marketplace.json` | The marketplace manifest that installs the skill |
| `NOTICE` | Provenance: the skill is a port of Anthropic's `claude-api` skill |

## Rules

1. **Every claim comes from a source.** Method names, flags, field names and event shapes come from
   the engine repository, `ork <command> --help`, or the type definitions in `@runorca/orca-sdk`,
   in the order `skills/orca-api/shared/live-sources.md` gives. Never extrapolate from Anthropic's
   API or SDKs: the engine is compatible with them, not identical, and the skill documents where
   they differ.
2. **Run `scripts/check-all.sh` before every commit**, and read its output. Setup is in
   [CONTRIBUTING.md](CONTRIBUTING.md#build-and-test).
3. **Fix the markdown, never the extracted snippets.** `scripts/.snippets/` is regenerated from the
   fences in the skill files on every run.
4. **`<!-- orca-warn -->` markers** exempt their lines from `check-skill.sh`. Use them only to name an
   unsupported value in order to warn readers off it, never to silence a wrong claim.
5. **Public names only.** The CLI is `ork`, the SDK is `@runorca/orca-sdk`, and the engine
   repository is `orca-ae/orca-agent-engine`. Don't write internal hostnames, private repository
   names, personal paths or AI session links. Call the API group that only hosted deployments serve
   "the hosted extension group", and mark hosted-only features as such.
6. **Keep the router small.** The `SKILL.md` description stays within 1024 characters
   (`check-xrefs.sh` enforces it), and topic detail belongs in `shared/`, not in `SKILL.md`.
7. **Record provenance.** If you copy material from another project, keep its license header and
   add it to `NOTICE` in the same change. When you take an upstream change from Anthropic's
   `claude-api` skill, follow [Syncing from upstream](CONTRIBUTING.md#syncing-from-upstream).

## Commits and outward actions

- Subjects start with the part you changed: `orca-api: ...`, `scripts: ...`, `repo: ...`.
- Add one `Assisted-by:` trailer that names the tool (`.claude/settings.json` does this for Claude
  Code). Never add `Signed-off-by`: only the human who reviewed the change signs off. Never credit a
  tool with `Co-authored-by:`, and never add session links.
- A human approves every outward action. Don't push, open or update a pull request or issue, or
  post a comment, unless the human has approved that specific action. See the
  [AI policy](AI_POLICY.md).
