#!/bin/sh
# Install CamCoreEQ onto a piCorePlayer box. Run this ON the player.
#
#   wget -O /tmp/cc.tar.gz https://github.com/nzilberberg/CamCoreEQ/archive/refs/heads/main.tar.gz
#   tar -xzf /tmp/cc.tar.gz -C /tmp
#   sh /tmp/CamCoreEQ-main/tools/install-on-player.sh
#
# Idempotent: safe to re-run to upgrade. Does NOT touch your presets or saved state.
#
# By design this does NOT edit /opt/bootlocal.sh unless you pass --wire-boot. That
# file is invoked as an executable at boot, and a bad edit there is a latent brick
# that only shows on the next reboot (no ssh, no web UI, no player, box still pings).
# Without --wire-boot the exact lines to add are printed for you to review.
set -e

PREFIX=/mnt/mmcblk0p2/tce/eqeditor
SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WIRE_BOOT=0
[ "$1" = "--wire-boot" ] && WIRE_BOOT=1

CGIS="save.sh presets.sh state.sh log.sh status.sh sysinfo.sh cmd.sh _lmssrv.sh"

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$SRC/index.html" ] || die "run this from inside a CamCoreEQ checkout (no index.html at $SRC)"
[ -d /mnt/mmcblk0p2/tce ] || die "/mnt/mmcblk0p2/tce not found - is this a piCorePlayer box with a mounted data partition?"

say "installing into $PREFIX"
mkdir -p "$PREFIX/cgi-bin" "$PREFIX/presets"

cp "$SRC/index.html"  "$PREFIX/index.html"
cp "$SRC/httpd.conf"  "$PREFIX/httpd.conf"
for f in $CGIS; do
  [ -f "$SRC/$f" ] || die "missing $f in the checkout"
  cp "$SRC/$f" "$PREFIX/cgi-bin/$f"
done

# busybox httpd will NOT run a CGI that is not executable: the app would load and
# then every save / preset / status / transport call would fail. Set the bit here
# and VERIFY it, rather than trusting the copy or the source checkout's modes.
say "setting and verifying execute bits"
for f in $CGIS; do chmod 755 "$PREFIX/cgi-bin/$f"; done
for f in $CGIS; do
  [ -x "$PREFIX/cgi-bin/$f" ] || die "$PREFIX/cgi-bin/$f is not executable after chmod"
done

if [ -f "$SRC/early-squeeze.sh" ]; then
  cp "$SRC/early-squeeze.sh" "$PREFIX/early-squeeze.sh"
  chmod 755 "$PREFIX/early-squeeze.sh"
  [ -x "$PREFIX/early-squeeze.sh" ] || die "early-squeeze.sh is not executable after chmod"
fi

# Restart the EQ's own web server. It MUST use -c with the EQ's own httpd.conf:
# piCorePlayer's global /etc/httpd.conf contains "H:/var/www", and that H: directive
# OVERRIDES the -h flag, so "httpd -p 8080 -h $PREFIX" silently serves the wrong tree.
say "restarting the web server on :8080"
kill $(ps -ef 2>/dev/null | awk '/[b]usybox httpd -p 8080/{print $1}') 2>/dev/null || true
setsid /bin/busybox httpd -p 8080 -c "$PREFIX/httpd.conf" </dev/null >/dev/null 2>&1 &
sleep 1

# Assert CONTENT, not a status code: piCorePlayer answers 200 on :8080 too, with a
# redirect page, so an HTTP 200 alone proves nothing.
say "verifying the served content is CamCoreEQ"
body="$(wget -qO- --timeout=5 http://127.0.0.1:8080/ 2>/dev/null || true)"
if printf '%s' "$body" | grep -qi '<title>[[:space:]]*CamCoreEQ[[:space:]]*</title>'; then
  echo "    OK - CamCoreEQ is being served on :8080"
else
  got="$(printf '%s' "$body" | grep -oiE '<title>[^<]*</title>' | head -1)"
  die "served content is NOT CamCoreEQ (got ${got:-<no title>}). Check $PREFIX/httpd.conf and the -c flag."
fi

say "verifying a CGI actually executes"
out="$(wget -qO- --timeout=5 'http://127.0.0.1:8080/cgi-bin/cmd.sh?c=zzz' 2>/dev/null || true)"
case "$out" in
  *'"ok"'*) echo "    OK - cgi-bin is executing ($out)" ;;
  *) die "cgi-bin did not execute (got: ${out:-<empty>}). Almost always a missing execute bit." ;;
esac

BOOTLINE="[ -f $PREFIX/index.html ] && [ -f $PREFIX/httpd.conf ] && /bin/busybox httpd -p 8080 -c $PREFIX/httpd.conf"
if [ "$WIRE_BOOT" = 1 ]; then
  say "wiring /opt/bootlocal.sh (backup at /opt/bootlocal.sh.bak.camcoreeq)"
  cp /opt/bootlocal.sh /opt/bootlocal.sh.bak.camcoreeq
  grep -qF "httpd -p 8080 -c $PREFIX/httpd.conf" /opt/bootlocal.sh || {
    printf '%s\n' "$BOOTLINE" >> /opt/bootlocal.sh
  }
  chmod 755 /opt/bootlocal.sh
  [ -x /opt/bootlocal.sh ] || die "/opt/bootlocal.sh lost its execute bit - RESTORE THE BACKUP BEFORE REBOOTING"
  say "backing up /opt so the change survives reboot"
  filetool.sh -b mmcblk0p2/tce
  echo "    wired. /opt is tmpfs restored from mydata.tgz, so the backup above was required."
else
  echo
  echo "NOT wired to boot (default). To start automatically, add this line to"
  echo "/opt/bootlocal.sh BEFORE its #pCPstart block, then run: filetool.sh -b mmcblk0p2/tce"
  echo
  echo "  $BOOTLINE"
  echo
  echo "Or re-run this installer with --wire-boot to do it with a backup and verification."
fi

echo
say "done. Open http://<this-player>:8080/ from your phone or browser."
echo "    Presets you create live in $PREFIX/presets/ and are NOT part of the repo."
echo "    Back that directory up before you ever re-image the card."
