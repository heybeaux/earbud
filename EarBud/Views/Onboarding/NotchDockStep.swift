import SwiftUI

/// Mockup 10. Shown only on Macs with a camera notch: previews the notch dock resting and
/// expanded, and turns it on (from the end of onboarding) with "Turn on".
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

    /// A MacBook screen's top edge with the dock resting beside the notch, or expanded on hover.
    private func notchPreview(hovering: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.95, green: 0.88, blue: 0.80), Color(red: 0.64, green: 0.75, blue: 0.68)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                previewMenuBar
                if hovering { previewPanel } else { previewResting }
            }
            .frame(width: 250, height: 140)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous))
            .padding([.top, .horizontal], 5)
            .background(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous).fill(Color.black))
            .accessibilityHidden(true)

            Text(hovering ? "Hover: sync, record, newest transcript" : "Resting: a status dot and time since last sync")
                .font(Typography.caption).foregroundStyle(Palette.label2)
                .multilineTextAlignment(.center)
                .frame(width: 260)
        }
    }

    private var previewMenuBar: some View {
        HStack(spacing: 8) {
            Text("Finder").fontWeight(.bold)
            Text("File")
            Spacer()
            Text("1:48 PM")
        }
        .font(.system(size: 8))
        .foregroundStyle(.black.opacity(0.75))
        .padding(.horizontal, 9)
        .frame(height: 18)
        .background(.white.opacity(0.45))
    }

    private var previewResting: some View {
        HStack {
            StatusDot(color: Palette.green, size: 5)
            Spacer()
            Text("2h").font(.system(size: 8, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .frame(width: 110, height: 18)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6, style: .continuous).fill(Color.black))
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                StatusDot(color: Palette.green, size: 5)
                Text("Fieldy connected · 82%").fontWeight(.semibold).foregroundStyle(.white)
                Spacer(minLength: 4)
                Text("Synced 2h ago").foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 7))
            HStack(spacing: 5) {
                Text("Sync now")
                    .frame(maxWidth: .infinity, minHeight: 14)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Palette.accentHi))
                Text("Record from Mac")
                    .frame(maxWidth: .infinity, minHeight: 14)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.12)))
            }
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.white)
            Text("“Okay so for Saturday, we meet at the seawall by the rowing club at seven…”")
                .font(.system(size: 7))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.07)))
        }
        .padding(.horizontal, 8)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .frame(width: 180)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous).fill(Color.black))
    }
}
