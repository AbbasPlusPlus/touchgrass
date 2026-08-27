// TGUpdate — every way an update can fail, phrased for a settings row.
import Foundation

public enum UpdateError: LocalizedError, Equatable {
    case offline
    case badAppcast(String)
    case downloadFailed(String)
    case checksumMismatch(expected: String, got: String)
    case unpackFailed(String)
    case noAppInArchive
    case validationFailed(String)
    case notAnAppBundle
    case notWritable(String)
    case swapFailed(String)
    case unsupportedOS(String)

    public var errorDescription: String? {
        switch self {
        case .offline:
            return "Couldn't reach the update server."
        case .badAppcast(let why):
            return "Update information was unreadable — \(why)."
        case .downloadFailed(let why):
            return "Download failed — \(why)."
        case .checksumMismatch(let expected, let got):
            return "Download didn't match its checksum (expected \(expected.prefix(12))…, got \(got.prefix(12))…)."
        case .unpackFailed(let why):
            return "Couldn't unpack the download — \(why)."
        case .noAppInArchive:
            return "The download didn't contain TouchGrass.app."
        case .validationFailed(let why):
            return "The downloaded app failed validation — \(why)."
        case .notAnAppBundle:
            return "TouchGrass isn't running from an app bundle, so it can't update itself."
        case .notWritable(let path):
            return "No permission to write to \(path). Move TouchGrass to your Applications folder and try again."
        case .swapFailed(let why):
            return "Couldn't replace the app — \(why). Your current version is untouched."
        case .unsupportedOS(let minOS):
            return "That update needs macOS \(minOS) or later."
        }
    }
}
