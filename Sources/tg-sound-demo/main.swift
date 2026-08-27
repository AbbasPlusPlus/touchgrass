// tg-sound-demo — plays every bundled TouchGrass sound in order, with labels.
//
//   swift run tg-sound-demo                    (bundle sits beside the binary)
//   build/TouchGrass.app/Contents/MacOS/…      (bundle in Contents/Resources)
//
// Exits non-zero if any of the 28 assets is missing, so it doubles as a check
// that `Bundle.module`-style resource lookup resolves in both layouts.

import Foundation
import TGAudio
import TGCore

MainActor.assumeIsolated { runDemo() }

// MARK: - Demo

@MainActor
func runDemo() {
    var volume = 0.8
    var gap: TimeInterval = 0.35
    // Every style that has assets, in Settings order. Driven off `allCases` so a
    // style added to the contract is played here without touching this file.
    var styles: [SoundStyle] = SoundStyle.allCases.filter { $0 != SoundStyle.none }
    var silent = false
    var preview = false

    var arguments = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = arguments.next() {
        switch argument {
        case "--volume":
            volume = arguments.next().flatMap(Double.init) ?? volume
        case "--gap":
            gap = arguments.next().flatMap(Double.init) ?? gap
        case "--style":
            guard let name = arguments.next(), let style = SoundStyle(rawValue: name),
                  style != SoundStyle.none else {
                fail("--style expects one of: " + styleNames)
            }
            styles = [style]
        case "--list":
            silent = true
        case "--preview":
            preview = true
        case "-h", "--help":
            say("""
                usage: tg-sound-demo [--style \(styleNames.replacingOccurrences(of: ", ", with: "|"))] \
                [--volume 0…1] [--gap SECONDS] [--list] [--preview]
                """)
            return
        default:
            fail("unknown argument: \(argument)")
        }
    }

    let player = SoundPlayer()
    say("resource bundle: \(SoundPlayer.resourceBundleURL?.path ?? "<not found>")")
    say("volume: \(volume) → gain \(SoundPlayer.perceptualGain(volume))\n")
    player.preloadAll()

    if preview {
        // Exercises preview()/stopAll(): each cue cuts the previous one off
        // mid-ring, which is what clicking around in Settings does.
        say("interrupting previews (should cross-fade, never click)")
        for style in styles {
            for event in SoundEvent.allCases {
                say("  ▶  \(style.rawValue)-\(event.rawValue)")
                player.preview(style, event: event)
                wait(0.45)
            }
        }
        player.stopAll()
        wait(0.3)
        return
    }

    var missing: [String] = []
    for style in styles {
        say("\(style.title.uppercased())")
        for event in SoundEvent.allCases {
            let name = "\(style.rawValue)-\(event.rawValue)"
            guard let url = player.url(for: style, event: event),
                  let duration = player.duration(for: style, event: event) else {
                say("  ✗  \(name)  — missing")
                missing.append(name)
                continue
            }
            say("  ▶  \(name.padding(toLength: 22, withPad: " ", startingAt: 0))"
                + String(format: "%5.2fs  ", duration) + url.lastPathComponent)
            guard !silent else { continue }
            player.play(style, event: event, volume: volume)
            wait(duration + gap)
        }
        say("")
    }

    guard missing.isEmpty else {
        fail("\(missing.count) missing asset(s): \(missing.joined(separator: ", "))")
    }
    say("all \(styles.count * SoundEvent.allCases.count) sounds played")
}

// MARK: - Helpers

/// The styles that ship with assets, for argument parsing and `--help`.
@MainActor
let styleNames = SoundStyle.allCases
    .filter { $0 != SoundStyle.none }
    .map(\.rawValue)
    .joined(separator: ", ")

func say(_ text: String) {
    print(text)
    fflush(stdout)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("tg-sound-demo: \(message)\n".utf8))
    exit(1)
}

/// Blocks while servicing the run loop, so AVAudioPlayer keeps feeding audio.
func wait(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}
