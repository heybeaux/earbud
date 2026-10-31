import SwiftUI

/// Mockup 08: consent before downloading the speech model, then progress.
struct SpeechModelStep: View {
    @Bindable var model: OnboardingModel

    private var targetModel: SpeechModel? {
        model.targetSpeechModel
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            HStack(spacing: 12) {
                OnboardingIconTile(systemName: "waveform", background: Palette.accentTint, foreground: Palette.accent)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.label3)
                OnboardingIconTile(systemName: "laptopcomputer", background: Palette.accent, foreground: .white)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.label3)
                OnboardingIconTile(systemName: "doc.text", background: Palette.fill2, foreground: Palette.label2)
            }

            if let fraction = model.modelDownloadFraction {
                VStack(spacing: 8) {
                    Text("Downloading the speech model…").font(Typography.largeTitle).foregroundStyle(Palette.label)
                    Text("You can keep using your Mac. EarBud moves on by itself when it's done.")
                        .font(Typography.lead).foregroundStyle(Palette.label2)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 6) {
                    HStack {
                        Text(targetModel?.name ?? "Speech model").font(Typography.stepTitle).foregroundStyle(Palette.label)
                        Spacer()
                        Text("\(Int((fraction * 100).rounded()))%").font(Typography.body).foregroundStyle(Palette.label2)
                    }
                    ProgressBar(value: fraction)
                    HStack {
                        if let model = targetModel {
                            Text("\(Formatting.standard.bytes(Int(Double(model.sizeBytes) * fraction))) of \(Formatting.standard.bytes(model.sizeBytes))")
                                .font(Typography.caption).foregroundStyle(Palette.label2)
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: 440)
            } else {
                VStack(spacing: 8) {
                    Text("Download the speech model").font(Typography.largeTitle).foregroundStyle(Palette.label)
                    Text("EarBud turns speech into text right here on your Mac. To do that, it needs a speech model.")
                        .font(Typography.lead).foregroundStyle(Palette.label2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                FormGroup {
                    FormRow(title: "Size", leading: { rowIcon("arrow.down.circle") }, trailing: {
                        Text(targetModel.map { Formatting.standard.bytes($0.sizeBytes) } ?? "—").font(Typography.body).foregroundStyle(Palette.label2)
                    })
                    FormDivider()
                    FormRow(title: "One time only", leading: { rowIcon("checkmark") }, trailing: {
                        Text("Never again after this").font(Typography.body).foregroundStyle(Palette.label2)
                    })
                    FormDivider()
                    FormRow(title: "The only thing EarBud downloads", leading: { rowIcon("checkmark.shield") }, trailing: {
                        Text("Nothing is uploaded").font(Typography.body).foregroundStyle(Palette.label2)
                    })
                }
                .frame(maxWidth: 440)
                Text("Not on good Wi-Fi? Choose Later. Recordings still copy and play, and you can download the model any time.")
                    .font(Typography.caption).foregroundStyle(Palette.label2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Spacer(minLength: 4)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                if model.modelDownloadFraction != nil {
                    Button("Cancel download") {}
                        .buttonStyle(EarBudButtonStyle())
                        .disabled(true)
                    Button("Continue") {}
                        .buttonStyle(EarBudButtonStyle(kind: .primary))
                        .disabled(true)
                } else {
                    Button("Later") { model.deferSpeechModel() }
                        .buttonStyle(EarBudButtonStyle())
                    Button("Download") { Task { await model.downloadSpeechModel() } }
                        .buttonStyle(EarBudButtonStyle(kind: .primary))
                }
            }
        }
    }
}

/// A small inline icon for form rows that mirrors the callout glyph style.
private func rowIcon(_ systemName: String) -> some View {
    Image(systemName: systemName).font(.system(size: 13)).foregroundStyle(Palette.accent).frame(width: 20)
}
