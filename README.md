# CamCoreEQ

Independent real-time parametric EQ and playback control for CamillaDSP on piCorePlayer.

> **CamCoreEQ is an independent community project and is not affiliated with or endorsed by the
> CamillaDSP or piCorePlayer projects.**

A single-page web application that drives a running [CamillaDSP](https://github.com/HEnquist/camilladsp)
instance live over its control WebSocket. Drag EQ nodes on a response graph and hear the change
immediately; save a curve to the player when you want it to survive a reboot. It runs from the
piCorePlayer box itself, or from the companion Android app.

---

## What it does

**Parametric EQ** — draggable Peaking / Low-shelf / High-shelf bands on a log-frequency response
graph. Drag a node for frequency and gain, wheel for Q, double-click to add or delete, arrow keys to
nudge. Per-band enable/disable.

**Clip-safe automatic preamp** — computes the true combined peak on a dedicated 2000-point grid and
attenuates to sit just under the limiter ceiling, so a boosted band cannot clip the DAC. Manual
override available.

**Crossfeed** — two models: *Classic* (mono-flat mid/side, no coloration) and *Spatial* (delayed
cross with inter-aural delay and a mono-compensation shelf), with a computed separation and
comb-response visualiser.

**Loudness** — a static, drawable bass-weighted shelf pair tied to your listening level, kept
deliberately separate from the curve so loading a headphone preset does not disturb it.

**Imported biquads** — REW biquad exports import losslessly as raw coefficient stacks rather than
being reverse-solved, and are folded into the auto-preamp peak so imported coefficients are
clip-protected too. Equalizer APO / AutoEQ text, JSON and YAML profiles import as editable bands.

**Export** — APO/Peace, AutoEQ, Oratory, JSON, YAML and raw biquad text.

**A/B slots, undo/redo, presets** — two independently editable slots with an optional ghost overlay
and level-matched comparison; named presets stored on the player.

**Live output meter** — true peak-meter ballistics with peak hold, a limiter-active indicator and
real clipping detection.

**Transport and now-playing** — play/pause/next/previous plus track metadata and album art, when a
Lyrion Music Server (LMS) is present. This is optional; the EQ works fully without it.

**Diagnostics** — CamillaDSP engine state, processing load, buffer level, ALSA hardware parameters,
device sample rate and format, host health, and an on-device output log.

---

## Requirements

- piCorePlayer with CamillaDSP running, its control WebSocket reachable (default port `1234`)
- squeezelite configured to output through CamillaDSP
- A browser, or the Android app
- Optional: a Lyrion Music Server for transport control, track metadata and artwork

Developed and tested against piCorePlayer 11.1 (32-bit armv7 userland) with CamillaDSP 4.1.3 on a
Raspberry Pi 4 and a USB DAC. Other configurations are likely to work but are unverified.

---

## Install

See [`docs/INSTALL.md`](docs/INSTALL.md). It covers the parts that are easy to get wrong:

- the web server needs **its own** `httpd.conf`, because piCorePlayer's global one overrides the
  document-root flag and will silently serve the wrong directory
- the LMS port is not fixed, so the CGI scripts probe for it instead of hardcoding
- optional fix for USB DACs that emit a loud buzz during boot before the player starts
- how to avoid a phantom I2S card configuration that bypasses the EQ entirely
- which files are persistent and which need an explicit backup step

---

## Security

Please read this before exposing the box to an untrusted network.

The control endpoints are **unauthenticated** and send `Access-Control-Allow-Origin: *`. That is what
lets the editor run from the Android app, but it also means **any web page loaded in a browser on
your network can reach them** if it knows or guesses the player's address. Some are destructive:
saving overwrites the boot configuration, preset deletion happens over a plain `GET`, and transport
commands control playback.

The practical consequences:

- Keep the player on a trusted LAN. Do not port-forward it to the internet.
- Treat this as a tool for a private network, not a hardened appliance.

This is inherent to the current design rather than a regression, and hardening it is tracked as
future work. If you need authentication today, put the player behind a reverse proxy that provides it.

---

## Android app

An Android client is included. It bundles the web application and updates itself over the air, so the
app can be installed once and then track releases without reinstalling.

It must load its own document over plain HTTP. A browser tab served over HTTPS **cannot** talk to
CamillaDSP at all, because an insecure WebSocket from a secure page is blocked outright by every
modern browser and CamillaDSP does not offer TLS. That is a browser security rule, not a limitation
of this project, and it is why a hosted web version is not offered.

See [`android/README.md`](android/README.md) for building and installing.

---

## Trademarks

CamillaDSP and piCorePlayer are the work and property of their respective authors. CamCoreEQ names
them only to describe what it interoperates with. It is not produced, endorsed, reviewed, or
supported by either project, and nothing in this repository should be read as implying otherwise.
Please direct CamCoreEQ issues here rather than to those projects.
