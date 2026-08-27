// TGDetection — microphone in-use detection + per-app attribution via CoreAudio.
//
// Two layers:
//   1. Device level — `kAudioDevicePropertyDeviceIsRunningSomewhere` on the *input* scope of every
//      device that has input channels. Cheap and push-based, but lies: Bluetooth mics (AirPods) read
//      0 while recording (Apple bug), and aggregate devices (BlackHole, Krisp) pin themselves to 1.
//   2. Process level — macOS 14.4+ audio process objects ('prs#') give the bundle ID ('pbid') of every
//      client and whether it is recording ('piri'). This is the layer the meeting policy trusts,
//      because "which app" is the entire question. Its listeners are unreliable, so we poll it.
// Neither layer prompts for permission or needs an entitlement (verified on macOS 26.6).
import CoreAudio
import Foundation

// MARK: - Model

public struct AudioInputDeviceInfo: Sendable, Hashable, Identifiable {
    public let objectID: AudioObjectID
    public let name: String
    public let uid: String
    public let transportType: UInt32
    public let inputChannels: Int
    public let isRunningSomewhere: Bool
    public let isExcluded: Bool

    public var id: AudioObjectID { objectID }
    public var transport: String { fourCharString(transportType) }
    /// AirPods & friends: `IsRunningSomewhere` is known to stay 0 while recording.
    public var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE
    }
    public var isAggregate: Bool {
        transportType == kAudioDeviceTransportTypeAggregate || transportType == kAudioDeviceTransportTypeAutoAggregate
    }
    public var countsAsRunning: Bool { isRunningSomewhere && !isExcluded }
}

/// One process currently holding the mic open.
public struct MicrophoneUser: Sendable, Hashable {
    public let audioObjectID: AudioObjectID
    public let pid: pid_t
    /// Exactly what CoreAudio reported, e.g. "com.tinyspeck.slackmacgap.helper".
    public let rawBundleID: String?
    /// Owning app after helper→parent resolution, e.g. "com.tinyspeck.slackmacgap".
    public let bundleID: String?
    public let appName: String?

    public var display: String { appName ?? bundleID ?? rawBundleID ?? "pid \(pid)" }
}

// MARK: - Detector

@MainActor
public final class MicrophoneDetector {

    /// Any non-excluded input device reports itself running. Unreliable on its own — see class notes.
    public private(set) var deviceLevelInUse: Bool = false
    public private(set) var devices: [AudioInputDeviceInfo] = []
    /// Processes with `kAudioProcessPropertyIsRunningInput == 1`, resolved to owning apps.
    public private(set) var recordingProcesses: [MicrophoneUser] = []
    /// False on < macOS 14.4 or if 'prs#' is refused — the policy then falls back to device level only.
    public private(set) var processAttributionAvailable: Bool = false
    /// Set when a Bluetooth input exists and process attribution disagrees with the device flag.
    public private(set) var bluetoothDeviceFlagSuspect: Bool = false
    /// Total CoreAudio client processes, and how many are *playing*. Not used by any policy — it is
    /// the only way to see the 'prs#'/'pbid' attribution pipeline working when nobody is recording.
    public private(set) var audioClientCount: Int = 0
    public private(set) var playbackProcesses: [MicrophoneUser] = []

    public var excludedUIDs: [String] = [] {
        didSet { if excludedUIDs != oldValue { refresh() } }
    }

    public var onChange: (@MainActor () -> Void)?

    /// Process-object listeners are documented-unreliable, so a slow poll backstops them.
    private let pollInterval: TimeInterval = 3
    private var poll: PollTimer?
    private var isRunning = false
    private var listeners: [Listener] = []
    private let queue = DispatchQueue(label: "com.touchgrass.mic-detector", qos: .utility)
    private let coalescer = OneShotTimer()
    /// audioObjectID → bundle ID; process objects are stable for the life of the client.
    private var bundleIDCache: [AudioObjectID: String] = [:]
    private var pidCache: [AudioObjectID: pid_t] = [:]

    private struct Listener {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    public init() {}

    // MARK: Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        addListener(on: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
        addListener(on: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultInputDevice)
        addListener(on: AudioObjectID(kAudioObjectSystemObject),
                    selector: AudioObjectPropertySelector(kAudioHardwarePropertyProcessObjectList))
        let timer = PollTimer(interval: pollInterval) { [weak self] in self?.refresh() }
        poll = timer
        timer.start()
        refresh()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        poll?.stop()
        poll = nil
        coalescer.cancel()
        removeAllListeners()
        devices = []
        recordingProcesses = []
        deviceLevelInUse = false
        bundleIDCache.removeAll()
        pidCache.removeAll()
    }

    // MARK: Reading

    public func refresh() {
        let excluded = Set(excludedUIDs.map { $0.lowercased() })
        let deviceIDs = Self.systemObjectIDs(kAudioHardwarePropertyDevices)

        var infos: [AudioInputDeviceInfo] = []
        for id in deviceIDs {
            let channels = Self.inputChannelCount(id)
            guard channels > 0 else { continue }
            let uid = Self.stringProperty(id, kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal) ?? ""
            infos.append(AudioInputDeviceInfo(
                objectID: id,
                name: Self.stringProperty(id, kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal) ?? "Input \(id)",
                uid: uid,
                transportType: Self.uint32Property(id, kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal) ?? 0,
                inputChannels: channels,
                isRunningSomewhere: (Self.uint32Property(id, kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                        scope: kAudioDevicePropertyScopeInput) ?? 0) != 0,
                isExcluded: excluded.contains(uid.lowercased())
            ))
        }

        if isRunning { syncDeviceListeners(for: infos.map(\.objectID)) }

        let users = readRecordingProcesses()

        let newDeviceLevel = infos.contains { $0.countsAsRunning }
        let btSuspect = infos.contains { $0.isBluetooth && !$0.isRunningSomewhere } && !users.isEmpty

        let changed = infos != devices || users != recordingProcesses || newDeviceLevel != deviceLevelInUse
        devices = infos
        recordingProcesses = users
        deviceLevelInUse = newDeviceLevel
        bluetoothDeviceFlagSuspect = btSuspect
        if changed { onChange?() }
    }

    /// Reads 'prs#' → for each process 'piri'; only the recorders pay for a 'pbid' + pid lookup.
    private func readRecordingProcesses() -> [MicrophoneUser] {
        let processObjects = Self.systemObjectIDs(AudioObjectPropertySelector(kAudioHardwarePropertyProcessObjectList))
        processAttributionAvailable = !processObjects.isEmpty
        audioClientCount = processObjects.count
        guard processAttributionAvailable else {
            playbackProcesses = []
            return []
        }

        let live = Set(processObjects)
        bundleIDCache = bundleIDCache.filter { live.contains($0.key) }
        pidCache = pidCache.filter { live.contains($0.key) }

        let resolver = ProcessAppResolver.shared
        var users: [MicrophoneUser] = []
        var playing: [MicrophoneUser] = []
        for object in processObjects {
            let recording = Self.uint32Property(object,
                                                AudioObjectPropertySelector(kAudioProcessPropertyIsRunningInput),
                                                scope: kAudioObjectPropertyScopeGlobal) ?? 0
            let outputting = Self.uint32Property(object,
                                                 AudioObjectPropertySelector(kAudioProcessPropertyIsRunningOutput),
                                                 scope: kAudioObjectPropertyScopeGlobal) ?? 0
            guard recording != 0 || outputting != 0 else { continue }

            let raw = bundleIDCache[object] ?? {
                let value = Self.stringProperty(object,
                                                AudioObjectPropertySelector(kAudioProcessPropertyBundleID),
                                                scope: kAudioObjectPropertyScopeGlobal) ?? ""
                bundleIDCache[object] = value
                return value
            }()
            let pid = pidCache[object] ?? {
                let value = Self.pidProperty(object) ?? 0
                pidCache[object] = value
                return value
            }()

            let identity = pid > 0 ? resolver.identity(for: pid) : nil
            // Prefer the resolved owner (Slack, not "Slack Helper"); fall back to CoreAudio's string.
            let owner = identity?.bundleID ?? (raw.isEmpty ? nil : raw)
            let user = MicrophoneUser(
                audioObjectID: object,
                pid: pid,
                rawBundleID: raw.isEmpty ? nil : raw,
                bundleID: owner,
                appName: identity?.name ?? identity?.processName
            )
            if recording != 0 { users.append(user) }
            if outputting != 0 { playing.append(user) }
        }
        playbackProcesses = playing.sorted { $0.audioObjectID < $1.audioObjectID }
        return users.sorted { $0.audioObjectID < $1.audioObjectID }
    }

    // MARK: Listeners

    private func scheduleRefresh() {
        coalescer.schedule(after: 0.15) { [weak self] in self?.refresh() }
    }

    private func addListener(on objectID: AudioObjectID,
                             selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            hopToMain { self?.scheduleRefresh() }
        }
        if AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block) == noErr {
            listeners.append(Listener(objectID: objectID, address: address, block: block))
        }
    }

    private func syncDeviceListeners(for ids: [AudioObjectID]) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let wanted = Set(ids)
        for listener in listeners where listener.objectID != system && !wanted.contains(listener.objectID) {
            remove(listener)
        }
        listeners.removeAll { $0.objectID != system && !wanted.contains($0.objectID) }

        let watched = Set(listeners.filter { $0.objectID != system }.map(\.objectID))
        for id in ids where !watched.contains(id) {
            addListener(on: id, selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                        scope: kAudioDevicePropertyScopeInput)
        }
    }

    private func remove(_ listener: Listener) {
        var address = listener.address
        _ = AudioObjectRemovePropertyListenerBlock(listener.objectID, &address, queue, listener.block)
    }

    private func removeAllListeners() {
        for listener in listeners { remove(listener) }
        listeners.removeAll()
    }

    // MARK: CoreAudio plumbing

    static func systemObjectIDs(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    static func inputChannelCount(_ deviceID: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func stringProperty(_ objectID: AudioObjectID,
                               _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    static func uint32Property(_ objectID: AudioObjectID,
                               _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func pidProperty(_ objectID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(mSelector: AudioObjectPropertySelector(kAudioProcessPropertyPID),
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    // MARK: Debug

    private static func describe(_ u: MicrophoneUser) -> String {
        let rawSuffix = (u.rawBundleID != nil && u.rawBundleID != u.bundleID) ? " raw=\(u.rawBundleID ?? "")" : ""
        return "\(u.display) bundle=\(u.bundleID ?? "nil") pid=\(u.pid)\(rawSuffix)"
    }

    public func debugDescription() -> String {
        var lines: [String] = []
        lines.append("mic: deviceLevelInUse=\(deviceLevelInUse) recorders=\(recordingProcesses.count) "
                     + "processAttribution=\(processAttributionAvailable ? "ok" : "UNAVAILABLE")"
                     + " audioClients=\(audioClientCount)"
                     + (bluetoothDeviceFlagSuspect ? " btFlagSuspect=true" : ""))
        for d in devices {
            var flags: [String] = []
            if d.isBluetooth { flags.append("bluetooth") }
            if d.isAggregate { flags.append("aggregate") }
            if d.isExcluded { flags.append("excluded") }
            lines.append("  · \(d.name) [\(d.transport)] ch=\(d.inputChannels) running=\(d.isRunningSomewhere)"
                         + (flags.isEmpty ? "" : " (\(flags.joined(separator: ",")))"))
        }
        if devices.isEmpty { lines.append("  · (no input devices)") }
        for u in recordingProcesses {
            lines.append("  → recording: " + Self.describe(u))
        }
        for u in playbackProcesses {
            lines.append("  ♪ playing:   " + Self.describe(u))
        }
        return lines.joined(separator: "\n")
    }
}
