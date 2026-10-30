# EarBud

A Mac app for the Fieldy 3 wristband recorder. EarBud copies your recordings
from the Fieldy to your Mac over Bluetooth and turns them into text on your Mac.
No phone app, no account, no cloud.

> **Status: spec approved, build not started.** The v1 specification is the
> OpenSpec change in [`openspec/changes/earbud-mac-v1/`](openspec/changes/earbud-mac-v1/).
> Start with [`proposal.md`](openspec/changes/earbud-mac-v1/proposal.md).

## Planned for v1

- Guided setup: reset, pair, and set the clock on your Fieldy, with pictures.
- One-click sync, once a day. Each recording is saved the moment it arrives.
- On-device transcription with Whisper (WhisperKit), English only in v1.
- A library of recordings by day, with playback, search, and export.
- Device controls: battery, storage, recording mode, light, mute, buzz.
- Menu-bar status, a daily reminder, and an optional dock around the MacBook
  camera notch.

Requires macOS 14 or later on an Apple silicon Mac.

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
