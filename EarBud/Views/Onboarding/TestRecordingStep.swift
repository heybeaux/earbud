import SwiftUI

/// Mockup 09: make a short test recording, then show the synced transcript.
struct TestRecordingStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        if model.testRecordingPhase == .done, let recording = model.testRecording {
            doneView(recording)
        } else {
            promptView
        }
    }

    private var promptView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            VStack(spacing: 8) {
                Text("Let's try it").font(Typography.largeTitle).foregroundStyle(Palette.label)
                Text("Make a short recording so you can see the whole thing work.")
                    .font(Typography.lead).foregroundStyle(Palette.label2)
            }

            HStack(spacing: 16) {
                stepColumn(number: 1, title: "Press once", detail: "Your Fieldy starts recording.") {
                    FieldyArtwork(width: 86, led: Palette.accent)
                }
                Text("\u{201C}This is my first recording with EarBud.\u{201D}")
                    .font(Typography.caption).foregroundStyle(Palette.label)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(width: 140)
                    .softCard(radius: 10, fill: Palette.accentTint)
                stepColumn(number: 3, title: "Press again", detail: "Your Fieldy stops recording.") {
                    FieldyArtwork(width: 86, led: nil)
                }
            }

            OnboardingCallout(systemName: "info.circle") {
                Text("If your Fieldy buzzes twice and doesn't record, its clock needed setting. EarBud has just fixed it. Press the button again.")
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
                if model.testRecordingPhase == .idle {
                    Button("Sync test recording") { Task { await model.makeTestRecording() } }
                        .buttonStyle(EarBudButtonStyle(kind: .primary))
                } else {
                    HStack(spacing: 8) {
                        Spinner(size: 14)
                        Text(model.testRecordingPhase == .recording ? "Recording…" : "Syncing…")
                            .font(Typography.footnote).foregroundStyle(Palette.label2)
                    }
                }
            }
        }
    }

    private func doneView(_ recording: RecordingItem) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.white, Palette.green)
            VStack(spacing: 8) {
                Text("It works").font(Typography.largeTitle).foregroundStyle(Palette.label)
                Text("EarBud copied your recording from your Fieldy and turned it into text, all on this Mac.")
                    .font(Typography.lead).foregroundStyle(Palette.label2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "play.circle.fill").font(.system(size: 20)).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(recording.recordedAt.formatted(date: .omitted, time: .shortened)).font(Typography.rowTitle).foregroundStyle(Palette.label)
                        Text("\(Formatting.standard.clock(recording.duration)) · copied just now").font(Typography.caption).foregroundStyle(Palette.label2)
                    }
                    Spacer()
                }
                .padding(12)
                FormDivider()
                Text(recording.preview ?? "")
                    .font(Typography.segment).foregroundStyle(Palette.label)
                    .cssLineHeight(1.4, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            }
            .softCard(radius: 12)
            .frame(maxWidth: 440)

            Text("You'll find it in your library with every recording after this one.")
                .font(Typography.caption).foregroundStyle(Palette.label2)
            Spacer(minLength: 4)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button(model.provider.hasNotch ? "Continue" : "Finish setup") { model.finishTestRecording() }
                    .buttonStyle(EarBudButtonStyle(kind: .primary))
            }
        }
    }

    private func stepColumn<Artwork: View>(number: Int, title: String, detail: String, @ViewBuilder artwork: () -> Artwork) -> some View {
        VStack(spacing: 8) {
            artwork()
            Text("\(number). \(title)").font(Typography.stepTitle).foregroundStyle(Palette.label)
            Text(detail).font(Typography.caption).foregroundStyle(Palette.label2)
        }
    }
}
