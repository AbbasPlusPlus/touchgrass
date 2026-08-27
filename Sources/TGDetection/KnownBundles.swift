// TGDetection — curated bundle-ID vocabulary used by the detection policies.
// Everything here is data + matching rules; no system calls.
import Foundation

// MARK: - Matching

/// Bundle-ID matching that tolerates helper processes.
///
/// macOS reports helper/XPC processes with derived bundle IDs — CoreAudio on this machine reports
/// `com.tinyspeck.slackmacgap.helper`, `company.thebrowser.browser.helper` and
/// `com.electron.wispr-flow.accessibility-mac-app` for Slack / Arc / Wispr Flow. A plain `==` against
/// a user's exclusion list would miss all of them, so every comparison is "equal, or a dotted
/// descendant of, case-insensitively".
public enum BundleMatch {

    public static func normalize(_ bundleID: String?) -> String? {
        guard let b = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty else { return nil }
        return b.lowercased()
    }

    /// True when `bundleID` is `entry` or a dotted descendant of it (`com.foo` matches `com.foo.helper`).
    public static func matches(_ bundleID: String?, entry: String) -> Bool {
        guard let b = normalize(bundleID), let e = normalize(entry) else { return false }
        return b == e || b.hasPrefix(e + ".")
    }

    public static func matches<S: Sequence>(_ bundleID: String?, anyOf entries: S) -> Bool where S.Element == String {
        guard normalize(bundleID) != nil else { return false }
        return entries.contains { matches(bundleID, entry: $0) }
    }

    /// Substring rule, for vendors that ship a dozen differently-named bundles (Webex, GoTo…).
    public static func contains<S: Sequence>(_ bundleID: String?, anyOf needles: S) -> Bool where S.Element == String {
        guard let b = normalize(bundleID) else { return false }
        return needles.contains { b.contains($0.lowercased()) }
    }
}

// MARK: - Known apps

public enum KnownBundles {

    /// Apps whose microphone use, on its own, is strong evidence of a call.
    public static let conferencing: Set<String> = [
        "us.zoom.xos",
        "us.zoom.videomeetings",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.microsoft.skypeforbusiness",
        "com.skype.skype",
        "com.tinyspeck.slackmacgap",
        "com.apple.facetime",
        "com.apple.avconferenced",
        "com.discordapp.discord",
        "com.hnc.discord",
        "com.google.chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",   // Meet PWA
        "com.readdle.spark",
        "com.bluejeansnet.bluejeans",
        "com.gotomeeting.gotomeeting",
        "com.logmein.gotomeeting",
        "com.ringcentral.glip",
        "com.pop.pop",
        "com.around.around",
        "co.teamflowhq.teamflow",
        "com.gather.town",
        "com.whereby.whereby",
        "com.jitsi.jitsi-meet",
        "com.8x8.workspace",
        "com.dialpad.dialpad",
        "com.zoom.workplace",
        "net.whatsapp.whatsapp",
        "com.facebook.archon",                                       // Messenger
        "org.telegram.desktop",
        "ru.keepcoder.telegram",
        "com.tdesktop.telegram",
        "com.apple.identityservicesd",
        "com.loom.desktop",
        "com.highfidelity.spatial",
    ]

    /// Vendors with many bundle IDs — matched by substring.
    public static let conferencingNeedles: [String] = [
        "webex",
        "gotomeeting",
        "bluejeans",
        "chime.amazon",
        "amazonchime",
        "zoom.us",
    ]

    /// Any browser can be a Google Meet / Teams-web / Whereby tab, so browser mic use counts as a call.
    public static let browsers: Set<String> = [
        "com.apple.safari",
        "com.apple.safaritechnologypreview",
        "com.google.chrome",
        "com.google.chrome.beta",
        "com.google.chrome.dev",
        "com.google.chrome.canary",
        "org.chromium.chromium",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.beta",
        "com.microsoft.edgemac.dev",
        "com.microsoft.edgemac.canary",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "com.brave.browser",
        "com.brave.browser.beta",
        "com.brave.browser.nightly",
        "com.vivaldi.vivaldi",
        "com.operasoftware.opera",
        "com.operasoftware.operagx",
        "com.operasoftware.operadeveloper",
        "company.thebrowser.browser",       // Arc
        "company.thebrowser.dia",
        "com.sigmaos.sigmaos.macos",
        "com.pushplaylabs.sidekick",
        "com.kagi.kagimacos",               // Orion
        "org.torproject.torbrowser",
        "com.naver.whale",
        "ru.yandex.desktop.yandex-browser",
        "com.coccoc.coccoc",
        "com.zenbrowser.zen",
        "app.zen-browser.zen",
        "io.github.zen-browser.zen",
        "com.island.island",
        "com.openai.chat",                  // ChatGPT desktop hosts calls too
        "com.perplexity.comet",
    ]

    /// Apps that hold display-sleep assertions for reasons unrelated to watching something.
    public static let caffeinators: Set<String> = [
        "com.if.amphetamine",
        "net.domzilla.caffeine",
        "com.stick.app.jiggler",
        "co.marcoedwards.caffeine",
        "com.lightheadsw.caffeine",
        "com.newmarcel.keepingyouawake",
        "org.softwarebysteve.caffeinated",
        "com.dmitriyvasilyev.mousejigglerapp",
        "com.jiggler.jiggler",
        "com.mysticalbits.",        // another break app holding assertions
        "com.apple.screensaver",
    ]

    /// Game launchers, Windows-compat wrappers, and games that ship without a games
    /// `LSApplicationCategoryType`. Matched with `BundleMatch`, so helper bundles
    /// (`com.valvesoftware.steam.helper`, `net.minecraft.launcher`) are covered too.
    ///
    /// Only consulted for the app that is *currently fullscreen* — Parallels or CrossOver windowed on
    /// a desktop is not a game session, and Steam's own storefront window never goes fullscreen.
    public static let gameApps: Set<String> = [
        "com.valvesoftware.steam",              // + steam.helper, steamhelper…
        "com.valvesoftware.steamhelper",
        "com.mojang.minecraftlauncher",
        "net.minecraft",                        // net.minecraft.* (vanilla, MultiMC forks)
        "com.epicgames.epicgameslauncher",
        "net.battle.app",                       // Battle.net
        "com.blizzard.worldofwarcraft",
        "com.gog.galaxy",
        "com.codeweavers.crossover",
        "com.isaacmarovitz.whisky",
        "com.parallels.desktop.console",
        "org.prismlauncher.prismlauncher",
        "com.riotgames.leagueoflegends",
    ]

    /// Matched against the assertion's `Process Name` (CLI tools have no bundle ID).
    public static let caffeinatorProcessNames: Set<String> = [
        "caffeinate",
        "amphetamine",
        "caffeine",
        "jiggler",
        "mousejiggler",
        "keepingyouawake",
    ]

    // MARK: Queries

    public static func isConferencing(_ bundleID: String?) -> Bool {
        BundleMatch.matches(bundleID, anyOf: conferencing) || BundleMatch.contains(bundleID, anyOf: conferencingNeedles)
    }

    public static func isBrowser(_ bundleID: String?) -> Bool {
        BundleMatch.matches(bundleID, anyOf: browsers)
    }

    /// Camera/mic use by these means "a call is happening".
    public static func isMeetingCapable(_ bundleID: String?) -> Bool {
        isConferencing(bundleID) || isBrowser(bundleID)
    }

    /// True for the `LSApplicationCategoryType` values Apple assigns to games:
    /// `public.app-category.games` and the per-genre `public.app-category.<genre>-games`
    /// (action-games, puzzle-games, role-playing-games, …). Pure — the caller reads the plist.
    public static func isGameCategory(_ category: String?) -> Bool {
        guard let raw = category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return false }
        let prefix = "public.app-category."
        guard raw.hasPrefix(prefix) else { return false }
        return raw.dropFirst(prefix.count).contains("games")
    }

    /// Launchers / wrappers / games that carry no games category of their own.
    public static func isGameBundle(_ bundleID: String?) -> Bool {
        BundleMatch.matches(bundleID, anyOf: gameApps)
    }

    /// The full "is this a game?" rule: an App Store games category, or a known game bundle.
    public static func isGame(bundleID: String?, category: String?) -> Bool {
        isGameCategory(category) || isGameBundle(bundleID)
    }

    public static func isCaffeinator(bundleID: String?, processName: String?) -> Bool {
        if BundleMatch.matches(bundleID, anyOf: caffeinators) { return true }
        guard let name = processName?.lowercased(), !name.isEmpty else { return false }
        return caffeinatorProcessNames.contains(name)
    }
}
