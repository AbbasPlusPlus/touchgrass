// TGUpdate — streaming SHA-256 so a 40 MB zip never lands in RAM twice.
import CryptoKit
import Foundation

enum FileHash {

    /// Lower-case hex digest, or `nil` if the file can't be read.
    static func sha256Hex(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1 << 20   // 1 MB
        while true {
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
