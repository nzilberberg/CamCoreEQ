#!/bin/sh
F=/mnt/mmcblk0p2/tce/eqeditor/log.json
printf 'Content-type: application/json\r\n'
printf 'Access-Control-Allow-Origin: *\r\n'
printf '\r\n'
if [ "$REQUEST_METHOD" = "POST" ]; then
  head -c "${CONTENT_LENGTH:-0}" > "$F.tmp" 2>/dev/null && mv "$F.tmp" "$F"
  printf '{"ok":1}'
else
  if [ -s "$F" ]; then cat "$F"; else printf '[]'; fi
fi
