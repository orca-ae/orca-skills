#!/usr/bin/env bash
# Copyright The Orca Authors
# SPDX-License-Identifier: Apache-2.0
#
# Run every verification gate. The pre-commit command for this repo.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

rc=0
scripts/check-hygiene.sh              || rc=1
scripts/check-skill.sh                || rc=1
scripts/check-ts-snippets.sh          || rc=1
scripts/check-cli-commands.sh         || rc=1
scripts/check-xrefs.sh                || rc=1
node scripts/check-license-headers.mjs || rc=1

if [[ $rc -eq 0 ]]; then
  echo "check-all.sh: all gates clean"
else
  echo "check-all.sh: FAILURES above" >&2
fi
exit $rc
