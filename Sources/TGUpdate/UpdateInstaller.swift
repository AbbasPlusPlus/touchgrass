// TGUpdate — download → verify → unpack → validate → swap → relaunch.
//
// The order matters more than any single step: nothing that exists is destroyed until the
// replacement has been checksummed, unpacked and read back as a plausible TouchGrass. If any
// stage throws, the running app is byte-for-byte untouched and keeps running.
//
// Swap/relaunch mechanics follow exelban/stats' `Kit/plugins/Updater.swift` (MIT): stage
// outside the bundle, hand the relaunch to a detached `/bin/sh`, then exit. We differ in that
// we ship a zip rather than a DMG, and we do the copy ourselves rather than from a script.
import Foundation

public enum UpdateInstaller {

    // MARK: - Tools

    private static let ditto = "/usr/bin/ditto"
    private static let xattr = "/usr/bin/xattr"
    private static let codesign = "/usr/bin/codesign"
    private static let sh = "/bin/sh"
    private static let open = "/usr/bin/open"

    // MARK: - Stage

    /// Everything up to (but not including) touching the installed app.
    ///
    /// Runs off the main actor — it blocks on `ditto` and on a megabyte-at-a-time hash.
    public static func stage(
        release: Release,
        app: InstalledApp,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> StagedUpdate {

        // macOS floor. Refuse early rather than shipping a binary that won't launch.
        if let minOS = release.minOS {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let running = AppVersion(numbers: [os.majorVersion, os.minorVersion, os.patchVersion])
            guard release.supportsOS(running) else { throw UpdateError.unsupportedOS(minOS) }
        }

        let staging = try makeStagingDirectory()
        do {
            let zipURL = staging.appendingPathComponent("TouchGrass.zip")
            _ = try await UpdateDownloader.download(from: release.url, to: zipURL, progress: progress)

            try verifyChecksum(of: zipURL, against: release.sha256)

            let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
            let extraction = Shell.run(ditto, ["-x", "-k", zipURL.path, unpacked.path])
            guard extraction.ok else { throw UpdateError.unpackFailed(extraction.message) }
            // The zip is 40 MB of dead weight from here on.
            try? FileManager.default.removeItem(at: zipURL)

            guard let newApp = findAppBundle(in: unpacked) else { throw UpdateError.noAppInArchive }

            // We aren't sandboxed and don't set LSFileQuarantineEnabled, so our own downloads
            // carry no com.apple.quarantine — strip it anyway, cheaply, in case that changes or
            // the zip was produced somewhere that did apply one.
            _ = Shell.run(xattr, ["-dr", "com.apple.quarantine", newApp.path])

            try validate(newApp, release: release, against: app)
            let signatureNote = signatureComplaint(for: newApp)

            return StagedUpdate(
                release: release,
                appURL: newApp,
                stagingDirectory: staging,
                destination: app.installDestination,
                signatureNote: signatureNote
            )
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    // MARK: - Install

    /// Puts `staged.appURL` where the app lives, then hands the relaunch to a detached shell.
    /// Returns once the swap is done; the caller terminates the process.
    ///
    /// The old bundle is *renamed*, never deleted, until the new one is fully in place — and it
    /// is renamed rather than removed because the code we are executing right now lives inside
    /// it. Unix keeps the open inode alive across a rename; a delete would too, but a rename
    /// leaves something to put back if `ditto` fails halfway.
    public static func install(_ staged: StagedUpdate) throws {
        let fm = FileManager.default
        let destination = staged.destination
        let parent = destination.deletingLastPathComponent()

        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        guard fm.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable(parent.path)
        }

        var backup: URL?
        if fm.fileExists(atPath: destination.path) {
            let candidate = staged.stagingDirectory
                .appendingPathComponent("previous-" + destination.lastPathComponent)
            do {
                try fm.moveItem(at: destination, to: candidate)
                backup = candidate
            } catch {
                // Cross-device rename (staging is /var/folders, app may be on another volume):
                // fall back to a sibling of the destination, which is always same-device.
                let sibling = parent.appendingPathComponent(
                    ".\(destination.lastPathComponent).tg-old-\(UUID().uuidString.prefix(8))"
                )
                do {
                    try fm.moveItem(at: destination, to: sibling)
                    backup = sibling
                } catch {
                    throw UpdateError.swapFailed(error.localizedDescription)
                }
            }
        }

        // `--noqtn` keeps the copy quarantine-free; ditto preserves extended attributes and the
        // signature, which a naive FileManager.copyItem does not reliably do for bundles.
        let copy = Shell.run(ditto, ["--noqtn", staged.appURL.path, destination.path])
        guard copy.ok else {
            try? fm.removeItem(at: destination)
            if let backup { try? fm.moveItem(at: backup, to: destination) }
            throw UpdateError.swapFailed(copy.message)
        }

        _ = Shell.run(xattr, ["-dr", "com.apple.quarantine", destination.path])

        // Only now is it safe to let go of the old build.
        if let backup { try? fm.removeItem(at: backup) }
        try? fm.removeItem(at: staged.stagingDirectory)
    }

    /// Spawns a shell that waits for this process to die, then reopens the app. Detached, so it
    /// survives our exit; bounded, so a wedged quit can't leave a shell spinning forever.
    @discardableResult
    public static func scheduleRelaunch(at appURL: URL) -> Bool {
        let script = """
        pid=$1; app=$2; i=0
        while /bin/kill -0 "$pid" 2>/dev/null && [ "$i" -lt 150 ]; do /bin/sleep 0.2; i=$((i+1)); done
        /bin/sleep 1
        \(open) "$app"
        """
        // Arguments rather than interpolation: no path ever reaches the shell as source text.
        return Shell.spawnDetached(sh, ["-c", script, "touchgrass-relaunch",
                                        String(ProcessInfo.processInfo.processIdentifier),
                                        appURL.path])
    }

    // MARK: - Verification

    private static func verifyChecksum(of file: URL, against expected: String) throws {
        let wanted = expected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard wanted.count == 64, wanted.allSatisfy({ $0.isHexDigit }) else {
            throw UpdateError.validationFailed("appcast has no usable sha256")
        }
        guard let actual = FileHash.sha256Hex(ofFileAt: file) else {
            throw UpdateError.downloadFailed("couldn't read the downloaded file")
        }
        guard actual == wanted else {
            throw UpdateError.checksumMismatch(expected: wanted, got: actual)
        }
    }

    /// Reads the unpacked bundle back and insists it is a newer TouchGrass — same bundle ID,
    /// the version the appcast promised, and an executable that actually exists.
    private static func validate(_ newApp: URL, release: Release, against current: InstalledApp) throws {
        let plistURL = newApp.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            throw UpdateError.validationFailed("no readable Info.plist")
        }

        guard let identifier = plist["CFBundleIdentifier"] as? String else {
            throw UpdateError.validationFailed("no bundle identifier")
        }
        guard identifier == current.bundleIdentifier else {
            throw UpdateError.validationFailed("bundle identifier is \(identifier), expected \(current.bundleIdentifier)")
        }

        let shortVersion = plist["CFBundleShortVersionString"] as? String ?? ""
        guard AppVersion(shortVersion) == AppVersion(release.version) else {
            throw UpdateError.validationFailed("archive is version \(shortVersion.isEmpty ? "unknown" : shortVersion), appcast promised \(release.version)")
        }

        let buildString = plist["CFBundleVersion"] as? String ?? "0"
        let buildNumber = Int(buildString) ?? 0
        let inArchive = Release(
            version: shortVersion, build: buildNumber,
            url: release.url, sha256: release.sha256
        )
        guard inArchive.isNewer(thanVersion: current.shortVersion, build: current.build) else {
            throw UpdateError.validationFailed("archive is not newer than the running \(current.shortVersion) (\(current.build))")
        }

        if let executable = plist["CFBundleExecutable"] as? String {
            let binary = newApp.appendingPathComponent("Contents/MacOS/\(executable)")
            guard FileManager.default.isExecutableFile(atPath: binary.path) else {
                throw UpdateError.validationFailed("no executable at Contents/MacOS/\(executable)")
            }
        }
    }

    /// Best-effort only. TouchGrass is ad-hoc signed with no Developer ID, so there is no team
    /// identifier to pin and no notarisation to check — `codesign --verify` still catches a
    /// bundle that was truncated or tampered with after signing, which is worth knowing about,
    /// but the checksum is what actually protects the download.
    private static func signatureComplaint(for app: URL) -> String? {
        let result = Shell.run(codesign, ["--verify", "--strict", "--deep", app.path])
        return result.ok ? nil : result.message
    }

    // MARK: - Files

    private static func makeStagingDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TouchGrassUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            throw UpdateError.unpackFailed("no temporary directory: \(error.localizedDescription)")
        }
        return base
    }

    private static func findAppBundle(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        // `__MACOSX` is zip's metadata sidecar, never the payload.
        return contents.first { $0.pathExtension == "app" && $0.lastPathComponent != "__MACOSX" }
    }
}
