#!/usr/bin/env bash
# Copyright The Orca Authors
# SPDX-License-Identifier: Apache-2.0
#
# Name and link hygiene for everything this repository publishes.
#
#   check-hygiene.sh              (no arguments; scans the whole tree)
#
# check-skill.sh judges what the skill claims. This gate judges names and
# links, in every tracked and untracked-but-not-ignored file: frontmatter and
# orca-warn blocks included, and the README, scripts, workflows and manifest
# too. It flags names that changed before launch, links into repositories that
# aren't public, personal paths, and vendor names.
#
# Attribution files (NOTICE, LICENSE*) are exempt: they must name third parties
# exactly as those parties do. Every pattern is written so that it doesn't match
# its own text, which lets this file pass its own scan.
#
# POSIX awk and ERE. Each line is padded with one space on both sides, so a
# pattern can require a non-name character around a word without alternating
# on ^ or $ (BSD grep mishandles that shape).
#
# Exit 0 clean, 1 on any hit, 2 on usage error.

set -uo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.." || exit 2

patfile=$(mktemp) || exit 2
listfile=$(mktemp) || { rm -f "$patfile"; exit 2; }
trap 'rm -f "$patfile" "$listfile"' EXIT

# label <TAB> ERE pattern
cat >"$patfile" <<'PATTERNS'
the CLI binary is ork	[^A-Za-z0-9_.-]orca([)`]| (agent|agents|healthz|readyz|login|logout|profile|auth|sessions?|vaults?|version|completion|local|workspace|CLI|<|--[a-z]|-o ))
the SDK package is @runorca/orca-sdk	@orca-ae/orca-sd[k]
the SDK is on npmjs, not GitHub Packages	npm\.pkg\.github\.co[m]
the CLI source is not public	github\.com/orca-ae/orca-cl[i]|[^A-Za-z0-9_.:/-]orca-cl[i]/
the engine repo is orca-ae/orca-agent-engine	orca-managed-agent[s]
the TypeScript SDK source is not public	orca-sdk-typescrip[t]
the install path is orca-ae/orca-skills	orca-ae/skill[s][^A-Za-z0-9_-]
personal path	~/Workspace[s]|/User[s]/
the docs site is not public	docs\.runorca\.a[i]
vendor name	[Ss]tream[Nn]ativ[e]
vendor host outside an API path	[^A-Za-z0-9-]sn\.i[o][^A-Za-z0-9-]
AI session trailer or link	Claude-Sessio[n]|claude\.ai/cod[e]
PATTERNS

git ls-files --cached --others --exclude-standard >"$listfile" || exit 2

files=()
while IFS= read -r f; do
  [[ -f "$f" && ! -L "$f" ]] || continue          # deleted in the tree, or a symlink
  case "${f##*/}" in NOTICE | LICENSE*) continue ;; esac
  files+=("$f")
done <"$listfile"
[[ ${#files[@]} -gt 0 ]] || { echo "check-hygiene.sh: no files to scan" >&2; exit 2; }

report=$(awk -v pfile="$patfile" '
  BEGIN {
    n = 0
    while ((getline entry < pfile) > 0) {
      if (entry == "") continue
      i = index(entry, "\t")
      lab[++n] = substr(entry, 1, i - 1)
      pat[n]   = substr(entry, i + 1)
    }
  }
  {
    padded = " " $0 " "
    for (j = 1; j <= n; j++) {
      probe = padded
      # The hosted extension group keeps its wire name in API paths.
      if (lab[j] ~ /^vendor host/) gsub(/\/apis\/cloud\.sn\.io\//, "/apis/<hosted-group>/", probe)
      if (probe ~ pat[j]) {
        shown = $0
        sub(/^[ \t]+/, "", shown)
        if (length(shown) > 96) shown = substr(shown, 1, 96) "..."
        printf "  [%s]\n    %s:%d: %s\n", lab[j], FILENAME, FNR, shown
      }
    }
  }
' "${files[@]}") || { echo "check-hygiene.sh: awk failed; check the pattern list" >&2; exit 2; }

if [[ -n "$report" ]]; then
  printf '\ncheck-hygiene.sh found names or links that must not ship:\n\n%s\n\n' "$report"
  printf 'Use the public names (ork, @runorca/orca-sdk, orca-ae/orca-agent-engine,\n'
  printf 'orca-ae/orca-skills) and call the hosted group "the hosted extension group".\n\n'
  exit 1
fi

echo "check-hygiene.sh: clean (${#files[@]} files)"
