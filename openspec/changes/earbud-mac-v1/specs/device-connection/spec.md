## ADDED Requirements

### Requirement: Find the user's Fieldy
EarBud SHALL find Fieldy 3 devices by their Bluetooth advertisement and SHALL remember the paired device so that later connections go to the same Fieldy.

#### Scenario: Remembered device
- **WHEN** the paired Fieldy is awake and within range
- **THEN** EarBud connects to it without asking the user to choose a device

#### Scenario: Several Fieldy devices nearby during setup
- **WHEN** more than one Fieldy is advertising during onboarding
- **THEN** EarBud lists them by name and signal strength and asks the user to press the button on theirs to identify it

### Requirement: Pair using the device's built-in method
EarBud SHALL pair by reading the device's protected storage status, which makes macOS bond with the device. EarBud SHALL NOT ask the user for a PIN.

#### Scenario: Unpaired Fieldy accepts the Mac
- **WHEN** EarBud reads protected storage on a Fieldy with no existing pairing
- **THEN** macOS bonds with the device and the read succeeds

#### Scenario: Fieldy paired elsewhere
- **WHEN** protected reads keep failing with insufficient encryption or insufficient authentication for 15 seconds
- **THEN** EarBud reports "This Fieldy is paired with another device" and offers the reset steps from onboarding

### Requirement: Keep the device clock set
EarBud SHALL write the current time to the device on every connection, in the format the device expects (UTC, year big-endian, weekday Monday = 1), and SHALL acknowledge a pending device reset report.

#### Scenario: Connection
- **WHEN** EarBud connects to the paired Fieldy
- **THEN** it writes the current UTC time before it does anything else

#### Scenario: Device reports clock not set
- **WHEN** the recording status reports error "time not set"
- **THEN** EarBud writes the time and shows "Your Fieldy's clock was reset. EarBud fixed it."

### Requirement: Connection state is always visible
EarBud SHALL show the device state in the main window and the menu bar: Connected, Searching, Not nearby, Paired elsewhere, or Bluetooth off.

#### Scenario: Device goes out of range
- **WHEN** the connection drops
- **THEN** the state changes to "Not nearby" within 10 seconds, and any sync in progress follows the interruption rules in `recording-sync`

### Requirement: Disconnect when idle
EarBud SHALL disconnect from the device when no sync or device action is running, so the device can save battery and record to its own storage.

#### Scenario: Sync finished
- **WHEN** a sync completes and the user has not opened the device panel
- **THEN** EarBud disconnects within 30 seconds
