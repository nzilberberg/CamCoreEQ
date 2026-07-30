#!/bin/sh
# GATE: every file the player invokes as a program must be committed EXECUTABLE.
#
# Why this is not a style rule. busybox httpd silently refuses to run a CGI that
# lacks the execute bit, so the EQ loads and then every save / preset / status /
# transport call fails -- and the cause looks like a network or CORS problem, not a
# file mode. Worse, early-squeeze.sh is invoked from /opt/bootlocal.sh as an
# executable; without the bit it never runs, and its absence re-arms the loud
# full-level DAC buzz at boot, which is a HEARING HAZARD with headphones on.
#
# This project has already lost hours to a mode regression on a boot script, and the
# git index is exactly where it silently happens: files copied on Windows and added
# to git land as 100644 with nothing to notice it.
#
# Usage:  sh tools/check-repo-modes.sh          check the git index (pre-commit)
#         sh tools/check-repo-modes.sh --work   also check the working tree bits
# Exit 0 clean / 1 findings / 2 could not run (fails closed, never silently clean).

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root" || { echo "SCAN ERROR: cannot cd to $root" >&2; exit 2; }

# Served by busybox httpd as CGI, plus the boot-invoked helper and the repo's own
# shell tooling. _lmssrv.sh is sourced rather than executed, but it is copied into
# cgi-bin/ and kept executable for consistency with its siblings.
NEED="save.sh presets.sh state.sh log.sh status.sh sysinfo.sh cmd.sh _lmssrv.sh
early-squeeze.sh check-camcoreeq.sh lint-lms-ports.sh lint-exec-bits.sh
tools/install-on-player.sh tools/install-hooks.sh tools/check-repo-modes.sh tools/deploy-to-player.sh"

listing="$(git ls-files -s 2>/dev/null)" || { echo "SCAN ERROR: git ls-files failed" >&2; exit 2; }
[ -n "$listing" ] && : || { echo "SCAN ERROR: git index is empty - gate would be vacuous" >&2; exit 2; }

fail=0
checked=0
for f in $NEED; do
  mode="$(printf '%s\n' "$listing" | awk -v p="$f" '$4==p{print $1}')"
  if [ -z "$mode" ]; then
    echo "MODE FAIL - $f is expected to exist and be executable, but is not tracked by git"
    fail=1; continue
  fi
  checked=$((checked + 1))
  if [ "$mode" != "100755" ]; then
    echo "MODE FAIL - $f is committed as $mode, must be 100755 (executable)"
    echo "            fix: git update-index --chmod=+x '$f'"
    fail=1
  fi
done

if [ "$checked" = 0 ]; then
  echo "SCAN ERROR: matched none of the expected files - gate would be vacuous" >&2
  exit 2
fi

if [ "$1" = "--work" ]; then
  for f in $NEED; do
    [ -f "$f" ] || continue
    [ -x "$f" ] || { echo "MODE WARN - working tree: $f is not executable locally"; }
  done
fi

[ "$fail" = 0 ] || { echo ""; echo "A non-executable CGI fails at RUNTIME, not at install time."; exit 1; }
echo "MODE PASS - $checked program file(s) committed executable"
