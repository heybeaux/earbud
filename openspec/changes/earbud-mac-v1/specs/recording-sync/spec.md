## ADDED Requirements

### Requirement: Sync downloads every stored recording
When the user taps Sync, EarBud SHALL connect, set the device clock, read how many recordings and bytes are stored, and download all of them using the device's storage-sync protocol at the highest transfer version both sides support (up to 3).

#### Scenario: Recordings waiting
- **WHEN** the device holds 3 recordings and the user taps Sync
- **THEN** EarBud shows "Copying 3 recordings", a progress bar based on bytes received, and adds all 3 recordings to the library when done

#### Scenario: Nothing waiting
- **WHEN** the device holds no recordings
- **THEN** EarBud shows "No new recordings. Last synced just now." and records the sync in the history

### Requirement: Audio is saved before anything else
Because the device deletes a recording once it has sent it, EarBud SHALL write every received packet to disk and flush it before processing the next packet. EarBud SHALL keep the exact bytes received for each file until that recording has been decoded and verified.

#### Scenario: App quits during sync
- **WHEN** EarBud quits or the Mac sleeps in the middle of a file
- **THEN** the bytes received so far are on disk, and on next launch EarBud recovers them as a recording marked "Incomplete" with its playable length

#### Scenario: Decode fails
- **WHEN** a downloaded file cannot be decoded
- **THEN** EarBud keeps the raw file, shows the recording as "Couldn't read this recording", and offers "Show raw file in Finder"

### Requirement: Acknowledge files when the device supports it
EarBud SHALL send the file acknowledgement only after the file is flushed to disk, and only for transfer version 3 or later. For a reported file failure, EarBud SHALL ask the device to retry once, then to drop the file, and SHALL tell the user.

#### Scenario: Version 3 device
- **WHEN** a file finishes on a version 3 transfer
- **THEN** EarBud flushes it to disk, then sends the acknowledgement with the file ID and byte count

#### Scenario: Device reports a failed file twice
- **WHEN** the device reports the same file failed after a retry
- **THEN** EarBud drops it and shows "1 recording on your Fieldy was damaged and couldn't be copied"

### Requirement: Recordings get their real time
EarBud SHALL date each recording from the device's file header (UTC) and show it in the Mac's local time. If the header has no valid time, EarBud SHALL use the sync time and mark the recording "Time unknown".

#### Scenario: Normal file header
- **WHEN** a recording's header says 20:12:03 UTC on 30 October 2026 and the Mac is in Pacific time
- **THEN** the library shows it at 1:12 PM on Friday 30 October

### Requirement: Sync history
EarBud SHALL keep a history of syncs with time, number of recordings, total length, and result.

#### Scenario: Viewing history
- **WHEN** the user opens Sync history
- **THEN** each past sync is listed newest first with its result, including failed or interrupted syncs
