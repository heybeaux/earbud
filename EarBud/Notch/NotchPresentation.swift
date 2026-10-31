import Foundation

/// What the notch dock shows without being expanded (mockup 19, states 1, 3 and 4).
enum NotchActivity: Equatable {
    /// Status dot on the left, time since the last sync on the right.
    case resting(dot: NotchDot, sinceSync: String)
    /// Sync icon, "2 of 3", and a progress bar below the notch.
    case syncing(label: String, fraction: Double)
    /// "3 new recordings" for a few seconds after a sync.
    case syncResult(NotchSyncResult, dot: NotchDot, sinceSync: String)
    /// Red dot and running timer.
    case recording(elapsed: String)

    var layout: NotchGeometry.Layout {
        switch self {
        case .resting: .resting
        case .syncing: .syncing
        case .syncResult: .message
        case .recording: .recording
        }
    }
}

enum NotchDot: Equatable {
    case connected, recording, away
}

struct NotchSyncResult: Equatable {
    enum Tone: Equatable { case success, neutral, warning, failure }
    var message: String
    var tone: Tone
}

/// The expanded quick panel (mockup 19, state 2).
struct NotchPanel: Equatable {
    struct Newest: Equatable {
        var id: String
        /// "Newest · Run club planning · 1:12 PM".
        var heading: String
        var text: String
    }

    var deviceName: String
    var dot: NotchDot
    /// "Connected · battery 82%", "Recording · 03:42", "Not nearby".
    var status: String
    /// "Today, 1:40 PM" or "Not yet".
    var lastSynced: String
    var syncTitle: String
    var canSync: Bool
    var recordTitle: String
    var isRecording: Bool
    var canRecord: Bool
    var newest: Newest?
}

/// Maps app state to what the dock shows. Pure, so it's covered by unit tests.
enum NotchPresenter {
    /// How long "3 new recordings" stays after a sync.
    static let resultDuration: TimeInterval = 5

    static func activity(device: DeviceSnapshot?, sync: SyncActivity, lastResult: (outcome: SyncOutcome, at: Date)?,
                         now: Date, formatting: Formatting) -> NotchActivity {
        if let started = device?.recordingStartedAt {
            return .recording(elapsed: formatting.timestamp(now.timeIntervalSince(started)))
        }
        if case .running(let progress) = sync {
            return .syncing(label: syncLabel(progress), fraction: progress.fraction)
        }
        let dot = dot(for: device)
        let since = sinceSync(device?.lastSynced, now: now)
        if let lastResult, now.timeIntervalSince(lastResult.at) < resultDuration, now >= lastResult.at {
            return .syncResult(result(lastResult.outcome, formatting: formatting), dot: dot, sinceSync: since)
        }
        return .resting(dot: dot, sinceSync: since)
    }

    static func dot(for device: DeviceSnapshot?) -> NotchDot {
        guard let device else { return .away }
        if device.isRecording { return .recording }
        return device.connection == .connected ? .connected : .away
    }

    /// "now", "23m", "5h", "3d"; "–" before the first sync.
    static func sinceSync(_ date: Date?, now: Date) -> String {
        guard let date else { return "–" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    /// The capsule's longer form of `sinceSync`: "Synced 23m ago", "Synced just now", "Not synced yet".
    static func capsuleSince(_ since: String) -> String {
        switch since {
        case "–": "Not synced yet"
        case "now": "Synced just now"
        default: "Synced \(since) ago"
        }
    }

    /// "2 of 3" while copying; empty while connecting or checking.
    static func syncLabel(_ progress: SyncProgressSnapshot) -> String {
        guard progress.fileCount > 0, progress.fileIndex > 0 else { return "" }
        return "\(min(progress.fileIndex, progress.fileCount)) of \(progress.fileCount)"
    }

    static func result(_ outcome: SyncOutcome, formatting: Formatting) -> NotchSyncResult {
        switch outcome {
        case .copied(let count):
            return NotchSyncResult(message: count == 1 ? "1 new recording" : "\(count) new recordings", tone: .success)
        case .nothingNew:
            return NotchSyncResult(message: "Nothing new", tone: .neutral)
        case .interrupted(let saved):
            return NotchSyncResult(message: "Interrupted · \(formatting.recordings(saved)) saved", tone: .warning)
        case .failed:
            return NotchSyncResult(message: "Sync didn't finish", tone: .failure)
        }
    }

    static func panel(device: DeviceSnapshot?, sync: SyncActivity, newest: RecordingItem?, isChangingRecording: Bool,
                      now: Date, formatting: Formatting) -> NotchPanel {
        let connected = device?.connection == .connected
        let recording = device?.isRecording ?? false
        return NotchPanel(
            deviceName: device?.name ?? "Fieldy",
            dot: dot(for: device),
            status: status(device, now: now, formatting: formatting),
            lastSynced: device?.lastSynced.map { formatting.statDate($0, now: now) } ?? "Not yet",
            syncTitle: syncTitle(sync),
            canSync: !sync.isRunning,
            recordTitle: recording ? "Stop recording" : "Record from Mac",
            isRecording: recording,
            canRecord: connected && !isChangingRecording,
            newest: newest.map { newestCard($0, now: now, formatting: formatting) })
    }

    static func syncTitle(_ sync: SyncActivity) -> String {
        guard case .running(let progress) = sync else { return "Sync now" }
        return progress.phase == .copying ? "Syncing… \(Int((progress.fraction * 100).rounded()))%" : "Syncing…"
    }

    static func status(_ device: DeviceSnapshot?, now: Date, formatting: Formatting) -> String {
        guard let device else { return "Looking for your Fieldy…" }
        if let started = device.recordingStartedAt {
            return "Recording · \(formatting.timestamp(now.timeIntervalSince(started)))"
        }
        switch device.connection {
        case .connected: return device.batteryPercent.map { "Connected · battery \($0)%" } ?? "Connected"
        case .notNearby: return "Not nearby"
        case .bluetoothOff: return "Bluetooth is off"
        default: return "Looking for your Fieldy…"
        }
    }

    static func newestCard(_ item: RecordingItem, now: Date, formatting: Formatting) -> NotchPanel.Newest {
        var parts = ["Newest"]
        if let title = item.title, !title.isEmpty { parts.append(title) }
        let day = formatting.dayHeading(item.recordedAt, now: now)
        parts.append(day == "Today" ? formatting.time(item.recordedAt) : formatting.statDate(item.recordedAt, now: now))
        return NotchPanel.Newest(id: item.id, heading: parts.joined(separator: " · "), text: newestText(item))
    }

    static func newestText(_ item: RecordingItem) -> String {
        if let preview = item.preview, !preview.isEmpty { return preview }
        switch item.transcript {
        case .waiting, .none: return "Waiting to be transcribed."
        case .transcribing: return "Transcribing…"
        case .noSpeech: return "Nothing was said."
        case .failed: return "Couldn't transcribe this recording."
        case .done: return "No transcript."
        }
    }
}

/// Hover-to-expand: half a second inside expands it, a click expands it at once, and leaving
/// collapses it.
struct NotchHoverTracker: Equatable {
    static let hoverDelay: TimeInterval = 0.5

    private(set) var isExpanded = false
    /// When the pointer entered the dock, while waiting to expand.
    private(set) var enteredAt: Date?

    /// Feed the pointer position; returns whether the dock should be expanded now.
    @discardableResult
    mutating func pointer(inside: Bool, at now: Date) -> Bool {
        guard inside else {
            isExpanded = false
            enteredAt = nil
            return false
        }
        if isExpanded { return true }
        let entered = enteredAt ?? now
        enteredAt = entered
        if now.timeIntervalSince(entered) >= Self.hoverDelay {
            isExpanded = true
            enteredAt = nil
        }
        return isExpanded
    }

    /// When to check again for the hover delay, if one is pending.
    var expandDeadline: Date? {
        enteredAt.map { $0.addingTimeInterval(Self.hoverDelay) }
    }

    mutating func click() {
        isExpanded = true
        enteredAt = nil
    }

    mutating func collapse() {
        isExpanded = false
        enteredAt = nil
    }
}
