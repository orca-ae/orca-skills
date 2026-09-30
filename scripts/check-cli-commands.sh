#!/usr/bin/env bash
# Copyright The Orca Authors
# SPDX-License-Identifier: Apache-2.0
#
# Parse-check every `ork ...` invocation in the skill against the real CLI.
#
#   check-cli-commands.sh
#
# Uses the ork binary named by $ORK_BIN, or the first `ork` on PATH (install it
# with `brew install orca-ae/tap/ork`, or from the orca-ae/homebrew-tap release
# archives). --help needs no env vars and no server: the URL/token are plain
# cobra flag defaults. Then, for every line starting with `ork `, and every
# `<(ork ...)` process substitution, in a bash/sh/shell fence:
#   - the subcommand path (leading lowercase words) must resolve: `ork <path> --help` exits 0
#   - every `--flag` on the line must appear in that command's --help output
#     (cobra prints local + inherited flags)
# A fence line that still invokes the CLI by its pre-rename binary name is
# reported as STALE rather than skipped.
# It also drives the CLI against a local SSE fixture and checks that the
# documented jq expressions use the resulting {id,event,data} NDJSON shape.
# A `<!-- cli-check: skip -->` comment on the line above a fence skips the
# whole fence. Compatible with macOS bash 3.2 (no associative arrays).
# Exit 0 clean, 1 on any failure, 2 on setup errors.

set -uo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.." || exit 2

bin="${ORK_BIN:-$(command -v ork || true)}"
if [[ -z "$bin" || ! -x "$bin" ]]; then
  echo "check-cli-commands.sh: no ork binary (brew install orca-ae/tap/ork, or set ORK_BIN)" >&2
  exit 2
fi

mkdir -p scripts/.snippets
cache=$PWD/scripts/.snippets/.helpcache
rm -rf "$cache" && mkdir -p "$cache"

fail=0

check_line() {
  # $1=file $2=lineno $3=command line (starts with "ork ")
  local file=$1 lineno=$2 cmd=$3
  cmd=${cmd%%|*}; cmd=${cmd%%>*}; cmd=${cmd%%#*}
  cmd=${cmd%)}   # trailing ) from VAR=$(ork ...) command substitutions
  local toks tok path="" i=0
  # shellcheck disable=SC2206
  toks=($cmd)
  for tok in "${toks[@]}"; do
    i=$((i + 1))
    [[ $i -eq 1 ]] && continue           # the leading "ork"
    if [[ "$tok" =~ ^[a-z][a-z-]*$ ]]; then
      path="$path $tok"
    else
      break
    fi
  done
  path=${path# }
  local key=${path// /_}; key=${key:-_root_}
  local helpfile="$cache/$key.help" failfile="$cache/$key.fail"
  if [[ ! -e "$helpfile" && ! -e "$failfile" ]]; then
    # shellcheck disable=SC2086
    if ! "$bin" $path --help >"$helpfile" 2>&1; then
      mv "$helpfile" "$failfile"
    fi
  fi
  if [[ -e "$failfile" ]]; then
    echo "UNKNOWN COMMAND: ork $path"
    echo "    $file:$lineno: $cmd"
    fail=1
    return
  fi
  local f
  for f in $(printf '%s\n' "$cmd" | grep -oE -- '--[a-z][a-z-]*' | sort -u); do
    if ! grep -qF -- "$f" "$helpfile"; then
      echo "UNKNOWN FLAG: $f on 'ork $path'"
      echo "    $file:$lineno: $cmd"
      fail=1
    fi
  done
  # Short flags (-o, -f, ...): cobra help prints them as "-X, --long" or "-X value".
  local s
  for s in "${toks[@]}"; do
    if [[ "$s" =~ ^-[A-Za-z]$ ]]; then
      if ! grep -qE -- "(^|[[:space:]])${s}[, ]" "$helpfile"; then
        echo "UNKNOWN SHORT FLAG: $s on 'ork $path'"
        echo "    $file:$lineno: $cmd"
        fail=1
      fi
    fi
  done
}

tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT

find skills/orca-api -type f -name '*.md' | sort | while IFS= read -r f; do
  awk -v FILE="$f" '
    /^<!-- cli-check: skip -->$/ { skipnext = 1; next }
    /^```(bash|sh|shell)[ \t]*$/ { infence = 1; doskip = skipnext; skipnext = 0; buf = ""; next }
    /^```/ { infence = 0; buf = ""; next }
    !infence { if ($0 !~ /^[ \t]*$/) skipnext = 0; next }
    doskip { next }
    {
      line = $0
      sub(/\r$/, "", line)
      if (buf != "") { line = buf " " line; buf = "" }
      if (line ~ /\\[ \t]*$/) { sub(/\\[ \t]*$/, "", line); buf = line; next }
      stripped = line
      sub(/^[ \t]*\$?[ \t]*/, "", stripped)
      # VAR=$(ork ...) command substitutions count too
      sub(/^[A-Za-z_][A-Za-z0-9_]*=\$\(/, "", stripped)
      if (stripped ~ /^ork /) printf "%s\t%d\tork\t%s\n", FILE, NR, stripped
      else if (stripped ~ /^orca /) printf "%s\t%d\tstale\t%s\n", FILE, NR, stripped
      # A process substitution, `... < <(ork ...)`, counts too. The invocation
      # ends at the first ")"; documented stream commands contain none.
      else if (match(stripped, /<\(ork [^)]*/)) printf "%s\t%d\tork\t%s\n", FILE, NR, substr(stripped, RSTART + 2, RLENGTH - 2)
      else if (match(stripped, /<\(orca [^)]*/)) printf "%s\t%d\tstale\t%s\n", FILE, NR, substr(stripped, RSTART + 2, RLENGTH - 2)
    }
  ' "$f"
done > "$tmp"

while IFS=$'\t' read -r file lineno kind cmd; do
  [[ -z "${cmd:-}" ]] && continue
  if [[ "$kind" == "stale" ]]; then
    echo "STALE CLI NAME: the binary is ork"
    echo "    $file:$lineno: $cmd"
    fail=1
    continue
  fi
  check_line "$file" "$lineno" "$cmd"
done < "$tmp"

# The CLI's SSE decoder preserves framing fields. Registry stream lines are
# {id,event,data}, so examples must inspect .data.* and persist outer .id.
cli_doc=skills/orca-api/shared/orca-cli.md
if grep -qE 'if \.type == "session\.status_idle"|select\(\.type == "agent\.message"\)' "$cli_doc" \
  || grep -qF "jq -r '.type?" "$cli_doc"; then
  echo "STALE STREAM JQ: $cli_doc reads flat events; CLI emits {id,event,data}"
  fail=1
fi
for required in '.data.type' '.data.content' "Outer \`.id\`" '--from-cursor 0'; do
  if ! grep -qF -- "$required" "$cli_doc"; then
    echo "MISSING STREAM CONTRACT: $cli_doc must document $required"
    fail=1
  fi
done

if command -v python3 >/dev/null 2>&1; then
  if ! python3 - "$bin" <<'PY'
import http.server
import json
import os
import subprocess
import sys
import threading

binary = sys.argv[1]
# The fixture passes its own URL and credential as flags. A contributor's exported
# ORCA_API_KEY or ORCA_ACCESS_TOKEN would conflict with them, so drop both, and the URL.
fixture_env = {
    k: v for k, v in os.environ.items()
    if k not in ('ORCA_API_KEY', 'ORCA_ACCESS_TOKEN', 'ORCA_REGISTRY_URL')
}

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if not self.path.startswith('/v1/sessions/ses_test/events/stream'):
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        self.wfile.write(
            b'id: 42\n'
            b'event: agent.message\n'
            b'data: {"id":"evt_x","type":"agent.message","content":[{"type":"text","text":"hello"}]}\n\n'
            b'id: 43\n'
            b'event: session.status_idle\n'
            b'data: {"id":"evt_y","type":"session.status_idle","stop_reason":{"type":"end_turn"}}\n\n'
        )
        self.wfile.flush()

    def log_message(self, _format, *args):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    proc = subprocess.run(
        [
            binary,
            '--registry-url', f'http://127.0.0.1:{server.server_port}',
            '--access-token', 'test',
            'agent', 'sessions', 'events', 'stream',
            '--session', 'ses_test', '--from-cursor', '0', '--timeout', '2s',
        ],
        capture_output=True,
        text=True,
        timeout=5,
        env=fixture_env,
    )
    if proc.returncode != 0:
        raise RuntimeError(f'CLI stream failed ({proc.returncode}): {proc.stderr.strip()}')
    lines = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
    if len(lines) != 2:
        raise RuntimeError(f'expected 2 NDJSON frames, got {len(lines)}: {proc.stdout!r}')
    first = lines[0]
    if first.get('id') != '42' or first.get('event') != 'agent.message':
        raise RuntimeError(f'SSE framing fields were not preserved: {first!r}')
    if first.get('data', {}).get('type') != 'agent.message':
        raise RuntimeError(f'SSE data payload was not nested under data: {first!r}')
finally:
    server.shutdown()
    server.server_close()
    thread.join()
PY
  then
    echo "STREAM DECODER: CLI did not preserve canonical {id,event,data} frames"
    fail=1
  fi
else
  echo "check-cli-commands.sh: python3 is required for the live CLI SSE decoder fixture" >&2
  exit 2
fi

command -v jq >/dev/null 2>&1 || {
  echo "check-cli-commands.sh: jq is required for the documented stream filter fixture" >&2
  exit 2
}
fixture='{"id":"42","event":"agent.message","data":{"id":"evt_x","type":"agent.message","content":[{"type":"text","text":"hello"}]}}'
rendered=$(printf '%s\n' "$fixture" | jq -r 'select(.data.type == "agent.message") | .data.content[]? | select(.type == "text") | .text')
if [[ "$rendered" != "hello" ]]; then
  echo "STREAM FIXTURE: canonical CLI NDJSON jq contract failed"
  fail=1
fi

if [[ $fail -eq 0 ]]; then
  n=$(wc -l < "$tmp" | tr -d ' ')
  echo "check-cli-commands.sh: clean ($n ork invocations checked)"
else
  exit 1
fi
