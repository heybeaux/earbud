# Device test: interrupted sync (2026-10-31)

Task 4.5. Fieldy 3, firmware 3.3.5, transport v2. Times are UTC.

## What was done

1. The owner made one recording of about 11 minutes (14:46:56–14:57:46).
   The device stored it as two files: file 1 (610 s, ends 14:57:02) and
   file 2 (44 s, ends 14:57:46).
2. Sync 6 was cut off before any data arrived (0 bytes).
3. Sync 7 was cut off after 38,064 bytes of file 1. It left
   `raw/20261031T150549Z-4972/00001.part` and an "Incomplete" recording.
4. Sync 8 ran to the end.

## What the device keeps

- **The device keeps a file when a sync is cut off. On the next sync it sends
  the whole file again, from the start.** Sync 8 returned file 1 complete
  (1,220,146 bytes, 610 s, decoded fine). The 38,064 bytes from sync 7 are
  byte for byte the start of that file.
- **The device splits a long recording into files.** It closed file 1 at
  610 s by itself and went on recording into file 2. File 1's trailer gives
  stop reason 4 (file limit); file 2's gives 1 (manual, the owner's stop).
- The file trailer `'*' 'E' reason u8, time u32, 00 00, '#'` holds the file's
  end time: `6a e6 01 be` = 14:57:02 for file 1, `6a e6 01 ea` = 14:57:46 for
  file 2. File 1's header (`2a 02 10 6a e5 ff 60 00 0a 00 00 00 00 0a 73 23`)
  holds the start, 14:46:56, and recording ID 10.
- File 2 starts where file 1 ends: 14:57:46 minus its 44.18 s of frames is
  14:57:01.8, 0.2 s from file 1's end time.

## Bugs found and fixed

Sync 8 also made two bad library rows.

1. **Phantom file 10818 (0 s, "unreadable").** When file 1 finished, the app
   refreshed the device status. That reads `...66E1` while the sync has
   notifications on. CoreBluetooth reports read replies and notifications
   through the same callback, so:
   - the read took the next notification, the **first packet of file 2**,
     as its reply, and
   - the real reply, the 20-byte `*B` status record, went to the sync. It was
     parsed as a data packet for file `0x2A42` ("*B" = 10818), and a size byte
     (0xF9) set its end-of-file flag.

   Fix: during a sync, `FieldyDevice` returns the last status read instead of
   reading `...66E1`, and `BluetoothCentral` refuses any read of a
   characteristic whose notifications are on. The sync parser no longer
   treats any `*B` record as file data.

2. **File 2 unreadable, and shown as a second recording.** `00002.bin`
   (88,378 bytes) had lost its first 488-byte packet to the read above. The
   device's own status shows 88,866 bytes for that file, exactly one packet
   more. The file then started 8 bytes before a frame, so the decoder read a
   frame tail as a 2.5 ms Opus packet and failed the whole file. It also had
   its own library row, but it is the last 44 s of the same recording.

   What the first 8 bytes (`e4 df 8d ac 46 36 86 f2`) are: the end of a
   frame, not a continuation header. The lost packet held 488 bytes and the
   next packet starts 8 bytes before a frame start (0xB8 every 40 bytes from
   offset 8). 488 = 16 + 11 × 40 + 32, so the lost packet began with 16
   bytes that are not frames: a v2 header of the same length as file 1's.
   With no header (488 = 12 × 40 + 8) the next packet would start 32 bytes
   before a frame; with a 10-byte v1 header, 2 bytes. So file 2 had a header
   of its own, but its contents (recording ID, start time) are lost, and the
   bytes cannot prove that file 2 continues file 1. 12 frames (240 ms) of
   audio were lost with that packet.

   Fix, besides the root cause above:
   - Frame alignment is found again by looking for frame starts (0xB8) every
     40 bytes, at the start of a headerless file or after a lost packet.
   - A headerless file is timed from its trailer: end time minus length. The
     audio runs about 0.7 % longer than the device clock (610 s of frames
     against 606 s), so this is close, not exact.
   - **A file that continues the previous file of the same sync is appended
     to that recording** (one row, one M4A, transcribed as one). The
     previous file is the one with the next lower device file ID in the same
     sync; its recording must be complete, have a header, and still have its
     audio and raw file. Its trailer end time must equal this file's start
     within 2 s plus 1 % of this file's length (clock drift). A headerless
     file's start is its trailer time minus its length. A file with a header
     also needs stop reason 4 (file limit) in the previous trailer: now that
     headers are no longer lost, the next split recording arrives with file
     2's header intact, and only the file-limit stop says it continues. A
     file that does not match stays its own recording.
   - The appended file is kept as a part of the recording (`recordingPart`
     table), so crash recovery does not import it again, and deleting the
     recording or raw cleanup removes it too. The recording is queued for
     transcription again; the old transcript stays until the new one is done.
   - The gap of a lost packet is not filled: the 240 ms are missing at the
     join.
   - A frame that decodes to the wrong length is concealed instead of failing
     the file.
   - Packet index gaps are now logged.

3. **"Incomplete" duplicate.** Sync 7's "Incomplete" row (19 s, recording ID
   10, 14:46:56) stayed next to the complete copy from sync 8.

   Fix: when a complete file arrives whose header recording ID and start
   time match an "Incomplete" row, the complete one supersedes it. The
   partial row, its transcript, its audio and its `.part` are deleted for
   good (not moved to Recently Deleted). A `.part` recovered after the
   complete copy is already in is deleted and gets no row.

## Repairing a library hurt by this

`earbud-cli repair` fixes rows made by the earlier build. It deletes
phantom file 10818 rows (with their raw file), deletes "Incomplete" rows
whose complete copy is in (Recently Deleted included), and imports
headerless files that have their own row again (appended when they
continue the previous file, else their own recording timed from the
trailer). It is safe to run twice. `--dry-run` prints the plan only, but
still upgrades the database schema. Quit EarBud and back up the library
first.

```
earbud-cli repair --dry-run
earbud-cli repair
```

On a copy of the owner's library it did:

```
delete phantom recording 48ED04F6-… (raw/20261031T150603Z-c11b/10818.bin)
delete incomplete recording 7E09F0B1-… (raw/20261031T150549Z-4972/00001.part): complete copy is B28FC616-…
re-import raw/20261031T150603Z-c11b/00002.bin (recording 7DDA9A65-…): append to recording B28FC616-…
  -> appended to recording B28FC616-…, ok, 654.24 s
```

The result is one recording, 14:46:56, 654.24 s (30,503 + 2,209 frames),
queued for transcription again.

## Not determined

- How syncs 6 and 7 were cut off (out of range, quit, or sleep) is not
  recorded with the evidence.
- What the device does with a file in a v3 sync that is cut off before the
  ACK. This device offers v2 only.
- What the header of a continuation file holds (same recording ID 10 or a
  new one, start time). Record a recording longer than 610 s and sync it
  without interference to see it.
