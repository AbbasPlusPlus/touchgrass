import Testing
@testable import TGUpdate

@Suite("AppVersion")
struct AppVersionTests {

    @Test("Parses plain dotted versions")
    func parsesDotted() throws {
        let v = try #require(AppVersion("0.2.0"))
        #expect(v.numbers == [0, 2, 0])
        #expect(v.prerelease.isEmpty)
        #expect(v.description == "0.2.0")
    }

    @Test("Tolerates a leading v and build metadata")
    func tolerantParsing() throws {
        #expect(AppVersion("v1.4.2") == AppVersion("1.4.2"))
        #expect(AppVersion("1.4.2+deadbeef") == AppVersion("1.4.2"))
        #expect(AppVersion("  1.4.2 ") == AppVersion("1.4.2"))
    }

    @Test("Rejects strings with no leading number")
    func rejectsGarbage() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("v") == nil)
    }

    @Test("Missing components read as zero")
    func missingComponents() {
        #expect(AppVersion("1.2") == AppVersion("1.2.0"))
        #expect(AppVersion("1") == AppVersion("1.0.0.0"))
        #expect(AppVersion("1.2")?.hashValue == AppVersion("1.2.0")?.hashValue)
    }

    @Test("Orders by component, not lexically")
    func ordering() throws {
        let ascending = ["0.1.0", "0.2.0", "0.9.9", "0.10.0", "1.0.0", "1.0.1", "2.0.0"]
        let parsed = try ascending.map { try #require(AppVersion($0)) }
        #expect(parsed == parsed.sorted())
        // The classic string-compare trap.
        #expect(try #require(AppVersion("0.10.0")) > #require(AppVersion("0.9.9")))
    }

    @Test("A pre-release sorts below its release")
    func prereleaseOrdering() throws {
        let beta = try #require(AppVersion("1.0.0-beta.1"))
        let beta2 = try #require(AppVersion("1.0.0-beta.2"))
        let final = try #require(AppVersion("1.0.0"))
        #expect(beta < final)
        #expect(beta < beta2)
        #expect(beta != final)
        #expect(try beta2 < #require(AppVersion("1.0.1")))
        // Numeric identifiers compare numerically, not as text.
        #expect(try #require(AppVersion("1.0.0-rc.2")) < #require(AppVersion("1.0.0-rc.10")))
    }

    @Test("Fewer pre-release identifiers sorts lower")
    func prereleaseLength() throws {
        #expect(try #require(AppVersion("1.0.0-beta")) < #require(AppVersion("1.0.0-beta.1")))
    }
}
