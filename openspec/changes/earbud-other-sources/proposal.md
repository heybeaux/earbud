## Why

EarBud v1 only knows one recorder: the Fieldy 3. People who use EarBud also
own better microphones (for example a RØDE Wireless PRO for meetings, talks,
or podcasts) and already have audio files from other recorders. They want the
same thing EarBud gives Fieldy recordings: one private library, transcribed on
the Mac, searchable, with nothing sent to a server. A Fieldy microphone on a
wrist is fine for notes, but a lapel microphone gives far better transcripts.

## What Changes

Two additions, built and released in this order. Each one is useful alone.

1. **Import audio files (v1.1).** The user can drag audio files into EarBud,
   or choose **File > Import Audio…**. EarBud copies each file into its
   library, transcribes it on the Mac, and lists it with the Fieldy
   recordings. This covers RØDE Wireless PRO onboard recordings (exported with
   RØDE Central), Voice Memos, handheld recorders, and any WAV, AIFF, CAF,
   M4A, MP3, or FLAC file.
2. **Record from any Mac microphone (v1.2).** A new **Record with** setting
   chooses what the Record button uses: the Fieldy (default, as in v1) or any
   microphone the Mac sees, such as the RØDE Wireless PRO receiver plugged in
   over USB-C. EarBud records to disk as it goes, so a crash or quit loses
   nothing, then transcribes the recording like any other.

Recordings from every source share one library, one search, one export, and
one trash. Each recording shows where it came from.

Out of scope: audio from video files, separate tracks per speaker, speaker
labels, live transcription while recording, recording system audio or other
apps, editing or trimming audio, using EarBud without a Fieldy (onboarding is
unchanged), and any cloud service.

## Capabilities

### New Capabilities
- `audio-import`: importing audio files into the library, duplicate
  detection, recording time from file metadata, transcription of long files.
- `mic-recording`: the Record with setting, microphone choice and permission,
  durable recording to disk, device unplug handling, and controls in the main
  window, menu bar, and notch dock.

### Modified Capabilities
- None formally. `earbud-mac-v1` is not archived yet, so this change adds new
  capabilities only. Where it changes v1 behaviour (the library shows a source
  for each recording; the Record button follows the Record with setting), the
  requirement is stated in the new capability.

## Impact

- `Library`: new columns `source`, `sourceName`, `originalPath`,
  `contentHash`, and a migration. Existing recordings become source `fieldy`.
- New `AudioIngest` module in EarBudKit: decode any AVFoundation-readable file
  to M4A plus 16 kHz mono for transcription, in chunks.
- New `MicRecorder` in the app target (AVAudioEngine; macOS only).
- `Transcriber`: chunked input so a 3-hour file does not load into memory at
  once.
- Info.plist gains `NSMicrophoneUsageDescription`; the hardened-runtime
  entitlements gain `com.apple.security.device.audio-input` (v1.2 only).
- No new third-party dependencies. FLAC and MP3 decode with the system
  frameworks.
