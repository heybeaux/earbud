## ADDED Requirements

### Requirement: Device status
The device panel SHALL show battery percentage, recordings waiting on the device and their total size, firmware version, model, and when the device was last synced.

#### Scenario: Open device panel
- **WHEN** the user opens the device panel and the Fieldy is nearby
- **THEN** EarBud connects and shows current values within 10 seconds

#### Scenario: Device not nearby
- **WHEN** the Fieldy is out of range
- **THEN** the panel shows the last known values with the time they were read

### Requirement: Device settings
The panel SHALL let the user change recording mode (Manual or Automatic, each explained in one sentence), turn the always-on light on or off, and mute or unmute the microphone. Each change SHALL be read back from the device to confirm it.

#### Scenario: Change recording mode
- **WHEN** the user switches recording mode to Automatic
- **THEN** EarBud writes the setting, reads it back, and shows the new value only after the device confirms it

### Requirement: Find my Fieldy
The panel SHALL have a "Buzz my Fieldy" button that makes the device vibrate.

#### Scenario: Buzz
- **WHEN** the user taps "Buzz my Fieldy" and the device is nearby
- **THEN** the Fieldy vibrates

### Requirement: Record from the Mac
The panel SHALL let the user start and stop a recording on the Fieldy from the Mac, for desk use.

#### Scenario: Start and stop
- **WHEN** the user taps Record, waits, then taps Stop
- **THEN** the Fieldy records to its own storage, the panel shows elapsed time while recording, and the new recording appears on the next sync

#### Scenario: Device muted
- **WHEN** the device reports it cannot record because it is muted
- **THEN** EarBud shows "Your Fieldy is muted" with an Unmute button
