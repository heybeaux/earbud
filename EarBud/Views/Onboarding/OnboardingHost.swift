import AppKit
import SwiftUI

/// Builds the onboarding provider and model, and closes the onboarding window when it finishes.
struct OnboardingHost: View {
    let appModel: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model: OnboardingModel

    init(appModel: AppModel) {
        self.appModel = appModel
        let library = appModel.library as? FixtureLibrary
        let hasNotch = NSScreen.main?.safeAreaInsets.top ?? 0 > 0
        let provider = FixtureOnboarding(hasNotch: hasNotch, library: library)
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
