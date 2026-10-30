## 1. Project setup

- [ ] 1.1 Create `heybeaux/earbud` repo with Xcode project (macOS 14+, arm64), `EarBudKit` Swift package, MIT license, README
- [ ] 1.2 Add dependencies: WhisperKit, GRDB, an Opus decoder package (libopus)
- [ ] 1.3 CI: build and unit tests on every push (GitHub Actions, macOS runner)

## 2. Protocol (EarBudKit/FieldyProtocol)

- [ ] 2.1 Parse storage status, recording status, reset report, profile status
- [ ] 2.2 Build commands: sync start, ACK, retry, drop; clock payload
- [ ] 2.3 Parse sync notifications (v1, v2, v3 packets; end, no files, header, file failed)
- [ ] 2.4 Parse file header (v1, v2 with CRC check) and trailer
- [ ] 2.5 Unit tests using byte fixtures captured from the real device (no personal audio)

## 3. Device (EarBudKit/FieldyDevice)

- [ ] 3.1 Scan, connect, remember peripheral, connection state stream
- [ ] 3.2 Bond via protected read; detect "paired elsewhere"
- [ ] 3.3 Clock write and reset-report ACK on every connect
- [ ] 3.4 Controls: recording mode, LED, mute, buzz, record start/stop, battery, DIS
- [ ] 3.5 Idle disconnect

## 4. Sync (EarBudKit/SyncEngine)

- [ ] 4.1 Durable per-packet writes, `.part` to `.bin`, v3 ACK after flush, retry/drop
- [ ] 4.2 Progress by bytes; sync history records
- [ ] 4.3 Crash recovery of `.part` files on launch
- [ ] 4.4 Opus to PCM to M4A; frame-count verification; raw cleanup after 7 days
- [ ] 4.5 Test on device: interrupt mid-file (out of range, quit, sleep); document what the device keeps

## 5. Transcription (EarBudKit/Transcriber)

- [ ] 5.1 Model download with consent, progress, resume, "Later"
- [ ] 5.2 Persistent queue, oldest first, resumes after relaunch
- [ ] 5.3 Segments with timestamps; drop no-speech segments; "No speech detected"
- [ ] 5.4 Faster / More accurate setting; transcribe again; failure + retry

## 6. Library (EarBudKit/Library + app views)

- [ ] 6.1 SQLite schema, FTS5 search
- [ ] 6.2 Day-grouped list with empty state
- [ ] 6.3 Detail: player, speed, segment highlight, click-to-seek
- [ ] 6.4 Copy, export (M4A/WAV, TXT/Markdown), rename, delete with 30-day Recently Deleted, Show in Finder

## 7. Onboarding

- [ ] 7.1 Visual design proposal (icon, palette, onboarding illustrations) for Beaux's approval
- [ ] 7.2 Welcome, Bluetooth permission (granted and denied paths)
- [ ] 7.3 Find device, paired-elsewhere warning and confirmation, reset steps with "It didn't work" help
- [ ] 7.4 Pair, clock, model download step, test recording to transcript
- [ ] 7.5 Optional launch at login

## 8. Device panel, menu bar, reminders

- [ ] 8.1 Device panel with status and controls (read-back confirmation)
- [ ] 8.2 Menu-bar icon and menu; working state; toggle in Settings
- [ ] 8.3 Daily reminder notification, interval/time settings, click-to-sync

## 9. Release

- [ ] 9.1 DMG build script: sign (Developer ID), hardened runtime, notarize, staple
- [ ] 9.2 Verify signed DMG on a clean macOS user account
- [ ] 9.3 Fresh-install walkthrough by someone new to EarBud, Fieldy starting paired to a phone; fix every confusing step
- [ ] 9.4 GitHub release with notes, link from `fieldy-local` README
