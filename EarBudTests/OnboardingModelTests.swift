import XCTest
@testable import EarBud

@MainActor
final class OnboardingModelTests: XCTestCase {
    private func makeModel(denyBluetooth: Bool = false, hasNotch: Bool = true) -> (OnboardingModel, FixtureOnboarding) {
        let provider = FixtureOnboarding(pace: .zero, now: { TestClock.reference }, denyBluetooth: denyBluetooth, hasNotch: hasNotch)
        let speech = FixtureSpeechModels(pace: .zero)
        let model = OnboardingModel(provider: provider, speech: speech)
        return (model, provider)
    }

    // MARK: Step order

    func testHappyPathStepOrder() async {
        let (model, _) = makeModel()
        XCTAssertEqual(model.step, .welcome)

        model.getStarted()
        XCTAssertEqual(model.step, .bluetoothPermission)

        await model.allowBluetooth()
        XCTAssertEqual(model.step, .findFieldy)

        // The fixture's Fieldy starts out paired with a phone, so the happy path goes through reset first.
        await waitForFoundFieldy(model)
        model.handleFoundFieldy()
        XCTAssertEqual(model.step, .pairedElsewhere)
        model.confirmReset()
        XCTAssertEqual(model.step, .resetSteps)
        await waitUntil { model.step == .connected }
        XCTAssertEqual(model.step, .connected)

        await model.continueFromConnected()
        XCTAssertEqual(model.step, .speechModel)

        model.deferSpeechModel()
        XCTAssertEqual(model.step, .testRecording)

        await model.makeTestRecording()
        XCTAssertEqual(model.testRecordingPhase, .done)
        XCTAssertNotNil(model.testRecording)

        model.finishTestRecording()
        XCTAssertEqual(model.step, .notchDock)

        model.chooseNotchDock(false)
        XCTAssertEqual(model.step, .finished)
    }

    // MARK: Denied Bluetooth path

    func testDeniedBluetoothStaysOnDeniedStep() async {
        let (model, _) = makeModel(denyBluetooth: true)
        model.getStarted()
        await model.allowBluetooth()
        XCTAssertEqual(model.step, .bluetoothDenied)
        XCTAssertEqual(model.bluetoothAuthorization, .denied)
    }

    func testRecheckAfterSettingsAdvancesOnceAuthorized() async {
        // Simulate: denied once, then the user grants it in System Settings and the app refocuses.
        let provider = FixtureOnboarding(pace: .zero, now: { TestClock.reference }, denyBluetooth: true, hasNotch: true)
        let model = OnboardingModel(provider: provider, speech: FixtureSpeechModels(pace: .zero))
        model.getStarted()
        await model.allowBluetooth()
        XCTAssertEqual(model.step, .bluetoothDenied)

        // The fixture always denies; recheck without state change keeps the user on the denied step.
        await model.recheckBluetoothAuthorization()
        XCTAssertEqual(model.step, .bluetoothDenied)
    }

    // MARK: Paired-elsewhere / reset path

    func testPairedElsewhereRoutesThroughResetBeforeConnecting() async {
        let (model, _) = makeModel()
        model.getStarted()
        await model.allowBluetooth()
        await waitForFoundFieldy(model)
        XCTAssertEqual(model.foundFieldy?.isPairedElsewhere, true)

        model.handleFoundFieldy()
        XCTAssertEqual(model.step, .pairedElsewhere)

        model.confirmReset()
        XCTAssertEqual(model.step, .resetSteps)

        await waitUntil { model.step == .connected }
        XCTAssertEqual(model.step, .connected)
        XCTAssertNotNil(model.connectedDevice)
    }

    func testItDidntWorkShowsHelpAndTryAgainResetsOutcome() async {
        let (model, _) = makeModel()
        model.getStarted()
        await model.allowBluetooth()
        await waitForFoundFieldy(model)
        model.handleFoundFieldy()
        model.confirmReset()

        model.itDidntWork()
        XCTAssertTrue(model.showResetHelp)

        model.tryResetAgain()
        XCTAssertFalse(model.showResetHelp)
        await waitUntil { model.step == .connected }
    }

    // MARK: Notch step

    func testNotchStepSkippedOnNonNotchMac() async {
        let (model, _) = makeModel(hasNotch: false)
        model.getStarted()
        await model.allowBluetooth()
        await connectToFieldy(model)
        await model.continueFromConnected()
        model.deferSpeechModel()
        await model.makeTestRecording()
        model.finishTestRecording()
        XCTAssertEqual(model.step, .finished, "non-notch Macs should skip straight to Finished")
    }

    func testNotchStepShownOnNotchedMac() async {
        let (model, _) = makeModel(hasNotch: true)
        model.getStarted()
        await model.allowBluetooth()
        await connectToFieldy(model)
        await model.continueFromConnected()
        model.deferSpeechModel()
        await model.makeTestRecording()
        model.finishTestRecording()
        XCTAssertEqual(model.step, .notchDock)
    }

    // MARK: Completion flag

    func testFinishMarksOnboardingCompleted() async {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: OnboardingState.completedKey)
        defer { defaults.removeObject(forKey: OnboardingState.completedKey) }
        XCTAssertTrue(OnboardingState.isNeeded)

        let (model, _) = makeModel(hasNotch: false)
        model.finish()
        XCTAssertFalse(OnboardingState.isNeeded)
    }

    func testGoBackReturnsToPreviousVisitedStep() async {
        let (model, _) = makeModel()
        model.getStarted()
        await model.allowBluetooth()
        XCTAssertEqual(model.step, .findFieldy)
        model.goBack()
        XCTAssertEqual(model.step, .bluetoothPermission)
    }

    // MARK: Helpers

    private func waitForFoundFieldy(_ model: OnboardingModel, timeout: TimeInterval = 2) async {
        await waitUntil(timeout: timeout) { model.foundFieldy != nil }
    }

    /// Runs the full discover -> paired-elsewhere -> reset -> connected sequence, since the fixture's
    /// Fieldy always starts out paired with a phone.
    private func connectToFieldy(_ model: OnboardingModel) async {
        await waitForFoundFieldy(model)
        model.handleFoundFieldy()
        if model.step == .pairedElsewhere { model.confirmReset() }
        await waitUntil { model.step == .connected }
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
