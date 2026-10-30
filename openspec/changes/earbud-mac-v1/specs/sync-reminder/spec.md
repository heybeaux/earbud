## ADDED Requirements

### Requirement: Menu-bar status
EarBud SHALL show a menu-bar icon with a menu containing: last synced time, device state, "Sync now", "Open EarBud", and "Quit". The icon SHALL change while a sync runs.

#### Scenario: Sync from the menu bar
- **WHEN** the user chooses "Sync now" from the menu-bar menu
- **THEN** the sync runs, the icon shows it is working, and the menu shows the result when done

#### Scenario: Menu bar turned off
- **WHEN** the user turns off "Show in menu bar" in Settings
- **THEN** the icon disappears and EarBud behaves as a normal windowed app

### Requirement: Daily reminder
EarBud SHALL send a macOS notification when the device has not been synced for 24 hours (the default), at a time the user picks. Clicking it SHALL start a sync. The user SHALL be able to change the interval or turn reminders off.

#### Scenario: Reminder due
- **WHEN** the last sync was more than 24 hours ago and the reminder time arrives
- **THEN** a notification says "Time to sync your Fieldy" and clicking it opens EarBud and starts a sync

#### Scenario: Already synced today
- **WHEN** the user synced within the last 24 hours
- **THEN** no reminder is sent

### Requirement: Launch at login is optional
EarBud SHALL offer "Open EarBud when you log in" during onboarding and in Settings, off by default, so reminders work without the user opening the app.

#### Scenario: Enabled
- **WHEN** the user turns it on and restarts the Mac
- **THEN** EarBud starts in the menu bar without opening its window
