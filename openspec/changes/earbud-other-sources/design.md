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
"Wireless PRO RX"), and `contentHash` (SHA-256 of an imported file). Migration `v2` sets
`source = 'fieldy'` on existing rows. Fieldy-only fields (`syncId`,
`deviceFileId`, `frameCount`, `opusPath`) stay nullable or zero for other
sources. `rawPath` stays NOT NULL: for imports it points at the full-size copy,
for microphone recordings at the capture file. When that file is deleted
(imports: right after verification; captures: after 7 days), `rawDeletedAt`
is set, exactly as for Fieldy raw files.
Alternative: a separate table per source. Rejected because search, list,
export, and trash would all need unions.

### Import copies the file, then keeps only the compressed audio
EarBud copies each imported file into `imported/<id>.<ext>.part` before
anything else, then works only from the copy. Once the playback M4A is written
and verified (readable, length within 0.25 s of the source), the copy is
deleted. The library keeps only the M4A, so a 32-bit float hour from a RØDE
transmitter (about 690 MB) costs about 30 MB. The user's original is never
touched, and moving or deleting it later never breaks the library. Duplicate
detection still works after the copy is gone, because the hash is stored.
Trade-off: audio export is from the M4A, not a lossless file; the user still
has their original.
Alternative: reference the file in place with a security bookmark. Rejected
because external drives and cleaned-up Downloads folders would leave dead
recordings. (Decided by Beaux, 2026-10-30.)

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

### Transcripts outlive audio
Today a recording row owns its audio files and its `segment` rows (cascade
delete). The row becomes the durable entry: date, title, source, length, and
transcript. Audio becomes an attachment the user can remove. New columns:
`audioDeletedAt` (audio in Recently Deleted since) and `audioPurgedAt` (files
gone). Delete Audio moves the M4A (and `.opus`, if any) into
`trash/audio/<id>/` and sets `audioDeletedAt`; restore moves them back;
the 30-day purge, or Empty Recently Deleted, removes the files and sets
`audioPurgedAt`. The row and its segments are untouched, so search and text
export keep working. Full Delete is unchanged and still removes everything.
The action is offered only when `transcriptState` is `done`, so EarBud can
never be left with neither audio nor words. Automatic cleanup (off by default)
runs at launch and once a day, and only picks transcribed recordings past the
chosen age. Fieldy raw files keep their own 7-day rule.
Alternative: a separate transcript table independent of recordings. Rejected
as unnecessary; the row already holds everything a transcript needs, and one
table keeps search and the list simple. (Requested by Beaux, 2026-10-30.)

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

- [Imported copies need space while processing] → The copy exists only
  until its M4A is verified; Settings > Storage shows audio and transcript
  sizes.
- [The `bext` time is in the recorder's local time with no time zone] →
  Interpret it as the Mac's current time zone; document this.
- [Long transcriptions keep the Mac busy] → Run at utility priority, one file
  at a time.
- [Untested with a real RØDE Wireless PRO] → Acceptance includes a real
  import and a real live recording with Beaux's unit.

## Decisions by Beaux (2026-10-30)

1. Keep only the compressed copy once it is checked; the imported original
   copy is deleted after verification.
2. Dropping a folder imports every audio file inside it, including subfolders,
   with one summary at the end.
3. Transcripts are independent of audio: the user can delete audio to save
   space and keep the transcript.
