// TGDetection — camera in-use detection via CoreMediaIO.
//
// `kCMIODevicePropertyDeviceIsRunningSomewhere` tells us a camera is streaming *for any process*,
// with no TCC prompt, no usage string and no orange indicator, because we never open the device.
// Two gotchas, both verified on macOS 26.6:
//   • the property must be read with WILDCARD scope+element ('****' / 0xFFFFFFFF); the "main"
//     element returns kCMIOHardwareUnknownPropertyError on several devices.
//   • sandboxed builds need `com.apple.security.device.camera` or the device list is silently EMPTY
//     (still no prompt — the entitlement alone doesn't trigger TCC).
import CoreMediaIO
import Foundation

// MARK: - Model

/// FourCC transport types — CoreMediaIO reuses CoreAudio's vocabulary but ships no constants.
enum CameraTransport {
    static let virtual: UInt32 = 0x7669_7274   // 'virt' — OBS / Camo / mmhmm DAL plug-ins
    static let screen: UInt32 = 0x7363_726E    // 'scrn' — screen-capture pseudo devices
}

public struct CameraDeviceInfo: Sendable, Hashable, Identifiable {
    public let objectID: UInt32
    public let name: String
    public let uid: String
    public let modelUID: String
    public let transportType: UInt32
    public let isRunning: Bool
    public let isExcluded: Bool

    public var id: UInt32 { objectID }
    public var transport: String { fourCharString(transportType) }

    /// OBS / Camo / mmhmm style DAL plug-ins report 'virt'. They frequently pin themselves "running",
    /// so they must not by themselves mean "the user is on a call".
    public var isVirtual: Bool {
        transportType == CameraTransport.virtual || transportType == CameraTransport.screen
    }

    /// Counts toward "camera is on".
    public var isMeaningfullyRunning: Bool { isRunning && !isVirtual && !isExcluded }
}

// MARK: - Detector

@MainActor
public final class CameraDetector {

    public private(set) var devices: [CameraDeviceInfo] = []
    /// True when at least one real, non-excluded camera is streaming.
    public private(set) var isCameraInUse: Bool = false
    public private(set) var activeDevices: [CameraDeviceInfo] = []
    /// Non-nil if CoreMediaIO refused to answer (sandbox without the camera entitlement).
    public private(set) var lastError: OSStatus?

    /// Device UIDs the user opted out of (`Settings.excludedDeviceUIDs`).
    public var excludedUIDs: [String] = [] {
        didSet { if excludedUIDs != oldValue { refresh() } }
    }

    public var onChange: (@MainActor () -> Void)?

    private var isRunning = false
    private var listeners: [Listener] = []
    private let queue = DispatchQueue(label: "com.touchgrass.camera-detector", qos: .utility)
    private let coalescer = OneShotTimer()

    private struct Listener {
        let objectID: CMIOObjectID
        var address: CMIOObjectPropertyAddress
        let block: CMIOObjectPropertyListenerBlock
    }

    public init() {}


    // MARK: Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        installDeviceListListener()
        refresh()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        coalescer.cancel()
        removeAllListeners()
        devices = []
        activeDevices = []
        isCameraInUse = false
    }

    // MARK: Reading

    /// Re-reads the device list and every device's running state, then re-arms per-device listeners.
    public func refresh() {
        let ids = Self.deviceIDs(error: &lastErrorStorage)
        lastError = lastErrorStorage == noErr ? nil : lastErrorStorage

        let excluded = Set(excludedUIDs.map { $0.lowercased() })
        let infos: [CameraDeviceInfo] = ids.map { id in
            let uid = Self.stringProperty(id, kCMIODevicePropertyDeviceUID) ?? ""
            return CameraDeviceInfo(
                objectID: id,
                name: Self.stringProperty(id, kCMIOObjectPropertyName) ?? "Camera \(id)",
                uid: uid,
                modelUID: Self.stringProperty(id, kCMIODevicePropertyModelUID) ?? "",
                transportType: Self.uint32Property(id, kCMIODevicePropertyTransportType) ?? 0,
                isRunning: (Self.uint32Property(id, kCMIODevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0,
                isExcluded: excluded.contains(uid.lowercased())
            )
        }

        if isRunning { syncDeviceListeners(for: ids) }

        let active = infos.filter { $0.isMeaningfullyRunning }
        let changed = infos != devices || active.map(\.objectID) != activeDevices.map(\.objectID)
        devices = infos
        activeDevices = active
        isCameraInUse = !active.isEmpty
        if changed { onChange?() }
    }

    private var lastErrorStorage: OSStatus = noErr

    // MARK: Listeners

    private func scheduleRefresh() {
        coalescer.schedule(after: 0.15) { [weak self] in self?.refresh() }
    }

    private func installDeviceListListener() {
        var address = Self.address(kCMIOHardwarePropertyDevices)
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            hopToMain { self?.scheduleRefresh() }
        }
        let status = CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, queue, block)
        if status == noErr {
            listeners.append(Listener(objectID: CMIOObjectID(kCMIOObjectSystemObject), address: address, block: block))
        }
    }

    /// Adds an `IsRunningSomewhere` listener for every device we don't already watch, and drops the
    /// ones that went away (hot-unplug).
    private func syncDeviceListeners(for ids: [CMIOObjectID]) {
        let wanted = Set(ids)
        let systemObject = CMIOObjectID(kCMIOObjectSystemObject)

        for listener in listeners where listener.objectID != systemObject && !wanted.contains(listener.objectID) {
            remove(listener)
        }
        listeners.removeAll { $0.objectID != systemObject && !wanted.contains($0.objectID) }

        let watched = Set(listeners.map(\.objectID))
        for id in ids where !watched.contains(id) {
            var address = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                hopToMain { self?.scheduleRefresh() }
            }
            if CMIOObjectAddPropertyListenerBlock(id, &address, queue, block) == noErr {
                listeners.append(Listener(objectID: id, address: address, block: block))
            }
        }
    }

    private func remove(_ listener: Listener) {
        var address = listener.address
        _ = CMIOObjectRemovePropertyListenerBlock(listener.objectID, &address, queue, listener.block)
    }

    private func removeAllListeners() {
        for listener in listeners { remove(listener) }
        listeners.removeAll()
    }

    // MARK: CoreMediaIO plumbing

    /// Wildcard scope + element: required for `IsRunningSomewhere` to answer on every device.
    static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
    }

    static func deviceIDs(error: inout OSStatus) -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var dataSize: UInt32 = 0
        let sizeStatus = CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else {
            error = sizeStatus
            return []
        }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, dataSize, &used, &ids)
        guard status == noErr else {
            error = status
            return []
        }
        error = noErr
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    static func stringProperty(_ objectID: CMIOObjectID, _ selector: Int) -> String? {
        var address = address(selector)
        var value: CFString?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            CMIOObjectGetPropertyData(objectID, &address, 0, nil, size, &used, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    static func uint32Property(_ objectID: CMIOObjectID, _ selector: Int) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(objectID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
        guard status == noErr else { return nil }
        return value
    }

    // MARK: Debug

    public func debugDescription() -> String {
        var lines: [String] = []
        lines.append("camera: inUse=\(isCameraInUse) devices=\(devices.count)" + (lastError.map { " error=\($0)" } ?? ""))
        for d in devices {
            var flags: [String] = []
            if d.isVirtual { flags.append("virtual") }
            if d.isExcluded { flags.append("excluded") }
            lines.append("  · \(d.name) [\(d.transport)] running=\(d.isRunning)\(flags.isEmpty ? "" : " (\(flags.joined(separator: ",")))") uid=\(d.uid)")
        }
        if devices.isEmpty { lines.append("  · (no CoreMediaIO devices — sandbox without com.apple.security.device.camera?)") }
        return lines.joined(separator: "\n")
    }
}
