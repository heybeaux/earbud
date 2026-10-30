## ADDED Requirements

### Requirement: Welcome explains EarBud in plain language
On first launch, EarBud SHALL show a welcome screen before any other screen. It SHALL explain, in plain words with no technical terms, that EarBud copies recordings from a Fieldy 3 to this Mac and turns them into text, that audio and text stay on this Mac, and that EarBud is not made by Field Labs.

#### Scenario: First launch
- **WHEN** a user opens EarBud for the first time on a Mac
- **THEN** the welcome screen appears with a "Get started" button and no other app window is shown

#### Scenario: Later launches
- **WHEN** a user who finished onboarding opens EarBud
- **THEN** EarBud opens to the recordings library and does not show the welcome screen

### Requirement: Bluetooth permission is requested with an explanation
EarBud SHALL explain why it needs Bluetooth before macOS asks for permission. If permission is denied, EarBud SHALL show how to turn it on in System Settings, with a button that opens the right settings page.

#### Scenario: Permission granted
- **WHEN** the user taps "Allow Bluetooth" and approves the macOS prompt
- **THEN** onboarding moves to the device setup step

#### Scenario: Permission denied
- **WHEN** the user denies Bluetooth access
- **THEN** EarBud shows "EarBud can't reach your Fieldy without Bluetooth", step-by-step instructions, and an "Open System Settings" button, and it does not continue until access is granted

### Requirement: Guided device setup
EarBud SHALL guide the user to connect their Fieldy, one step per screen, with a picture or animation for every physical action. The steps SHALL be: wake the Fieldy and bring it close, check whether it is already paired with a phone, factory reset if needed, pair with this Mac, set the clock, and make a test recording.

#### Scenario: Fieldy already paired with a phone
- **WHEN** EarBud finds the Fieldy but cannot pair because it is paired with another device
- **THEN** EarBud explains that a Fieldy can only pair with one device at a time, warns that a reset erases any recordings still on the Fieldy and disconnects it from the Fieldy phone app, and asks the user to confirm before showing the reset steps

#### Scenario: Reset instructions
- **WHEN** the user confirms they want to reset
- **THEN** EarBud shows the reset steps (short click under 1 second, then immediately press and hold for 10 seconds until the light cycles through 4 colours), and offers "It didn't work" help that explains a plain restart means the short click was missed

#### Scenario: Pairing succeeds
- **WHEN** the reset Fieldy is near the Mac
- **THEN** EarBud pairs with it without asking the user to type a code, sets its clock, and shows "Connected" with the device's battery level

#### Scenario: Fieldy not found
- **WHEN** EarBud cannot find a Fieldy for 30 seconds
- **THEN** EarBud shows troubleshooting tips (press the button to wake it, charge it, turn off the phone's Bluetooth, bring it closer) and keeps searching

### Requirement: Speech model download needs consent
Before downloading the speech model, EarBud SHALL tell the user its size, that it is a one-time download, and that it is the only thing EarBud downloads. The user SHALL be able to start, postpone, or cancel it.

#### Scenario: User approves download
- **WHEN** the user taps "Download" on the speech model step
- **THEN** EarBud shows download progress and moves on when finished

#### Scenario: User postpones
- **WHEN** the user taps "Later"
- **THEN** onboarding continues, recordings still sync and play, and each recording shows "Waiting for speech model" with a button to download it

### Requirement: Test recording proves the full path
Onboarding SHALL finish with a test: the user presses the Fieldy button, says a sentence, presses again, and EarBud syncs and shows the transcript.

#### Scenario: Test succeeds
- **WHEN** the user makes a short recording and taps "Sync test recording"
- **THEN** EarBud downloads it, shows the transcript on screen, and offers "Finish setup"

#### Scenario: Button buzzes twice and does not record
- **WHEN** the device reports that its clock is not set
- **THEN** EarBud sets the clock automatically and asks the user to try the button again

### Requirement: Fresh-install acceptance
v1 SHALL be accepted only after a person who has not used EarBud completes onboarding on a fresh macOS user account with a Fieldy 3 that is paired to a phone, and reaches a transcribed test recording, using only the app's on-screen instructions.

#### Scenario: Stranger walkthrough
- **WHEN** the walkthrough is run from DMG download to first transcript
- **THEN** the person finishes without help from outside the app, and every step that confused them is fixed before release
