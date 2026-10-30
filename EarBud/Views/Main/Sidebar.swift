import SwiftUI

/// Library and Device sections, with the device card pinned to the bottom (mockup 12).
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding<SidebarItem?>(get: { model.sidebar }, set: { if let item = $0 { model.sidebar = item } })) {
            Section("Library") {
                Label { Text("Recordings") } icon: { Image(systemName: "waveform").foregroundStyle(Palette.sidebarIcon) }
                    .badge(model.recordings.isEmpty ? 0 : model.recordings.count)
                    .tag(SidebarItem.recordings)
                Label { Text("Sync History") } icon: { Image(systemName: "clock").foregroundStyle(Palette.sidebarIcon) }
                    .tag(SidebarItem.syncHistory)
                Label { Text("Recently Deleted") } icon: { Image(systemName: "trash").foregroundStyle(Palette.sidebarIcon) }
                    .badge(model.deleted.count)
                    .tag(SidebarItem.recentlyDeleted)
            }
            Section("Device") {
                Label {
                    HStack {
                        Text("My Fieldy")
                        Spacer()
                        deviceIndicator
                    }
                } icon: {
                    PodGlyph(size: 16).foregroundStyle(Palette.sidebarIcon)
                }
                .tag(SidebarItem.device)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            DeviceCard()
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder private var deviceIndicator: some View {
        if model.sync.isRunning {
            Spinner(size: 11, lineWidth: 1.5)
        } else if model.isRecordingOnDevice {
            StatusDot(color: Palette.red)
        } else if model.deviceState?.connection == .connected {
            StatusDot()
        } else {
            StatusDot(color: Palette.neutralDot)
        }
    }
}

/// `.devcard`: the Fieldy's name, state and last sync.
struct DeviceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                PodGlyph(size: 18)
                    .foregroundStyle(Palette.podIcon)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.accentTint))
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.deviceState?.name ?? "Fieldy")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.label)
                    HStack(spacing: 5) {
                        StatusDot(color: statusColor)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(status(at: context.date))
                        }
                    }
                    .font(Typography.small)
                    .foregroundStyle(Palette.label2)
                }
            }
            Rectangle().fill(Palette.separator).frame(height: Metrics.hairline)
                .padding(.top, 8)
            Text(lastSynced)
                .font(Typography.small)
                .foregroundStyle(Palette.label2)
                .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.deviceCard))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.deviceCardBorder, lineWidth: Metrics.hairline))
        .contentShape(Rectangle())
        .onTapGesture { model.sidebar = .device }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var statusColor: Color {
        if model.isRecordingOnDevice { return Palette.red }
        return model.deviceState?.connection == .connected ? Palette.green : Palette.neutralDot
    }

    private func status(at date: Date) -> String {
        guard let device = model.deviceState else { return "Looking for your Fieldy…" }
        let battery = device.batteryPercent.map { " · \($0)%" } ?? ""
        if let started = device.recordingStartedAt {
            return "Recording · \(model.formatting.timestamp(date.timeIntervalSince(started)))"
        }
        if model.sync.isRunning { return "Syncing\(battery)" }
        return switch device.connection {
        case .connected: "Connected\(battery)"
        case .connecting, .searching: "Looking for your Fieldy…"
        case .notNearby: "Not nearby"
        case .bluetoothOff: "Bluetooth is off"
        case .pairedElsewhere: "Paired with another device"
        case .notSetUp: "Not set up"
        }
    }

    private var lastSynced: String {
        guard let date = model.deviceState?.lastSynced else { return "Not synced yet" }
        return "Last synced \(model.formatting.relativeMoment(date, now: model.now()))"
    }
}
