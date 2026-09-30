#!/usr/bin/env bash
# Copyright The Orca Authors
# SPDX-License-Identifier: Apache-2.0
#
# Cross-reference and structure integrity for the orca-api skill.
#
#   check-xrefs.sh            (no arguments; always checks skills/orca-api)
#
# Five checks:
#   1. Every skill-file path mentioned in prose (shared/x.md, typescript/.../README.md,
#      curl/x.md) exists on disk.
#   2. Every .md file on disk (except SKILL.md) is referenced from at least one
#      other file - orphans are invisible to a reader following the router.
#   3. SKILL.md opens with frontmatter carrying name: and description:, the
#      description fits the 1024-character cap, and no other .md file carries
#      frontmatter (upstream convention).
#   4. The marketplace manifest has the published shape and identity.
#   5. Ground-truth paths the skill cites exist:
#      - `orca-agent-engine/<path>` against a checkout of github.com/orca-ae/orca-agent-engine
#        named by ORCA_ENGINE_DIR (skipped when unset)
#      - `@runorca/orca-sdk/<path>` against the package that
#        `npm ci --prefix scripts` installs (skipped when absent)
#      ORCA_REQUIRE_LIVE_SOURCES=1 turns either skip into a failure.
#
# Exit 0 clean, 1 on any failure, 2 on setup errors.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 2
root=skills/orca-api
[[ -d "$root" ]] || { echo "check-xrefs.sh: no $root directory" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "check-xrefs.sh: jq is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "check-xrefs.sh: python3 is required" >&2; exit 2; }

fail=0

# --- 1. referenced paths exist ------------------------------------------------
refs=$(grep -RhoE '(^|[^A-Za-z0-9_-])(shared|typescript|curl)/[A-Za-z0-9_./-]+\.md' "$root" \
  | sed -E 's/^[^A-Za-z0-9_-]//' | sort -u)
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  if [[ ! -f "$root/$ref" ]]; then
    echo "MISSING: referenced path does not exist: $ref"
    grep -RnF "$ref" "$root" | head -3 | sed 's/^/    /'
    fail=1
  fi
done <<<"$refs"

# --- 2. no orphan files -------------------------------------------------------
while IFS= read -r f; do
  rel=${f#"$root"/}
  [[ "$rel" == "SKILL.md" ]] && continue
  base=$(basename "$f")
  if ! grep -RqF "$base" --include='*.md' "$root" --exclude-dir="$(dirname "$rel")" 2>/dev/null; then
    # search all files except the file itself
    hits=$(grep -RlF "$base" --include='*.md' "$root" | grep -vF "$f" || true)
    if [[ -z "$hits" ]]; then
      echo "ORPHAN: $rel is never referenced by another skill file"
      fail=1
    fi
  fi
done < <(find "$root" -type f -name '*.md' | sort)

# --- 3. frontmatter -----------------------------------------------------------
if [[ "$(head -1 "$root/SKILL.md")" != "---" ]]; then
  echo "FRONTMATTER: SKILL.md does not open with ---"
  fail=1
else
  fm=$(awk 'NR==1{next} /^---$/{exit} {print}' "$root/SKILL.md")
  grep -q '^name:' <<<"$fm" || { echo "FRONTMATTER: SKILL.md missing name:"; fail=1; }
  grep -q '^description:' <<<"$fm" || { echo "FRONTMATTER: SKILL.md missing description:"; fail=1; }
  # The Agent Skills spec caps description at 1024 characters (characters, not bytes).
  # The parser exits non-zero when it can't measure, so a malformed frontmatter fails
  # this check instead of slipping past it.
  desc_len=$(python3 - "$root/SKILL.md" <<'PY'
import re
import sys

lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
try:
    end = lines.index("---", 1)
except ValueError:
    sys.exit("frontmatter has no closing ---")
fm = lines[1:end]
# A missing closing marker makes the frontmatter run on to a horizontal rule in
# the body, so every line must look like YAML: a top-level key, an indented
# continuation, a comment, or blank.
for n, line in enumerate(fm, start=2):
    if line and not re.match(r"[A-Za-z0-9_-]+:( |$)|[ \t]|#", line):
        sys.exit(f"frontmatter line {n} is not YAML (is the closing --- missing?)")
for i, line in enumerate(fm):
    if not line.startswith("description:"):
        continue
    value = line[len("description:"):].strip()
    rest = []
    for nxt in fm[i + 1:]:
        if nxt and not nxt.startswith((" ", "\t")):
            break
        rest.append(nxt.strip())
    if re.fullmatch(r"[|>][+-]?[1-9]?", value):  # block scalar: |, |-, |+, >2, ...
        joiner = "\n" if value.startswith("|") else " "
        value = joiner.join(rest).strip("\n")
    elif rest:  # plain scalar continued on indented lines
        value = " ".join([value] + [r for r in rest if r])
    print(len(value))
    sys.exit(0)
sys.exit("frontmatter has no description: key")
PY
) || desc_len=""
  if ! [[ "$desc_len" =~ ^[0-9]+$ ]]; then
    echo "FRONTMATTER: could not measure the SKILL.md description"
    fail=1
  elif [[ "$desc_len" -gt 1024 ]]; then
    echo "FRONTMATTER: SKILL.md description is $desc_len characters (cap 1024)"
    fail=1
  fi
fi
while IFS= read -r f; do
  [[ "$f" == "$root/SKILL.md" ]] && continue
  if [[ "$(head -1 "$f")" == "---" ]]; then
    echo "FRONTMATTER: ${f#"$root"/} carries frontmatter but only SKILL.md should"
    fail=1
  fi
done < <(find "$root" -type f -name '*.md' | sort)

# --- 4. manifest --------------------------------------------------------------
jq -e '
  .name == "orca-skills"
  and (.owner.name | type == "string")
  and (.owner.email | test("@runorca\\.ai$"))
  and (.plugins | length == 1)
  and .plugins[0].name == "orca-api"
  and .plugins[0].skills == ["./skills/orca-api"]
  and .plugins[0].license == "Apache-2.0"
  and (.plugins[0].homepage | startswith("https://"))
  and (.plugins[0].repository | startswith("https://github.com/orca-ae/"))
' .claude-plugin/marketplace.json >/dev/null \
  || { echo "MANIFEST: marketplace.json shape or identity unexpected"; fail=1; }

# --- 5. ground-truth paths ----------------------------------------------------
require_live_sources="${ORCA_REQUIRE_LIVE_SOURCES:-0}"
engine_dir="${ORCA_ENGINE_DIR:-}"
sdk_dir=scripts/node_modules/@runorca/orca-sdk
checked=0
skipped=""

if [[ -n "$engine_dir" && ! -d "$engine_dir" ]]; then
  echo "check-xrefs.sh: ORCA_ENGINE_DIR points to a missing checkout: $engine_dir" >&2
  exit 2
fi
if [[ "$require_live_sources" == "1" ]]; then
  [[ -n "$engine_dir" ]] || { echo "check-xrefs.sh: ORCA_REQUIRE_LIVE_SOURCES=1 needs ORCA_ENGINE_DIR" >&2; exit 2; }
  [[ -e "$sdk_dir/package.json" ]] || { echo "check-xrefs.sh: ORCA_REQUIRE_LIVE_SOURCES=1 needs npm ci --prefix scripts" >&2; exit 2; }
fi
[[ -n "$engine_dir" ]] || skipped="$skipped orca-agent-engine"
[[ -e "$sdk_dir/package.json" ]] || skipped="$skipped @runorca/orca-sdk"

# shellcheck disable=SC2016 # backticks are Markdown delimiters in the regex below.
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  case "$ref" in
    orca-agent-engine/*) base=$engine_dir; rel=${ref#orca-agent-engine/} ;;
    @runorca/orca-sdk/*) base=$sdk_dir; rel=${ref#@runorca/orca-sdk/}
                         [[ -e "$sdk_dir/package.json" ]] || continue ;;
    *) continue ;;
  esac
  [[ -n "$base" ]] || continue
  checked=$((checked + 1))
  if [[ ! -e "$base/$rel" ]]; then
    echo "MISSING SOURCE: $ref (expected $base/$rel)"
    grep -RnF "$ref" "$root" | head -2 | sed 's/^/    /'
    fail=1
  fi
done < <(grep -RhoE '`(orca-agent-engine|@runorca/orca-sdk)/[^` ]+`' "$root" | tr -d '`' | sort -u)

if [[ $fail -eq 0 ]]; then
  if [[ -n "$skipped" ]]; then
    echo "check-xrefs.sh: skipped unavailable sources:${skipped}"
  fi
  echo "check-xrefs.sh: clean ($checked source paths checked)"
else
  exit 1
fi
