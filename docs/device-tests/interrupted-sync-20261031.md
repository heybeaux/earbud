# Device test: interrupted sync (2026-10-31)

Task 4.5. Fieldy 3, firmware 3.3.5, transport v2. Times are UTC.

## What was done

1. The Fieldy recorded clip A (14:46:56–14:57:02, 610 s of audio), then
   clip B (14:57:02–14:57:46, 44 s).
2. Sync 6 was cut off before any data arrived (0 bytes).
3. Sync 7 was cut off after 38,064 bytes of file 1. It left
   `raw/20261031T150549Z-4972/00001.part` and an "Incomplete" recording.
4. Sync 8 ran to the end.

## What the device keeps

- **The device keeps a file when a sync is cut off. On the next sync it sends
  the whole file again, from the start.** Sync 8 returned file 1 complete
  (1,220,146 bytes, 610 s, decoded fine). The 38,064 bytes from sync 7 are
  byte for byte the start of that file.
- Clip A ended at 610 s without anyone stopping it, and the device started
  clip B in a new file. Its trailer gives stop reason 4 (file limit); clip B's
  gives 1 (manual).
- The file trailer `'*' 'E' reason u8, time u32, 00 00, '#'` holds the
  recording's end time: `6a e6 01 be` = 14:57:02 for A, `6a e6 01 ea` =
  14:57:46 for B. A's header holds its start, 14:46:56.

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

2. **Clip B unreadable.** `00002.bin` (88,378 bytes) had lost its first
   488-byte packet (the header and the first frames) to the read above. The
   device's own status shows 88,866 bytes for that file, exactly one packet
   more. The file then started 8 bytes before a frame, so the decoder read a
   frame tail as a 2.5 ms Opus packet and failed the whole file.

   Fix, besides the root cause above:
   - Frame alignment is found again by looking for frame starts (0xB8) every
     40 bytes, at the start of a headerless file or after a lost packet.
   - A headerless file is timed from its trailer: end time minus length. The
     audio runs about 0.7 % longer than the device clock (610 s of frames
     against 606 s), so this is close, not exact.
   - A frame that decodes to the wrong length is concealed instead of failing
     the file.
   - Packet index gaps are now logged.

## Leftover `.part`

Before: the sync 7 `.part` stayed for good (raw files of "Incomplete"
recordings are never cleaned up), and its "Incomplete" row stayed beside the
complete recording from sync 8.

Now: when a complete file arrives with the same header (recording ID and
start time), the "Incomplete" row goes to Recently Deleted. Its files,
`.part` included, go when Recently Deleted is emptied or after 30 days. A
`.part` recovered after the complete copy is already in goes straight to
Recently Deleted.

## Not determined

- How syncs 6 and 7 were cut off (out of range, quit, or sleep) is not
  recorded with the evidence.
- What the device does with a file in a v3 sync that is cut off before the
  ACK. This device offers v2 only.
