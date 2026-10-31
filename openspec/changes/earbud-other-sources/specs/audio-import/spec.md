## ADDED Requirements

### Requirement: Import audio files
The user SHALL be able to import audio files by dragging files or folders onto
the EarBud window or the Dock icon, or by choosing File > Import Audio…. EarBud
SHALL accept WAV, AIFF, CAF, M4A, MP3, and FLAC at any sample rate and bit
depth, mono or stereo. Folders SHALL be searched recursively for those types.

#### Scenario: Drag in a RØDE recording
- **WHEN** the user drags a 32-bit float WAV exported from RØDE Central onto the EarBud window
- **THEN** a new recording appears in the list under the day it was recorded, marked Waiting, and is transcribed on the Mac

#### Scenario: Unsupported file
- **WHEN** the user drops a PDF and two WAV files
- **THEN** the two WAV files are imported and the summary names the PDF with "EarBud can't read this kind of file"

### Requirement: Imported files are copied and kept safe
EarBud SHALL copy each imported file into its library before processing it and
SHALL never modify, move, or delete the user's original. Once the compressed
playback copy is written and verified, EarBud SHALL delete its full-size copy
and keep only the compressed audio. A failure partway through an import SHALL
leave no half-imported recording in the list.

#### Scenario: Original deleted later
- **WHEN** the user imports a file, then deletes the original from Downloads
- **THEN** the recording still plays, and its transcript and export still work

#### Scenario: Only the compressed copy is kept
- **WHEN** the user imports a 1-hour 32-bit float WAV (about 690 MB)
- **THEN** after the import finishes, the library holds a compressed copy of about 30 MB and no full-size copy

#### Scenario: Quit during import
- **WHEN** EarBud quits while copying a large file
- **THEN** on the next launch the partial copy is removed and the file is not listed; the user can import it again

### Requirement: No duplicates
EarBud SHALL detect a file it has already imported, by content, and SHALL skip
it, including when the earlier copy is in Recently Deleted.

#### Scenario: Same file twice
- **WHEN** the user imports a file that is already in the library under a different name
- **THEN** no second recording is created and the summary says "Already in EarBud"

### Requirement: Recording time from the file
EarBud SHALL date an imported recording from the recording time embedded in
the file when present (Broadcast WAV origination time, or M4A/MP3 creation
metadata), otherwise from the file's creation date. EarBud SHALL skip an
M4A/MP3 creation date that is less than half the recording's duration before
the file's last modification, or after it, because a re-saved file carries the
save time. When the file date is used, the detail view SHALL say "Time taken
from the file".

#### Scenario: Field recorder WAV
- **WHEN** the user imports a WAV with a Broadcast WAV origination date of 2026-10-28 14:05
- **THEN** the recording is listed under that day at 2:05 PM

#### Scenario: Converted M4A
- **WHEN** the user imports a one-hour M4A whose creation metadata is 40 seconds before the file was last modified
- **THEN** EarBud uses the file's creation date and the detail view says "Time taken from the file"

### Requirement: Long files
EarBud SHALL import and transcribe files of at least 4 hours without loading
the whole file into memory, and SHALL show transcription progress as a
percentage in the list row.

#### Scenario: Three-hour meeting
- **WHEN** the user imports a 3-hour M4A
- **THEN** the import completes, the row shows transcription progress, and the full transcript appears when done

### Requirement: Source shown and shared library
Every recording SHALL show its source in the list and detail view (Fieldy,
the imported file name, or the microphone name). Imported recordings SHALL
work with search, playback, copy, export, rename, and delete exactly like
Fieldy recordings, and SHALL NOT affect Fieldy sync, device storage counts,
or the sync reminder.

#### Scenario: Search across sources
- **WHEN** the user searches for a phrase said in both a Fieldy recording and an imported file
- **THEN** both recordings are listed, each with its source shown

### Requirement: Import summary
After each import EarBud SHALL show a short summary: how many files were
imported, skipped as duplicates, and rejected, with the names of skipped and
rejected files.

#### Scenario: Mixed import
- **WHEN** the user drops a folder with 5 audio files, one already imported
- **THEN** the summary reads "4 imported, 1 already in EarBud"
