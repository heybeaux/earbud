# EarBudKit decisions

Decisions made while building `EarBudKit` (tasks 1 to 6.1 of
`openspec/changes/earbud-mac-v1`). Newest last.

## Package layout

- One Swift package at the repo root, `EarBudKit`, Swift 6 language mode,
  macOS 14 and iOS 17. Modules: `FieldyProtocol`, `FieldyDevice`,
  `SyncEngine`, `AudioCodec`, `Transcriber`, `Library`, plus the
  `earbud-cli` executable. The app target (task 7+) will depend on the
  package by local path.
- `FieldyProtocol` has no dependencies and no I/O. It holds GATT UUIDs as
  strings so it builds without CoreBluetooth.
- Tests use swift-testing (`import Testing`).

## Opus decoder: vendored libopus via `alta/swift-opus` (Copus)

- `alta/swift-opus` vendors the libopus C sources as a SwiftPM C target
  (`Copus`, BSD-3-Clause). It compiles into our binary, so it works the same
  in a signed, hardened, notarized app bundle and on iOS, with no dylib to
  embed and no Homebrew at build or run time. CI needs nothing installed.
- Rejected: a system-library target against Homebrew's `/opt/homebrew/lib`
  (`libopus.dylib`). It would build only on machines with Homebrew, and an
  app would have to embed and re-sign the dylib.
- The package's last tag (0.0.2) is old, so we pin the `main` revision
  `6f3cb6bd` (June 2024). Revision pins are allowed for a root/local package;
  if EarBudKit ever becomes a versioned dependency of something else, fork and
  tag it.
- We use only the C API (`Copus`), not the package's AVAudioFormat wrapper.
  `opus_*_ctl` is variadic and not callable from Swift, so the small C target
  `COpusShim` wraps the two calls we need: a Fieldy-format encoder (CELT-only
  restricted-low-delay, 16 kbit/s CBR: 40-byte frames with TOC `0xB8`, used
  by tests to make realistic fixtures) and decoder reset.
- A frame libopus rejects is replaced by packet-loss concealment, so decoded
  length is always `frames x 20 ms`; the count is reported as `failedFrames`.

## Durable download

- `DurableSyncWriter.handle(_:)` runs synchronously inside CoreBluetooth's
  `didUpdateValueFor` callback (the delegate queue is the queue that owns
  all Bluetooth state). It appends the payload to `raw/<syncID>/<fileID>.part`
  and calls `FileHandle.synchronize()` (fsync) before returning, so the next
  notification is not processed until the previous bytes are on disk.
- At end of file it also issues `F_FULLFSYNC` (fsync on Apple platforms does
  not flush the drive cache), renames `.part` to `.bin`, and fsyncs the
  directory. Only then is the `fileCompleted` event emitted, and only on that
  event does the engine send an ACK (transport v3+ only). Per-packet
  `F_FULLFSYNC` was rejected as too slow for long recordings (thousands of
  packets); the spec asks for `synchronize()` per packet.
- If the device restarts a file (packet index 1 for a file already open, as
  after a retry), the earlier partial file is renamed `*.part.superseded`
  once the new copy completes: received bytes are never deleted, and the
  superseded copy is not imported twice.
- `FILE_FAILED`: first report for a file -> `R` (retry), second -> `D`
  (drop) and "N recording(s) on your Fieldy was/were damaged and couldn't be
  copied".
- A sync history row is inserted as `interrupted` when the sync starts and
  updated at the end, so a crash leaves an honest entry.
- Interrupted syncs (no packet for 30 s, or the connection drops) close their
  `.part` files and import them immediately as `incomplete`. On launch,
  `SyncEngine.recoverAndCleanUp()` imports any `.bin`/`.part` under `raw/`
  that is not in the library (raw paths are unique in the database).
- Import verifies decoded frames == frames in the file and that the M4A's
  duration is within 0.25 s of the decoded length. Only verified, complete
  recordings get `verifiedAt`; raw bytes are deleted 7 days after that.
  Incomplete and unreadable recordings keep their raw bytes.

## CoreBluetooth layer

- `FieldyDevice` is an actor (default executor) for policy: connect, clock,
  pairing, controls, idle disconnect, state stream. It wraps
  `BluetoothCentral`, a class whose state is confined to one dispatch queue
  that is also the CBCentralManager delegate queue. We did not give the actor
  a custom executor and use `assumeIsolated` from delegate callbacks, because
  `assumeIsolated` from a GCD callback needs the Swift 6 runtime's
  `checkIsolated` (macOS 15) and would trap on macOS 14.
- Scanning also checks `retrieveConnectedPeripherals` for the Fieldy service:
  a Fieldy already connected to the Mac does not advertise.
- Device name prefix is `Fieldy`. The bonded device on the dev Mac is named
  `Fieldy-654B` (protocol.md says `FieldyXX`), so we match the prefix only.
- "Paired elsewhere": three protected reads of `...66E1` spread over the
  15-second window. Pairing failures are ATT 0x05, 0x0F and also 0x0C
  (insufficient key size) plus CoreBluetooth `peerRemovedPairingInformation`
  and `encryptionTimedOut`, which is how macOS reports a peer that refuses to
  bond. If an unprotected read (battery level) still works, the state becomes
  `pairedElsewhere`.
- On every connect: write the clock first, then read `...66EE` and write `01`
  if bit 0 of byte 2 is set, then read Device Information. A pending reset
  report is surfaced as `ConnectionInfo.acknowledgedResetReport` (the app's
  "Your Fieldy's clock was reset. EarBud fixed it.").
- Controls write and then read back, returning the device's value.
- Idle disconnect: 30 s after the last operation unless an activity
  (`beginActivity`/`endActivity`, used by sync) is open.

## Library

- GRDB `DatabasePool` (WAL). Tables: `recording`, `segment`, `segment_fts`
  (FTS5, external content synchronized with `segment`, unicode61
  tokenizer), `syncHistory`, `transcriptionJob`, `setting`.
- File paths are stored relative to the library root so the root can move;
  the root is injectable (`LibraryPaths(root:)`), defaulting to
  `~/Library/Application Support/EarBud`.
- Search matches the typed words as a phrase with the last word as a prefix
  (`"powell riv" *`), within one segment. A phrase split across two segments
  is not found; acceptable for v1.
- Recently Deleted (30 days) is a `deletedAt` column with purge helpers; the
  views are task 6.4.

## Transcription

- WhisperKit 1.1.x (`argmaxinc/WhisperKit`, package now named
  `argmax-oss-swift`; we use only the `WhisperKit` product).
  `openai_whisper-small.en` = "More accurate" (default),
  `openai_whisper-base.en` = "Faster".
- Models download into `<root>/models`. After download the model is loaded
  once so the tokenizer is cached there too; then transcription works
  offline. An `<variant>.installed.json` marker records a completed install.
  Resume is at file granularity (already-downloaded files are skipped).
- Decoding: English, timestamps on, `chunkingStrategy: .vad` for audio longer
  than 30 s. Segments with `noSpeechProb > 0.6` are dropped, as are special
  tokens and pure annotations (`[BLANK_AUDIO]`, `(silence)`). An empty result
  is stored as `noSpeech = true` and shown as "No speech detected".
- Queue state is in SQLite (`transcriptionJob`), oldest recording first.
  On launch `resume()` puts jobs left `running` back to `waiting`.
  "Transcribe again" keeps the old segments until the new run succeeds.
  Failed jobs wait for "Try again" (`retry`).
- Samples come from the original Opus frames (lossless relative to what the
  device recorded), not the AAC copy.

## Spec ambiguities resolved

- Task 2.1 "profile status": taken to mean the 18-byte device status record
  on `...66E9`. Its layout is not decoded (protocol.md "Next steps"), so
  `DeviceProfileStatus` only validates length and keeps the raw bytes.
- Reset report: only "byte 2 bit 0 = acknowledgement pending" is known
  (from fieldy-local's tools). Bytes 0 and 1 are exposed raw as version and
  cause.
- v2 file header CRC: read big-endian like every other multi-byte field in
  the storage section; checked on the real device (see below).
- Device file format, as seen on device (Fieldy 3, firmware 3.3.5,
  2026-10-31): v2 header `'*' 0x02 len=16, start u32, recording ID u16,
  4 bytes, CRC u16, '#'`; frames; trailer `'*' 'E' stop reason u8, end u32,
  2 bytes, '#'`, then zero padding. Stop reason 1 = manual, 4 = file limit.
  The device closes a file at about 610 s and goes on recording into the
  next file, so one recording can be several files. EarBud joins them: a
  file whose start equals the previous file's trailer end (same sync, within
  2 s + 1 % of its length) is appended to that recording. A headered file
  also needs stop reason 4 before it. What the next file's header holds
  (same recording ID or not) is not known yet. See
  docs/device-tests/interrupted-sync-20261031.md.
- Trailer stripping: zero padding is stripped only to find the `*E...#`
  trailer. Without a trailer, trailing whole all-zero frames are dropped but a
  frame that merely ends in zero bytes is kept (fieldy-local's `rstrip`
  could cut a real frame).
