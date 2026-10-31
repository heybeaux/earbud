import AppKit
import ServiceManagement
import SwiftUI

/// UserDefaults keys for app preferences.
enum SettingsKey {
    static let transcriptionModel = "transcription.model"
    static let reminderEnabled = "reminder.enabled"
    static let reminderDays = "reminder.days"
    /// Minutes after midnight.
    static let reminderTime = "reminder.time"
    static let showInMenuBar = "menuBar.show"
    static let showInNotch = "notch.show"
    static let notchDisplay = "notch.display"
}

/// EarBud Settings (mockup 17).
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @AppStorage(SettingsKey.transcriptionModel) private var modelID = "openai_whisper-small.en"
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = true
    @AppStorage(SettingsKey.reminderDays) private var reminderDays = ReminderSettings.defaultDays
    @AppStorage(SettingsKey.reminderTime) private var reminderTime = ReminderSettings.defaultMinutes
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true
    @AppStorage(SettingsKey.showInNotch) private var showInNotch = true
    @AppStorage(SettingsKey.notchDisplay) private var notchDisplay = ""
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            transcription
            reminder
            placement
            general
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.settingsBackground)
        .navigationTitle("EarBud Settings")
        .task { await model.start() }
        .onAppear { if notchDisplay.isEmpty { notchDisplay = NSScreen.screens.first?.localizedName ?? "" } }
    }

    // MARK: Sections

    private var transcription: some View {
        FormSection(title: "Transcription",
                    footer: "Transcripts are made on this Mac. Your recordings never go online. To redo an older transcript, open it and choose Transcribe Again.") {
            FormGroup(fill: Palette.content) {
                ForEach(Array(model.speechModels.enumerated()), id: \.element.id) { index, speech in
                    if index > 0 { FormDivider() }
                    SpeechModelRow(speech: speech, isSelected: modelID == speech.id) {
                        modelID = speech.id
                    }
                }
            }
        }
    }

    private var reminder: some View {
        FormSection(title: "Sync reminder") {
            FormGroup(fill: Palette.content) {
                FormRow(title: "Remind me to sync", detail: "Sends a notification. Click it to start a sync.") {
                    RowIcon(systemName: "bell")
                } trailing: {
                    AccentSwitch(isOn: $reminderEnabled, label: "Remind me to sync")
                }
                FormDivider()
                FormRow(title: "Remind me when it's been", indent: 28) {
                    Picker("Remind me when it's been", selection: $reminderDays) {
                        Text("1 day without a sync").tag(1)
                        Text("2 days without a sync").tag(2)
                        Text("3 days without a sync").tag(3)
                        Text("1 week without a sync").tag(7)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(!reminderEnabled)
                FormDivider()
                FormRow(title: "At", indent: 28) {
                    Picker("At", selection: $reminderTime) {
                        ForEach([9, 12, 17, 18, 19, 20, 21], id: \.self) { hour in
                            Text(timeLabel(hour * 60)).tag(hour * 60)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(!reminderEnabled)
            }
        }
    }

    private var placement: some View {
        FormSection(title: "Where EarBud shows up",
                    footer: "On a screen without a notch, EarBud shows a small floating capsule at the top centre instead.") {
            FormGroup(fill: Palette.content) {
                FormRow(title: "Show in menu bar", detail: "Sync and see your Fieldy's status from the top of the screen.") {
                    RowIcon(background: Palette.accent) {
                        StrokedGlyph(kind: .bud)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 15, height: 15)
                    }
                } trailing: {
                    AccentSwitch(isOn: $showInMenuBar, label: "Show in menu bar")
                }
                FormDivider()
                FormRow(title: "Show EarBud in the notch", detail: "A small strip beside the camera shows sync progress and recording time.") {
                    RowIcon(systemName: "laptopcomputer")
                } trailing: {
                    AccentSwitch(isOn: $showInNotch, label: "Show EarBud in the notch")
                }
                FormDivider()
                FormRow(title: "Show it on", indent: 28) {
                    Picker("Show it on", selection: $notchDisplay) {
                        ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(!showInNotch)
            }
        }
    }

    private var general: some View {
        FormSection(title: "General", footer: loginItemError) {
            FormGroup(fill: Palette.content) {
                FormRow(title: "Open EarBud when you log in", detail: "EarBud starts quietly in the menu bar, so reminders still arrive.") {
                    RowIcon(systemName: "power", background: Palette.neutralIcon)
                } trailing: {
                    AccentSwitch(isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin), label: "Open EarBud when you log in")
                }
            }
        }
    }

    // MARK: Helpers

    private func timeLabel(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return model.formatting.time(date)
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = "macOS didn't allow this change. You can add EarBud in System Settings, General, Login Items."
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Faster / More accurate, with size and Download or Installed.
private struct SpeechModelRow: View {
    @Environment(AppModel.self) private var model
    var speech: SpeechModel
    var isSelected: Bool
    var choose: () -> Void

    var body: some View {
        let download = model.modelDownloads[speech.id]
        Button {
            if speech.installed { choose() } else { Task { await model.downloadModel(speech.id); choose() } }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RadioMark(isOn: isSelected && speech.installed)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(speech.name).font(Typography.bodyMedium).foregroundStyle(Palette.label)
                        if speech.recommended {
                            Text("Recommended")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.accentTint))
                        }
                    }
                    Text(speech.detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.formatting.bytes(speech.sizeBytes))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.label2)
                    .padding(.top, 2)
                trailing(download: download)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(download != nil)
    }

    @ViewBuilder private func trailing(download: Double?) -> some View {
        if let download {
            ProgressBar(value: download, height: 4).frame(width: 74).padding(.top, 7)
        } else if speech.installed {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                Text("Installed")
            }
            .font(Typography.captionSemibold)
            .foregroundStyle(Palette.pillDoneText)
            .padding(.top, 2)
        } else {
            Button("Download") { Task { await model.downloadModel(speech.id) } }
                .buttonStyle(EarBudButtonStyle())
        }
    }
}
