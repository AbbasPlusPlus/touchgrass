// TGDetection — STUB. Aggregates all detectors into published PauseReasons / ActivityHint / idle.
import Foundation
import Combine
import TGCore

@MainActor
public final class ActivityMonitor: ObservableObject {
    @Published public private(set) var pauseReasons: Set<PauseReason> = []
    @Published public private(set) var activityHint: ActivityHint? = nil
    @Published public private(set) var idleSeconds: TimeInterval = 0

    public var settings: Settings
    public init(settings: Settings) { self.settings = settings }
    public func start() {}
    public func stop() {}
}
