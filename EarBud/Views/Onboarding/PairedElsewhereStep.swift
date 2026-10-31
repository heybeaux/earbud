import SwiftUI

/// Mockup 05: warns that resetting erases on-device recordings and disconnects the phone app.
struct PairedElsewhereStep: View {
    @Bindable var model: OnboardingModel
    @State private var confirmed = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            HStack(spacing: 16) {
                FieldyArtwork(width: 110, led: nil)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14)).foregroundStyle(Palette.orange)
                            .padding(5).background(Circle().fill(Palette.content))
                            .offset(x: 6, y: -6)
                    }
                Image(systemName: "ellipsis").foregroundStyle(Palette.label3)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Palette.label, lineWidth: 2)
                    .frame(width: 54, height: 92)
            }

            VStack(spacing: 8) {
                Text("This Fieldy is paired with another device").font(Typography.largeTitle).foregroundStyle(Palette.label)
                    .multilineTextAlignment(.center)
                Text("A Fieldy can only pair with one device at a time. Yours is probably still paired with your phone. To use it with this Mac, you'll need to reset it.")
                    .font(Typography.lead).foregroundStyle(Palette.label2)
                    .multilineTextAlignment(.center)
                    .cssLineHeight(1.4, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }

            OnboardingCallout(tone: .warning, systemName: "exclamationmark.triangle.fill") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Before you reset").font(Typography.stepTitle).foregroundStyle(Palette.label)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("•  Any recordings still on your Fieldy will be **erased**.")
                        Text("•  Your Fieldy will **disconnect from the Fieldy phone app**.")
                    }
                    .font(Typography.footnote).foregroundStyle(Palette.label)
                    Text("If you want to keep those recordings, sync them in the phone app first, then come back.")
                        .font(Typography.caption).foregroundStyle(Palette.label2)
                        .cssLineHeight(1.4, size: 11.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 440)

            Toggle(isOn: $confirmed) {
                Text("I understand. Erase and reset my Fieldy.").font(Typography.body).foregroundStyle(Palette.label)
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 4)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Not now") { model.goBack() }
                    .buttonStyle(EarBudButtonStyle())
                Button("Show reset steps") { model.confirmReset() }
                    .buttonStyle(EarBudButtonStyle(kind: .primary))
                    .disabled(!confirmed)
            }
        }
    }
}
