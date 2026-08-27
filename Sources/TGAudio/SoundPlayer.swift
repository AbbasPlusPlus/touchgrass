// TGAudio — STUB.
import Foundation
import TGCore

@MainActor
public final class SoundPlayer {
    public init() {}
    public func play(_ style: SoundStyle, event: SoundEvent, volume: Double) {}
}
public enum SoundEvent { case breakStart, breakEnd, preBreak, wellness }
