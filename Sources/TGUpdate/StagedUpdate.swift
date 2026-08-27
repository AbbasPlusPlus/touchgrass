// TGUpdate — a verified, unpacked build sitting next door, waiting for the swap.
import Foundation

public struct StagedUpdate: Sendable, Equatable {
    public let release: Release
    /// The unpacked `TouchGrass.app` inside `stagingDirectory`.
    public let appURL: URL
    /// Everything we created for this attempt; removed after a successful install.
    public let stagingDirectory: URL
    /// Where `appURL` will be copied to.
    public let destination: URL
    /// `codesign --verify` output when it wasn't happy. Ad-hoc signatures are legitimate here,
    /// so this is advisory only — never a reason to refuse an install.
    public let signatureNote: String?
}
