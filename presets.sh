#!/bin/sh
printf "Content-type: application/json\r\n"
printf "Access-Control-Allow-Origin: *\r\n"
printf "\r\n"
DIR=/mnt/mmcblk0p2/tce/eqeditor/presets
mkdir -p "$DIR"
NAME=""; DEL=""
IFS="&"
for kv in $QUERY_STRING; do
  k=${kv%%=*}; v=${kv#*=}
  case "$k" in name) NAME=$v;; del) DEL=$v;; esac
done
unset IFS
decode(){ printf "%s" "$1" | sed "s/+/ /g; s/%20/ /g"; }
san(){ printf "%s" "$1" | tr -cd "A-Za-z0-9 _.-"; }
NAME=$(san "$(decode "$NAME")"); DEL=$(san "$(decode "$DEL")")
if [ "$REQUEST_METHOD" = "POST" ] && [ -n "$NAME" ]; then
  head -c "${CONTENT_LENGTH:-0}" > "$DIR/$NAME.json" && printf "{\"ok\":true,\"saved\":\"%s\"}" "$NAME"
elif [ -n "$DEL" ]; then
  rm -f "$DIR/$DEL.json"; printf "{\"ok\":true,\"deleted\":\"%s\"}" "$DEL"
elif [ -n "$NAME" ]; then
  if [ -f "$DIR/$NAME.json" ]; then cat "$DIR/$NAME.json"; else printf "{\"error\":\"not found\"}"; fi
else
  printf "["; first=1
  for f in "$DIR"/*.json; do [ -e "$f" ] || continue
    b=$(basename "$f" .json); [ $first -eq 1 ] || printf ","; printf "\"%s\"" "$b"; first=0
  done
  printf "]"
fi
