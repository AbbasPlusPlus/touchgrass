import Foundation
import Testing
@testable import TGUpdate

@Suite("Release / appcast")
struct ReleaseTests {

    static let canonical = """
    {
      "version": "0.2.0",
      "build": 3,
      "url": "https://github.com/AbbasPlusPlus/touchgrass-releases/releases/download/v0.2.0/TouchGrass.zip",
      "sha256": "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855",
      "notes": "Quieter nudges.",
      "minOS": "26.0"
    }
    """

    @Test("Decodes the documented appcast shape")
    func decodesCanonical() throws {
        let release = try Release.decode(Data(Self.canonical.utf8))
        #expect(release.version == "0.2.0")
        #expect(release.build == 3)
        #expect(release.url.host() == "github.com")
        #expect(release.notes == "Quieter nudges.")
        #expect(release.minOS == "26.0")
        // Hex digests are normalised so a hand-edited file can shout if it wants to.
        #expect(release.sha256 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("notes and minOS are optional")
    func optionalFields() throws {
        let json = """
        {"version":"0.3.0","build":4,"url":"https://example.com/a.zip","sha256":"abc"}
        """
        let release = try Release.decode(Data(json.utf8))
        #expect(release.notes == nil)
        #expect(release.minOS == nil)
        #expect(release.build == 4)
    }

    @Test("A stringly-typed build number still decodes")
    func stringBuild() throws {
        let json = """
        {"version":"0.3.0","build":"12","url":"https://example.com/a.zip","sha256":"abc"}
        """
        #expect(try Release.decode(Data(json.utf8)).build == 12)
    }

    @Test("Non-https or malformed URLs are rejected")
    func rejectsBadURL() {
        let insecure = """
        {"version":"0.3.0","build":4,"url":"http://example.com/a.zip","sha256":"abc"}
        """
        #expect(throws: (any Error).self) { try Release.decode(Data(insecure.utf8)) }

        let missing = """
        {"version":"0.3.0","build":4,"sha256":"abc"}
        """
        #expect(throws: (any Error).self) { try Release.decode(Data(missing.utf8)) }
    }

    @Test("An array appcast yields the highest release")
    func arrayPicksNewest() throws {
        let json = """
        [
          {"version":"0.1.0","build":1,"url":"https://example.com/1.zip","sha256":"a"},
          {"version":"0.10.0","build":9,"url":"https://example.com/10.zip","sha256":"b"},
          {"version":"0.9.0","build":8,"url":"https://example.com/9.zip","sha256":"c"}
        ]
        """
        #expect(try Release.decode(Data(json.utf8)).version == "0.10.0")
    }

    // MARK: - Update decisions

    private func release(_ version: String, _ build: Int) -> Release {
        Release(
            version: version,
            build: build,
            url: URL(string: "https://example.com/TouchGrass.zip")!,
            sha256: String(repeating: "a", count: 64)
        )
    }

    @Test("Newer version wins regardless of build number")
    func newerVersion() {
        #expect(release("0.2.0", 1).isNewer(thanVersion: "0.1.0", build: 99))
        #expect(!release("0.1.0", 99).isNewer(thanVersion: "0.2.0", build: 1))
    }

    @Test("Same version falls back to the build number")
    func sameVersionTiebreak() {
        #expect(release("0.2.0", 4).isNewer(thanVersion: "0.2.0", build: 3))
        #expect(!release("0.2.0", 3).isNewer(thanVersion: "0.2.0", build: 3))
        #expect(!release("0.2.0", 2).isNewer(thanVersion: "0.2.0", build: 3))
    }

    @Test("Identical builds are never an update")
    func noSelfUpdate() {
        #expect(!release("0.1.0", 1).isNewer(thanVersion: "0.1.0", build: 1))
    }

    @Test("Unparseable current version falls back to build comparison")
    func garbageCurrentVersion() {
        #expect(release("0.2.0", 5).isNewer(thanVersion: "dev", build: 4))
        #expect(!release("0.2.0", 4).isNewer(thanVersion: "dev", build: 4))
    }

    @Test("minOS gates the release")
    func minOSGate() throws {
        let gated = Release(
            version: "1.0.0", build: 1,
            url: URL(string: "https://example.com/a.zip")!,
            sha256: "a", notes: nil, minOS: "26.0"
        )
        #expect(gated.supportsOS(try #require(AppVersion("26.0.1"))))
        #expect(gated.supportsOS(try #require(AppVersion("27.0"))))
        #expect(!gated.supportsOS(try #require(AppVersion("15.5"))))
        // No floor means everyone qualifies.
        #expect(release("1.0.0", 1).supportsOS(try #require(AppVersion("13.0"))))
    }

    @Test("displayVersion reads like the About page")
    func displayVersion() {
        #expect(release("0.2.0", 3).displayVersion == "0.2.0 (3)")
        #expect(release("0.2.0", 0).displayVersion == "0.2.0")
    }
}
