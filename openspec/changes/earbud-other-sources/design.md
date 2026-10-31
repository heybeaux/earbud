## Context

EarBud v1 (`earbud-mac-v1`) stores every recording in one SQLite library
(`Library` module, GRDB) with audio under
`~/Library/Application Support/EarBud/audio/YYYY/MM/<id>.m4a`. The
`RecordingImporter` turns raw Fieldy bytes into a library row, an `.opus` file
and an `.m4a`, then queues transcription. `Transcriber` reads the M4A as
16 kHz mono floats (`AudioFiles.readMono16k`) and runs WhisperKit.

Facts that shape this design:

- The app is not sandboxed. It is signed with hardened runtime, so microphone
  access needs the `com.apple.security.device.audio-input` entitlement and an
  `NSMicrophoneUsageDescription` string.
- The RØDE Wireless PRO receiver is a class-compliant USB audio device. macOS
  lists it as an ordinary input; no driver is needed. Its transmitters also
  record on board (up to 32-bit float WAV), and RØDE Central exports those
  files. These are expected behaviours, not yet tested with Beaux's unit.
- Fieldy recordings are short (seconds to minutes). Imported and microphone
  recordings can be hours long. One hour of 16 kHz mono float samples is about
  230 MB, so loading a whole file into memory is not acceptable.

## Goals / Non-Goals

**Goals:**
- Any common audio file, and any Mac microphone, ends up as a normal EarBud
  recording: playable, transcribed, searchable, exportable, deletable.
- The v1 durability promise holds for the new sources: a crash, quit, or
  unplugged microphone never loses audio already captured.
- The Fieldy path is unchanged.

**Non-Goals:**
- Video files, multitrack or per-speaker tracks, speaker labels, live
  transcription, system audio capture, audio editing, a Fieldy-free setup.

## Decisions

### One library, a `source` per recording
Add columns to `recording`: `source` (`fieldy`, `imported`, `microphone`),
`sourceName` (original file name, or the microphone name such as
"Wireless PRO RX"), `originalPath` (library-relative copy of an imported
file), and `contentHash` (SHA-256 of an imported file). Migration `v2` sets
`source = 'fieldy'` on existing rows. Fieldy-only fields (`syncId`,
`deviceFileId`, `frameCount`, `opusPath`) stay nullable or zero for other
sources. `rawPath` stays NOT NULL: for imports it points at the original copy,
for microphone recordings at the capture file. The raw-cleanup job runs only
for `source = 'fieldy'`.
Alternative: a separate table per source. Rejected because search, list,
export, and trash would all need unions.

### Import copies the file
EarBud copies each imported file into `imported/<id>.<ext>` before anything
else, then works only from the copy. Moving, renaming, or deleting the
original never breaks the library, and the user's original stays untouched.
The cost is disk space (a 32-bit float hour from a RØDE transmitter is about
690 MB). Alternative: reference the file in place with a security bookmark.
Rejected because external drives and cleaned-up Downloads folders would leave
dead recordings. Open question 1 asks whether to keep the copy forever.

### `AudioIngest`: decode with AVFoundation, write in chunks
A new EarBudKit module. It opens the copy with `AVAudioFile` (WAV, AIFF, CAF,
M4A, MP3, FLAC, any sample rate, 16/24/32-bit integer or float, mono or
stereo). It reads 30-second blocks, writes a playback M4A (AAC, source sample
rate, channels mixed to mono), and writes a 16 kHz mono float file
(`.f32`, removed after transcription) for the recognizer. Memory stays flat
for any length. Files the system cannot decode are rejected at drop time with
the file name and "EarBud can't read this kind of file."

### Chunked transcription
`TranscriptionQueue` gains a chunked input: WhisperKit runs on 10-minute
windows with 5 seconds of overlap, and segments in the overlap are kept from
the earlier window only. Fieldy recordings fit in one window, so their path
does not change. Progress for long files shows as a percentage in the list
row.

### Recording time
For imports, EarBud uses, in order: the BWF `bext` origination date and time
(written by RØDE and most field recorders), the M4A/MP3 creation date
metadata, then the file's creation date. When it falls back to the file date,
the detail view says "Time taken from the file", because a copied file can
carry the copy date. Editing the time is out of scope.

### Duplicates
Before copying, EarBud hashes the file. If a live or trashed recording has the
same `contentHash`, the file is skipped and the import summary says
"Already in EarBud". Hashing runs off the main thread and takes a few seconds even
for a 1 GB file.

### Microphone recording: AVAudioEngine to a CAF capture file
`MicRecorder` (app target) installs a tap on the input node of the chosen
device and writes 16-bit PCM at the device's sample rate, mixed to mono, to
`capture/<id>.caf.part`. It flushes every second. CAF tolerates an unknown
data length, so a file cut off by a crash is still readable. On Stop it
renames to `.caf`, then the normal ingest path makes the M4A and queues
transcription. On launch, any `.caf.part` is ingested as "Incomplete", the
same rule as an interrupted Fieldy sync. PCM costs about 5.8 MB a minute at
48 kHz; the capture file is deleted 7 days after the M4A is verified, matching
the Fieldy raw-file rule.
Alternative: write AAC directly. Rejected because an M4A cut off before its
index is written cannot be read.

### Choosing the microphone
Settings > Recording gains **Record with**: "Fieldy" (default) or a microphone
picker that lists Core Audio input devices by name, plus "Mac's default
input". EarBud remembers the device by its unique ID. If the chosen
microphone is not connected when the user presses Record, EarBud says
"Wireless PRO RX isn't connected" and offers the Mac's default input or
Cancel. It never silently records from a different microphone.

### Unplug and sleep during a recording
If the device disappears mid-recording (`AVAudioEngineConfigurationChange` or
the device leaving the Core Audio list), EarBud stops, keeps what it has,
ingests it, and shows a notification: "Recording stopped: Wireless PRO RX was
disconnected. 14 min saved." On sleep it stops and saves the same way.

### Permission
The macOS microphone prompt is asked the first time the user presses Record
with a microphone selected, not during onboarding (same lazy pattern as the
reminder permission). If denied, the Record button explains how to allow it in
System Settings and opens the Privacy & Security pane.

## Risks / Trade-offs

- [Disk use from copied 32-bit float files] → Show the library size in
  Settings; open question 1.
- [The `bext` time is in the recorder's local time with no time zone] →
  Interpret it as the Mac's current time zone; document this.
- [Long transcriptions keep the Mac busy] → Run at utility priority, one file
  at a time.
- [Untested with a real RØDE Wireless PRO] → Acceptance includes a real
  import and a real live recording with Beaux's unit.

## Open Questions

1. Keep the imported original forever (default here), or delete it after the
   M4A is verified and keep only the M4A? Keeping it costs disk; deleting it
   loses the lossless file.
2. Should drag and drop of a whole folder import every audio file inside it?
   This design says yes, recursively, with one summary at the end.
