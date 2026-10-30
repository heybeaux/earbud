# Real-device proof

Status (2026-10-30): **not completed. The Fieldy was not reachable.**

## What happened

- Bluetooth works from `earbud-cli` (authorized; `earbud-cli scan --all`
  lists nearby advertisers).
- macOS lists the bonded device as `Fieldy-654B` (F3:D3:C0:E0:22:11), not
  connected.
- From 13:59 to 14:48 PDT the CLI scanned and tried to connect about 120
  times. The Fieldy advertised once, at 14:16:04, as `Fieldy4B`
  (CoreBluetooth identifier `6856C89A-348F-595F-6C3C-EDC5886BB021`) at
  RSSI -101 dBm, the edge of range. Every connect attempt (20 s timeout)
  timed out, and it was not seen again. It is probably out of range or
  asleep.
- No commands were sent to the device. Its clock, mode, LED, mute, and
  storage are unchanged.

## Transcription without the device

The WhisperKit path was checked with speech from macOS `say`:

```
$ earbud-cli transcribe --out /tmp/eb-proof-lib /tmp/eb-say.aiff
downloading More accurate model openai_whisper-small.en (about 490 MB) ...
model ready at /tmp/eb-proof-lib/models/models/argmaxinc/whisperkit-coreml/openai_whisper-small.en (486 MB)
audio: 3.99 s
[00:00] Testing your bud.
[00:01] We drove up Two Powell River on Friday.
```

## To finish the proof

With the Fieldy awake and next to the Mac:

```
swift build
.build/debug/earbud-cli scan
.build/debug/earbud-cli status --device <identifier>
.build/debug/earbud-cli record 10 --device <identifier>
.build/debug/earbud-cli sync --device <identifier> --out /tmp/eb-proof-lib --wav
```

Expected: `status` prints clock, battery, DIS, recording status, and storage.
`record 10` shows state starting, then active, then stopped. `sync` writes
one `raw/<syncID>/<fileID>.bin`, decodes about 10 s of audio, and prints a
transcript (or "No speech detected" if the room is quiet). Then capture the
real v2 file header (the first `headerLen` bytes of the `.bin`, no audio) as
a test fixture and confirm the CRC-16/XMODEM check passes on it.
