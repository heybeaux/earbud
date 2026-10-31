import SwiftUI

/// The onboarding window shell: a card with step content and a footer of step dots plus buttons.
/// Mirrors `.card` from the mockups — white content on the window background, no toolbar.
struct OnboardingWindow: View {
    @State var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .welcome: WelcomeStep(model: model)
                case .bluetoothPermission: BluetoothPermissionStep(model: model)
                case .bluetoothDenied: BluetoothDeniedStep(model: model)
                case .findFieldy: FindFieldyStep(model: model)
                case .pairedElsewhere: PairedElsewhereStep(model: model)
                case .resetSteps: ResetStepsStep(model: model)
                case .connected: ConnectedStep(model: model)
                case .speechModel: SpeechModelStep(model: model)
                case .testRecording: TestRecordingStep(model: model)
                case .notchDock: NotchDockStep(model: model)
                case .finished: FinishedStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(32)

            Divider().foregroundStyle(Palette.separator)
            OnboardingFooter(model: model)
        }
        .frame(width: 560, height: 560)
        .background(Palette.content)
    }
}

/// `.dots` + the Back/primary action pair.
private struct OnboardingFooter: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        HStack {
            StepDots(current: model.step)
            Spacer()
            if model.path.count > 1, model.step != .finished {
                Button("Back") { model.goBack() }
                    .buttonStyle(EarBudButtonStyle())
            }
            footerAction
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder private var footerAction: some View {
        switch model.step {
        case .welcome:
            Button("Get started") { model.getStarted() }
                .buttonStyle(EarBudButtonStyle(kind: .primary))
        default:
            EmptyView()
        }
    }
}

private struct StepDots: View {
    var current: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.dotted, id: \.self) { step in
                Capsule()
                    .fill(step == current ? Palette.accent : Palette.fill2)
                    .frame(width: step == current ? 16 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Icon tile used in the welcome bullet rows and the speech-model step.
struct OnboardingIconTile: View {
    var systemName: String
    var background: Color = Palette.accentTint
    var foreground: Color = Palette.accent

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(foreground)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background))
    }
}

/// A labelled info callout, as `.estep` boxes with a leading icon (Bluetooth, reset warning, etc).
struct OnboardingCallout<Content: View>: View {
    enum Tone { case neutral, warning }
    var tone: Tone = .neutral
    var systemName: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tone == .warning ? Palette.orange : Palette.accent)
                .padding(.top, 1)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(radius: 10, fill: tone == .warning ? Palette.orange.opacity(0.08) : Palette.content2)
    }
}
