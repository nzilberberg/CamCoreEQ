#!/bin/sh
# Health check for the CamCoreEQ web app.
# A bare HTTP 200 is NOT proof the EQ is up: piCorePlayer's own web server can answer on
# :8080 and return a 200 redirect page. Assert the served CONTENT is the EQ.
# The target is REQUIRED. It used to default to the author's own player, which both
# baked a LAN address into the source and meant a mistyped invocation silently
# checked someone else's machine.
if [ -z "$1" ]; then
  echo "usage: $(basename "$0") http://<player>:8080/" >&2
  exit 2
fi
URL="$1"
body="$(curl -s --max-time 8 "$URL")"
if printf '%s' "$body" | grep -qi '<title>[[:space:]]*CamCoreEQ[[:space:]]*</title>'; then
  echo "GREEN: CamCoreEQ is being served at $URL"
  exit 0
else
  title="$(printf '%s' "$body" | grep -oiE '<title>[^<]*</title>' | head -1)"
  echo "RED: $URL answered, but it is NOT CamCoreEQ (got ${title:-<no title>})"
  exit 1
fi
