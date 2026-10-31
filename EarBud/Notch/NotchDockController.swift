import AppKit
import Observation
import os
import SwiftUI

private let log = Logger(subsystem: "dev.heybeaux.earbud", category: "notch")

/// Shows EarBud around the camera notch (mockup 19). Turned on and off by "Show EarBud in the
/// notch" in Settings and the onboarding step; the menu-bar icon is unaffected either way.
@MainActor
final class NotchDockController {
    static let shared = NotchDockController()

    private(set) var isEnabled = false
    private(set) var displayName: String?

    let dock = NotchDockState()
    private var model: AppModel?
    private var openMainWindow: (() -> Void)?
    private var panel: NotchPanelWindow?
    private var screen: NSScreen?
    private var notch: CGRect?
    private var hover = NotchHoverTracker()
    private var isPointerInside = false
    private var isHiddenForFullScreen = false
    private var observers: [NSObjectProtocol] = []
    private var pointerMonitor: Any?
    private var hoverTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var isObserving = false

    /// Gives the dock the app state and a way to bring up the main window. Called once the main
    /// window's scene exists.
    func attach(model: AppModel, openMainWindow: @escaping () -> Void) {
        self.openMainWindow = openMainWindow
        guard self.model !== model else { return }
        self.model = model
        if isEnabled { show() }
    }

    /// Called when "Show EarBud in the notch" or "Show it on" changes.
    func update(enabled: Bool, displayName: String?) {
        let displayChanged = displayName != self.displayName
        isEnabled = enabled
        self.displayName = displayName
        if enabled {
            if panel == nil || displayChanged { show() }
        } else {
            hide()
        }
    }

    // MARK: Showing

    private func show() {
        guard isEnabled, let model else { return }
        if panel == nil {
            let panel = NotchPanelWindow()
            let actions = NotchDockActions(
                sync: { [weak model] in _ = model?.syncNow() },
                record: { [weak model] in Task { await model?.toggleRecording() } },
                open: { [weak self] id in self?.open(id) },
                expand: { [weak self] in self?.click() })
            let host = NotchHostingView(rootView: NotchDockView(model: model, dock: dock, actions: actions))
            host.appearance = NSAppearance(named: .darkAqua)
            host.onHoverChange = { [weak self] inside in self?.pointerMoved(inside: inside) }
            panel.contentView = host
            self.panel = panel
            startObservingSystem()
        }
        if !isObserving {
            isObserving = true
            observeModel()
        }
        placeOnScreen()
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
        stopObservingSystem()
        hoverTask?.cancel()
        hover.collapse()
        isPointerInside = false
        dock.layout = .resting
    }

    /// Picks the display, finds its notch, and puts the panel there. Without a notched display
    /// the dock stays hidden; the menu bar keeps working.
    private func placeOnScreen() {
        guard let panel else { return }
        let screens = NSScreen.screens
        let candidates = screens.map { NotchScreenPicker.Candidate(name: $0.localizedName, isBuiltIn: $0.isBuiltIn, hasNotch: $0.notchRect != nil) }
        guard let index = NotchScreenPicker.pick(candidates, preferred: displayName), let notch = screens[index].notchRect else {
            log.info("No display with a notch; the notch dock stays hidden")
            screen = nil
            self.notch = nil
            panel.orderOut(nil)
            return
        }
        screen = screens[index]
        self.notch = notch
        dock.notchSize = notch.size
        isHiddenForFullScreen = screens[index].hasFullScreenApp
        refresh(animated: false)
    }

    // MARK: State

    /// Re-reads the parts of the model that change the dock's shape whenever any of them change.
    private func observeModel() {
        guard panel != nil, let model else {
            isObserving = false
            return
        }
        withObservationTracking {
            _ = model.sync
            _ = model.deviceState
            _ = model.recordings.first?.id
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh(animated: true)
                self?.observeModel()
            }
        }
    }

    private func refresh(animated: Bool) {
        guard let model, let panel else { return }
        let now = model.now()
        if case .finished(let outcome, let at) = model.sync, dock.lastResult?.at != at {
            dock.lastResult = (outcome, at)
            resultTask?.cancel()
            resultTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(NotchPresenter.resultDuration))
                guard !Task.isCancelled else { return }
                self?.refresh(animated: true)
            }
        }
        let layout: NotchGeometry.Layout = hover.isExpanded
            ? .expanded(hasTranscript: model.recordings.first != nil)
            : NotchPresenter.activity(device: model.deviceState, sync: model.sync, lastResult: dock.lastResult,
                                      now: now, formatting: model.formatting).layout
        dock.layout = layout
        guard let screen, let notch, !isHiddenForFullScreen else {
            panel.orderOut(nil)
            return
        }
        let frame = NotchGeometry.frame(for: layout, notch: notch, screenFrame: screen.frame)
        if animated, panel.isVisible, panel.frame != frame {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    // MARK: Hover and click

    private func pointerMoved(inside: Bool) {
        isPointerInside = inside
        let wasExpanded = hover.isExpanded
        hover.pointer(inside: inside, at: Date())
        hoverTask?.cancel()
        if inside {
            startPointerMonitor()
            if let deadline = hover.expandDeadline {
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                    guard !Task.isCancelled, let self else { return }
                    self.pointerMoved(inside: self.pointerIsOverPanel)
                }
            }
        } else {
            stopPointerMonitor()
        }
        if hover.isExpanded != wasExpanded { refresh(animated: true) }
    }

    private func click() {
        guard !hover.isExpanded else { return }
        hoverTask?.cancel()
        hover.click()
        startPointerMonitor()
        refresh(animated: true)
    }

    private var pointerIsOverPanel: Bool {
        panel.map { $0.frame.contains(NSEvent.mouseLocation) } ?? false
    }

    /// Catches the pointer leaving over another app's window in case the exit event is missed.
    /// Watching pointer movement doesn't need Accessibility permission.
    private func startPointerMonitor() {
        guard pointerMonitor == nil else { return }
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.pointerIsOverPanel, self.isPointerInside || self.hover.isExpanded else { return }
                self.pointerMoved(inside: false)
            }
        }
    }

    private func stopPointerMonitor() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
    }

    // MARK: Actions

    private func open(_ id: String) {
        guard let model else { return }
        hover.collapse()
        isPointerInside = false
        stopPointerMonitor()
        refresh(animated: true)
        model.searchText = ""
        model.sidebar = .recordings
        model.choose(id)
        openMainWindow?()
    }

    // MARK: Screens, spaces and full screen

    private func startObservingSystem() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeOnScreen() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkFullScreenSoon() }
            })
        }
    }

    private func stopObservingSystem() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
        stopPointerMonitor()
    }

    /// Space switches animate, so look again once the new space has settled.
    private func checkFullScreenSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, let screen = self.screen else { return }
            let hidden = screen.hasFullScreenApp
            guard hidden != self.isHiddenForFullScreen else { return }
            self.isHiddenForFullScreen = hidden
            self.refresh(animated: false)
        }
    }
}
