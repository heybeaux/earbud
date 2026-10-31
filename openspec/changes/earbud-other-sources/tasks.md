## 1. Library (shared)

- [ ] 1.1 Migration v2: `source`, `sourceName`, `originalPath`, `contentHash`; existing rows become `fieldy`; raw cleanup limited to `fieldy`
- [ ] 1.2 Source shown in list rows and the detail view (Fieldy, file name, microphone name)
- [ ] 1.3 Chunked transcription input: 10-minute windows, 5-second overlap, de-duplicated segments, percent progress in the row

## 2. Import audio files (v1.1)

- [ ] 2.1 `AudioIngest` module: AVAudioFile decode in 30-second blocks to playback M4A and 16 kHz mono for the recognizer; unit tests with generated WAV/AIFF/CAF/M4A/FLAC/MP3 fixtures, including 32-bit float and stereo
- [ ] 2.2 Copy-first import with SHA-256 duplicate check (including trash) and cleanup of partial copies on launch
- [ ] 2.3 Recording time: Broadcast WAV `bext`, M4A/MP3 creation metadata, file date fallback with "Time taken from the file"
- [ ] 2.4 Drag and drop onto the window and Dock icon, File > Import Audio…, recursive folders, import summary sheet
- [ ] 2.5 Mockups for the drop target, import summary, and source labels; Beaux approves before 2.4 UI code
- [ ] 2.6 Acceptance: import a real RØDE Wireless PRO onboard recording exported from RØDE Central, plus a Voice Memos M4A and a 3-hour file; check time, playback, transcript, search, duplicate skip

## 3. Record from a Mac microphone (v1.2)

- [ ] 3.1 Input device list (Core Audio) with live plug/unplug updates; Record with setting in Settings > Recording
- [ ] 3.2 `MicRecorder`: AVAudioEngine tap to `capture/<id>.caf.part`, 1-second flush, rename on Stop, ingest through `AudioIngest`; `.caf.part` recovery on launch
- [ ] 3.3 Microphone permission on first use, denied state with System Settings link; entitlement and usage string
- [ ] 3.4 Record and Stop with elapsed time and input level in the main window, menu bar, and notch dock; button shows the chosen source
- [ ] 3.5 Missing-microphone prompt; stop and save on unplug or sleep with a notification
- [ ] 3.6 Mockups for the Record with setting, recording state, and missing-microphone prompt; Beaux approves before 3.4 UI code
- [ ] 3.7 Acceptance: live recording through Beaux's RØDE Wireless PRO receiver, an unplug mid-recording, and a force quit mid-recording
