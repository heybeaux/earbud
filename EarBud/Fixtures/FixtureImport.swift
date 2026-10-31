import Foundation

/// Simulated importer over `FixtureLibrary`, with the folder from mockups 23 and 24.
///
/// Files are judged by name: unsupported extensions are rejected, a name already imported (or listed
/// in `knownCopies`) is a duplicate, anything else becomes a Waiting recording. Folders on disk are
/// searched for real; `folders` adds virtual ones for tests and snapshots.
actor FixtureImport: ImportProviding {
    /// The folder dragged in mockup 23: 4 new files, 1 already in EarBud, 1 PDF.
    static let octoberInterviews = URL(fileURLWithPath: "/Fixtures/October interviews", isDirectory: true)
    static let sampleFolders: [URL: [String]] = [
        octoberInterviews: [
            "Panel discussion.m4a", "Lena Okafor follow-up.wav", "REC_0043.WAV", "Site walk.mp3",
            "Lena interview copy.wav", "Release form.pdf",
        ],
    ]
    /// File names whose audio is already in the library under another name (the real importer
    /// finds these by content).
    static let sampleCopies = ["Lena interview copy.wav": "Interview with Lena Okafor"]

    private let library: FixtureLibrary
    private let folders: [String: [String]]
    private let knownCopies: [String: String]
    private let now: @Sendable () -> Date
    private let pace: Duration
    private var count = 0
    private(set) var cleanupCount = 0

    init(library: FixtureLibrary, folders: [URL: [String]] = FixtureImport.sampleFolders,
         knownCopies: [String: String] = FixtureImport.sampleCopies,
         now: @escaping @Sendable () -> Date = Date.init, pace: Duration = .milliseconds(400)) {
        self.library = library
        self.folders = Dictionary(uniqueKeysWithValues: folders.map { (Self.key($0.key), $0.value) })
        self.knownCopies = knownCopies
        self.now = now
        self.pace = pace
    }

    func files(in urls: [URL]) async -> [URL] {
        urls.flatMap { url -> [URL] in
            if let names = folders[Self.key(url)] {
                return names.map { url.appendingPathComponent($0, isDirectory: false) }
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return [url]
            }
            let found = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])?
                .compactMap { $0 as? URL }
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true } ?? []
            return found.sorted { $0.path < $1.path }
        }
    }

    func importFile(_ url: URL) async -> ImportReport {
        try? await Task.sleep(for: pace)
        let name = url.lastPathComponent
        guard ImportFormats.extensions.contains(url.pathExtension.lowercased()) else {
            return ImportReport(rejected: [.init(fileName: name, reason: ImportFormats.unreadableReason)])
        }
        if let title = knownCopies[name] {
            return ImportReport(duplicates: [.init(fileName: name, existingTitle: title)])
        }
        if let title = await library.importedTitle(fileName: name) {
            return ImportReport(duplicates: [.init(fileName: name, existingTitle: title)])
        }
        count += 1
        let id = "import-\(count)"
        let script = FixtureData.waiting[(count - 1) % FixtureData.waiting.count]
        let recordedAt = now().addingTimeInterval(-Double(count) * 3_600 - 86_400)
        await library.addImported(id: id, fileName: name, recordedAt: recordedAt, script: script)
        return ImportReport(importedIDs: [id])
    }

    @discardableResult
    func cleanupAfterLaunch() async -> Int {
        cleanupCount += 1
        return 0
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
