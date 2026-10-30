## ADDED Requirements

### Requirement: Transcription runs on the Mac
EarBud SHALL transcribe recordings with an on-device Whisper model and SHALL NOT send audio or text to any server.

#### Scenario: Network off
- **WHEN** the Mac has no network connection and the speech model is installed
- **THEN** sync and transcription both complete normally

### Requirement: Transcription queue
After a sync, EarBud SHALL transcribe new recordings one at a time, oldest first, in the background, and SHALL show each recording's state: Waiting, Transcribing (with progress), Done, or Failed.

#### Scenario: Several new recordings
- **WHEN** a sync adds 3 recordings
- **THEN** the library shows them immediately with audio playable, and their transcripts appear one by one as each finishes

#### Scenario: App quits mid-queue
- **WHEN** EarBud quits while recordings are waiting
- **THEN** on next launch EarBud resumes the queue without the user doing anything

### Requirement: Timestamped transcripts
Each transcript SHALL be split into segments with start times. Clicking a segment SHALL play the audio from that point.

#### Scenario: Jump to a moment
- **WHEN** the user clicks the segment marked 02:15
- **THEN** playback starts at 2 minutes 15 seconds

### Requirement: Silence does not produce fake text
EarBud SHALL skip segments the model marks as no speech, and SHALL show "No speech detected" for a recording with no speech instead of invented words.

#### Scenario: Silent recording
- **WHEN** a recording contains only room noise
- **THEN** its transcript reads "No speech detected"

### Requirement: Model choice and retry
Settings SHALL offer two choices in plain words: "Faster" and "More accurate" (default), each with its download size. The user SHALL be able to re-transcribe any recording.

#### Scenario: Re-transcribe
- **WHEN** the user switches to "More accurate" and taps "Transcribe again" on a recording
- **THEN** EarBud replaces the transcript after confirming, and keeps the old one until the new one succeeds

#### Scenario: Transcription fails
- **WHEN** transcription of a recording throws an error
- **THEN** the recording shows "Transcription failed" with a "Try again" button, and its audio is unaffected
