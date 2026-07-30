#!/bin/sh
printf "Content-type: text/plain\r\n"
printf "Access-Control-Allow-Origin: *\r\n"
printf "\r\n"
LEN=${CONTENT_LENGTH:-0}
DEST=/mnt/mmcblk0p2/tce/camilladsp/configs/Topping.yml
TMP=/tmp/eq_save_$$.yml
if [ "$LEN" -le 0 ]; then echo "ERR: no data"; exit 0; fi
head -c "$LEN" > "$TMP"
if /usr/local/camilladsp -c "$TMP" >/dev/null 2>&1; then
  cp "$TMP" "$DEST" && echo "OK: saved & validated $LEN bytes"
else
  echo "ERR: config invalid, not saved"
fi
rm -f "$TMP"
