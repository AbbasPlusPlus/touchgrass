// TGUpdate — the appcast document. Pure Swift, no I/O.
import Foundation

/// One entry in the appcast:
/// ```json
/// { "version": "0.2.0", "build": 3,
///   "url": "https://…/TouchGrass.zip",
///   "sha256": "…", "notes": "…", "minOS": "26.0" }
/// ```
/// Decoding is deliberately forgiving — the file is hand-editable and lives in a repo we push
/// to by hand, so a stray string where an int belongs must not brick every client.
public struct Release: Codable, Equatable, Sendable {

    // MARK: Fields

    public let version: String
    public let build: Int
    public let url: URL
    /// Lower-case hex SHA-256 of the zip. Empty means "unverifiable" and is rejected at install.
    public let sha256: String
    public let notes: String?
    /// Minimum macOS version, e.g. "26.0". `nil` means no floor.
    public let minOS: String?

    public init(
        version: String,
        build: Int,
        url: URL,
        sha256: String,
        notes: String? = nil,
        minOS: String? = nil
    ) {
        self.version = version
        self.build = build
        self.url = url
        self.sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.notes = notes
        self.minOS = minOS
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case version, build, url, sha256, notes, minOS
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version).trimmingCharacters(in: .whitespaces)

        // `build` may arrive as 3 or "3".
        if let n = try? c.decode(Int.self, forKey: .build) {
            build = n
        } else if let s = try? c.decode(String.self, forKey: .build), let n = Int(s) {
            build = n
        } else {
            build = 0
        }

        let rawURL = try c.decode(String.self, forKey: .url).trimmingCharacters(in: .whitespaces)
        guard let parsed = URL(string: rawURL), parsed.scheme == "https" else {
            throw DecodingError.dataCorruptedError(
                forKey: .url, in: c,
                debugDescription: "url must be an absolute https URL, got \"\(rawURL)\""
            )
        }
        url = parsed

        sha256 = ((try? c.decode(String.self, forKey: .sha256)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        notes = try? c.decode(String.self, forKey: .notes)
        minOS = try? c.decode(String.self, forKey: .minOS)
    }

    // MARK: Decoding entry point

    /// Parses an appcast payload. Accepts either a single object or an array of them, in which
    /// case the highest version wins — so the file can grow a history later without a client change.
    public static func decode(_ data: Data) throws -> Release {
        let decoder = JSONDecoder()
        if let one = try? decoder.decode(Release.self, from: data) { return one }
        let many = try decoder.decode([Release].self, from: data)
        guard let best = many.max(by: { $0.isOlder(than: $1) }) else {
            throw UpdateError.badAppcast("appcast contained no releases")
        }
        return best
    }

    // MARK: Ordering

    public var semanticVersion: AppVersion? { AppVersion(version) }

    private func isOlder(than other: Release) -> Bool {
        guard let a = semanticVersion, let b = other.semanticVersion else { return build < other.build }
        if a != b { return a < b }
        return build < other.build
    }

    /// Is this release worth installing over `version` / `build`?
    /// Version number decides; the build number only breaks ties (re-spins of the same version).
    public func isNewer(thanVersion currentVersion: String, build currentBuild: Int) -> Bool {
        guard let mine = semanticVersion, let theirs = AppVersion(currentVersion) else {
            return build > currentBuild
        }
        if mine != theirs { return mine > theirs }
        return build > currentBuild
    }

    /// `minOS` satisfied by the running system?
    public func supportsOS(_ os: AppVersion) -> Bool {
        guard let minOS, let floor = AppVersion(minOS) else { return true }
        return os >= floor
    }

    /// Human-facing "0.2.0 (3)".
    public var displayVersion: String { build > 0 ? "\(version) (\(build))" : version }
}
