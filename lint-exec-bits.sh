#!/bin/sh
# GATE: any script that is INVOKED as an executable must carry the execute bit.
#
# Earned the hard way: an awk-rewrite of /opt/bootlocal.sh created the new file
# under the default umask (0644) and cp carried that mode onto the target. The
# contents and `sh -n` syntax were both verified and both were fine - but
# /opt/bootsync.sh runs it as `/opt/bootlocal.sh &`, which silently failed. That
# stopped pcp_startup.sh, so SSH and the pCP web UI never started, and the box
# looked bricked. Verifying content is NOT verifying executability.
#
# Usage:
#   lint-exec-bits.sh <file> [file...]      check specific files
#   lint-exec-bits.sh --tar <archive.tgz>   check the boot scripts inside a
#                                           pCP mydata.tgz backup
#
# Exit 0 = all executable. Exit 1 = at least one is not.

fail=0

check_mode() {
  # $1 = label, $2 = octal-ish mode string or symbolic
  case "$2" in
    *x*) return 0 ;;   # symbolic contains x
  esac
  return 1
}

if [ "$1" = "--tar" ]; then
  T="$2"
  [ -f "$T" ] || { echo "LINT ERROR: archive not found: $T"; exit 2; }
  # These are the scripts pCP/TinyCore invoke directly at boot.
  for f in opt/bootlocal.sh opt/bootsync.sh opt/shutdown.sh; do
    line=$(tar -tvzf "$T" 2>/dev/null | awk -v f="$f" '$NF==f {print; exit}')
    [ -z "$line" ] && continue
    perms=$(echo "$line" | awk '{print $1}')
    if check_mode "$f" "$perms"; then
      echo "ok   $f ($perms)"
    else
      echo "FAIL $f ($perms) - invoked as an executable but not executable"
      fail=1
    fi
  done
else
  [ $# -eq 0 ] && { echo "usage: lint-exec-bits.sh <file>... | --tar <archive.tgz>"; exit 2; }
  for f in "$@"; do
    if [ ! -e "$f" ]; then
      echo "FAIL $f - does not exist"; fail=1; continue
    fi
    if [ -x "$f" ]; then
      echo "ok   $f"
    else
      echo "FAIL $f - not executable"
      fail=1
    fi
  done
fi

if [ "$fail" -ne 0 ]; then
  echo "LINT FAIL - fix with: chmod +x <file>   (and re-run the backup)"
  exit 1
fi
echo "LINT PASS - every checked script is executable"
exit 0
