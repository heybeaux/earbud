import SwiftUI

/// Picks the app to run. When the unit tests use the app as their host, the real windows,
/// menu bar item and later-feature schedulers stay off so the tests don't wait on UI.
@main
enum Launcher {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil || NSClassFromString("XCTestCase") != nil {
            TestHostApp.main()
        } else {
            EarBudApp.main()
        }
    }
}

/// An empty app for the unit-test host.
struct TestHostApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}

struct EarBudApp: App {
    static let mainWindowID = "main"

    @State private var model = AppModel.fixture()
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true
    @AppStorage(SettingsKey.showInNotch) private var showInNotch = true
    @AppStorage(SettingsKey.notchDisplay) private var notchDisplay = ""
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = true
    @AppStorage(SettingsKey.reminderDays) private var reminderDays = 1
    @AppStorage(SettingsKey.reminderTime) private var reminderTime = 19 * 60

    var body: some Scene {
        Window("EarBud", id: Self.mainWindowID) {
            MainWindow()
                .environment(model)
                .onAppear {
                    if Onboarding.isNeeded { Onboarding.start() }
                    updateLaterFeatures()
                }
                .onChange(of: showInNotch) { updateLaterFeatures() }
                .onChange(of: notchDisplay) { updateLaterFeatures() }
                .onChange(of: reminderEnabled) { updateLaterFeatures() }
                .onChange(of: reminderDays) { updateLaterFeatures() }
                .onChange(of: reminderTime) { updateLaterFeatures() }
                .onChange(of: model.deviceState?.lastSynced) { updateLaterFeatures() }
        }
        .defaultSize(width: Metrics.windowWidth, height: Metrics.windowHeight)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Fieldy") {
                Button("Sync Now") { model.syncNow() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.sync.isRunning)
                Button(model.isRecordingOnDevice ? "Stop Recording" : "Record from Mac") {
                    Task { await model.toggleRecording() }
                }
                .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Show My Fieldy") { model.sidebar = .device }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Show Recordings") { model.sidebar = .recordings }
                    .keyboardShortcut("1", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarMenu()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarGlyph.image(for: model.menuBarState))
        }
        .menuBarExtraStyle(.window)
    }

    private func updateLaterFeatures() {
        NotchDockController.shared.update(enabled: showInNotch, displayName: notchDisplay.isEmpty ? nil : notchDisplay)
        SyncReminderScheduler.shared.reschedule(enabled: reminderEnabled, afterDays: reminderDays, atMinutes: reminderTime,
                                                lastSynced: model.deviceState?.lastSynced)
    }
}
