#!/bin/sh
printf 'Content-type: application/json\r\n'
printf 'Access-Control-Allow-Origin: *\r\n'
printf '\r\n'
PCP=$(sed -n 's/.*PCPVERS="[^0-9]*\([0-9][0-9.]*\).*/\1/p' /usr/local/etc/pcp/pcpversion.cfg 2>/dev/null)
MODEL=$(tr -d '\000' < /proc/device-tree/model 2>/dev/null | sed 's/ *$//')
KERN=$(uname -r)
HOST=$(hostname)
IP=$(ifconfig 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' | grep -v '^127' | head -1)
NET=unknown
[ "$(cat /sys/class/net/eth0/operstate 2>/dev/null)" = "up" ] && NET=ethernet
[ "$(cat /sys/class/net/wlan0/operstate 2>/dev/null)" = "up" ] && NET=wifi
SQZ=$(squeezelite -? 2>&1 | sed -n '1s/.*Squeezelite \([0-9][^, ]*\).*/\1/p')
. /mnt/mmcblk0p2/tce/eqeditor/cgi-bin/_lmssrv.sh
LMS=$(wget -qO- --timeout=3 "http://$SRV/jsonrpc.js" --post-data='{"id":1,"method":"slim.request","params":["",["version","?"]]}' 2>/dev/null | sed -n 's/.*"_version":"\([^"]*\)".*/\1/p')
printf '{"pcp":"%s","model":"%s","kernel":"%s","host":"%s","ip":"%s","net":"%s","squeezelite":"%s","lms":"%s"}' "$PCP" "$MODEL" "$KERN" "$HOST" "$IP" "$NET" "$SQZ" "$LMS"
