## Why

Fieldy 3 owners depend on the Fieldy phone app and Field Labs' cloud to get
their recordings back. When that service fails, the recordings are stuck on the
wristband. The `fieldy-local` project has now proved that a computer can pair
with the device, download its recordings over Bluetooth, and transcribe them
locally, but only from a terminal. EarBud packages that as a Mac app that a
non-technical Fieldy owner can install, set up, and use once a day.

## What Changes

- New macOS app, **EarBud**, distributed as a signed and notarized DMG.
- First-run onboarding that explains what EarBud does, then guides the user
  through factory-resetting the Fieldy, pairing it with the Mac, and setting its
  clock. No terminal, no Python.
- A **Sync** action that downloads every recording from the device, saves each
  one safely before anything else happens, and transcribes it on the Mac.
- A recordings library: recordings grouped by day, with playback, transcript,
  search, copy, export, and delete.
- A device panel: battery, storage, firmware, recording mode, LED, mute,
  "buzz my Fieldy", and start/stop recording from the Mac.
- A once-a-day sync reminder, with a menu-bar icon that shows when the device
  was last synced.
- An optional notch dock: EarBud can live around the MacBook camera notch,
  showing sync and recording status at a glance and expanding on hover, with a
  floating capsule for screens without a notch. Inspired by Vorssaint; written
  from scratch.
- On-device speech-to-text. Audio and transcripts never leave the Mac. The only
  network use is the one-time speech model download, which the user approves.

Out of scope for v1: iPhone app, automatic background sync, AI summaries,
speaker labels, live streaming, firmware updates, multiple devices, any cloud
service.

## Capabilities

### New Capabilities
- `onboarding`: first-run welcome, plain-language explanation, permissions, and
  the guided device setup (reset, pair, set clock, test recording).
- `device-connection`: finding the Fieldy, pairing, detecting a device that is
  paired elsewhere, keeping the device clock set, and reporting connection state.
- `recording-sync`: the Sync action, durable saving of downloaded audio,
  progress, interruption handling, and the sync history.
- `transcription`: speech model download, on-device transcription queue,
  retry, and the user's model choice.
- `recordings-library`: browsing, playback, transcript view, search, export,
  and deletion of recordings on the Mac.
- `device-controls`: device status and the settings the Fieldy exposes
  (recording mode, LED, mute, buzz, record from Mac).
- `sync-reminder`: menu-bar status and the daily reminder notification.
- `notch-dock`: the optional notch (or floating capsule) surface with live
  sync and recording status and an expanded quick panel.

### Modified Capabilities
- None. This is a new product.

## Impact

- New repo `heybeaux/earbud` (Swift, Xcode project, SwiftUI, macOS 14+,
  Apple silicon).
- Dependencies: CoreBluetooth (system), WhisperKit (MIT, on-device Whisper),
  libopus (BSD) via a Swift package.
- Reuses the protocol documented in `heybeaux/fieldy-local/docs/protocol.md`.
  EarBud contains no Field Labs code or assets.
- Signing and notarization use the existing Developer ID and App Store Connect
  key.
- Licensing: Vorssaint and Boring Notch are GPL-3.0. EarBud copies no code
  from them, so EarBud stays MIT.
- Trademark: the app is named EarBud and says "works with Fieldy 3". It does
  not use Field Labs logos or imply endorsement.
