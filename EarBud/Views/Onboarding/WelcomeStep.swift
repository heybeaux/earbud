import SwiftUI

/// Mockup 02: welcome, plain-language explanation, three bullet points.
struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Palette.accentHi, Palette.accent], startPoint: .top, endPoint: .bottom))
                .frame(width: 96, height: 96)
                .overlay {
                    Image(systemName: "waveform.and.person.filled")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                }

            VStack(spacing: 8) {
                Text("Welcome to EarBud").font(Typography.largeTitle).foregroundStyle(Palette.label)
                Text("EarBud copies the recordings from your Fieldy 3 to this Mac and turns them into text you can read and search.")
                    .font(Typography.lead)
                    .foregroundStyle(Palette.label2)
                    .multilineTextAlignment(.center)
                    .cssLineHeight(1.4, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                bullet(systemName: "waveform", title: "Your recordings, on your Mac",
                       detail: "Press the button on your Fieldy and talk. When you're back at your desk, click Sync.")
                bullet(systemName: "checkmark.shield", title: "Stays on this Mac",
                       detail: "Your audio and its text never leave this Mac. No account, no cloud.")
                bullet(systemName: "info.circle", title: "Not made by Field Labs",
                       detail: "EarBud is an independent app that works with Fieldy 3. Field Labs doesn't make or support it.")
            }
            .frame(maxWidth: 420)
        }
    }

    private func bullet(systemName: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            OnboardingIconTile(systemName: systemName)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.stepTitle).foregroundStyle(Palette.label)
                Text(detail).font(Typography.footnote).foregroundStyle(Palette.label2)
                    .cssLineHeight(1.4, size: 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
