#!/bin/sh
# GATE: no EQ CGI may hardcode an LMS port. The LMS httpport flaps between the two
# well-known values, so every LMS call must resolve the port via _lmssrv.sh.
# Fails only on a port literal in ACTIVE (non-comment) code of a runtime CGI.
# Excludes the resolver include and this linter itself. Path-colon safe (awk on content).
# DIR defaults to THIS SCRIPT'S directory, not the caller's cwd. It used to be
# `${1:-.}`, which meant running the gate from anywhere else scanned nothing.
DIR="${1:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
files=$(ls "$DIR"/*.sh 2>/dev/null | grep -vE '/(_lmssrv|lint-lms-ports)\.sh$')
# Scanning zero files is a FAILURE, never a pass. This previously exited 0 with
# "no CGIs found", so a wrong path or a moved tree reported success while
# checking nothing -- the vacuous-PASS trap this project's install notes warn about.
[ -z "$files" ] && { echo "LINT FAIL - no CGIs found under $DIR (gate would be vacuous)"; exit 1; }
count=$(printf '%s\n' "$files" | wc -l | tr -d ' ')
hits=$(awk '/^[[:space:]]*#/{next} /:900[01]/{print FILENAME": line "FNR": "$0}' $files)
if [ -n "$hits" ]; then
  echo "LINT FAIL - hardcoded LMS port in active code:"; echo "$hits"; exit 1
fi
echo "LINT PASS - no hardcoded LMS port in $count runtime CGIs under $DIR"
