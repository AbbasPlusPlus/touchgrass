// TGUpdate — URLSession download with progress, bridged to async/await.
import Foundation

enum UpdateDownloader {

    /// Holds the KVO token. `Process`-free box so the escaping completion handler stays Sendable.
    private final class ObservationBox: @unchecked Sendable {
        var token: NSKeyValueObservation?
        func invalidate() { token?.invalidate(); token = nil }
        deinit { token?.invalidate() }
    }

    /// Fetches the appcast. `reloadIgnoringLocalCacheData` because raw.githubusercontent.com
    /// is aggressively cached and a stale appcast is worse than no appcast.
    static func fetchAppcast(from url: URL) async throws -> Release {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.isOffline {
            throw UpdateError.offline
        } catch {
            throw UpdateError.badAppcast(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.badAppcast("HTTP \(http.statusCode)")
        }
        do {
            return try Release.decode(data)
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.badAppcast(error.localizedDescription)
        }
    }

    /// Downloads `url` to `destination`, reporting 0…1 as it goes. The temporary file URLSession
    /// hands back is only valid inside the completion handler, so the move happens there.
    static func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let box = ObservationBox()
        defer { box.invalidate() }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            let task = URLSession.shared.downloadTask(with: request) { temporaryURL, response, error in
                if let error {
                    let urlError = error as? URLError
                    continuation.resume(
                        throwing: urlError?.isOffline == true
                            ? UpdateError.offline
                            : UpdateError.downloadFailed(error.localizedDescription)
                    )
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    continuation.resume(throwing: UpdateError.downloadFailed("HTTP \(http.statusCode)"))
                    return
                }
                guard let temporaryURL else {
                    continuation.resume(throwing: UpdateError.downloadFailed("no file returned"))
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: temporaryURL, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: UpdateError.downloadFailed(error.localizedDescription))
                }
            }
            box.token = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
                progress(p.fractionCompleted)
            }
            task.resume()
        }
    }
}

// MARK: - Helpers

private extension URLError {
    var isOffline: Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .timedOut:
            return true
        default:
            return false
        }
    }
}
