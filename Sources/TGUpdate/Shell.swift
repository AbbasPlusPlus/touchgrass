// TGUpdate — a tiny synchronous process runner for ditto / xattr / codesign.
import Foundation

enum Shell {

    struct Result {
        let status: Int32
        let output: String
        let error: String
        var ok: Bool { status == 0 }
        /// stderr first — the tools we call put their diagnostics there.
        var message: String {
            let combined = (error + output).trimmingCharacters(in: .whitespacesAndNewlines)
            return combined.isEmpty ? "exit \(status)" : combined
        }
    }

    /// Blocking. Only ever called from a non-main-actor async context.
    static func run(_ tool: String, _ args: [String]) -> Result {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        task.standardInput = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return Result(status: -1, output: "", error: "couldn't run \(tool): \(error.localizedDescription)")
        }
        // Drain before waiting: a full 64 KB pipe buffer would otherwise deadlock the child.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return Result(
            status: task.terminationStatus,
            output: String(data: outData, encoding: .utf8) ?? "",
            error: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Fire-and-forget: the child outlives us on purpose (that's the relaunch).
    @discardableResult
    static func spawnDetached(_ tool: String, _ args: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do {
            try task.run()
            return true
        } catch {
            return false
        }
    }
}
