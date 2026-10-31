# EarBud

A Mac app for the Fieldy 3 wristband recorder. EarBud copies your recordings
from the Fieldy to your Mac over Bluetooth and turns them into text on your Mac.
No phone app, no account, no cloud.

> **Status: in development, not yet released.** EarBud already sets up, syncs,
> and transcribes a real Fieldy 3 end to end. There is no signed download yet.
> Work in progress is on the
> [`feat/app-ui`](https://github.com/heybeaux/earbud/tree/feat/app-ui) branch.
> The v1 specification is the OpenSpec change in
> [`openspec/changes/earbud-mac-v1/`](openspec/changes/earbud-mac-v1/).

## What works today

- Guided setup: reset, pair, and set the clock on your Fieldy, with pictures.
- One-click sync. Each recording is saved to disk the moment it arrives, so an
  interrupted sync loses nothing.
- On-device transcription with Whisper (WhisperKit), English only in v1.
- A library of recordings by day, with playback and transcripts.
- A daily sync reminder and menu-bar status.
- An optional dock around the MacBook camera notch.

Still to come before the first release: a floating capsule for Macs without a
notch, a signed and notarized download, and a fresh-install test by someone
new to EarBud.

Requires macOS 14 or later on an Apple silicon Mac.

## The Fieldy hardware

The Fieldy 3 is a simple device. It is a Bluetooth audio recorder with a
button and a light. Everything "smart" about it (transcripts, summaries, search)
happened on Field Labs' servers, not on your wrist.

| Part | What it is |
|------|------------|
| Processor | A low-power Bluetooth microcontroller, most likely a Nordic nRF5340 (two Arm Cortex-M33 cores, up to 128 MHz, 1 MB flash, 512 KB RAM). The same chip family runs fitness bands and wireless earbuds. |
| Operating system | Zephyr, an open-source real-time OS for small devices, with the MCUboot bootloader. |
| Recording storage | A Micron NAND flash chip. |
| Power | An Analog Devices ADP5360 battery charger and power manager. |
| Radio | Bluetooth Low Energy only. No Wi-Fi, no cellular, no GPS. |
| USB port | Charging, plus a read-only debug log. No file access over USB. |

The device does three things: record audio from its microphone, compress it,
and send it over Bluetooth when asked. Audio is Opus at 16 kHz mono, about
16 kbit/s, so one hour of speech is about 7 MB. That is small enough to copy
over Bluetooth Low Energy.

The processor is far too small to run speech recognition. A modern Mac is not.
Whisper on Apple silicon transcribes faster than real time, without sending
audio anywhere.

Detailed notes, including how each part was identified, are in
[fieldy-local/docs/hardware.md](https://github.com/heybeaux/fieldy-local/blob/main/docs/hardware.md).

## Why this approach is new

When a cloud-tied gadget loses its service, the usual options are to throw it
away, or to open it up and flash new firmware. Flashing usually means taking
the case apart, soldering to debug pads, and erasing the original software for
good.

EarBud does neither. It leaves the Fieldy's own firmware untouched and talks to
the device the way the official phone app does, using the device's own
Bluetooth commands:

- **No hardware changes.** Nothing is opened, soldered, or flashed. The
  factory firmware stays as it is. Setup does one factory reset (with the
  button) to move the pairing from your phone to your Mac.
- **No account and no server.** The Fieldy never needed the cloud to record or
  to hand over audio. Only the app did. EarBud replaces the app.
- **No phone.** The Mac pairs with the Fieldy directly.
- **Private by design.** Audio and transcripts stay on your Mac.

The Bluetooth protocol was worked out by observing the device and the official
app's traffic, then described in our own words in
[fieldy-local/docs/protocol.md](https://github.com/heybeaux/fieldy-local/blob/main/docs/protocol.md).
EarBud contains no Field Labs code.

## Background

The Bluetooth protocol work lives in
[heybeaux/fieldy-local](https://github.com/heybeaux/fieldy-local), including
command-line tools that already sync and transcribe.

## Legal

EarBud is an independent project. It is not affiliated with or endorsed by
Field Labs Inc. "Fieldy" is a trademark of its owner. EarBud contains no Field
Labs code or assets.

## License

MIT. See [LICENSE](LICENSE).
