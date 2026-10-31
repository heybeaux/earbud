## 1. Library (shared)

- [x] 1.1 Migration v2: `source`, `sourceName`, `contentHash`; existing rows become `fieldy`; `rawDeletedAt` set when an import copy or capture file is removed
- [x] 1.2 Source shown in list rows and the detail view (Fieldy, file name, microphone name)
- [x] 1.3 Chunked transcription input: 10-minute windows, 5-second overlap, de-duplicated segments, percent progress in the row

## 2. Import audio files (v1.1)

- [x] 2.1 `AudioIngest` module: AVAudioFile decode in 30-second blocks to playback M4A and 16 kHz mono for the recognizer; unit tests with generated WAV/AIFF/CAF/M4A/FLAC/MP3 fixtures, including 32-bit float and stereo
- [x] 2.2 Copy-first import with SHA-256 duplicate check (including trash), deletion of the full-size copy once the M4A is verified, and cleanup of partial copies on launch
- [x] 2.3 Recording time: Broadcast WAV `bext`, M4A/MP3 creation metadata, file date fallback with "Time taken from the file"
- [x] 2.4 Drag and drop onto the window and Dock icon, File > Import Audio…, recursive folders, import summary sheet
- [x] 2.5 Mockups for the drop target, import summary, and source labels; Beaux approves before 2.4 UI code
- [ ] 2.6 Acceptance: import a real RØDE Wireless PRO onboard recording exported from RØDE Central, plus a Voice Memos M4A and a 3-hour file; check time, playback, transcript, search, duplicate skip

## 3. Keep the transcript, delete the audio (v1.1)

- [x] 3.1 Migration: `audioDeletedAt`, `audioPurgedAt`; move audio to `trash/audio/<id>/` and back; purge after 30 days or on Empty Recently Deleted; unit tests that segments and search survive every step
- [x] 3.2 Delete Audio, Keep Transcript for one or many recordings (detail view, context menu, Edit menu), disabled until the transcript is done; "Transcript only" state in the list and detail; audio export and playback disabled with a reason
- [x] 3.3 Recently Deleted lists deleted audio separately from deleted recordings, with Restore
- [x] 3.4 Settings > Storage: audio and transcript sizes, optional "Delete audio older than 30/90/365 days, keep transcripts" (off by default)
- [x] 3.5 Mockups for the Transcript only state, the delete-audio confirmation, and Settings > Storage; Beaux approves before 3.2 UI code

## 4. Record from a Mac microphone (v1.2)

- [ ] 4.1 Input device list (Core Audio) with live plug/unplug updates; Record with setting in Settings > Recording
- [ ] 4.2 `MicRecorder`: AVAudioEngine tap to `capture/<id>.caf.part`, 1-second flush, rename on Stop, ingest through `AudioIngest`; `.caf.part` recovery on launch
- [ ] 4.3 Microphone permission on first use, denied state with System Settings link; entitlement and usage string
- [ ] 4.4 Record and Stop with elapsed time and input level in the main window, menu bar, and notch dock; button shows the chosen source
- [ ] 4.5 Missing-microphone prompt; stop and save on unplug or sleep with a notification
- [ ] 4.6 Mockups for the Record with setting, recording state, and missing-microphone prompt; Beaux approves before 4.4 UI code
- [ ] 4.7 Acceptance: live recording through Beaux's RØDE Wireless PRO receiver, an unplug mid-recording, and a force quit mid-recording
