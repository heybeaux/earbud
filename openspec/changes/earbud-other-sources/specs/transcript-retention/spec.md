## ADDED Requirements

### Requirement: Delete audio, keep transcript
EarBud SHALL let the user delete a recording's audio while keeping its
transcript, for one recording or a selection, from the detail view, the list's
context menu, and the Edit menu. This SHALL work for recordings from every
source. The full Delete (audio and transcript) SHALL remain a separate action.

#### Scenario: Free space, keep the words
- **WHEN** the user selects a 2-hour recording and chooses Delete Audio, Keep Transcript
- **THEN** the recording stays in the list with its full transcript, the player is replaced by "Audio deleted", and Settings shows the space freed

#### Scenario: Several at once
- **WHEN** the user selects ten recordings and chooses Delete Audio, Keep Transcript
- **THEN** all ten keep their transcripts and lose their audio

### Requirement: Transcript entries behave like recordings
A recording whose audio was deleted SHALL keep its date, title, source,
length, and timestamped transcript. It SHALL appear in the list and in search,
and the user SHALL be able to copy, export as text or Markdown, rename, and
delete it. Audio export and playback SHALL be unavailable and say why.

#### Scenario: Search finds it
- **WHEN** the user searches for a phrase from a recording whose audio was deleted
- **THEN** the recording is listed with the phrase highlighted, marked "Transcript only"

### Requirement: Audio deletion is recoverable for 30 days
Deleted audio SHALL go to Recently Deleted for 30 days, like a deleted
recording, and SHALL be restorable from there. Emptying Recently Deleted SHALL
free the space at once.

#### Scenario: Restore audio
- **WHEN** the user deletes a recording's audio, then restores it from Recently Deleted within 30 days
- **THEN** playback and audio export work again

### Requirement: Never delete audio that has no transcript yet
EarBud SHALL NOT offer Delete Audio, Keep Transcript while a recording is
waiting, transcribing, or failed. For a recording with no speech detected,
it SHALL explain that the transcript is empty before deleting.

#### Scenario: Still transcribing
- **WHEN** the user opens the context menu on a recording that is still transcribing
- **THEN** Delete Audio, Keep Transcript is disabled with "Available when the transcript is ready"

### Requirement: Optional automatic audio cleanup
Settings > Storage SHALL offer "Delete audio older than [30 / 90 / 365] days,
keep transcripts", off by default, applying only to transcribed recordings.
Settings > Storage SHALL show how much space audio and transcripts each use.

#### Scenario: Turn on cleanup
- **WHEN** the user turns on cleanup at 90 days
- **THEN** audio from transcribed recordings older than 90 days moves to Recently Deleted, and their transcripts stay
