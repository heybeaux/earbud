import ArgumentParser
import AudioCodec
import FieldyDevice
import FieldyProtocol
import Foundation
import Library
import SyncEngine
import Transcriber

@main
struct EarBudCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "earbud-cli",
        abstract: "Drive EarBudKit against a real Fieldy 3.",
        subcommands: [Status.self, Setup.self, Sync.self, Record.self, Transcribe.self, Scan.self])
}

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List nearby Fieldy devices (--all: every advertiser).")
    @Flag var all = false
    @Option var seconds: Double = 10

    func run() async throws {
        let dev = FieldyDevice()
        if all {
            for d in try await dev.scanAll(seconds: seconds) {
                print("\(d.identifier.uuidString) rssi=\(d.rssi) name=\(d.name ?? "-") services=\(d.services.joined(separator: ","))")
            }
        } else {
            for d in try await dev.scan(timeout: seconds) {
                print("\(d.identifier.uuidString) rssi=\(d.rssi) name=\(d.name)")
            }
        }
    }
}

func log(_ message: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    print("\(f.string(from: Date())) \(message)")
    fflush(stdout)
}

struct DeviceOptions: ParsableArguments {
    @Option(help: "CoreBluetooth identifier of the Fieldy (default: first device named Fieldy*).")
    var device: String?

    func makeDevice() throws -> FieldyDevice {
        var config = FieldyDevice.Configuration()
        config.idleDisconnectAfter = nil // the CLI disconnects explicitly
        let id = try device.map { s -> UUID in
            guard let u = UUID(uuidString: s) else { throw ValidationError("--device must be a UUID") }
            return u
        }
        return FieldyDevice(configuration: config, rememberedIdentifier: id)
    }
}

func connectAndReport(_ dev: FieldyDevice) async throws -> ConnectionInfo {
    let c = try await dev.connect()
    log("connected to \(c.name) (\(c.identifier.uuidString))")
    log("clock set to \(ISO8601DateFormatter().string(from: c.clockSetAt))")
    if let r = c.acknowledgedResetReport {
        log("acknowledged device reset report \(r.raw.hexString): the device was reset; clock fixed")
    }
    let i = c.deviceInfo
    log("model \(i.model ?? "?") firmware \(i.firmware ?? "?") hardware \(i.hardware ?? "?") software \(i.software ?? "?")")
    if !i.isTestedFirmware {
        log("warning: this Fieldy firmware has not been tested with EarBud (tested: \(FieldyGATT.testedFirmware))")
    }
    return c
}

func describe(_ s: StorageStatus) -> String {
    "storage: \(s.totalFileCount) file(s), \(s.totalFileSize) bytes, synced \(s.syncedFileCount), remaining \(s.remainingSyncSize) bytes, transport v\(s.maxTransportVersion)"
}

// MARK: status

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Connect, set the clock, and print device status.")
    @OptionGroup var deviceOptions: DeviceOptions

    func run() async throws {
        let dev = try deviceOptions.makeDevice()
        defer { Task { await dev.disconnect() } }
        _ = try await connectAndReport(dev)
        let b = try await dev.battery()
        log("battery \(b.percent.map { "\($0)%" } ?? "?") \(b.millivolts.map { "\($0) mV" } ?? "")")
        if let t = try? await dev.temperature() { log(String(format: "temperature %.2f °C", t)) }
        if let clock = try await dev.readClock() { log("device clock reads \(ISO8601DateFormatter().string(from: clock))") }
        log("recording: \(try await dev.recordingStatus().summary)")
        log("mode \(try await dev.recordingMode()) led \(try await dev.ledOn() ? "on" : "off") muted \(try await dev.muted())")
        do {
            log(describe(try await dev.pair()))
        } catch FieldyDeviceError.pairedElsewhere {
            log("storage: unavailable. This Fieldy is paired with another device.")
        }
        await dev.disconnect()
    }
}

// MARK: setup

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Pair (bond), set the clock and acknowledge a reset report.")
    @OptionGroup var deviceOptions: DeviceOptions

    func run() async throws {
        let dev = try deviceOptions.makeDevice()
        let c = try await connectAndReport(dev)
        do {
            let s = try await dev.pair()
            log("paired. \(describe(s))")
            log("recording: \(try await dev.recordingStatus().summary)")
            log("remember this device with --device \(c.identifier.uuidString)")
        } catch FieldyDeviceError.pairedElsewhere {
            log("This Fieldy is paired with another device. Reset it (short click, then hold 10 s) and run setup again.")
        }
        await dev.disconnect()
    }
}

// MARK: sync

struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Download every stored recording, decode, and transcribe.")
    @OptionGroup var deviceOptions: DeviceOptions

    @Option(help: "Library root (default ~/Library/Application Support/EarBud).")
    var out: String?

    @Flag(help: "Skip transcription.")
    var noTranscribe = false

    @Option(help: "accurate (small.en) or faster (base.en).")
    var model: String = "accurate"

    @Flag(help: "Also export WAV files next to the M4A.")
    var wav = false

    func run() async throws {
        let paths = out.map { LibraryPaths(root: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) } ?? .default
        let library = try LibraryStore(paths: paths)
        let tm = try parseModel(model)
        let importer = RecordingImporter(library: library, transcriptionModel: noTranscribe ? nil : tm.rawValue)
        let dev = try deviceOptions.makeDevice()
        let engine = SyncEngine(device: dev, importer: importer, log: { log($0) })

        let recovered = try await engine.recoverAndCleanUp()
        if !recovered.isEmpty { log("recovered \(recovered.count) recording(s) left by an earlier run") }

        let progressTask = Task {
            var lastShown = -1
            for await p in await engine.progressUpdates() where p.phase == .copying {
                let pct = Int(p.fraction * 100)
                if pct / 10 != lastShown / 10 { log("copying: \(p.bytesReceived)/\(p.bytesExpected) bytes (\(pct)%)"); lastShown = pct }
            }
        }
        let summary: SyncSummary
        do {
            summary = try await engine.sync()
        } catch {
            progressTask.cancel()
            await dev.disconnect()
            log("sync failed: \(error)")
            throw ExitCode.failure
        }
        progressTask.cancel()
        await dev.disconnect()

        log("sync \(summary.result.rawValue): \(summary.recordings.count) recording(s), \(summary.bytesReceived) bytes\(summary.message.map { "; \($0)" } ?? "")")
        let local = DateFormatter()
        local.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        for url in summary.rawFiles {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            log("raw \(paths.relative(url)): \(size) bytes")
        }
        for r in summary.recordings {
            log(String(format: "recording %@: %.2f s, %d frames, %@, recorded %@%@", r.id, r.durationSeconds, r.frameCount,
                       r.audioState.rawValue, local.string(from: r.recordedAt), r.timeUnknown ? " (time unknown)" : ""))
            if let a = r.audioPath { log("  audio \(a)") }
            if wav, let opus = r.opusPath {
                let audio = try FieldyOpusDecoder.decode(frames: try Data(contentsOf: paths.absolute(opus)))
                let wavURL = paths.absolute(opus).deletingPathExtension().appendingPathExtension("wav")
                try WAVFile.write(audio, to: wavURL)
                log("  wav \(paths.relative(wavURL))")
            }
        }
        if !noTranscribe {
            try await runQueue(library: library, model: tm)
            for r in summary.recordings { try printTranscript(library: library, recordingId: r.id) }
        }
    }
}

func parseModel(_ s: String) throws -> TranscriptionModel {
    switch s.lowercased() {
    case "accurate", "small", "small.en", TranscriptionModel.accurate.rawValue: return .accurate
    case "faster", "base", "base.en", TranscriptionModel.faster.rawValue: return .faster
    default: throw ValidationError("--model must be accurate or faster")
    }
}

func ensureModel(_ model: TranscriptionModel, library: LibraryStore) async throws {
    let dir = library.paths.models
    if WhisperKitRecognizer.isInstalled(model, in: dir) { return }
    log("downloading \(model.displayName) model \(model.rawValue) (about \(model.approximateDownloadMB) MB) to \(dir.path)")
    let shown = Shown()
    let folder = try await WhisperKitRecognizer.download(model, to: dir) { f in
        let step = Int(f * 10)
        if shown.advance(to: step) { log("model download \(step * 10)%") }
    }
    let bytes = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])?
        .compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }
        .reduce(0, +)) ?? 0
    log("model ready at \(folder.path) (\(bytes / 1_000_000) MB)")
}

final class Shown: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1
    func advance(to v: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard v > last else { return false }
        last = v
        return true
    }
}

func runQueue(library: LibraryStore, model: TranscriptionModel) async throws {
    try await ensureModel(model, library: library)
    let queue = TranscriptionQueue.whisperKit(library: library)
    try await queue.resume()
    let events = await queue.events()
    let printer = Task {
        for await e in events {
            switch e {
            case .started(let id): log("transcribing \(id)")
            case .finished(let id, let n): log("transcribed \(id): \(n) segment(s)")
            case .failed(let id, let m): log("transcription failed for \(id): \(m)")
            }
        }
    }
    let n = try await queue.processAll()
    try? await Task.sleep(for: .milliseconds(100))
    printer.cancel()
    log("transcription queue done: \(n) job(s)")
}

func printTranscript(library: LibraryStore, recordingId: String) throws {
    guard let r = try library.recording(id: recordingId) else { return }
    let segs = try library.segments(recordingId: recordingId)
    print("--- transcript \(recordingId) [\(r.transcriptState.rawValue)\(r.transcriptModel.map { ", \($0)" } ?? "")] ---")
    if r.transcriptState == .failed {
        print("Transcription failed: \(r.transcriptError ?? "unknown error")")
    } else {
        print(TranscriptFilter.plainText(segs.map { TranscriptSegment(start: $0.start, end: $0.end, text: $0.text) }))
    }
    print("---")
}

// MARK: record

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Record SECONDS on the Fieldy (to its own storage) from the Mac.")
    @OptionGroup var deviceOptions: DeviceOptions

    @Argument(help: "Seconds to record.")
    var seconds: Double

    func run() async throws {
        let dev = try deviceOptions.makeDevice()
        _ = try await connectAndReport(dev)
        await dev.beginActivity()
        let before = try await dev.recordingStatus()
        log("recording status before: \(before.summary)")
        try await dev.subscribe(FieldyGATT.recordingControl) { data in
            if let s = try? RecordingStatus(parsing: data) { log("notify: \(s.summary)") } else { log("notify: \(data.hexString)") }
        }
        let started = try await dev.startRecording()
        log("start: \(started.summary)")
        if started.errorReason == .muted {
            log("Your Fieldy is muted. Not recording.")
        } else if started.state == .error {
            log("device reported an error: \(started.errorReason)")
        } else {
            try await Task.sleep(for: .seconds(seconds))
        }
        let stopped = try await dev.stopRecording()
        log("stop: \(stopped.summary)")
        try await Task.sleep(for: .seconds(2))
        log("recording status after: \(try await dev.recordingStatus().summary)")
        await dev.unsubscribe(FieldyGATT.recordingControl)
        if let s = try? await dev.pair() { log(describe(s)) }
        await dev.endActivity()
        await dev.disconnect()
    }
}

// MARK: transcribe

struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the transcription queue for a library, or transcribe one raw/.opus/.wav/.m4a file.")

    @Option(help: "Library root (default ~/Library/Application Support/EarBud).")
    var out: String?

    @Option(help: "accurate (small.en) or faster (base.en).")
    var model: String = "accurate"

    @Option(help: "Re-queue this recording ID (\"Transcribe again\").")
    var again: String?

    @Argument(help: "Optional file to transcribe directly (.bin raw from the device, .opus frames, .wav, .m4a).")
    var file: String?

    func run() async throws {
        let tm = try parseModel(model)
        let paths = out.map { LibraryPaths(root: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) } ?? .default
        let library = try LibraryStore(paths: paths)
        if let file {
            try await ensureModel(tm, library: library)
            let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
            let samples: [Float]
            switch url.pathExtension.lowercased() {
            case "bin", "part":
                samples = try FieldyOpusDecoder.decode(frames: RecordingFile(parsing: try Data(contentsOf: url)).opusFrames).floatSamples
            case "opus":
                samples = try FieldyOpusDecoder.decode(frames: try Data(contentsOf: url)).floatSamples
            default:
                samples = try AudioFileInfo.readMono16k(url)
            }
            log(String(format: "audio: %.2f s", Double(samples.count) / 16_000))
            let rec = WhisperKitRecognizer(model: tm, modelsDirectory: paths.models)
            let segs = TranscriptFilter.clean(try await rec.recognize(samples: samples))
            print(TranscriptFilter.plainText(segs))
            return
        }
        if let again {
            try library.enqueueTranscription(recordingId: again, model: tm.rawValue)
        }
        try await runQueue(library: library, model: tm)
        for r in try library.recordings(limit: 20) { try printTranscript(library: library, recordingId: r.id) }
    }
}
