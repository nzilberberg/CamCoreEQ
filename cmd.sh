#!/bin/sh
printf 'Content-type: application/json\r\n'
printf 'Access-Control-Allow-Origin: *\r\n'
printf '\r\n'
# Player identity: read piCorePlayer's own pcp.cfg rather than hardcoding a MAC,
# so this works on any box. Same pattern as early-squeeze.sh. Empty is tolerated —
# the transport call below is skipped, which is better than driving a ghost player.
MAC=$(sed -n 's/^MAC_ADDRESS="\(.*\)"$/\1/p' /usr/local/etc/pcp/pcp.cfg 2>/dev/null | head -1)
. /mnt/mmcblk0p2/tce/eqeditor/cgi-bin/_lmssrv.sh
C=$(echo "$QUERY_STRING" | sed -n 's/.*c=\([a-z]*\).*/\1/p')
case "$C" in
  play)  P='["play"]';;
  pause) P='["pause","1"]';;
  next)  P='["playlist","index","+1"]';;
  prev)  P='["playlist","index","-1"]';;
  *)     P='';;
esac
[ -n "$P" ] && [ -n "$MAC" ] && wget -qO- --timeout=3 "http://$SRV/jsonrpc.js" --post-data="{\"id\":1,\"method\":\"slim.request\",\"params\":[\"$MAC\",$P]}" >/dev/null 2>&1
printf '{"ok":1,"c":"%s"}' "$C"
