## ADDED Requirements

### Requirement: Notch dock is an option
EarBud SHALL offer "Show EarBud in the notch" in Settings and, on Macs with a camera notch, as an optional onboarding step with a preview. It SHALL be off until the user turns it on. The menu-bar icon SHALL keep working whether the notch dock is on or off.

#### Scenario: Turn on during onboarding
- **WHEN** a user on a MacBook with a notch turns on the notch dock in onboarding
- **THEN** EarBud appears around the notch as soon as onboarding finishes

#### Scenario: Turn off
- **WHEN** the user turns off "Show EarBud in the notch"
- **THEN** the notch dock disappears immediately and the menu-bar icon remains

### Requirement: Resting state blends with the notch
When idle, the notch dock SHALL appear as a black extension of the notch, no wider than the notch plus a small indicator on each side: a device-state dot on the left and the time since the last sync on the right. It SHALL NOT cover menu-bar items or take keyboard focus.

#### Scenario: Idle
- **WHEN** no sync, recording, or hover is happening
- **THEN** the dock shows only the two small indicators beside the notch, and clicks on the menu bar outside it behave normally

### Requirement: Hover or click expands it
Hovering over the notch dock for half a second, or clicking it, SHALL expand it downward into a panel showing device state and battery, last synced time, a Sync now button, a Record from Mac button, and the first lines of the newest transcript. Moving the pointer away SHALL collapse it.

#### Scenario: Expand and sync
- **WHEN** the user hovers over the dock and clicks Sync now
- **THEN** the sync starts and the panel shows its progress

#### Scenario: Open a recording
- **WHEN** the user clicks the newest transcript preview
- **THEN** the main EarBud window opens with that recording selected

### Requirement: Live activity
The notch dock SHALL show live activity without being expanded: a progress bar during a sync, then "3 new recordings" (with the real count) for 5 seconds after it finishes; and a red dot with elapsed time while recording from the Mac.

#### Scenario: Sync from the menu bar or a reminder
- **WHEN** a sync runs from any entry point
- **THEN** the notch dock shows the progress bar and then the result

#### Scenario: Recording from the Mac
- **WHEN** the user starts a recording from the Mac
- **THEN** the dock shows a red dot and a running timer until the recording stops

### Requirement: Macs and screens without a notch
On a display without a notch, EarBud SHALL offer a floating capsule at the top centre of the screen that behaves like the notch dock, or menu bar only. The user SHALL choose which display shows the dock; the built-in display is the default.

#### Scenario: External monitor
- **WHEN** the user picks an external display without a notch
- **THEN** the dock appears as a floating capsule at the top centre of that display

#### Scenario: Display disconnected
- **WHEN** the chosen display is disconnected
- **THEN** the dock moves to the built-in display, or to the menu bar if there is none

### Requirement: Stays out of the way
The notch dock SHALL hide when an app is full screen on that display and during screen sharing in which the notch area is captured, and SHALL NOT require Accessibility or Screen Recording permission.

#### Scenario: Full-screen app
- **WHEN** the user puts an app into full screen on the dock's display
- **THEN** the dock hides, and it returns when the user leaves full screen
