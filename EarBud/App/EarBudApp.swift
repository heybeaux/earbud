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

/// The app's scenes. The model is only read inside child views and commands, not in this body,
/// so a model change doesn't re-run the whole scene graph and rebuild the main menu.
struct EarBudApp: App {
    static let mainWindowID = "main"
    static let onboardingWindowID = "onboarding"

    @State private var model: AppModel
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        let model = AppModel.usesFixtures ? AppModel.fixture() : AppModel.real()
        _model = State(initialValue: model)
        SyncReminderScheduler.shared.attach(model: model)
        ImportRouter.shared.attach(model: model)
        #if DEBUG
        DebugSnapshot.runIfRequested(model: model)
        #endif
    }

    var body: some Scene {
        Window("EarBud", id: Self.mainWindowID) {
            MainWindow()
                .modifier(LaterFeaturesHost())
                .environment(model)
        }
        .defaultSize(width: Metrics.windowWidth, height: Metrics.windowHeight)
        .windowToolbarStyle(.unified)
        .commands {
            FieldyCommands(model: model)
            RecordingEditCommands(model: model)
        }

        Window("Welcome to EarBud", id: Self.onboardingWindowID) {
            OnboardingHost(appModel: model)
        }
        .defaultSize(width: 560, height: 560)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarMenu()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }

    /// MenuBarExtra writes `isInserted` back on every scene update. Writing the same value to
    /// UserDefaults still invalidates @AppStorage, which re-ran this body forever, so only write changes.
    private var menuBarInserted: Binding<Bool> {
        Binding(get: { showInMenuBar }, set: { if $0 != showInMenuBar { showInMenuBar = $0 } })
    }
}

/// The Fieldy menu in the menu bar of the app.
private struct FieldyCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .importExport) { ImportMenuItem(model: model) }
        CommandMenu("Fieldy") { FieldyMenuItems(model: model) }
    }
}

private struct FieldyMenuItems: View {
    let model: AppModel

    var body: some View {
        Button("Sync Now") { _ = model.syncNow() }
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

/// File > Import Audio… ⇧⌘I (mockup 23).
private struct ImportMenuItem: View {
    let model: AppModel

    var body: some View {
        Button {
            if let urls = ImportPanel.choose() { model.importAudio(urls) }
        } label: {
            Label("Import Audio\u{2026}", systemImage: "arrow.down.circle")
        }
        .keyboardShortcut("i", modifiers: [.command, .shift])
    }
}

/// Edit menu additions for the selected recording (mockup 26: Delete Audio, Keep Transcript; ⌘⌫ Delete Recording…).
private struct RecordingEditCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Delete Audio, Keep Transcript") {
                if let id = model.selectedID { model.requestDeleteAudio([id]) }
            }
            .disabled(!canDeleteAudio)
            Button("Delete Recording…") {
                if let id = model.selectedID { Task { await model.moveToTrash(id) } }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.selectedRecording == nil)
        }
    }

    private var canDeleteAudio: Bool {
        guard let recording = model.selectedRecording else { return false }
        return !recording.isTranscriptOnly && recording.transcript.isFinished
    }
}

/// The menu bar icon: ready, syncing, recording or not nearby.
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarGlyph.image(for: model.menuBarState))
            .onAppear {
                #if DEBUG
                // Snapshot mode is menu-bar-first, so open the main window to capture it.
                if UserDefaults.standard.string(forKey: "EarBudSnapshot") != nil {
                    openWindow(id: EarBudApp.mainWindowID)
                }
                #endif
            }
    }
}

/// Keeps the later-feature stubs in step with Settings, and lets reminder clicks open this window.
private struct LaterFeaturesHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.showInNotch) private var showInNotch = false
    @AppStorage(SettingsKey.notchDisplay) private var notchDisplay = ""

    func body(content: Content) -> some View {
        content
            .onAppear {
                if OnboardingState.isNeeded { openWindow(id: EarBudApp.onboardingWindowID) }
                let openWindow = openWindow
                SyncReminderScheduler.shared.openMainWindow = { openWindow(id: EarBudApp.mainWindowID) }
                ImportRouter.shared.openMainWindow = { openWindow(id: EarBudApp.mainWindowID) }
                update()
            }
            .onChange(of: showInNotch) { update() }
            .onChange(of: notchDisplay) { update() }
    }

    private func update() {
        NotchDockController.shared.attach(model: model) {
            NSApp.activate()
            openWindow(id: EarBudApp.mainWindowID)
        }
        NotchDockController.shared.update(enabled: showInNotch, displayName: notchDisplay.isEmpty ? nil : notchDisplay)
    }
}
