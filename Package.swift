// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TouchGrass",
    platforms: [.macOS("15.0")],
    targets: [
        // Pure-Swift domain: settings, break engine state machine. No AppKit. Fully unit-tested.
        .target(name: "TGCore"),
        // System signal detectors (camera/mic/video/fullscreen/idle/typing) -> PauseReason / ActivityHint.
        .target(name: "TGDetection", dependencies: ["TGCore"]),
        // Bundled fonts (Fraunces, OFL) + registrar.
        .target(name: "TGAssets", resources: [.process("Resources")]),
        // Sounds.
        .target(name: "TGAudio", dependencies: ["TGCore"], resources: [.process("Resources")]),
        // Break overlay, pre-break card, cursor pill, wellness nudges.
        .target(name: "TGOverlay", dependencies: ["TGCore", "TGAudio"]),
        // Self-update: appcast poll, download + SHA-256 verify, bundle swap, relaunch.
        .target(name: "TGUpdate", dependencies: ["TGCore"]),
        // Status item, quick panel, settings window.
        .target(name: "TGMenuBar", dependencies: ["TGCore", "TGUpdate"]),
        // App entry + wiring.
        .executableTarget(
            name: "TouchGrass",
            dependencies: ["TGCore", "TGDetection", "TGAudio", "TGOverlay", "TGMenuBar", "TGUpdate", "TGAssets"]
        ),
        // Dev-only executables (not bundled into the app).
        .executableTarget(name: "tg-sound-demo", dependencies: ["TGCore", "TGAudio"]),
        .executableTarget(name: "tg-probe", dependencies: ["TGCore", "TGDetection"]),
        .executableTarget(name: "tg-menubar-demo", dependencies: ["TGCore", "TGMenuBar", "TGAssets"]),
        .executableTarget(name: "tg-overlay-demo", dependencies: ["TGCore", "TGOverlay", "TGAssets"]),
        .testTarget(name: "TGCoreTests", dependencies: ["TGCore"]),
        .testTarget(name: "TGDetectionTests", dependencies: ["TGCore", "TGDetection"]),
        .testTarget(name: "TGUpdateTests", dependencies: ["TGUpdate"]),
    ],
)
