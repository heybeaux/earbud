import SwiftUI

/// Mockup 03, pane 1: explain Bluetooth before macOS asks.
struct BluetoothPermissionStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            ZStack {
                Circle().fill(Palette.accentTint).frame(width: 140, height: 140)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.accentHi, Palette.accent], startPoint: .top, endPoint: .bottom))
                    .frame(width: 84, height: 84)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("EarBud needs Bluetooth").font(Typography.largeTitle).foregroundStyle(Palette.label)
                Text("Your Fieldy sends its recordings to this Mac over Bluetooth. When you click Allow Bluetooth, macOS will ask you to confirm.")
                    .font(Typography.lead)
                    .foregroundStyle(Palette.label2)
                    .multilineTextAlignment(.center)
                    .cssLineHeight(1.4, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }

            OnboardingCallout(systemName: "checkmark.shield") {
                Text("EarBud only connects to your Fieldy. It doesn't use Bluetooth for anything else.")
                    .font(Typography.footnote).foregroundStyle(Palette.label2)
                    .cssLineHeight(1.4, size: 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 8)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                if model.isWorking {
                    Spinner()
                } else {
                    Button("Allow Bluetooth") { Task { await model.allowBluetooth() } }
                        .buttonStyle(EarBudButtonStyle(kind: .primary))
                }
            }
        }
    }
}

/// Mockup 03, pane 2: the denied path, with step-by-step instructions to Open System Settings.
struct BluetoothDeniedStep: View {
    @Bindable var model: OnboardingModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(Palette.fill2).frame(width: 140, height: 140)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Palette.label3)
                        .frame(width: 84, height: 84)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white)
                }
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.orange)
                    .padding(6)
                    .background(Circle().fill(Palette.content))
            }

            Text("EarBud can't reach your Fieldy without Bluetooth")
                .font(Typography.largeTitle).foregroundStyle(Palette.label)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            VStack(alignment: .leading, spacing: 10) {
                numberedRow(1) { Text("Click **Open System Settings** below.") }
                numberedRow(2) { Text("In **Privacy & Security**, click **Bluetooth**.") }
                numberedRow(3) { Text("Turn on the switch next to **EarBud**.") }
                numberedRow(4) { Text("Come back here. EarBud carries on by itself.") }
            }
            .frame(maxWidth: 420, alignment: .leading)

            Spacer(minLength: 8)
        }
        .task { await model.recheckBluetoothAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.recheckBluetoothAuthorization() } }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Spinner(size: 14)
                Text("Waiting for Bluetooth access…").font(Typography.footnote).foregroundStyle(Palette.label2)
                Spacer()
                Button("Open System Settings") { Task { await model.openBluetoothSettings() } }
                    .buttonStyle(EarBudButtonStyle(kind: .primary))
            }
        }
    }

    private func numberedRow(_ n: Int, @ViewBuilder text: () -> Text) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(Typography.smallMedium)
                .foregroundStyle(Palette.accent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Palette.accentTint))
            text().font(Typography.body).foregroundStyle(Palette.label)
        }
    }
}
