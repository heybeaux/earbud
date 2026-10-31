import SwiftUI

/// Mockup 04: searching for the Fieldy, with troubleshooting tips after 30 seconds.
struct FindFieldyStep: View {
    @Bindable var model: OnboardingModel
    @State private var showTips = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            FieldyArtwork(width: 160, led: nil, radar: true)

            VStack(spacing: 8) {
                Text("Looking for your Fieldy…").font(Typography.largeTitle).foregroundStyle(Palette.label)
                Text("Keep your Fieldy close to this Mac. This can take a moment.")
                    .font(Typography.lead).foregroundStyle(Palette.label2)
                    .multilineTextAlignment(.center)
            }

            if showTips {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Still looking. Try these while EarBud keeps searching:")
                        .font(Typography.footnote).foregroundStyle(Palette.label2)
                        .padding(.bottom, 8)
                    FormGroup {
                        tipRow(systemName: "hand.point.up.left", "Press the button on your Fieldy once to wake it.")
                        FormDivider()
                        tipRow(systemName: "bolt", "Charge it for a few minutes if the light doesn't come on.")
                        FormDivider()
                        tipRow(systemName: "antenna.radiowaves.left.and.right.slash", "Turn off Bluetooth on your phone for now.")
                        FormDivider()
                        tipRow(systemName: "laptopcomputer", "Bring your Fieldy right next to this Mac.")
                    }
                }
                .frame(maxWidth: 440)
            }
            Spacer(minLength: 4)
        }
        .task { try? await Task.sleep(for: .seconds(30)); showTips = true }
        .onChange(of: model.foundFieldy) { _, found in
            if found != nil { model.handleFoundFieldy() }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Spinner(size: 14)
                Text("Searching").font(Typography.footnote).foregroundStyle(Palette.label2)
                Spacer()
                Button("Retry") { model.retryScan() }
                    .buttonStyle(EarBudButtonStyle())
            }
        }
    }

    private func tipRow(systemName: String, _ text: String) -> some View {
        FormRow(
            title: text,
            leading: { Image(systemName: systemName).font(.system(size: 13)).foregroundStyle(Palette.accent).frame(width: 20) },
            trailing: { EmptyView() })
    }
}
