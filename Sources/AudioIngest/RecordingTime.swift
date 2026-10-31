import AVFoundation
import Foundation

/// When an imported file was recorded, and where that time came from.
public struct RecordingTime: Sendable, Equatable {
    public enum Origin: String, Sendable {
        /// Broadcast WAV `bext` origination date and time.
        case broadcastWave
        /// M4A/MP3 creation-date metadata.
        case fileMetadata
        /// The file's creation date. The UI says "Time taken from the file".
        case fileDate
    }

    public var date: Date
    public var origin: Origin

    public init(date: Date, origin: Origin) {
        self.date = date
        self.origin = origin
    }

    public var timeFromFileDate: Bool { origin == .fileDate }
}

extension AudioIngest {
    /// Embedded metadata dates outside this range are treated as missing
    /// (an unset MPEG-4 header reads as 1904).
    static let earliestPlausibleDate = Date(timeIntervalSince1970: 631_152_000) // 1990-01-01

    /// Recording time, in order: `bext` origination (in `timeZone`, since BWF
    /// carries no zone), M4A/MP3 creation metadata, the file's creation date.
    /// Metadata that looks like it was stamped by a re-save is skipped.
    public static func recordingTime(of url: URL, timeZone: TimeZone = .current) async throws -> RecordingTime {
        if let date = broadcastWaveOrigination(of: url, timeZone: timeZone) {
            return RecordingTime(date: date, origin: .broadcastWave)
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        if let date = await metadataCreationDate(of: url) {
            let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            if !metadataDateLooksResaved(metadata: date, modified: values?.contentModificationDate, duration: duration) {
                return RecordingTime(date: date, origin: .fileMetadata)
            }
        }
        guard let date = values?.creationDate ?? values?.contentModificationDate else {
            throw AudioIngestError.unreadable(fileName: url.lastPathComponent)
        }
        return RecordingTime(date: date, origin: .fileDate)
    }

    /// Origination date and time from a RIFF/RF64/BW64 WAV `bext` chunk, or nil.
    public static func broadcastWaveOrigination(of url: URL, timeZone: TimeZone = .current) -> Date? {
        guard let bext = BroadcastWave.bextChunk(of: url) else { return nil }
        return BroadcastWave.originationDate(bext: bext, timeZone: timeZone)
    }

    static func metadataCreationDate(of url: URL) async -> Date? {
        let asset = AVURLAsset(url: url)
        var items: [AVMetadataItem] = []
        if let item = try? await asset.load(.creationDate) { items.append(item) }
        if let all = try? await asset.load(.metadata) {
            items += AVMetadataItem.metadataItems(from: all, filteredByIdentifier: .commonIdentifierCreationDate)
            items += AVMetadataItem.metadataItems(from: all, filteredByIdentifier: .quickTimeMetadataCreationDate)
            items += AVMetadataItem.metadataItems(from: all, filteredByIdentifier: .id3MetadataRecordingTime)
            items += AVMetadataItem.metadataItems(from: all, filteredByIdentifier: .id3MetadataDate)
        }
        let latest = Date().addingTimeInterval(86_400)
        for item in items {
            var date = try? await item.load(.dateValue)
            if date == nil, let s = try? await item.load(.stringValue) { date = parseMetadataDate(s) }
            if let date, date >= earliestPlausibleDate, date <= latest { return date }
        }
        return nil
    }

    /// A recorder stamps the creation date when it starts and finishes writing
    /// about one duration later. A converter or editor stamps the date when it
    /// saves and finishes faster than real time. So a metadata date less than
    /// half the duration before the file's last change, or after it, is the
    /// re-save time, not the recording time.
    static func metadataDateLooksResaved(metadata: Date, modified: Date?, duration: Double) -> Bool {
        guard let modified, duration.isFinite, duration > 0 else { return false }
        return modified.timeIntervalSince(metadata) < duration / 2
    }

    /// ISO 8601-style date with a time. Date-only and year-only strings are
    /// rejected: the file date is a better guess than midnight on Jan 1.
    static func parseMetadataDate(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            iso.formatOptions = options
            if let d = iso.date(from: trimmed) { return d }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            f.dateFormat = format
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }
}

enum BroadcastWave {
    /// v0 `bext` up to and including OriginationTime: 256 + 32 + 32 + 10 + 8.
    static let originationEnd = 338

    /// Raw `bext` chunk bytes (at least through OriginationTime), read
    /// without loading the audio.
    static func bextChunk(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 12), header.count == 12 else { return nil }
        let form = String(decoding: header[0..<4], as: UTF8.self)
        guard ["RIFF", "RF64", "BW64"].contains(form), String(decoding: header[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        var offset: UInt64 = 12
        var ds64DataSize: UInt64?
        for _ in 0..<1024 {
            guard offset + 8 <= fileSize, (try? handle.seek(toOffset: offset)) != nil,
                  let chunkHeader = try? handle.read(upToCount: 8), chunkHeader.count == 8 else { return nil }
            let id = String(decoding: chunkHeader[0..<4], as: UTF8.self)
            var size = UInt64(le32(chunkHeader, 4))
            switch id {
            case "bext":
                guard size >= UInt64(originationEnd),
                      let body = try? handle.read(upToCount: originationEnd), body.count == originationEnd else { return nil }
                return body
            case "ds64":
                if let body = try? handle.read(upToCount: 16), body.count == 16 {
                    ds64DataSize = UInt64(le32(body, 8)) | UInt64(le32(body, 12)) << 32
                }
            case "data":
                if size == 0xFFFF_FFFF, let ds64DataSize { size = ds64DataSize }
            default:
                break
            }
            offset += 8 + size + (size & 1)
        }
        return nil
    }

    /// OriginationDate "yyyy?mm?dd" at byte 320 and OriginationTime "hh?mm?ss"
    /// at byte 330; any separator is accepted. Nil when either is blank or invalid.
    static func originationDate(bext: Data, timeZone: TimeZone) -> Date? {
        guard bext.count >= originationEnd else { return nil }
        let bytes = [UInt8](bext[bext.startIndex + 320 ..< bext.startIndex + originationEnd])
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for b in bytes[range] {
                guard (0x30...0x39).contains(b) else { return nil }
                value = value * 10 + Int(b - 0x30)
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(10..<12), let minute = number(13..<15), let second = number(16..<18),
              year >= 1900, (1...12).contains(month), (1...31).contains(day),
              hour < 24, minute < 60, second < 60 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: parts),
              calendar.component(.day, from: date) == day else { return nil } // rejects Feb 31
        return date
    }

    private static func le32(_ d: Data, _ at: Int) -> UInt32 {
        let i = d.startIndex + at
        return UInt32(d[i]) | UInt32(d[i + 1]) << 8 | UInt32(d[i + 2]) << 16 | UInt32(d[i + 3]) << 24
    }
}
