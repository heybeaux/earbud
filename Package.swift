// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EarBudKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "EarBudKit",
            targets: ["FieldyProtocol", "FieldyDevice", "SyncEngine", "AudioCodec", "Transcriber", "Library"]
        ),
        .library(name: "FieldyProtocol", targets: ["FieldyProtocol"]),
        .library(name: "FieldyDevice", targets: ["FieldyDevice"]),
        .library(name: "SyncEngine", targets: ["SyncEngine"]),
        .library(name: "AudioCodec", targets: ["AudioCodec"]),
        .library(name: "Transcriber", targets: ["Transcriber"]),
        .library(name: "Library", targets: ["Library"]),
        .executable(name: "earbud-cli", targets: ["earbud-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.1"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
        // libopus vendored as C sources (BSD-3-Clause). See docs/decisions.md.
        .package(url: "https://github.com/alta/swift-opus.git", revision: "6f3cb6bd3ffed1fe5f06d00a962d5c191a50daf8"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Pure parsing and command building. No CoreBluetooth, no I/O.
        .target(name: "FieldyProtocol"),

        // CoreBluetooth actor: scan, connect, bond, clock, controls.
        .target(name: "FieldyDevice", dependencies: ["FieldyProtocol"]),

        // Non-variadic wrappers for opus_*_ctl (variadic C is not callable from Swift).
        .target(
            name: "COpusShim",
            dependencies: [.product(name: "Copus", package: "swift-opus")]
        ),

        // Opus CELT frames -> PCM -> WAV / M4A.
        .target(
            name: "AudioCodec",
            dependencies: ["FieldyProtocol", "COpusShim", .product(name: "Copus", package: "swift-opus")]
        ),

        // GRDB storage: recordings, segments, sync history, queue, settings, FTS5.
        .target(
            name: "Library",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),

        // Durable download, import, crash recovery, raw cleanup.
        .target(
            name: "SyncEngine",
            dependencies: ["FieldyProtocol", "FieldyDevice", "AudioCodec", "Library"]
        ),

        // WhisperKit wrapper and persistent transcription queue.
        .target(
            name: "Transcriber",
            dependencies: [
                "AudioCodec",
                "Library",
                "FieldyProtocol",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),

        .executableTarget(
            name: "earbud-cli",
            dependencies: [
                "FieldyProtocol", "FieldyDevice", "SyncEngine", "AudioCodec", "Transcriber", "Library",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        .testTarget(name: "FieldyProtocolTests", dependencies: ["FieldyProtocol"]),
        .testTarget(name: "FieldyDeviceTests", dependencies: ["FieldyDevice"]),
        .testTarget(
            name: "AudioCodecTests",
            dependencies: ["AudioCodec", .product(name: "Copus", package: "swift-opus")],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "LibraryTests", dependencies: ["Library"]),
        .testTarget(
            name: "SyncEngineTests",
            dependencies: ["SyncEngine", "FieldyProtocol", "AudioCodec", "Library", .product(name: "Copus", package: "swift-opus")]
        ),
        .testTarget(name: "TranscriberTests", dependencies: ["Transcriber", "Library"]),
    ],
    swiftLanguageModes: [.v6]
)
