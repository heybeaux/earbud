## ADDED Requirements

### Requirement: Recordings grouped by day
The main window SHALL list recordings newest first, grouped under day headings ("Today", "Yesterday", then dates), each showing start time, length, and the first line of its transcript.

#### Scenario: Library with recordings
- **WHEN** the user opens EarBud after syncing recordings from two days
- **THEN** the list shows two day groups with the newest recording at the top

#### Scenario: Empty library
- **WHEN** no recordings have been synced
- **THEN** the window explains how to record with the Fieldy and shows a Sync button, not a blank list

### Requirement: Recording detail
Selecting a recording SHALL show a player (play/pause, scrubber, speed 1x/1.5x/2x) and the full timestamped transcript.

#### Scenario: Play a recording
- **WHEN** the user selects a recording and presses play
- **THEN** the audio plays and the current transcript segment is highlighted

### Requirement: Search
EarBud SHALL search all transcripts as the user types and SHALL show matching recordings with the match highlighted.

#### Scenario: Search hit
- **WHEN** the user types "Powell River"
- **THEN** only recordings whose transcript contains that phrase are listed, with the phrase highlighted

### Requirement: Copy and export
The user SHALL be able to copy a transcript, and export a recording as an audio file (M4A or WAV) and its transcript as plain text or Markdown with timestamps.

#### Scenario: Export
- **WHEN** the user chooses Export and picks a folder
- **THEN** EarBud writes the audio and transcript files named with the recording's date and time

### Requirement: Rename and delete
The user SHALL be able to give a recording a title and to delete it. Deleting SHALL move it to an EarBud trash that is emptied after 30 days.

#### Scenario: Delete and restore
- **WHEN** the user deletes a recording and then opens Recently Deleted
- **THEN** the recording is listed there and can be restored

### Requirement: Where files live
EarBud SHALL store recordings in its Application Support folder and SHALL offer "Show in Finder" for any recording. Library data SHALL survive app updates.

#### Scenario: Update
- **WHEN** EarBud is replaced with a newer version
- **THEN** all recordings, transcripts, and titles are still present
