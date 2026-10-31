import SwiftUI

/// Mockup 10: preview-only. Shown only on Macs with a camera notch. The real notch dock ships later;
/// this just records the preference and shows what it would look like.
struct NotchDockStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            HStack(spacing: 12) {
                notchPreview(hovering: false)
                notchPreview(hovering: true)
            }

            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                Text("This MacBook has a camera notch")
            }
            .font(Typography.footnote).foregroundStyle(Palette.label2)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Palette.fill2))

            VStack(spacing: 8) {
                Text("Show EarBud in the notch?").font(Typography.largeTitle).foregroundStyle(Palette.label)
                Text("EarBud can sit quietly beside the camera notch. Glance up to see your Fieldy's status, or hover to sync.")
                    .font(Typography.lead).foregroundStyle(Palette.label2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            OnboardingCallout(systemName: "info.circle") {
                Text("Off unless you turn it on. You can change it any time in Settings, under **Show EarBud in the notch**. The menu bar icon stays either way.")
                    .font(Typography.footnote).foregroundStyle(Palette.label2)
                    .cssLineHeight(1.4, size: 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 440)
            Spacer(minLength: 4)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Not now") { model.chooseNotchDock(false) }
                    .buttonStyle(EarBudButtonStyle())
                Button("Turn on") { model.chooseNotchDock(true) }
                    .buttonStyle(EarBudButtonStyle(kind: .primary))
            }
        }
    }

    private func notchPreview(hovering: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 200, height: 110)
                Capsule()
                    .fill(Color.black)
                    .frame(width: hovering ? 150 : 70, height: hovering ? 54 : 18)
                    .overlay {
                        if hovering {
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    StatusDot(color: Palette.green, size: 5)
                                    Text("Fieldy connected · 82%").font(.system(size: 8)).foregroundStyle(.white)
                                }
                                Text("Sync now").font(.system(size: 7, weight: .semibold)).foregroundStyle(.white)
                            }
                        } else {
                            HStack(spacing: 4) {
                                StatusDot(color: Palette.green, size: 5)
                                Text("2h").font(.system(size: 8)).foregroundStyle(.white)
                            }
                        }
                    }
            }
            Text(hovering ? "Hover: sync, record, newest transcript" : "Resting: a status dot and time since last sync")
                .font(Typography.caption).foregroundStyle(Palette.label2)
                .multilineTextAlignment(.center)
                .frame(width: 200)
        }
    }
}
