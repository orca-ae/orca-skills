#!/usr/bin/env bash
# Copyright The Orca Authors
# SPDX-License-Identifier: Apache-2.0
#
# Grep gate for the orca-api skill, which is a port of Anthropic's claude-api skill.
#
# Every pattern here is something a careful writer still emits by copying upstream:
# Anthropic's hostnames, headers, prices and CLI/SDK shapes, plus values Orca's
# registry accepts but its harness ignores. Catching them mechanically beats any
# prose rule, because the wrong version always looks plausible.
#
#   check-skill.sh [path ...]     default: skills/orca-api
#
# Exit 0 clean, 1 on any hit, 2 on usage error. Lines between the sentinels
# `<!-- orca-warn -->` and `<!-- /orca-warn -->` are exempt: naming an
# unsupported value in order to warn readers off it is the point.
#
# POSIX grep/awk only - no ripgrep, no PCRE. Patterns are ERE, so no \b.
#
# `x-api-key` is deliberately NOT flagged. It looks like an Anthropic header, and
# it is, but Orca's registry adopted it on purpose: it is the only header that
# carries a workspace API key, and a present x-api-key is the authoritative
# credential (services/registry-service-ts/src/auth/api-key.ts in
# orca-ae/orca-agent-engine), so documenting it is correct. `Authorization: Bearer`
# carries OIDC access tokens only.
#
# CLI rows carry a left boundary so that words ending in "ork" ("network",
# "work") never match. Names, links and vendor strings are check-hygiene.sh's job.
#
# Allowed model ids in examples: claude-sonnet-4-6 (primary), claude-haiku-4-5
# (cheap multiagent worker), claude-opus-5 / claude-opus-4-8 (only as the
# fast-mode constraint facts). Everything else claude-* is flagged.

set -uo pipefail
export LC_ALL=C   # byte semantics: the 96-char report truncation may split a UTF-8 char

cd "$(dirname "$0")/.." || exit 2

targets=("${@:-skills/orca-api}")
for t in "${targets[@]}"; do
  [[ -e "$t" ]] || { echo "check-skill.sh: no such path: $t" >&2; exit 2; }
done

files=$(find "${targets[@]}" -type f -name '*.md' 2>/dev/null | sort)
[[ -z "$files" ]] && { echo "check-skill.sh: no .md files under ${targets[*]}" >&2; exit 2; }

patfile=$(mktemp) || exit 2
trap 'rm -f "$patfile"' EXIT

# label <TAB> ERE pattern
cat >"$patfile" <<'PATTERNS'
anthropic endpoint	api\.anthropic\.com
anthropic console/docs url	platform\.claude\.com|console\.anthropic\.com
anthropic header/env	anthropic-version|ANTHROPIC_[A-Z_]+
anthropic beta value	managed-agents-2026-04-01|skills-2025-10-02|files-api-2025-04-14|oauth-2025-04-20
anthropic key/secret format	sk-ant-|whsec_
anthropic CLI	(^|[ `(|])ant [a-z]|ant beta:
anthropic SDK	client\.beta\.|await client\.|@anthropic-ai/
ant-only output flags	--transform|--format[ =]
absent endpoint	/v1/(deployments|deployment_runs|dreams|tunnels|user_profiles|messages|complete|models)
webhooks are absent	[Ww]ebhook
advisor type does not exist	advisor([^y]|$)
sdk has no .tools	orca\.tools
sdk has no .mcpServers	orca\.mcpServers
sdk has no .permissionPolicies	orca\.permissionPolicies
sdk has no .github	orca\.github
sdk has no .runs	orca\.runs
sdk uses .memoryStores	orca\.memory\.
sdk triggers are core	orca\.cloud\.triggers
sdk has no .agents.delete	orca\.agents\.delete
sdk cloud APIs stay under .cloud	orca\.(deployments|deploymentRuns|agents\.providers)
sdk has no worker helpers	EnvironmentWorker|WorkPoller|betaAgentToolset
cli nests under 'ork agent'	(^|[^A-Za-z0-9_.-])ork (tools?|vaults?|sessions?|skills?|triggers?|environments?|files?|memory-stores?|memory-versions?|providers?)[ `'"]
cli has no login/profile	(^|[^A-Za-z0-9_.-])ork (login|logout|profile|auth)[ `'"]
cli has no mcp/policy/github cmd	(^|[^A-Za-z0-9_.-])ork (mcp|policy|github)[ `'"]
mcp accepts type url only	type["']?[ ]*[:=][ ]*["']?(sse|stdio|streamable_http|http)["',]
policy not settable via API	always_deny
tool never reaches the model	web_(fetch|search)
skills type anthropic needs seeding	type["']?[ ]*[:=][ ]*["']anthropic["']
checkout object, not branch key	["' ]branch["']?[ ]*:
url must be host root	ORCA_(BASE|REGISTRY)_URL=[^ ]*/(v1|api)
cloud dialect path	v1/registry
removed cloud trigger endpoint	/apis/cloud\.sn\.io/v1/agenttriggers
removed trigger field	agent_ref
removed trigger lifecycle	(^|[^A-Za-z0-9_.-])ork agent triggers (start|stop|restart)|orca\.triggers\.(start|stop|restart)|orca\.cloud\.triggers\.(start|stop|restart)
removed trigger status	NonReady|Ready[ ]*\|[ ]*NonReady
sse cursor is not event id	from_cursor=<event-id>|--from-cursor <event-id>|lastEventId|from_cursor[ ]*:[ ]*event\.id
cli stream event is nested	if \.type == "session\.status_idle"|select\(\.type == "agent\.message"\)|jq -r '\.type\?
pricing does not belong here	\$[0-9]+\.[0-9]+|\$[0-9]+[ ]*/|MTok|per million|per 1,?000
model id not in allow-list	claude-(fable|mythos|sonnet-5|sonnet-4-5|opus-4-[0-7]|opus-3|sonnet-3|haiku-3|3-)
dated model snapshot	claude-[a-z0-9-]+-2[0-9]{7}
inference geo is absent	inference_geo|allowed_inference_geos
say hosted, not managed	[Mm]anaged (Pulsar|Kafka|source|[Tt]riggers?|adapters?|deployments?|extensions?)
dropped file reference	managed-agents-(webhooks|scheduled-deployments|self-hosted-sandboxes)\.md|anthropic-cli\.md
upstream-only shared file	(model-migration|prompt-audit|tool-use-concepts|prompt-caching|claude-platform-on-aws|platform-availability|token-counting|error-codes|agent-design)\.md
PATTERNS

# shellcheck disable=SC2086 # $files is the newline-delimited find result; paths are repo-controlled.
report=$(awk -v pfile="$patfile" '
  BEGIN {
    n = 0
    while ((getline line < pfile) > 0) {
      if (line == "") continue
      i = index(line, "\t")
      lab[++n] = substr(line, 1, i - 1)
      pat[n]   = substr(line, i + 1)
    }
  }
  FNR == 1 { inwarn = 0; infm = ($0 == "---") ? 1 : 0; if (infm) next }
  infm { if ($0 == "---") infm = 0; next }   # YAML frontmatter (SKILL.md TRIGGER/SKIP legitimately names upstream)
  /<!-- orca-warn -->/ { inwarn = 1; next }
  /<!-- \/orca-warn -->/ { inwarn = 0; next }
  inwarn { next }
  {
    for (j = 1; j <= n; j++)
      if ($0 ~ pat[j]) {
        line = $0
        sub(/^[ \t]+/, "", line)
        if (length(line) > 96) line = substr(line, 1, 96) "..."
        printf "  [%s]\n    %s:%d: %s\n", lab[j], FILENAME, FNR, line
      }
  }
' $files) || { echo "check-skill.sh: awk failed; check the pattern list" >&2; exit 2; }

# Polarity-aware prose checks. A raw keyword regex would reject correct
# warnings such as "without a cursor does not replay" and miss case changes.
# shellcheck disable=SC2086 # same repo-controlled file list as the pattern pass above.
semantic_report=$(awk '
  FNR == 1 { inwarn = 0; infm = ($0 == "---") ? 1 : 0; if (infm) next }
  infm { if ($0 == "---") infm = 0; next }
  /<!-- orca-warn -->/ { inwarn = 1; next }
  /<!-- \/orca-warn -->/ { inwarn = 0; next }
  inwarn { next }
  {
    lower = tolower($0)
    stale_no_cursor = 0
    stale_after = 0
    nclauses = split(lower, clauses, /[.;]/)
    for (k = 1; k <= nclauses; k++) {
      clause = clauses[k]
      no_cursor = clause ~ /(empty[- ]cursor|no cursor|without a cursor|opened without a cursor)/
      replay = clause ~ /replay/
      replay_negated = clause ~ /(does not|doesn.t|do not|never|not)[^:]*replay/ || clause ~ /replay[^:]*(does not|doesn.t|not)/
      if (no_cursor && replay && !replay_negated) stale_no_cursor = 1

      cursor_resume = clause ~ /(cursor|from_cursor)/ && clause ~ /(resume|replay)/
      strict_after = clause ~ /(exactly|strictly)[ -]*after/
      after_negated = clause ~ /(does not|doesn.t|not)[^:]*(resume|replay|exactly|strictly)/ || clause ~ /(rather than|instead of)[^:]*exactly[ -]*after/
      if (cursor_resume && strict_after && !after_negated) stale_after = 1
    }

    if (stale_no_cursor) {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (length(line) > 96) line = substr(line, 1, 96) "..."
      printf "  [sse empty cursor is from-now]\n    %s:%d: %s\n", FILENAME, FNR, line
    }
    if (stale_after) {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (length(line) > 96) line = substr(line, 1, 96) "..."
      printf "  [sse explicit cursor is inclusive]\n    %s:%d: %s\n", FILENAME, FNR, line
    }
  }
' $files) || { echo "check-skill.sh: awk failed in the prose checks" >&2; exit 2; }

if [[ -n "$semantic_report" ]]; then
  report="${report}${report:+$'\n'}${semantic_report}"
fi

if [[ -n "$report" ]]; then
  printf '\ncheck-skill.sh found claims that do not match Orca:\n\n%s\n\n' "$report"
  printf 'Each hit is either wrong, or belongs between <!-- orca-warn --> markers.\n'
  printf 'Verify against the engine repo, orca-ae/orca-agent-engine (conformance matrix,\n'
  printf 'registry contracts, harness), `ork <command> --help`, and the type definitions\n'
  printf 'in @runorca/orca-sdk. shared/live-sources.md lists the exact paths.\n\n'
  exit 1
fi

echo "check-skill.sh: clean ($(wc -l <<<"$files" | tr -d ' ') files under ${targets[*]})"
