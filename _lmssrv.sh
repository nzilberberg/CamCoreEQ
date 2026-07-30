# Resolve the live LMS web/JSON-RPC host:port into $SRV.
# LMS httpport oscillates between 9000 and 9001, so probe both and use whichever
# answers a version request. A closed port returns ECONNREFUSED instantly (no wait).
# LMS host. Set it in the optional config file rather than editing this script, so
# an update does not clobber it and no address is baked into the source:
#   /mnt/mmcblk0p2/tce/eqeditor/camcoreeq.conf   ->   LMS_HOST=192.0.2.10
# Unset falls back to localhost, which is correct when LMS runs on the player itself.
# If no LMS answers, the LMS-dependent panels simply stay inactive.
[ -f /mnt/mmcblk0p2/tce/eqeditor/camcoreeq.conf ] && . /mnt/mmcblk0p2/tce/eqeditor/camcoreeq.conf
LMS_HOST="${LMS_HOST:-localhost}"
_lms_alive() {
  wget -qO- --timeout=1 "http://$1/jsonrpc.js" \
    --post-data='{"id":1,"method":"slim.request","params":["",["version","?"]]}' 2>/dev/null \
    | grep -q '"_version"'
}
if   _lms_alive "$LMS_HOST:9000"; then SRV="$LMS_HOST:9000"
elif _lms_alive "$LMS_HOST:9001"; then SRV="$LMS_HOST:9001"
else SRV="$LMS_HOST:9000"; fi
