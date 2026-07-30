#!/bin/sh
printf 'Content-type: application/json\r\n'
printf 'Access-Control-Allow-Origin: *\r\n'
printf '\r\n'
TEMP=$(awk '{printf "%.1f",$1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
LOAD=$(cut -d' ' -f1 /proc/loadavg)
CPUS=$(grep -c '^processor' /proc/cpuinfo)
SQZ=0; ps -ef | grep -q '[s]queezelite' && SQZ=1
CDSP=0; ps -ef | grep -q '[c]amilladsp -p' && CDSP=1
OUT=$(awk -F'"' '/^OUTPUT/{print $2}' /usr/local/etc/pcp/pcp.cfg)
BOOT=$(sed -n 's|.*config_path: .*/||p' /mnt/mmcblk0p2/tce/camilladsp/camilladsp_statefile.yml)
CARD=$(grep 'USB-Audio' /proc/asound/cards | tr -s ' ' | sed 's/^ //')
HW=/proc/asound/Pro/pcm0p/sub0/hw_params
STF=/proc/asound/Pro/pcm0p/sub0/status
if grep -q '^rate:' "$HW" 2>/dev/null; then
  RATE=$(awk '/^rate:/{print $2}' "$HW")
  FMT=$(awk '/^format:/{print $2}' "$HW")
  CH=$(awk '/^channels:/{print $2}' "$HW")
  BUF=$(awk '/^buffer_size:/{print $2}' "$HW")
  STATE=$(awk '/^state/{print $NF}' "$STF")
else
  RATE=0; FMT="-"; CH=0; BUF=0; STATE="closed"
fi
# Player identity: read piCorePlayer's own pcp.cfg rather than hardcoding a MAC,
# so this works on any box. Same pattern as early-squeeze.sh. Empty means the LMS
# queries below return nothing, which the callers already handle (LMS=null).
MAC=$(sed -n 's/^MAC_ADDRESS="\(.*\)"$/\1/p' /usr/local/etc/pcp/pcp.cfg 2>/dev/null | head -1)
. /mnt/mmcblk0p2/tce/eqeditor/cgi-bin/_lmssrv.sh
UP=$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)
FREEKB=$(df /mnt/mmcblk0p2 2>/dev/null | awk 'NR==2{print $4}')
BKP=$(date -r /mnt/mmcblk0p2/tce/mydata.tgz +%s 2>/dev/null)
LMS=$(wget -qO- --timeout=3 "http://$SRV/jsonrpc.js" --post-data="{\"id\":1,\"method\":\"slim.request\",\"params\":[\"$MAC\",[\"status\",\"-\",1,{\"tags\":\"aAlgGdiqtyrRTouxNcK\"}]]}" 2>/dev/null)
[ -z "$LMS" ] && LMS=null
SRC=$(wget -qO- --timeout=3 "http://$SRV/jsonrpc.js" --post-data="{\"id\":1,\"method\":\"slim.request\",\"params\":[\"$MAC\",[\"path\",\"?\"]]}" 2>/dev/null | sed -n 's/.*"_path":"\([^"]*\)".*/\1/p')
TID=$(printf '%s' "$LMS" | sed -n 's/.*"playlist_loop":\[{[^}]*"id":"\{0,1\}\([-0-9]*\).*/\1/p')
SONG=null
RBR=""
if [ -n "$TID" ]; then
  SONG=$(wget -qO- --timeout=3 "http://$SRV/jsonrpc.js" --post-data="{\"id\":1,\"method\":\"slim.request\",\"params\":[\"\",[\"songinfo\",0,60,\"track_id:$TID\",\"tags:aAlgGdiqtyrRTouxNcKovjI\"]]}" 2>/dev/null)
  [ -z "$SONG" ] && SONG=null
  # Real source bitrate: LMS computes it (prettyBitRate) only in songinfo.html, not in the JSON API.
  # 28KB skin render, so cache by track id and only re-fetch when the track changes.
  CACHE=/tmp/pcp_rbr.cache
  if [ "$(cut -d' ' -f1 "$CACHE" 2>/dev/null)" = "$TID" ]; then
    RBR=$(cut -d' ' -f2- "$CACHE" 2>/dev/null)
  else
    RBR=$(wget -qO- --timeout=5 "http://$SRV/songinfo.html?item=$TID&player=$MAC" 2>/dev/null | sed -n '/Bitrate:/,/kbps/p' | grep -i 'kbps' | head -1 | tr -d '\r\n"\\' | sed -e 's/<[^>]*>//g' -e 's/^[ \t]*//' -e 's/[ \t]*$//' -e 's/  */ /g')
    echo "$TID $RBR" > "$CACHE"
  fi
fi
printf '{"temp":%s,"load":%s,"cpus":%s,"sqz":%s,"cdsp":%s,"output":"%s","boot":"%s","card":"%s","source_url":"%s","server":"%s","mac":"%s","uptime":%s,"freekb":%s,"backup":%s,"realbitrate":"%s","alsa":{"rate":%s,"format":"%s","ch":%s,"buffer":%s,"state":"%s"},"lms":%s,"song":%s}' "${TEMP:-0}" "${LOAD:-0}" "${CPUS:-4}" "$SQZ" "$CDSP" "$OUT" "$BOOT" "$CARD" "$SRC" "$SRV" "$MAC" "${UP:-0}" "${FREEKB:-0}" "${BKP:-0}" "$RBR" "$RATE" "$FMT" "$CH" "$BUF" "$STATE" "$LMS" "$SONG"
