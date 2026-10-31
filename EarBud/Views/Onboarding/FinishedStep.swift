import ServiceManagement
import SwiftUI

/// Mockup 11: finished. Explains where EarBud lives and offers launch at login.
struct FinishedStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.accentHi, Palette.accent], startPoint: .top, endPoint: .bottom))
                    .frame(width: 96, height: 96)
                    .overlay {
                        Image(systemName: "waveform.and.person.filled")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white)
                    }
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, Palette.green)
                    .background(Circle().fill(Palette.content))
                    .offset(x: 4, y: 4)
            }

            VStack(spacing: 8) {
                Text("You're all set").font(Typography.largeTitle).foregroundStyle(Palette.label)
                Text("Record on your Fieldy whenever you like. When you're back at your Mac, click Sync and your recordings appear as text.")
                    .font(Typography.lead).foregroundStyle(Palette.label2)
                    .multilineTextAlignment(.center)
                    .cssLineHeight(1.4, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }

            FormGroup {
                FormRow(title: "EarBud lives in the menu bar", detail: "Look for the EarBud icon at the top of your screen to sync or check your Fieldy.",
                        leading: { OnboardingIconTile(systemName: "menubar.rectangle") }, trailing: { EmptyView() })
                FormDivider()
                FormRow(title: "A gentle daily reminder", detail: "If you haven't synced for a day, EarBud reminds you at 6:00 PM. Change it in Settings.",
                        leading: { OnboardingIconTile(systemName: "bell") }, trailing: { EmptyView() })
                FormDivider()
                FormRow(title: "Open EarBud when you log in", detail: "So reminders still arrive if you forget to open EarBud.",
                        leading: { OnboardingIconTile(systemName: "power") }, trailing: {
                    AccentSwitch(isOn: $model.openAtLogin, label: "Open EarBud when you log in")
                })
            }
            .frame(maxWidth: 440)
            Spacer(minLength: 4)
        }
        .onChange(of: model.openAtLogin) { _, newValue in
            try? (newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister())
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Open EarBud") { model.finish() }
                    .buttonStyle(EarBudButtonStyle(kind: .primary))
            }
        }
    }
}
