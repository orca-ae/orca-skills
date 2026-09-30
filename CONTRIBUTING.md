# Contributing to Orca Agent Skills

Thanks for your interest in Orca Agent Skills, the Agent Skills that teach AI coding agents to build on
[Orca Agent Engine](https://github.com/orca-ae/orca-agent-engine). Corrections, new coverage, and
reports of places where a skill and the engine disagree are all welcome.

> **Using an AI assistant?** Read the [AI policy](AI_POLICY.md) first.
> **Are you a coding agent?** Start with [AGENTS.md](AGENTS.md).

## Ways to contribute

- **Report a skill that's wrong.** If a skill tells an agent to do something the engine, `ork` or
  the TypeScript SDK doesn't do, open an [issue](https://github.com/orca-ae/orca-skills/issues/new/choose)
  with what the skill says and what actually happens.
- **Report a bug in the engine or its tools.** Bugs in Orca Agent Engine, the `ork` CLI and the
  TypeScript SDK belong in the [engine repository](https://github.com/orca-ae/orca-agent-engine/issues/new/choose).
- **Ask a question or share an idea.** Start a [discussion](https://github.com/orca-ae/orca-skills/discussions).
- **Fix something.** Comment on the issue to say you're working on it, so nobody duplicates your
  work.

## Where to talk

| For | Use |
| --- | --- |
| A skill that disagrees with the engine | [Issues](https://github.com/orca-ae/orca-skills/issues) |
| Bugs in the engine, `ork` or the TypeScript SDK | [Engine issues](https://github.com/orca-ae/orca-agent-engine/issues) |
| Questions | [Discussions: Q&A](https://github.com/orca-ae/orca-skills/discussions/categories/q-a) |
| Ideas to discuss before you write them | [Discussions: Ideas](https://github.com/orca-ae/orca-skills/discussions/categories/ideas) |
| Security vulnerabilities | Report privately, as described in [SECURITY.md](SECURITY.md) |
| Conduct concerns | See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |

## Before you write

- **Small, self-contained changes** can go straight to a pull request: a wrong flag, a stale field,
  an example that no longer typechecks, a typo.
- **For anything larger**, open an issue or a discussion first. That includes a new skill, a new
  topic file, a change to a skill's scope, and a change to the verification gates.
- **Every claim needs a source.** A skill documents what Orca Agent Engine serves today, not the
  Anthropic API it is compatible with. Take bindings, flags, field names and event shapes from the
  engine repository, `ork <command> --help`, or the SDK's type definitions;
  [`skills/orca-api/shared/live-sources.md`](skills/orca-api/shared/live-sources.md) gives their
  order of authority.

### When an OIP is needed

Orca Improvement Proposals (OIPs) record decisions that outlive a pull request.

- **Changes to the engine's API or behavior** need an OIP in the
  [engine repository](https://github.com/orca-ae/orca-agent-engine/tree/main/proposals), not here.
- **In this repository**, a new skill, a change to a skill's scope, or a change to how the gates
  verify skills needs an OIP in `proposals/`, numbered per repository and written from the engine's
  [template and process](https://github.com/orca-ae/orca-agent-engine/blob/main/proposals/README.md).
- Corrections, new examples and wording changes don't need one.

## Build and test

You need Node.js 20 or later with npm, `python3`, `jq`, and the `ork` CLI.

```bash
git clone https://github.com/orca-ae/orca-skills.git
cd orca-skills
npm ci --prefix scripts    # the pinned @runorca/orca-sdk, TypeScript and Node types
brew install orca-ae/tap/ork    # or set ORK_BIN to an ork binary
scripts/check-all.sh
```

`scripts/check-all.sh` runs every gate; the [README](README.md#development) says what each one
checks. Keep these conventions in mind when a gate fails:

- **Fix the markdown, never the extracted snippets.** `scripts/.snippets/` is regenerated on every
  run from the fences in the skill files.
- **Directives** tune the checks: `<!-- ts-check: skip -->` or `<!-- ts-check: reset -->` on the
  line before a TypeScript fence, a hidden `<!-- ts-check-context ... -->` block for declarations
  that fences share, and `<!-- cli-check: skip -->` before a shell fence.
- **`<!-- orca-warn -->` markers** exempt the lines between them from `check-skill.sh`. Use them
  only to name an unsupported value in order to warn readers off it.
- **Engine paths.** To check the engine paths the skill cites, run
  `ORCA_ENGINE_DIR=/path/to/orca-agent-engine scripts/check-xrefs.sh`.

### What CI runs

- `ci.yml` runs `scripts/check-all.sh` on every pull request and every push to `main`. It needs no
  secrets, so pull requests from forks run exactly the same checks.
- `engine-refs.yml` checks the engine paths the skill cites against the engine's `main` branch,
  daily and on pull requests that change `live-sources.md`. It isn't a required check: it tells you
  when an engine change has moved a file the skill cites.

## Syncing from upstream

The `orca-api` skill is a port of Anthropic's `claude-api` skill, and [NOTICE](NOTICE) records the
upstream commit it was taken from and the files that were renamed. To take an upstream change:

1. Diff upstream `skills/claude-api/` between the commit that NOTICE pins and the new commit.
2. Apply what still holds for Orca to the matching files here, adjusted to what the engine serves.
3. Run `scripts/check-all.sh`, and move the pinned commit in NOTICE forward in the same pull
   request.

## Style

- Files and commit messages are public. Don't write internal hostnames, private repository names,
  customer names, personal paths, credentials or AI session links into them.
  `scripts/check-hygiene.sh` catches the common cases.
- Use public names: `ork`, `@runorca/orca-sdk`, `orca-ae/orca-agent-engine`. Name the API group
  that only hosted deployments serve "the hosted extension group".
- Mark features that only hosted deployments offer as "hosted only", and give the alternative for
  an engine you run yourself where one exists.

## Commits

### Sign your commits (DCO)

Every commit needs a Developer Certificate of Origin sign-off:

```bash
git commit -s -m "orca-api: correct the stream cursor example"
```

The `-s` flag adds a line such as `Signed-off-by: Your Name <you@example.com>`. The line certifies
that you wrote the change, or otherwise have the right to submit it under the project's license. The
full text is at [developercertificate.org](https://developercertificate.org/).

If you forgot to sign off, fix the last commit with `git commit --amend -s --no-edit`, or a series
with `git rebase --signoff origin/main`, and then force-push your branch.

We don't use a CLA. The DCO sign-off is all we ask.

### Write useful messages

Start the subject with the part you changed (`orca-api:`, `scripts:`, `repo:`), then a short
summary in the imperative mood. In the body, explain why the change is needed and call out any
follow-up work.

Pull requests are squash-merged. The pull request title becomes the commit subject on `main`, so
title your pull request the same way. The squashed commit keeps the `Signed-off-by:` and
`Assisted-by:` trailers of the commits it replaces.

### Say when AI helped

If an AI tool helped meaningfully, add one `Assisted-by:` trailer that names the tool, such as
`Assisted-by: Claude Code`. Don't credit a tool with `Co-authored-by:`, which is for people, and
don't add session links or other trailers that a tool generates. The [AI policy](AI_POLICY.md)
explains what counts.

## Pull requests

1. Fork the repository on GitHub, and add your fork as a remote:
   `git remote add fork https://github.com/<your-username>/orca-skills.git`. Create a branch for
   your change, and push it to `fork`.
2. Keep each pull request to one logical change. Smaller pull requests get reviewed sooner.
3. Fill in the [pull request template](.github/pull_request_template.md): what changed and why,
   the sources behind it, how you checked it, and AI assistance.
4. Make sure CI passes.
5. A code owner reviews and approves the change. Code owners are listed in
   [CODEOWNERS](.github/CODEOWNERS).

If your pull request has been quiet for a while, @-mention one of the maintainers.

## Security issues

Don't report a vulnerability in a public issue, pull request or discussion. Follow
[SECURITY.md](SECURITY.md) instead.

## License

Orca Agent Skills is licensed under the [Apache License 2.0](LICENSE), and so is your contribution.
If you copy material from another project, keep its license header in the file and add the project
to [NOTICE](NOTICE) in the same pull request.
