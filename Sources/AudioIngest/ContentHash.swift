import CryptoKit
import Foundation

public enum ContentHash {
    /// Lowercase hex SHA-256 of the file, read in `chunkSize` pieces.
    public static func sha256(of url: URL, chunkSize: Int = 1 << 20) throws -> String {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch {
            throw AudioIngestError.unreadable(fileName: url.lastPathComponent)
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data? = try autoreleasepool {
                do { return try handle.read(upToCount: chunkSize) } catch {
                    throw AudioIngestError.readFailed(fileName: url.lastPathComponent, detail: error.localizedDescription)
                }
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
