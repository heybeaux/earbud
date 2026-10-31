import XCTest
@testable import EarBud

final class NotchGeometryTests: XCTestCase {
    /// A 14-inch MacBook Pro at its default scale: 1512 × 982 pt, 32 pt notch, 185 pt wide.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let left = CGRect(x: 0, y: 950, width: 663.5, height: 32)
    let right = CGRect(x: 848.5, y: 950, width: 663.5, height: 32)

    var notch: CGRect {
        NotchGeometry.notchRect(screenFrame: screen, safeAreaTop: 32, leftArea: left, rightArea: right)!
    }

    func testNotchSitsBetweenTheAuxiliaryAreasAtTheTop() {
        XCTAssertEqual(notch, CGRect(x: 663.5, y: 950, width: 185, height: 32))
    }

    func testNoNotchWithoutSafeAreaOrAuxiliaryAreas() {
        XCTAssertNil(NotchGeometry.notchRect(screenFrame: screen, safeAreaTop: 0, leftArea: left, rightArea: right))
        XCTAssertNil(NotchGeometry.notchRect(screenFrame: screen, safeAreaTop: 32, leftArea: nil, rightArea: right))
        XCTAssertNil(NotchGeometry.notchRect(screenFrame: screen, safeAreaTop: 32, leftArea: left, rightArea: nil))
        let overlapping = CGRect(x: 600, y: 950, width: 900, height: 32)
        XCTAssertNil(NotchGeometry.notchRect(screenFrame: screen, safeAreaTop: 32, leftArea: overlapping, rightArea: right))
    }

    func testNotchOnASecondaryScreenUsesThatScreensCoordinates() {
        let external = CGRect(x: 1512, y: -200, width: 1512, height: 982)
        let l = CGRect(x: 1512, y: 750, width: 663.5, height: 32)
        let r = CGRect(x: 2360.5, y: 750, width: 663.5, height: 32)
        let rect = NotchGeometry.notchRect(screenFrame: external, safeAreaTop: 32, leftArea: l, rightArea: r)
        XCTAssertEqual(rect, CGRect(x: 2175.5, y: 750, width: 185, height: 32))
    }

    func testRestingIsTheNotchPlusASmallIndicatorEachSide() {
        let frame = NotchGeometry.frame(for: .resting, notch: notch, screenFrame: screen)
        XCTAssertEqual(frame.height, 32)
        XCTAssertEqual(frame.width, 185 + 2 * NotchGeometry.restingWing, accuracy: 1)
        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.midX, notch.midX, accuracy: 1)
        XCTAssertLessThan(frame.minX, notch.minX)
        XCTAssertGreaterThan(frame.maxX, notch.maxX)
    }

    func testLiveStatesGrowDownwardAndExpandedIsLargest() {
        let resting = NotchGeometry.size(for: .resting, notch: notch.size)
        let recording = NotchGeometry.size(for: .recording, notch: notch.size)
        let syncing = NotchGeometry.size(for: .syncing, notch: notch.size)
        let message = NotchGeometry.size(for: .message, notch: notch.size)
        let expanded = NotchGeometry.size(for: .expanded(hasTranscript: true), notch: notch.size)
        let expandedShort = NotchGeometry.size(for: .expanded(hasTranscript: false), notch: notch.size)

        XCTAssertEqual(recording.height, resting.height)
        XCTAssertGreaterThan(recording.width, resting.width)
        XCTAssertGreaterThan(syncing.height, resting.height)
        XCTAssertGreaterThan(message.height, syncing.height)
        XCTAssertGreaterThan(expanded.height, expandedShort.height)
        XCTAssertGreaterThanOrEqual(expanded.width, NotchGeometry.expandedMinWidth)
        XCTAssertGreaterThan(expandedShort.height, message.height)
    }

    func testEveryFrameHangsFromTheTopOfTheScreen() {
        let layouts: [NotchGeometry.Layout] = [.resting, .recording, .syncing, .message, .expanded(hasTranscript: true)]
        for layout in layouts {
            let frame = NotchGeometry.frame(for: layout, notch: notch, screenFrame: screen)
            XCTAssertEqual(frame.maxY, screen.maxY, "\(layout)")
            XCTAssertTrue(screen.contains(frame), "\(layout)")
            XCTAssertTrue(frame.contains(notch), "\(layout)")
        }
    }

    func testFrameStaysOnScreenWhenTheNotchIsNearAnEdge() {
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 600)
        let edgeNotch = CGRect(x: 10, y: 568, width: 100, height: 32)
        let frame = NotchGeometry.frame(for: .expanded(hasTranscript: true), notch: edgeNotch, screenFrame: narrow)
        XCTAssertEqual(frame.minX, 0)
        XCTAssertEqual(frame.width, 300)
    }

    func testExpandedPanelHasRounderCorners() {
        XCTAssertGreaterThan(NotchGeometry.bottomRadius(for: .expanded(hasTranscript: false)), NotchGeometry.bottomRadius(for: .resting))
    }

    // MARK: Screen choice

    func testPrefersTheChosenDisplayWhenItHasANotch() {
        let screens = [
            NotchScreenPicker.Candidate(name: "Studio Display", isBuiltIn: false, hasNotch: false),
            NotchScreenPicker.Candidate(name: "Built-in Retina Display", isBuiltIn: true, hasNotch: true),
            NotchScreenPicker.Candidate(name: "Sidecar", isBuiltIn: false, hasNotch: true),
        ]
        XCTAssertEqual(NotchScreenPicker.pick(screens, preferred: "Sidecar"), 2)
        XCTAssertEqual(NotchScreenPicker.pick(screens, preferred: nil), 1)
        // A display without a notch falls back to the built-in one until the capsule exists.
        XCTAssertEqual(NotchScreenPicker.pick(screens, preferred: "Studio Display"), 1)
        XCTAssertEqual(NotchScreenPicker.pick(screens, preferred: "Unplugged"), 1)
    }

    func testNoDisplayWithANotch() {
        let screens = [NotchScreenPicker.Candidate(name: "Studio Display", isBuiltIn: false, hasNotch: false)]
        XCTAssertNil(NotchScreenPicker.pick(screens, preferred: nil))
        XCTAssertNil(NotchScreenPicker.pick([], preferred: nil))
    }

    func testAnyNotchedDisplayWhenNoneIsBuiltIn() {
        let screens = [
            NotchScreenPicker.Candidate(name: "A", isBuiltIn: false, hasNotch: false),
            NotchScreenPicker.Candidate(name: "B", isBuiltIn: false, hasNotch: true),
        ]
        XCTAssertEqual(NotchScreenPicker.pick(screens, preferred: nil), 1)
    }

    // MARK: Full screen

    func testFullScreenWhenAnotherAppCoversTheWholeDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let video = FullScreenDetector.Window(bounds: display, layer: 0, ownerPID: 42)
        XCTAssertTrue(FullScreenDetector.isFullScreen([video], displayBounds: display, ownPID: 7))
    }

    func testNotFullScreenForZoomedWindowsOwnWindowsOrOverlays() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let zoomed = FullScreenDetector.Window(bounds: CGRect(x: 0, y: 32, width: 1512, height: 950), layer: 0, ownerPID: 42)
        let mine = FullScreenDetector.Window(bounds: display, layer: 0, ownerPID: 7)
        let menuBar = FullScreenDetector.Window(bounds: display, layer: 25, ownerPID: 42)
        XCTAssertFalse(FullScreenDetector.isFullScreen([zoomed, mine, menuBar], displayBounds: display, ownPID: 7))
    }

    func testFullScreenOnAnotherDisplayDoesNotCount() {
        let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = FullScreenDetector.Window(bounds: CGRect(x: 1512, y: 0, width: 2560, height: 1440), layer: 0, ownerPID: 42)
        XCTAssertFalse(FullScreenDetector.isFullScreen([external], displayBounds: builtIn, ownPID: 7))
    }
}
