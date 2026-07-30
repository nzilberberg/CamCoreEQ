# CamCoreEQ — install notes / packaging checklist

What an installer must do on a fresh piCorePlayer box, beyond copying the EQ itself.
Derived from a working install on piCorePlayer 11.1.0 (Pi 4, USB DAC). Substitute your own
player address, DAC and player MAC throughout.

---

## 1. The EQ app

Copy to the **persistent** partition (survives reboot without `filetool.sh -b`):

```
/mnt/mmcblk0p2/tce/eqeditor/
  index.html          single self-contained file
  httpd.conf          REQUIRED - see §2
  cgi-bin/            save.sh presets.sh state.sh log.sh status.sh sysinfo.sh cmd.sh _lmssrv.sh
  presets/
```

## 2. Serve it — and it MUST have its own httpd.conf

`/etc/httpd.conf` (maintained by pCP) contains `H:/var/www`. busybox httpd applies that
**globally and it OVERRIDES the `-h` flag**, so `busybox httpd -p 8080 -h <eqeditor>`
silently serves `/var/www` (pCP's redirect page) instead of the EQ. Ship an EQ-private
config and use `-c`:

```
# /mnt/mmcblk0p2/tce/eqeditor/httpd.conf
H:/mnt/mmcblk0p2/tce/eqeditor
```
```sh
/bin/busybox httpd -p 8080 -c /mnt/mmcblk0p2/tce/eqeditor/httpd.conf
```

Health check must assert **content**, not HTTP status — pCP answers 200 on :8080 too:
`curl -s http://host:8080/ | grep -q '<title>CamCoreEQ</title>'`.
Gate: `lint-lms-ports.sh` style; see `check-camcoreeq.sh`.

## 3. LMS port is not fixed

The Lyrion `httpport` can differ per install (it flaps 9000↔9001 on the reference box).
CGIs must **probe**, never hardcode: see `_lmssrv.sh`, sourced by `status.sh`, `cmd.sh`,
`sysinfo.sh`. Gate: `lint-lms-ports.sh` (fails on a `:900[01]` literal in active code).

## 4. The DAC boot-buzz fix (needed on USB DACs)

**Symptom:** on every boot the USB DAC is configured by `snd-usb-audio` (~5s) but pCP does
not start squeezelite until after its `Waiting for network` loop (measured **9.6s** on
WiFi). In between the DAC has no valid stream, loses clock lock, and emits a loud
full-level buzz — a **hearing hazard** with headphones on.

**Fix — two parts, both required:**

1. **Pin the player MAC** in `pcp.cfg`:
   ```
   MAC_ADDRESS="<the MAC LMS already knows this player by>"
   ```
   ⚠️ Installer must **derive** this, not hardcode it. Use the MAC of the interface the
   player actually reaches LMS on (on the reference box that is **wlan0**, not eth0).
   If the box already has a player registered in LMS, use that exact ID or LMS will
   treat it as a brand-new player.

2. **`early-squeeze.sh`** on the persistent partition, called backgrounded from
   `/opt/bootlocal.sh` **before** the `#pCPstart` block. It waits for the playback card
   (discovered from the CamillaDSP config, then `OUTPUT`, then first `USB-Audio`), then
   runs pCP's own `init.d/squeezelite start`.

**Why part 1 is mandatory:** without it, squeezelite starting before the network cannot
auto-detect a MAC and registers with LMS as a NEW player `00:00:00:00:00:00`. The real
player is then absent and there is **no audio at all**. The script therefore **refuses to
start early if `MAC_ADDRESS` is empty** — keep that gate.

**Why it is safe:** pCP's `squeezelite start` begins
`if [ -f $PIDFILE ]; then echo "already running"; exit 1; fi`, so pCP's later start is a
no-op. On any failure the script clears the pidfile so pCP starts squeezelite normally.

## 5. Card selection — don't ship a phantom HAT

If pCP's `AUDIO=` names an I2S HAT the box doesn't have (e.g. `ess9023`), it adds
`dtoverlay=hifiberry-dac` to `config.txt`, creating a phantom `sndrpihifiberry` ALSA card
that pCP's boot-time card wait then watches **instead of the real DAC**. For a USB DAC set:

```
AUDIO="USB"
```
and remove the stale `dtoverlay=` line from `config.txt`.

⚠️ **Do NOT do this through pCP's web UI.** The card confs declare `OUTPUT` — e.g.
`ess9023.conf` has `OUTPUT="hw:CARD=sndrpihifiberry"` — and the CGI writes it into
`pcp.cfg`, which would replace `OUTPUT="camilladsp"` and **silently bypass the EQ**.
Edit `pcp.cfg` directly and keep `OUTPUT="camilladsp"`.

With `OUTPUT=camilladsp` (no `CARD=`), `pcp_get_card_name` returns `None`, so
`pcp_startup.sh` skips the card wait rather than waiting on a fake card. `ALSA_PARAMS`
for squeezelite comes from `pcp.cfg` (its init sources it directly), not from the card
conf, so switching card conf does not change the audio params.

## 6. Persistence

`/opt/*` and `/usr/local/etc/pcp/pcp.cfg` live in the backup archive
`tce/mydata.tgz` — changes need `filetool.sh -b mmcblk0p2/tce` (**pass the target
explicitly**; a bare `-b` follows `/etc/sysconfig/backup_device`, which may point
elsewhere). Files under `/mnt/mmcblk0p2/tce/` are already persistent.

⚠️ **`/opt` is tmpfs restored from that archive at boot, so tar carries the file mode.**
A script that loses its execute bit there is a latent brick that only fires on the next
reboot: `/opt/bootsync.sh` invokes `/opt/bootlocal.sh` as an executable, and if that
fails silently `pcp_startup.sh` never runs — no SSH, no web UI, no squeezelite, no WiFi,
while the box still answers ping. Gate before shipping: `lint-exec-bits.sh --tar <archive>`.

## 7. Verification traps (learned the hard way)

- **`/proc/<pid>/cmdline` is NOT evidence of what a process received.** squeezelite
  `strtok`s colon args in place, so a correctly-passed MAC shows as
  `-m aa bb cc dd ee ff` after parsing. Read the program's own log
  (`-d slimproto=info` → `sendHELO mac: ...`).
- **`hw_ptr` advancing does NOT prove audible audio** — idle squeezelite feeds silence.
- **A DAC's USB mute may not gate its analog output.** On the D30 Pro, muting across the
  whole buzz window changed the control state but silenced nothing.
- **Assert content, not status codes** (§2), and make any diff-based gate assert its
  inputs are non-empty first — `tar -tvf --numeric-owner X` puts the flag in the filename
  slot, yielding an empty listing and a vacuous PASS.
