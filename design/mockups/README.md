# EarBud UI mockups

Static mockups for EarBud v1, the native macOS app (SwiftUI, macOS 14+) that works with Fieldy 3.
They follow the approved spec in `openspec/changes/earbud-mac-v1/` and use its plain-language copy where it gives copy.
All names, recordings, and transcripts are fictional. No Field Labs logos or artwork are used.

How they are made: each screen is an HTML page in `src/`, styled by `mockups.css` (one teal accent, warm neutrals) and
`kit.js` (icons, waveform, wristband drawing). `./render.sh NAME[:WIDTHxHEIGHT]` renders a page to a 2x PNG with headless Chrome.
`00-contact-sheet.png` shows every screen on one page.

## Screens

- **01-app-icon.png**: two app icon concepts ("Bud" and "Voice to words") with 64/32/16 px samples and a Dock preview. Covers the open question on app icon and visual style (design.md).
- **01a-icon-concept-a-1024.png**: icon concept A at full size. Same open question.
- **01b-icon-concept-b-1024.png**: icon concept B at full size. Same open question.
- **02-onboarding-welcome.png**: first-run welcome explaining what EarBud does. onboarding: Welcome explains EarBud in plain language.
- **03-onboarding-bluetooth.png**: Bluetooth explanation before macOS asks, and the state after permission is denied. onboarding: Bluetooth permission is requested with an explanation.
- **04-onboarding-find-fieldy.png**: searching for the Fieldy, and choosing between several nearby. device-connection: Find the user's Fieldy.
- **05-onboarding-paired-elsewhere.png**: the Fieldy is paired with a phone or another computer. device-connection: Pair using the device's built-in method (paired elsewhere); onboarding: Guided device setup.
- **06-onboarding-reset-steps.png**: factory-reset steps and "It didn't work" help. onboarding: Guided device setup.
- **07-onboarding-connected.png**: connected, with the clock set. device-connection: Pair using the device's built-in method, Keep the device clock set.
- **08-onboarding-speech-model.png**: asking before the speech model download, then the download in progress. onboarding: Speech model download needs consent.
- **09-onboarding-test-recording.png**: making a test recording and seeing its transcript. onboarding: Test recording proves the full path.
- **10-onboarding-notch-dock.png**: optional "Show EarBud in the notch?" step with previews, off by default. notch-dock: Notch dock is an option.
- **11-onboarding-finished.png**: setup finished. onboarding: Guided device setup; sync-reminder: Launch at login is optional.
- **12-main-window.png**: library grouped by day, player with 1x/1.5x/2x speeds, timestamped transcript with the current line highlighted. recordings-library: Recordings grouped by day, Recording detail; transcription: Silence does not produce fake text.
- **13-main-window-empty.png**: empty library that explains how to record and shows a Sync button. recordings-library: Recordings grouped by day (empty library).
- **14-search-results.png**: search for "Powell River" with highlighted matches. recordings-library: Search.
- **15-sync-in-progress.png**: sync progress and the transcription queue, with recordings appearing as each file finishes copying. recording-sync: Sync downloads every stored recording; transcription: Transcription queue.
- **16-device-panel.png**: device status, record from the Mac, recording mode, light, mute, Buzz my Fieldy. device-controls: all four requirements.
- **17-settings.png**: Settings window: speech model choice, sync reminder, menu bar, notch dock, open at login. transcription: Model choice and retry; sync-reminder: Daily reminder, Launch at login is optional; notch-dock: Notch dock is an option.
- **18-menu-bar-menu.png**: menu-bar menu over the desktop: device state, last synced, Sync now, Record from Mac, Open EarBud, Settings, Quit; plus the icon's states. sync-reminder: Menu-bar status.
- **19-notch-dock-states.png**: notch dock on a MacBook in four states: resting, hover panel, sync live activity (progress, then "3 new recordings"), and recording timer. notch-dock: Resting state blends with the notch, Hover or click expands it, Live activity.
- **20-floating-capsule.png**: floating capsule at the top centre of an external display without a notch, its hover panel and live states, and the display picker. notch-dock: Macs and screens without a notch.
- **21-sync-reminder-notification.png**: "Time to sync your Fieldy" notification banner, with the reminder settings. sync-reminder: Daily reminder.
- **22-main-window-dark.png**: screen 12 in macOS dark appearance. recordings-library: Recordings grouped by day, Recording detail (dark mode).

## Open questions for Beaux

1. **Automatic recording mode (16).** The one-sentence explanation ("starts and stops recording by itself when it hears people talking") is a guess at what the device does. Please confirm.
2. **"Faster" model size (17).** 75 MB is an estimate for `whisper-base.en`. The real size will come from the build.
3. **Recordings appear as each file finishes copying (15).** The recording-sync and transcription specs word this differently. The mockups show each recording in the list as soon as its file is saved, with its transcript queued.
4. **Menu-bar menu contents (18).** The spec lists last synced, device state, Sync now, Open EarBud, and Quit. The mockup also adds Record from Mac, Settings, and a "Waiting on your Fieldy" count.
5. **Menu-bar icon states (18).** The spec only says the icon changes during a sync. The mockup also shows a red dot while recording and a dimmed icon when the Fieldy is not nearby.
6. **Stop from the notch dock (19, 20).** The spec lists Record from Mac in the hover panel but does not say how to stop. The mockups show a Stop button on hover while recording.
7. **Floating capsule at rest (20).** There is no notch to hide behind, so the resting capsule shows the device name and "Synced 23m ago" instead of only two small indicators.
8. **Display picker location (20).** "Show it on" is placed under "Show EarBud in the notch" in Settings. Built-in display is the default.
9. **Reminder body and actions (21).** The spec gives only the title. The body ("Your last sync was yesterday at 1:40 PM. Click to sync now.") and the Options actions (Sync now, Open EarBud) are our wording. Closing the banner does not snooze; the next reminder comes at the same time the next day.

## Approval

Beaux approved these mockups on 2026-10-30 (14:11 PDT), including the choices listed above. The app build follows them. The app icon concept is not chosen yet; the build uses concept A for now.
