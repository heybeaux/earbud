## Context

`heybeaux/fieldy-local` (October 2026) mapped the Fieldy 3 (model FL3B,
firmware 3.3.5) Bluetooth protocol and proved a full local path in Python:
pair, set clock, download stored recordings, decode Opus, transcribe with
Whisper. Facts that shape this design:

- Offline storage (`...66E1`) and the manifest (`...66E6`) need a bonded,
  encrypted link. Other characteristics do not.
- The device keeps one bond. A Fieldy paired with a phone refuses the Mac until
  it is factory reset. After a reset, macOS bonds silently (Just Works) on the
  first protected read.
- A reset clears the device clock. Until the clock is set, the button gives two
  short buzzes and records nothing (`TIME_NOT_SET`).
- The device deletes a file once it has sent it during a sync (transport v2),
  with or without an ACK. ACKs exist for transport v3.
- Audio is bare 40-byte Opus CELT frames, 16 kHz mono, 20 ms, with a small
  file header and optional trailer.
- A recording started from a computer (write `01` to `...66E7`) is stored like
  a button recording.

## Goals / Non-Goals

**Goals:**
- A Mac app a stranger can install and set up from the DMG alone.
- No recording is ever lost by EarBud, including on crash, quit, or sleep.
- Everything except the one-time model download works offline.

**Non-Goals:**
- iPhone app (planned next; the core package is written to be shared).
- Automatic background sync, AI summaries, speaker labels, firmware updates,
  multiple devices, any server.

## Decisions

### Swift + SwiftUI, macOS 14+, Apple silicon only
Native CoreBluetooth gives the same bonding behaviour we proved. SwiftUI keeps
the UI small. Apple silicon only keeps transcription fast and the build simple.
Alternatives: Electron/Tauri wrapping the Python tools (bundling Python and
BLE in a web shell is fragile), Python GUI (poor packaging and look).

### Code layout: one shared package, thin app
- `EarBudKit` (Swift package, no UI, also builds for iOS):
  `FieldyProtocol` (pure parsing and command building, fully unit tested),
  `FieldyDevice` (CoreBluetooth actor: scan, connect, bond, clock, status,
  controls), `SyncEngine` (download with durable writes), `AudioCodec`
  (Opus to PCM, PCM to M4A/WAV), `Transcriber` (WhisperKit wrapper and queue),
  `Library` (storage and search).
- `EarBud` (macOS app target): SwiftUI views, menu bar, notifications,
  onboarding.

### Durable download (most important)
`SyncEngine` opens `raw/<syncID>/<fileID>.part`, appends each payload and calls
`FileHandle.synchronize()` per packet before it returns from the notify
handler. On EOF it renames `.part` to `.bin`, then (v3 only) sends the ACK.
Decoding, library insertion, and transcription run only from the `.bin` file.
On launch, any `.part` file is decoded up to its last whole frame and imported
as "Incomplete". The device keeps a file after an interrupted sync and sends it
whole next time; the "Incomplete" copy then moves to Recently Deleted.
`...66E1` is never read while its notifications are on (CoreBluetooth cannot
tell the reply from a notification). Raw files are deleted only after the decoded recording is
verified (frame count matches, M4A written) and 7 days have passed.
Alternative considered: buffer in memory and write on EOF. Rejected because
the device has already deleted the data by then.

### Storage
`~/Library/Application Support/EarBud/`:
- `library.sqlite` (GRDB): recordings, segments, sync history, settings.
  Transcript search uses SQLite FTS5.
- `audio/YYYY/MM/<recordingID>.m4a` (AAC 32 kbit/s, converted from Opus
  for playback with AVFoundation), plus the original `.opus` frames.
- `raw/` as above. `models/` for WhisperKit.

### Transcription
WhisperKit with `openai_whisper-small.en` ("More accurate", default) and
`openai_whisper-base.en` ("Faster"). English only in v1. Segments use
WhisperKit's `noSpeechProb`; segments above the threshold are dropped, and an
empty result shows "No speech detected". Queue state is in SQLite, so it
resumes after relaunch.

### Device clock and identity
On connect: write `0x2A2B` (UTC, year big-endian, weekday Mon = 1), ACK a
pending reset report on `...66EE`, read DIS for model and firmware. The paired
device is remembered by its CoreBluetooth peripheral identifier.

### Detecting "paired elsewhere"
If protected reads return ATT 0x0F or 0x05 for 15 seconds (three attempts)
while unprotected reads succeed, EarBud reports "Paired with another device".

### Notch dock
A borderless, non-activating `NSPanel` (status-bar window level, joins all
Spaces, not shown over full-screen apps) hosts SwiftUI content. Notch
geometry comes from `NSScreen.safeAreaInsets.top` and
`auxiliaryTopLeftArea`/`auxiliaryTopRightArea`; a screen with zero top inset
gets the floating capsule instead. Hover uses a tracking area with a 0.5 s
delay; expansion animates the panel frame downward. The panel ignores
mouse events outside its visible shape so menu-bar clicks pass through. It
observes `SyncEngine` and `FieldyDevice` state, so every sync entry point
drives the same live activity. Implemented from scratch: Vorssaint and Boring
Notch are GPL-3.0, so we study their behaviour, not their code.

### Distribution
Developer ID signed, hardened runtime, notarized DMG built by a script in the
repo. Bluetooth usage string in Info.plist. No auto-update in v1; the About
window links to GitHub releases.

## Risks / Trade-offs

- [Firmware changes the protocol] → EarBud reads the firmware version and
  shows "This Fieldy firmware has not been tested with EarBud" for versions other
  than 3.3.5, but still attempts sync. Parsing is isolated in `FieldyProtocol`.
- [Interrupted sync may lose the rest of a file on the device] → Not yet
  tested. Before release, test pulling the device out of range mid-file and
  record the result in the protocol doc. The UI never claims the device keeps a
  copy.
- [Model download (~250 MB) on slow connections] → resumable download, clear
  size up front, app usable without it.
- [User loses Fieldy phone app access after the reset] → stated before the
  reset, and requires explicit confirmation.
- [macOS changes notch window behaviour in a future release] → the dock is
  optional and isolated in its own module; the menu bar is always available.
- [Trademark] → name EarBud, "works with Fieldy 3" wording only, no Field Labs
  assets.

## Open Questions

- App icon and visual style: mockups to be approved by Beaux before the UI
  build (task 7.1).

Resolved 2026-10-30 (Beaux): spec approved; English only for v1; mockups
before UI; public repo `heybeaux/earbud` approved.

## Notch dock details approved by Beaux (2026-10-30)

Small gaps filled while building 9.4 and 9.5, all approved:

- The capsule has a fixed width per state; long names or messages are cut off.
- It sits 8 pt below the menu bar (8 pt below the top on a display without one).
- Resting text: "● Fieldy 3A7C | Synced 23m ago", "Synced just now", "Not synced yet".
- "Menu bar only" is the existing "Show EarBud in the notch" switch turned off.
- An unplugged chosen display stays selected, shown as "Name (not connected)".
- Displays are matched by name; two identical monitors cannot be told apart.
- With no setting and no built-in display, the dock is menu bar only.
- A display with a notch always gets the notch dock, never the capsule.
- "Not now" in onboarding saves the dock as off.
- The recording capsule has no hover Stop button; the quick panel's Record
  button becomes Stop.
