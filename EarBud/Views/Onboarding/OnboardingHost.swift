import AppKit
import SwiftUI

/// Builds the onboarding provider and model, and closes the onboarding window when it finishes.
struct OnboardingHost: View {
    let appModel: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model: OnboardingModel

    init(appModel: AppModel) {
        self.appModel = appModel
        // Any display with a notch, not just the main one: the laptop may be next to a monitor.
        let hasNotch = NSScreen.screens.contains { $0.notchRect != nil }
        let provider: any OnboardingProviding
        if let realDevice = appModel.device as? RealDeviceProvider, let realLibrary = appModel.library as? RealLibraryProvider {
            provider = RealOnboarding(device: realDevice.device, store: realLibrary.store, library: realLibrary, hasNotch: hasNotch)
        } else {
            provider = FixtureOnboarding(hasNotch: hasNotch, library: appModel.library as? FixtureLibrary)
        }
        _model = State(initialValue: OnboardingModel(provider: provider, speech: appModel.speech))
    }

    var body: some View {
        OnboardingWindow(model: model)
            .onAppear {
                model.onFinished = {
                    Task { await appModel.start() }
                    dismissWindow(id: EarBudApp.onboardingWindowID)
                }
            }
    }
}
