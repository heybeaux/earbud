import SwiftUI

/// Mockup 07: paired, clock set, battery shown.
struct ConnectedStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            ZStack(alignment: .topTrailing) {
                FieldyArtwork(width: 150, led: .green)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, Palette.green)
                    .offset(x: 4, y: -4)
            }

            VStack(spacing: 8) {
                Text("Connected").font(Typography.largeTitle).foregroundStyle(Palette.label)
                Text("Your Fieldy is paired with this Mac. No code needed.")
                    .font(Typography.lead).foregroundStyle(Palette.label2)
            }

            if let device = model.connectedDevice {
                FormGroup {
                    FormRow(title: "Paired with this Mac", leading: { checkDot }, trailing: {
                        Text(device.name).font(Typography.body).foregroundStyle(Palette.label2)
                    })
                    FormDivider()
                    FormRow(title: "Clock set", leading: { checkDot }, trailing: {
                        Text(device.pairedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
                            .font(Typography.body).foregroundStyle(Palette.label2)
                    })
                    FormDivider()
                    FormRow(title: "Battery", leading: { checkDot }, trailing: {
                        Text("\(device.batteryPercent ?? 0)%").font(Typography.bodyMedium).foregroundStyle(Palette.label)
                    })
                }
                .frame(maxWidth: 440)
            }
            Spacer(minLength: 4)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Continue") { Task { await model.continueFromConnected() } }
                    .buttonStyle(EarBudButtonStyle(kind: .primary))
            }
        }
    }

    private var checkDot: some View {
        Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white, Palette.green)
    }
}
