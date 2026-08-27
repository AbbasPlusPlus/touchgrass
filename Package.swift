// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TouchGrass",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure-Swift domain: settings, break engine state machine. No AppKit. Fully unit-tested.
        .target(name: "TGCore"),
        // System signal detectors (camera/mic/video/fullscreen/idle/typing) -> PauseReason / ActivityHint.
        .target(name: "TGDetection", dependencies: ["TGCore"]),
        // Sounds.
        .target(name: "TGAudio", dependencies: ["TGCore"], resources: [.process("Resources")]),
        // Break overlay, pre-break card, cursor pill, wellness nudges.
        .target(name: "TGOverlay", dependencies: ["TGCore", "TGAudio"]),
        // Status item, quick panel, settings window.
        .target(name: "TGMenuBar", dependencies: ["TGCore"]),
        // App entry + wiring.
        .executableTarget(
            name: "TouchGrass",
            dependencies: ["TGCore", "TGDetection", "TGAudio", "TGOverlay", "TGMenuBar"]
        ),
        // Standalone harness for the menu bar surfaces (status item, quick panel,
        // settings, onboarding) so they can be run and screenshotted without the full app.
        .executableTarget(name: "tg-menubar-demo", dependencies: ["TGCore", "TGMenuBar"]),
        .testTarget(name: "TGCoreTests", dependencies: ["TGCore"]),
    ],
)
