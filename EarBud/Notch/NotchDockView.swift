import SwiftUI

/// What the dock window shows and how it's shaped. The controller owns it; the view only reads.
/// A display without a notch (the floating capsule, later) can reuse the same view with a zero
/// `notchSize.width` gap and a rounded top.
@MainActor
@Observable
final class NotchDockState {
    var layout: NotchGeometry.Layout = .resting
    /// The camera housing the top row leaves room for.
    var notchSize = CGSize(width: 185, height: 32)
    var topRadius: CGFloat = 0
    var lastResult: (outcome: SyncOutcome, at: Date)?

    var isExpanded: Bool {
        if case .expanded = layout { return true }
        return false
    }
}

/// The dock's buttons, provided by the controller.
struct NotchDockActions {
    var sync: () -> Void
    var record: () -> Void
    var open: (String) -> Void
    var expand: () -> Void
}

/// The black shape around the notch: indicators beside it, live activity under it, and the
/// quick panel when expanded (mockup 19).
struct NotchDockView: View {
    let model: AppModel
    let dock: NotchDockState
    let actions: NotchDockActions

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { _ in
            let now = model.now()
            content(activity: NotchPresenter.activity(device: model.deviceState, sync: model.sync, lastResult: dock.lastResult,
                                                      now: now, formatting: model.formatting), now: now)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(shape.fill(.black))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { if !dock.isExpanded { actions.expand() } }
        .environment(\.colorScheme, .dark)
    }

    private var shape: UnevenRoundedRectangle {
        let bottom = NotchGeometry.bottomRadius(for: dock.layout)
        return UnevenRoundedRectangle(topLeadingRadius: dock.topRadius, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: dock.topRadius, style: .continuous)
    }

    /// The timer needs every second; "23m" only needs the odd refresh.
    private var tickInterval: TimeInterval {
        model.isRecordingOnDevice || dock.isExpanded ? 1 : 15
    }

    @ViewBuilder
    private func content(activity: NotchActivity, now: Date) -> some View {
        VStack(spacing: 0) {
            topRow(activity)
            if dock.isExpanded {
                NotchQuickPanel(panel: NotchPresenter.panel(device: model.deviceState, sync: model.sync, newest: model.recordings.first,
                                                            isChangingRecording: model.isChangingRecording, now: now,
                                                            formatting: model.formatting),
                                actions: actions)
            } else {
                below(activity)
            }
        }
    }

    // MARK: Beside the notch

    private func topRow(_ activity: NotchActivity) -> some View {
        let wing = dock.isExpanded ? nil : (dock.layout == .resting ? NotchGeometry.restingWing : NotchGeometry.liveWing)
        return HStack(spacing: 0) {
            leading(activity)
                .frame(width: wing, alignment: dock.isExpanded ? .leading : .center)
            Spacer(minLength: dock.notchSize.width)
            trailing(activity)
                .frame(width: wing, alignment: dock.isExpanded ? .trailing : .center)
        }
        .padding(.horizontal, dock.isExpanded ? 22 : 0)
        .frame(height: dock.notchSize.height)
    }

    @ViewBuilder
    private func leading(_ activity: NotchActivity) -> some View {
        switch activity {
        case .resting(let dot, _), .syncResult(_, let dot, _):
            StatusDot(color: color(dot))
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accentHi)
                .accessibilityLabel("Syncing")
        case .recording:
            StatusDot(color: Palette.red, size: 9)
                .background(Circle().fill(Palette.recordDotHalo).frame(width: 15, height: 15))
                .accessibilityLabel("Recording")
        }
    }

    @ViewBuilder
    private func trailing(_ activity: NotchActivity) -> some View {
        switch activity {
        case .resting(_, let since), .syncResult(_, _, let since):
            Text(since)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityLabel(since == "now" ? "Synced just now" : "Last synced \(since) ago")
        case .syncing(let label, _):
            Text(label)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
        case .recording(let elapsed):
            Text(elapsed)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    // MARK: Under the notch

    @ViewBuilder
    private func below(_ activity: NotchActivity) -> some View {
        switch activity {
        case .syncing(_, let fraction):
            ProgressBar(value: fraction, height: 4, track: .white.opacity(0.14), tint: Palette.accentHi)
                .padding(.horizontal, 22)
                .padding(.top, 2)
        case .syncResult(let result, _, _):
            HStack(spacing: 6) {
                Image(systemName: symbol(result.tone))
                    .font(.system(size: 12))
                    .foregroundStyle(.white, tint(result.tone))
                Text(result.message)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        case .resting, .recording:
            EmptyView()
        }
    }

    private func color(_ dot: NotchDot) -> Color {
        switch dot {
        case .connected: Palette.green
        case .recording: Palette.red
        case .away: Palette.neutralDot
        }
    }

    private func symbol(_ tone: NotchSyncResult.Tone) -> String {
        switch tone {
        case .success: "checkmark.circle.fill"
        case .neutral: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .failure: "xmark.circle.fill"
        }
    }

    private func tint(_ tone: NotchSyncResult.Tone) -> Color {
        switch tone {
        case .success: Palette.green
        case .neutral: Palette.neutralIcon
        case .warning: Palette.orange
        case .failure: Palette.red
        }
    }
}

/// The expanded panel: device, Sync now, Record from Mac, and the newest transcript.
private struct NotchQuickPanel: View {
    let panel: NotchPanel
    let actions: NotchDockActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 10) {
                Button(action: actions.sync) {
                    Label(panel.syncTitle, systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(EarBudButtonStyle(kind: .primary, size: .large, fullWidth: true))
                .disabled(!panel.canSync)
                Button(action: actions.record) {
                    Label {
                        Text(panel.recordTitle)
                    } icon: {
                        Image(systemName: panel.isRecording ? "stop.fill" : "circle.fill").foregroundStyle(Palette.red)
                    }
                }
                .buttonStyle(EarBudButtonStyle(kind: .standard, size: .large, fullWidth: true))
                .disabled(!panel.canRecord)
            }
            if let newest = panel.newest {
                newestCard(newest)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            PodGlyph(size: 18)
                .foregroundStyle(Palette.podIcon)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.accentTint))
            VStack(alignment: .leading, spacing: 2) {
                Text(panel.deviceName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    StatusDot(color: panel.dot == .connected ? Palette.green : (panel.dot == .recording ? Palette.red : Palette.neutralDot),
                              size: 6)
                    Text(panel.status)
                }
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Last synced").foregroundStyle(.white.opacity(0.5))
                Text(panel.lastSynced).foregroundStyle(.white.opacity(0.85))
            }
            .font(Typography.caption)
        }
    }

    private func newestCard(_ newest: NotchPanel.Newest) -> some View {
        Button {
            actions.open(newest.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(newest.heading)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("Open \(Image(systemName: "chevron.right"))")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.accentHi)
                }
                .font(Typography.caption)
                Text(newest.text)
                    .font(Typography.callout)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: Metrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open newest recording")
    }
}
