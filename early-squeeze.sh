#!/bin/sh
# Start squeezelite as soon as the playback card exists, so the USB DAC is never
# left configured-but-unfed. That idle window makes the Topping D30 Pro emit a
# loud buzz for ~10s on every boot - a HEARING HAZARD with headphones on.
#
# MEASURED TIMELINE (Pi4 + Topping D30 Pro, pCP 11.1, WiFi):
#   5.1s  snd-usb-audio attaches -> DAC configured, analog stage live, UNFED
#   7.5s  pCP begins "Waiting for network"
#  16.2s  ...finishes 9.6s later (WiFi association + DHCP)
#  16.3s  pCP starts squeezelite -> DAC locks, buzz stops
#
# HISTORY - why this needs the MAC gate below:
# The first version of this script started squeezelite before the network was up.
# squeezelite then could not auto-detect an interface MAC, so it registered with
# LMS as a NEW player "00:00:00:00:00:00"; the real player was absent and there
# was NO AUDIO AT ALL. Pinning MAC_ADDRESS in pcp.cfg removes that dependency -
# verified from squeezelite's own log: "sendHELO mac: <the pinned MAC>".
#
# NOTE on a red herring: squeezelite strtok's colon-separated args IN PLACE, so
# /proc/<pid>/cmdline shows "-m aa bb cc dd ee ff" AFTER parsing. That is
# cosmetic. Do NOT use argv as evidence the MAC was mangled - check the log.
#
# SAFETY RULES:
#   * MAC_ADDRESS empty -> DO NOT early start (would risk a ghost player).
#   * Start failure -> clear the pidfile so pCP starts squeezelite normally.
#   * All waits bounded. Worst case is stock pCP behaviour, never worse.

PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

PCPCFG=/usr/local/etc/pcp/pcp.cfg
STATEFILE=/mnt/mmcblk0p2/tce/camilladsp/camilladsp_statefile.yml
INIT=/usr/local/etc/init.d/squeezelite
PIDFILE=/var/run/squeezelite.pid
LOG=/var/log/early_squeeze.log
POLLS=200          # 200 * 0.1s = 20s to wait for the card
VERIFY=24          # 24 * 0.25s = 6s to confirm it came up

now() { cut -d' ' -f1 /proc/uptime 2>/dev/null; }
log() { echo "$(now) $1" >> "$LOG" 2>/dev/null; }

log "=== early-squeeze start ==="
[ -x "$INIT" ]   || { log "no squeezelite init - defer"; exit 0; }
[ -f "$PIDFILE" ] && { log "pidfile already present - defer"; exit 0; }
[ -r "$PCPCFG" ] || { log "no pcp.cfg - defer"; exit 0; }

# Read config WITHOUT clobbering this script's own variables.
MAC=$(sed -n 's/^MAC_ADDRESS="\(.*\)"$/\1/p' "$PCPCFG" | head -1)
OUT=$(sed -n 's/^OUTPUT="\(.*\)"$/\1/p'      "$PCPCFG" | head -1)

# ---- SAFETY GATE: no pinned MAC => no early start -------------------------
if [ -z "$MAC" ]; then
  log "MAC_ADDRESS is empty in pcp.cfg - REFUSING to early start (identity would"
  log "  depend on the network being up, which caused a ghost LMS player before)."
  log "  Deferring to pCP's normal network-aware start."
  exit 0
fi
log "MAC pinned in pcp.cfg: $MAC"

# ---- 1. discover the playback card (never hardcoded) ---------------------
CARD=""
CFG=$(sed -n 's/^[[:space:]]*config_path:[[:space:]]*//p' "$STATEFILE" 2>/dev/null | tr -d '"'"'" | head -1)
if [ -n "$CFG" ] && [ -f "$CFG" ]; then
  CARD=$(grep -oE 'hw:CARD=[A-Za-z0-9_-]+' "$CFG" 2>/dev/null | head -1 | sed 's/.*CARD=//')
  [ -n "$CARD" ] && log "card from camilladsp config: $CARD"
fi
if [ -z "$CARD" ]; then
  case "$OUT" in
    *CARD=*) CARD=$(echo "$OUT" | sed 's/.*CARD=//; s/[,:].*//'); log "card from OUTPUT: $CARD" ;;
    *)       log "OUTPUT='$OUT' names no card - will auto-detect USB audio" ;;
  esac
fi

i=0; FOUND=""
while [ "$i" -lt "$POLLS" ]; do
  if [ -n "$CARD" ] && [ -d "/proc/asound/$CARD" ]; then FOUND="$CARD"; break; fi
  if [ -z "$CARD" ]; then
    u=$(awk -F'[][]' '/USB-Audio/{print $2; exit}' /proc/asound/cards 2>/dev/null | tr -d ' ')
    [ -n "$u" ] && [ -d "/proc/asound/$u" ] && { FOUND="$u"; break; }
  fi
  i=$((i+1)); sleep 0.1
done
[ -n "$FOUND" ] || { log "no playback card after $i polls - defer to pCP"; exit 0; }
log "card '$FOUND' present after $i polls"

# ---- 2. start via pCP's own init (identical options, incl. -m) -----------
"$INIT" start >/dev/null 2>&1
log "init start issued"

# ---- 3. verify it is alive; else self-revert ------------------------------
j=0; p=""
while [ "$j" -lt "$VERIFY" ]; do
  p=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$p" ] && [ -d "/proc/$p" ] && break
  j=$((j+1)); sleep 0.25
done

if [ -n "$p" ] && [ -d "/proc/$p" ]; then
  s=$(awk '/^state/{print $NF}' "/proc/asound/$FOUND/pcm0p/sub0/status" 2>/dev/null)
  log "squeezelite alive pid=$p  pcm=${s:-closed}"
else
  log "early start FAILED - clearing stale pidfile so pCP starts it normally"
  rm -f "$PIDFILE"
fi

log "=== early-squeeze done ==="
exit 0
