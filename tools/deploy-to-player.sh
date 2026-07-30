#!/bin/sh
# Deploy the web app + CGIs to a piCorePlayer box, with the checks that history earned.
#
#   sh tools/deploy-to-player.sh <player-host>
#   EXTRA_SSH_OPTS="-i ~/.ssh/mykey" sh tools/deploy-to-player.sh 192.0.2.10
#
# Why this script exists: the app updates itself over the air from GitHub Pages, but
# BROWSERS load the copy the player serves -- and that copy only moves when someone
# deploys it. Every version drift between "the app looks right, the browser is old"
# (or the reverse) came from forgetting this step. One command, fully verified.
#
# Checks, each of which has already caught a real shipped defect once:
#   - the page must PARSE before anything is copied (build b213 shipped a dead page)
#   - md5 of the deployed file must equal the local one (a stale-tmp copy once shipped)
#   - CGIs must be executable AFTER copying (a fresh install once had none executable)
#   - the served CONTENT must be this app, not a 200 from pCP's own redirect page
#   - a CGI must actually execute, not just exist
set -e

HOST="$1"
[ -n "$HOST" ] || { echo "usage: $(basename "$0") <player-host>   (e.g. 192.0.2.10)"; exit 2; }
PREFIX=/mnt/mmcblk0p2/tce/eqeditor
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SSH="ssh $EXTRA_SSH_OPTS -o ConnectTimeout=8 tc@$HOST"
SCP="scp $EXTRA_SSH_OPTS -q"
CGIS="save.sh presets.sh state.sh log.sh status.sh sysinfo.sh cmd.sh _lmssrv.sh"

command -v node >/dev/null 2>&1 && NODE=node || NODE="/c/Users/nzilb/tools/node-dist/node.exe"

echo "== 1/5 the page must parse before it goes anywhere =="
"$NODE" "$ROOT/tools/check-page-parses.mjs" "$ROOT/index.html" | tail -1

echo "== 2/5 copy (explicit destination filenames) =="
$SCP "$ROOT/index.html" "tc@$HOST:$PREFIX/index.html"
for f in $CGIS; do $SCP "$ROOT/$f" "tc@$HOST:$PREFIX/cgi-bin/$f"; done
echo "   copied index.html + $(echo $CGIS | wc -w) CGIs"

echo "== 3/5 exec bits set and verified =="
$SSH "cd $PREFIX/cgi-bin && chmod 755 *.sh && for f in *.sh; do [ -x \$f ] || { echo \"NOT EXECUTABLE: \$f\"; exit 1; }; done && echo '   all executable'"

echo "== 4/5 md5 must match =="
L=$(md5sum "$ROOT/index.html" | cut -d' ' -f1)
R=$($SSH "md5sum $PREFIX/index.html" | cut -d' ' -f1)
[ "$L" = "$R" ] || { echo "   MISMATCH local=$L remote=$R"; exit 1; }
echo "   $L"

echo "== 5/5 served content + CGI execution =="
body=$(wget -qO- --timeout=8 "http://$HOST:8080/" 2>/dev/null || curl -s -m 8 "http://$HOST:8080/")
printf '%s' "$body" | grep -qi '<title>[[:space:]]*CamCoreEQ[[:space:]]*</title>' \
  || { echo "   served page is NOT CamCoreEQ (httpd.conf / -c problem?)"; exit 1; }
out=$(curl -s -m 8 "http://$HOST:8080/cgi-bin/cmd.sh?c=zzz")
case "$out" in *'"ok"'*) : ;; *) echo "   CGI did not execute (got: ${out:-empty})"; exit 1;; esac
echo "   page served + CGI executes"
echo "DEPLOY OK -> http://$HOST:8080/"
