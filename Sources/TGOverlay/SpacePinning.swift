// TGOverlay — pins break windows into their own window-server space.
//
// Space swipes slide every window that belongs to a user Space — even `.canJoinAllSpaces` windows
// at screensaver/assistive levels (verified live on macOS 26; the window leaves with the outgoing
// Space's composite and pops back after). The only way to hold a window truly still is for it not
// to live in a user Space at all: create a private CGS space at a high absolute level, move the
// windows there, and show it. This is the technique  ships for the same problem.
//
// This is private SkyLight API — the ONE deliberate exception to the project's no-private-API rule
// (user-approved). Every symbol is dlsym-guarded: if any lookup fails, `pin` returns nil and the
// break screen simply keeps its all-Spaces behavior. Nothing here can crash on a missing symbol.

import AppKit

@MainActor
enum SpacePinning {

    struct Token {
        fileprivate let space: UInt64
        fileprivate let windowNumbers: [Int]
    }

    // MARK: - Symbols

    private typealias MainConnectionFn = @convention(c) () -> UInt32
    private typealias SpaceCreateFn = @convention(c) (UInt32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceDestroyFn = @convention(c) (UInt32, UInt64) -> Void
    private typealias SpaceSetLevelFn = @convention(c) (UInt32, UInt64, Int32) -> Void
    private typealias WindowsSpacesFn = @convention(c) (UInt32, CFArray, CFArray) -> Void
    private typealias ShowHideSpacesFn = @convention(c) (UInt32, CFArray) -> Void
    private typealias CopySpacesForWindowsFn = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func sym<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: type)
    }

    private static let mainConnection = sym("CGSMainConnectionID", as: MainConnectionFn.self)
    private static let spaceCreate = sym("CGSSpaceCreate", as: SpaceCreateFn.self)
    private static let spaceDestroy = sym("CGSSpaceDestroy", as: SpaceDestroyFn.self)
    private static let spaceSetLevel = sym("CGSSpaceSetAbsoluteLevel", as: SpaceSetLevelFn.self)
    private static let addWindows = sym("CGSAddWindowsToSpaces", as: WindowsSpacesFn.self)
    private static let removeWindows = sym("CGSRemoveWindowsFromSpaces", as: WindowsSpacesFn.self)
    private static let showSpaces = sym("CGSShowSpaces", as: ShowHideSpacesFn.self)
    private static let hideSpaces = sym("CGSHideSpaces", as: ShowHideSpacesFn.self)
    private static let copySpacesForWindows = sym("CGSCopySpacesForWindows", as: CopySpacesForWindowsFn.self)

    static var isAvailable: Bool {
        mainConnection != nil && spaceCreate != nil && spaceDestroy != nil && spaceSetLevel != nil
            && addWindows != nil && showSpaces != nil && hideSpaces != nil
    }

    // MARK: - Pin / unpin

    /// Moves the windows into a fresh always-visible space. Call after the windows are ordered in.
    static func pin(_ windows: [NSWindow]) -> Token? {
        guard isAvailable,
              let mainConnection, let spaceCreate, let spaceSetLevel,
              let addWindows, let showSpaces else { return nil }

        let cid = mainConnection()
        let space = spaceCreate(cid, 1, nil)
        guard space != 0 else { return nil }

        // Above every managed space (regular spaces are 0, fullscreen ~200s).
        spaceSetLevel(cid, space, 400)

        let numbers = windows.map(\.windowNumber).filter { $0 > 0 }
        guard !numbers.isEmpty else {
            spaceDestroy?(cid, space)
            return nil
        }
        let windowArray = numbers as CFArray

        // Take the windows out of the user Spaces they were auto-added to, so the swipe's
        // outgoing composite doesn't also carry a sliding copy.
        if let copySpacesForWindows, let removeWindows,
           let current = copySpacesForWindows(cid, 7, windowArray)?.takeRetainedValue() as? [UInt64] {
            let others = current.filter { $0 != space }
            if !others.isEmpty {
                removeWindows(cid, windowArray, others as CFArray)
            }
        }

        addWindows(cid, windowArray, [space] as CFArray)
        showSpaces(cid, [space] as CFArray)
        return Token(space: space, windowNumbers: numbers)
    }

    /// Tears the space down. The windows are being closed by the caller, so no re-adding needed.
    static func unpin(_ token: Token) {
        guard let mainConnection, let hideSpaces, let spaceDestroy else { return }
        let cid = mainConnection()
        hideSpaces(cid, [token.space] as CFArray)
        spaceDestroy(cid, token.space)
    }
}
