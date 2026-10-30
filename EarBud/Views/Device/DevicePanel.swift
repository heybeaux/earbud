import SwiftUI

/// My Fieldy: status, record from Mac, and the device's settings (mockup 16).
struct DevicePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let device = model.deviceState {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 18) {
                        DeviceHero(device: device)
                        FormSection(title: "About this Fieldy",
                                    footer: device.firmware == DeviceSnapshot.testedFirmware ? nil
                                        : "This Fieldy firmware has not been tested with EarBud. Syncing should still work.") {
                            FormGroup {
                                FormRow(title: "Model") { value(device.model) }
                                FormDivider()
                                FormRow(title: "Name") { value(device.name) }
                                FormDivider()
                                FormRow(title: "Paired with this Mac") {
                                    value(device.pairedAt.map { model.formatting.shortDay($0, now: model.now()) } ?? "Not yet")
                                }
                            }
                        }
                    }
                    .frame(width: 404)

                    VStack(alignment: .leading, spacing: 18) {
                        FormSection(title: "Record from Mac") {
                            RecordCard(device: device)
                        }
                        if let notice = model.deviceNotice {
                            DeviceNoticeView(notice: notice)
                        }
                        FormSection(title: "Recording") {
                            FormGroup {
                                ForEach(Array(RecordingMode.allCases.enumerated()), id: \.element) { index, mode in
                                    if index > 0 { FormDivider() }
                                    RecordingModeRow(mode: mode, device: device)
                                }
                            }
                        }
                        FormSection(footer: "EarBud checks each change with your Fieldy before showing it here.") {
                            FormGroup {
                                DeviceToggleRow(setting: .light, title: "Always-on light",
                                                detail: "A small light shows your Fieldy is on. Turn it off to save battery.",
                                                symbol: "lightbulb", tint: Palette.accent, isOn: device.lightOn) { on in
                                    await model.setLight(on)
                                }
                                FormDivider()
                                DeviceToggleRow(setting: .mute, title: "Mute microphone",
                                                detail: "While muted, your Fieldy can't record, even if you press the button.",
                                                symbol: "mic.slash", tint: Palette.neutralIcon, isOn: device.muted) { on in
                                    await model.setMuted(on)
                                }
                            }
                        }
                        FormSection(title: "Can't find it?") {
                            FormGroup {
                                FormRow(title: "Buzz my Fieldy", detail: "Makes your Fieldy vibrate so you can find it nearby.") {
                                    RowIcon(systemName: "iphone.radiowaves.left.and.right")
                                } trailing: {
                                    Button(model.isBuzzing ? "Buzzing…" : "Buzz my Fieldy") { Task { await model.buzz() } }
                                        .buttonStyle(EarBudButtonStyle())
                                        .disabled(model.isBuzzing)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
        }
        .background(Palette.content)
    }

    private func value(_ text: String) -> some View {
        Text(text).foregroundStyle(Palette.label2)
    }
}

/// `.dhero`: picture, name, connection, stats and the Sync button.
private struct DeviceHero: View {
    @Environment(AppModel.self) private var model
    var device: DeviceSnapshot

    var body: some View {
        let f = model.formatting
        VStack(spacing: 0) {
            FieldyArtwork(width: 200, led: led)
            Text(device.name)
                .font(Typography.deviceName)
                .foregroundStyle(Palette.label)
                .padding(.top, 8)
            HStack(spacing: 6) {
                StatusDot(color: device.connection == .connected ? Palette.green : Palette.neutralDot)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(connectionText(now: context.date))
                }
            }
            .font(Typography.callout)
            .foregroundStyle(Palette.label2)
            .padding(.top, 2)

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    StatTile(label: "Battery") {
                        HStack(spacing: 6) {
                            Text(device.batteryPercent.map { "\($0)%" } ?? "–").font(Typography.statValue)
                            if let pct = device.batteryPercent { BatteryGlyph(percent: pct) }
                        }
                    }
                    StatTile(label: "Waiting on your Fieldy") {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(device.waitingCount)").font(Typography.statValue)
                            Text(device.waitingCount == 1 ? "recording" : "recordings")
                                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.label2)
                            if device.waitingBytes > 0 {
                                Text("· \(f.bytes(device.waitingBytes))")
                                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.label2)
                            }
                        }
                    }
                }
                GridRow {
                    StatTile(label: "Last synced") {
                        Text(device.lastSynced.map { f.statDate($0, now: model.now()) } ?? "Not yet")
                            .font(Typography.statValueSmall)
                            .padding(.top, 3)
                    }
                    StatTile(label: "Firmware") {
                        Text(device.firmware).font(Typography.statValueSmall).padding(.top, 3)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 14)

            Button {
                model.syncNow()
            } label: {
                if model.sync.isRunning {
                    Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label(device.waitingCount > 0 ? "Sync \(f.recordings(device.waitingCount))" : "Sync now",
                          systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(EarBudButtonStyle(kind: .primary, size: .large, fullWidth: true))
            .disabled(model.sync.isRunning || device.connection != .connected)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .softCard(radius: Metrics.cardRadius)
    }

    private var led: Color? {
        if device.isRecording { return Palette.red }
        return device.lightOn ? Color(red: 0x3B / 255, green: 0xD3 / 255, blue: 0x6B / 255) : nil
    }

    private func connectionText(now: Date) -> String {
        switch device.connection {
        case .connected:
            let checked = device.checkedAt.map { "checked \(model.formatting.ago($0, now: now))" } ?? "nearby"
            return "Connected · nearby · \(checked)"
        case .notNearby:
            let read = device.checkedAt.map { " · last seen \(model.formatting.ago($0, now: now))" } ?? ""
            return "Not nearby\(read)"
        case .connecting, .searching: return "Looking for your Fieldy…"
        case .bluetoothOff: return "Bluetooth is off"
        case .pairedElsewhere: return "Paired with another device"
        case .notSetUp: return "Not set up yet"
        }
    }
}

/// `.stat`.
private struct StatTile<Value: View>: View {
    var label: String
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Typography.smallMedium).foregroundStyle(Palette.label2)
            value.foregroundStyle(Palette.label)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .softCard(radius: Metrics.statRadius, fill: Palette.content)
        .accessibilityElement(children: .combine)
    }
}

/// `.batt`.
private struct BatteryGlyph: View {
    var percent: Int

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5).strokeBorder(Palette.label3, lineWidth: 1.2)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(percent <= 20 ? Palette.red : Palette.green)
                    .frame(width: 22 * CGFloat(percent) / 100, height: 8)
                    .padding(.leading, 2)
            }
            .frame(width: 26, height: 12)
            RoundedRectangle(cornerRadius: 1).fill(Palette.label3).frame(width: 2, height: 4)
        }
        .accessibilityHidden(true)
    }
}

/// `.reccard`: start and stop a recording on the Fieldy.
private struct RecordCard: View {
    @Environment(AppModel.self) private var model
    var device: DeviceSnapshot

    var body: some View {
        let recording = device.isRecording
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(recording ? Palette.recordDotHalo : Palette.fill)
                    Circle().fill(Palette.red).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Palette.red.opacity(recording ? 0.2 : 0), lineWidth: 8))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording ? "Your Fieldy is recording" : "Start a recording from this Mac")
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.label)
                    if let started = device.recordingStartedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(model.formatting.timestamp(context.date.timeIntervalSince(started)))
                                .font(Typography.timer)
                                .foregroundStyle(Palette.label)
                        }
                    } else {
                        Text("Your Fieldy records to its own storage, just like pressing its button.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.label2)
                    }
                }
                Spacer()
                Button {
                    Task { await model.toggleRecording() }
                } label: {
                    if recording {
                        Label("Stop", systemImage: "stop.fill")
                    } else {
                        Label("Record", systemImage: "record.circle")
                    }
                }
                .buttonStyle(EarBudButtonStyle(kind: recording ? .destructiveFill : .standard, size: .large))
                .disabled(model.isChangingRecording || device.connection != .connected)
            }
            Rectangle().fill(recording ? Palette.recordCardBorder.opacity(0.8) : Palette.separator)
                .frame(height: Metrics.hairline)
                .padding(.top, 10)
            Text("Handy for meetings at your desk. The recording is saved on your Fieldy and comes over on your next sync.")
                .font(Typography.rowMeta)
                .foregroundStyle(Palette.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(recording ? Palette.recordCard : Palette.group))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .strokeBorder(recording ? Palette.recordCardBorder : Palette.groupBorder, lineWidth: Metrics.hairline))
    }
}

/// "Your Fieldy is muted" with Unmute, or another problem talking to the device.
private struct DeviceNoticeView: View {
    @Environment(AppModel.self) private var model
    var notice: DeviceNotice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.orange).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                switch notice {
                case .muted:
                    Text("Your Fieldy is muted").font(Typography.bodySemibold)
                    Text("It can't record while the microphone is muted.").font(Typography.callout).foregroundStyle(Palette.label2)
                case .message(let text):
                    Text(text).font(Typography.callout)
                }
            }
            .foregroundStyle(Palette.label)
            Spacer()
            if notice == .muted {
                Button("Unmute") { Task { await model.setMuted(false) } }
                    .buttonStyle(EarBudButtonStyle())
            } else {
                Button("OK") { model.deviceNotice = nil }
                    .buttonStyle(EarBudButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.orange.opacity(0.3), lineWidth: Metrics.hairline))
    }
}

/// Manual / Automatic, each explained in one sentence.
private struct RecordingModeRow: View {
    @Environment(AppModel.self) private var model
    var mode: RecordingMode
    var device: DeviceSnapshot

    var body: some View {
        let selected = device.recordingMode == mode
        let pending = model.pendingSettings.contains(.recordingMode)
        Button {
            Task { await model.setRecordingMode(mode) }
        } label: {
            FormRow(title: mode == .manual ? "Manual" : "Automatic",
                    detail: mode == .manual ? "Your Fieldy records only when you press its button."
                        : "Your Fieldy starts and stops recording by itself when it hears people talking.",
                    alignTop: true) {
                RadioMark(isOn: selected)
            } trailing: {
                if pending && !selected {
                    Spinner(size: 12, lineWidth: 1.5)
                } else if selected && model.savedSettings.contains(.recordingMode) {
                    SavedLabel()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pending)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A switch that only moves once the Fieldy confirms the change.
private struct DeviceToggleRow: View {
    @Environment(AppModel.self) private var model
    var setting: DeviceSetting
    var title: String
    var detail: String
    var symbol: String
    var tint: Color
    var isOn: Bool
    var change: (Bool) async -> Void

    var body: some View {
        FormRow(title: title, detail: detail) {
            RowIcon(systemName: symbol, background: tint)
        } trailing: {
            HStack(spacing: 10) {
                if model.pendingSettings.contains(setting) {
                    HStack(spacing: 4) {
                        Spinner(size: 11, lineWidth: 1.5)
                        Text("Checking…")
                    }
                    .font(Typography.small)
                    .foregroundStyle(Palette.label3)
                } else if model.savedSettings.contains(setting) {
                    SavedLabel()
                }
                AccentSwitch(isOn: Binding(get: { isOn }, set: { value in Task { await change(value) } }), label: title)
                    .disabled(model.pendingSettings.contains(setting))
            }
        }
    }
}

/// `.readback`: "✓ Saved".
private struct SavedLabel: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.green)
            Text("Saved")
        }
        .font(Typography.small)
        .foregroundStyle(Palette.label3)
        .transition(.opacity)
    }
}
