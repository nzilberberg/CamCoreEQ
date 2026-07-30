# Resolve the live LMS web/JSON-RPC host:port into $SRV.
# LMS's httpport oscillates between 9000 and 9001, so the wrong one must never be
# assumed -- but it must not be re-probed on every call either: probing a CLOSED port
# through a firewall that DROPS (rather than refuses) burns the full 1s timeout, and
# that measured as a constant ~1.03s added to EVERY transport/status call while LMS
# sat on 9001 (the probe tried 9000 first). The user felt it as a multi-second
# play/pause lag.
#
# Strategy: try the LAST KNOWN GOOD port first (one fast request on the hot path);
# only on a miss or failure fall back to the full both-ports probe and re-cache.
# A mid-session port flap costs one slow call, then it is fast again.

# LMS host. Set it in the optional config file rather than editing this script, so
# an update does not clobber it and no address is baked into the source:
#   /mnt/mmcblk0p2/tce/eqeditor/camcoreeq.conf   ->   LMS_HOST=192.0.2.10
# Unset falls back to localhost, which is correct when LMS runs on the player itself.
# If no LMS answers, the LMS-dependent panels simply stay inactive.
[ -f /mnt/mmcblk0p2/tce/eqeditor/camcoreeq.conf ] && . /mnt/mmcblk0p2/tce/eqeditor/camcoreeq.conf
LMS_HOST="${LMS_HOST:-localhost}"

_SRV_CACHE=/tmp/camcoreeq_srv.cache

_lms_alive() {
  wget -qO- --timeout=1 "http://$1/jsonrpc.js" \
    --post-data='{"id":1,"method":"slim.request","params":["",["version","?"]]}' 2>/dev/null \
    | grep -q '"_version"'
}

SRV=""
# Hot path: the cached port, accepted only if it matches the two known shapes (the
# cache lives in world-writable /tmp, so its content is validated, never trusted).
if [ -f "$_SRV_CACHE" ]; then
  _c=$(cat "$_SRV_CACHE" 2>/dev/null)
  case "$_c" in
    "$LMS_HOST:9000"|"$LMS_HOST:9001") _lms_alive "$_c" && SRV="$_c" ;;
  esac
fi
# Miss or dead: full probe, then remember the answer.
if [ -z "$SRV" ]; then
  if   _lms_alive "$LMS_HOST:9000"; then SRV="$LMS_HOST:9000"
  elif _lms_alive "$LMS_HOST:9001"; then SRV="$LMS_HOST:9001"
  else SRV="$LMS_HOST:9000"; fi
  printf '%s' "$SRV" > "$_SRV_CACHE" 2>/dev/null
fi
