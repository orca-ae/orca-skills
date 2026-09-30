#!/usr/bin/env bash
# Copyright The Orca Authors
# SPDX-License-Identifier: Apache-2.0
#
# Typecheck the skill's TypeScript examples against the published SDK.
#
#   check-ts-snippets.sh
#
# Extracts ```ts fences (see extract-ts-snippets.mjs for the directives), then
# runs tsc with scripts/tsconfig.snippets.json. The SDK (@runorca/orca-sdk from
# npm), the compiler and @types/node are pinned in scripts/package.json;
# install them once with `npm ci --prefix scripts`.
# Exit 0 clean, non-zero on extraction or type errors.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 2
tsc=scripts/node_modules/.bin/tsc
sdk=scripts/node_modules/@runorca/orca-sdk
if [[ ! -x "$tsc" || ! -e "$sdk/package.json" ]]; then
  echo "check-ts-snippets.sh: tools not installed (run: npm ci --prefix scripts)" >&2
  exit 2
fi

node scripts/extract-ts-snippets.mjs || exit $?

if ! ls scripts/.snippets/ts/*.ts >/dev/null 2>&1; then
  echo "check-ts-snippets.sh: no snippets extracted - nothing to check"
  exit 0
fi

if "$tsc" -p scripts/tsconfig.snippets.json; then
  count=$(find scripts/.snippets/ts -maxdepth 1 -type f -name '*.ts' | wc -l | tr -d ' ')
  echo "check-ts-snippets.sh: clean ($count snippet files)"
else
  echo
  echo "check-ts-snippets.sh: type errors above. Snippet files mirror the markdown"
  echo "(scripts/.snippets/ts/<file-slug>.ts); fix the markdown, not the snippet."
  exit 1
fi
