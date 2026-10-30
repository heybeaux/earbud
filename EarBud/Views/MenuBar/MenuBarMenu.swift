import AppKit
import SwiftUI

/// The menu-bar menu (mockup 18): device status, Sync now, Record from Mac, Open, Settings, Quit.
struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            stats
            MenuSeparator()
            MenuItem(title: syncTitle, symbol: "arrow.triangle.2.circlepath", shortcut: "⌘S", enabled: !model.sync.isRunning) {
                model.syncNow()
            }
            .keyboardShortcut("s", modifiers: .command)
            MenuItem(title: model.isRecordingOnDevice ? "Stop recording" : "Record from Mac",
                     symbol: model.isRecordingOnDevice ? "stop.fill" : "circle.fill", symbolTint: Palette.red, shortcut: "⌘R",
                     enabled: model.deviceState?.connection == .connected && !model.isChangingRecording) {
                Task { await model.toggleRecording() }
            }
            .keyboardShortcut("r", modifiers: .command)
            MenuSeparator()
            MenuItem(title: "Open EarBud", symbol: "macwindow", shortcut: "⌘O") {
                openMainWindow()
            }
            .keyboardShortcut("o", modifiers: .command)
            MenuItem(title: "Settings…", symbol: "gearshape", shortcut: "⌘,") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            MenuSeparator()
            MenuItem(title: "Quit EarBud", symbol: "power", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(5)
        .frame(width: 286)
        .task { await model.start() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PodGlyph(size: 20)
                .foregroundStyle(Palette.podIcon)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.accentTint))
            VStack(alignment: .leading, spacing: 1) {
                Text(model.deviceState?.name ?? "Fieldy")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.label)
                HStack(spacing: 5) {
                    StatusDot(color: model.isRecordingOnDevice ? Palette.red
                              : (model.deviceState?.connection == .connected ? Palette.green : Palette.neutralDot))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(status(now: context.date))
                    }
                }
                .font(Typography.menuInfo)
                .foregroundStyle(Palette.label2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 9)
    }

    private var stats: some View {
        VStack(spacing: 3) {
            statLine("Last synced", model.deviceState?.lastSynced.map { lastSynced($0) } ?? "Not yet")
            statLine("Waiting on your Fieldy", model.formatting.recordings(model.deviceState?.waitingCount ?? 0))
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.label2)
            Spacer()
            Text(value).fontWeight(.medium).foregroundStyle(Palette.label)
        }
        .font(Typography.menuInfo)
    }

    private func lastSynced(_ date: Date) -> String {
        let moment = model.formatting.relativeMoment(date, now: model.now())
        return moment.prefix(1).uppercased() + moment.dropFirst()
    }

    private var syncTitle: String {
        if case .running(let p) = model.sync {
            return p.phase == .copying ? "Syncing… \(Int((p.fraction * 100).rounded()))%" : "Syncing…"
        }
        return "Sync now"
    }

    private func status(now: Date) -> String {
        guard let device = model.deviceState else { return "Looking for your Fieldy…" }
        if let started = device.recordingStartedAt {
            return "Recording · \(model.formatting.timestamp(now.timeIntervalSince(started)))"
        }
        switch device.connection {
        case .connected:
            return device.batteryPercent.map { "Connected · battery \($0)%" } ?? "Connected"
        case .notNearby: return "Not nearby"
        default: return "Looking for your Fieldy…"
        }
    }

    private func openMainWindow() {
        NSApp.activate()
        openWindow(id: EarBudApp.mainWindowID)
    }
}

/// `.menu .it`: a menu row that highlights in the accent colour on hover.
private struct MenuItem: View {
    var title: String
    var symbol: String
    var symbolTint: Color? = nil
    var shortcut: String
    var enabled = true
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            action()
            NSApp.keyWindow?.close()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: symbol == "circle.fill" ? 11 : 13))
                    .foregroundStyle(highlighted ? .white : (symbolTint ?? Palette.label2))
                    .frame(width: 16)
                Text(title)
                    .font(Typography.menuItem)
                    .foregroundStyle(highlighted ? .white : Palette.label)
                Spacer()
                Text(shortcut)
                    .font(.system(size: 13))
                    .foregroundStyle(highlighted ? .white.opacity(0.75) : Palette.label3)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(highlighted ? Palette.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
    }

    private var highlighted: Bool { hovering && enabled }
}

private struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.separatorStrong.opacity(0.85))
            .frame(height: Metrics.hairline)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
    }
}
