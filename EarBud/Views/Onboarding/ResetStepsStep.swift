import SwiftUI

/// Mockup 06, pane 1: the three reset steps, waiting for the Fieldy to come back.
/// Pane 2 ("It didn't work" help) is a sheet over this step.
struct ResetStepsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            VStack(spacing: 8) {
                Text("Reset your Fieldy").font(Typography.largeTitle).foregroundStyle(Palette.label)
                Text("Follow these three steps. Keep your Fieldy near this Mac.")
                    .font(Typography.lead).foregroundStyle(Palette.label2)
            }

            HStack(spacing: 8) {
                stepColumn(number: 1, title: "Click once, quickly", detail: "A short click.\nLet go in under 1 second.", badge: "under 1 s")
                Image(systemName: "chevron.right").foregroundStyle(Palette.label3)
                stepColumn(number: 2, title: "Then press and hold", detail: "Straight away. Keep holding for 10 seconds.", badge: "hold 10 s")
                Image(systemName: "chevron.right").foregroundStyle(Palette.label3)
                stepColumn(number: 3, title: "Hold until the light cycles", detail: "It shows 4 colours in turn. Then let go.", badge: nil)
            }

            HStack(spacing: 8) {
                Spinner(size: 14)
                Text("Waiting for your Fieldy to come back…").font(Typography.footnote).foregroundStyle(Palette.label2)
            }
            Spacer(minLength: 4)
        }
        .sheet(isPresented: $model.showResetHelp) {
            ResetHelpSheet(model: model)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("It didn't work") { model.itDidntWork() }
                    .buttonStyle(EarBudButtonStyle())
            }
        }
    }

    private func stepColumn(number: Int, title: String, detail: String, badge: String?) -> some View {
        VStack(spacing: 8) {
            FieldyArtwork(width: 80, led: number == 3 ? Palette.accent : nil, radar: number == 2)
            Text("STEP \(number)").font(Typography.smallMedium).foregroundStyle(Palette.accent)
            Text(title).font(Typography.stepTitle).foregroundStyle(Palette.label).multilineTextAlignment(.center)
            Text(detail).font(Typography.caption).foregroundStyle(Palette.label2)
                .multilineTextAlignment(.center)
                .cssLineHeight(1.3, size: 11.5)
            if let badge {
                Text(badge).font(Typography.small).foregroundStyle(Palette.label2)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Palette.fill2))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Mockup 06, pane 2: "No problem, let's try again."
private struct ResetHelpSheet: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No problem, let's try again").font(Typography.detailTitle).foregroundStyle(Palette.label)
            Text("If the light came on once and your Fieldy just restarted, the first short click was missed. That's the most common slip.")
                .font(Typography.body).foregroundStyle(Palette.label)
                .cssLineHeight(1.4, size: 13)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                outcomeCard(title: "Restarted only", detail: "Light came on once, no colours. The click was too long, or the hold started too late.",
                            fill: Palette.red.opacity(0.08))
                outcomeCard(title: "Reset worked", detail: "The light cycled through 4 colours. EarBud will find it in a moment.",
                            fill: Palette.green.opacity(0.1))
            }

            VStack(alignment: .leading, spacing: 6) {
                bullet("Click and let go **in under 1 second**, then press and hold **straight away**.")
                bullet("Keep holding a full **10 seconds**. Count it out.")
                bullet("Nothing at all? Charge your Fieldy for a few minutes and try again.")
            }
            .font(Typography.footnote).foregroundStyle(Palette.label)

            HStack {
                Spacer()
                Button("Show steps again") { model.showResetHelp = false }
                    .buttonStyle(EarBudButtonStyle())
                Button("Try again") { model.tryResetAgain() }
                    .buttonStyle(EarBudButtonStyle(kind: .primary))
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func outcomeCard(title: String, detail: String, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Typography.stepTitle).foregroundStyle(Palette.label)
            Text(detail).font(Typography.caption).foregroundStyle(Palette.label2)
                .cssLineHeight(1.35, size: 11.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(radius: 10, fill: fill)
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text).cssLineHeight(1.4, size: 12)
        }
    }
}
