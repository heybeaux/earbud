## ADDED Requirements

### Requirement: Record with setting
Settings > Recording SHALL have a **Record with** choice: "Fieldy" (the
default, v1 behaviour) or a microphone. The microphone list SHALL show every
input device the Mac sees by name, plus "Mac's default input", and SHALL
update when a device is plugged in or removed. The Record button in the main
window, menu bar, and notch dock SHALL use this choice and SHALL show which
source it will use.

#### Scenario: Choose the RØDE receiver
- **WHEN** the user plugs in a RØDE Wireless PRO receiver and picks "Wireless PRO RX" under Record with
- **THEN** the Record button reads "Record with Wireless PRO RX" everywhere it appears

#### Scenario: Fieldy stays the default
- **WHEN** a user who never opens this setting presses Record
- **THEN** the Fieldy records, exactly as in v1

### Requirement: Microphone permission asked when needed
EarBud SHALL ask for microphone permission the first time the user records
with a microphone, not during onboarding. If permission is denied, the Record
button SHALL explain how to allow it and offer to open System Settings.

#### Scenario: First microphone recording
- **WHEN** the user presses Record with a microphone selected for the first time
- **THEN** macOS asks for microphone permission, and recording starts once it is allowed

### Requirement: Never record from the wrong microphone
EarBud SHALL NOT switch microphones without asking. If the chosen microphone
is not connected when the user presses Record, EarBud SHALL say so by name and
offer the Mac's default input or Cancel.

#### Scenario: Receiver not plugged in
- **WHEN** the chosen microphone is unplugged and the user presses Record
- **THEN** EarBud shows "Wireless PRO RX isn't connected" with "Use Mac's default input" and "Cancel"

### Requirement: Durable microphone recording
EarBud SHALL write microphone audio to disk continuously while recording, so
that a crash, force quit, or power loss loses at most the last 2 seconds. On
the next launch a cut-off recording SHALL be listed as "Incomplete" with the
audio it has.

#### Scenario: Crash mid-recording
- **WHEN** EarBud is force-quit 10 minutes into a microphone recording
- **THEN** on the next launch a recording of about 10 minutes is listed as Incomplete and is transcribed

### Requirement: Recording status
While recording from a microphone, EarBud SHALL show elapsed time and a live
input level in the main window, a red dot with elapsed time in the menu bar
and notch dock, and a Stop button in each place. Stopping SHALL save the
recording and queue it for transcription.

#### Scenario: Stop from the notch
- **WHEN** the user clicks Stop in the expanded notch dock after 5 minutes
- **THEN** a 5-minute recording appears at the top of today's list, marked Waiting

### Requirement: Unplug and sleep
EarBud SHALL stop, keep everything recorded so far, and post a notification
saying what happened and how much was saved, if the microphone is
disconnected or the Mac sleeps during a recording.

#### Scenario: Receiver unplugged
- **WHEN** the RØDE receiver is unplugged 14 minutes into a recording
- **THEN** recording stops, a 14-minute recording is saved and queued, and a notification reads "Recording stopped: Wireless PRO RX was disconnected. 14 min saved."

### Requirement: Microphone recordings in the library
Microphone recordings SHALL be listed with the microphone's name as their
source and SHALL behave like every other recording for playback, transcript,
search, export, rename, and delete.

#### Scenario: Export a microphone recording
- **WHEN** the user exports a microphone recording as WAV
- **THEN** EarBud writes the audio and transcript named with the recording's date and time
