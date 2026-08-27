// Fullscreen auto-pause only fires for games, and the "is this a game?" rule is the one pure
// function in that path: an `LSApplicationCategoryType` in the games family, or a known launcher.
import Foundation
import Testing
@testable import TGDetection

// MARK: - Category matching

@Test func plainGamesCategoryMatches() {
    #expect(KnownBundles.isGameCategory("public.app-category.games"))
}

@Test func genreGameCategoriesMatch() {
    let genres = [
        "action", "adventure", "arcade", "board", "card", "casino", "dice", "educational",
        "family", "kids", "music", "puzzle", "racing", "role-playing", "simulation", "sports",
        "strategy", "trivia", "word",
    ]
    for genre in genres {
        #expect(KnownBundles.isGameCategory("public.app-category.\(genre)-games"),
                "expected \(genre)-games to be a game category")
    }
}

@Test func nonGameCategoriesDoNotMatch() {
    let others = [
        "public.app-category.developer-tools",
        "public.app-category.productivity",
        "public.app-category.video",
        "public.app-category.entertainment",
        "public.app-category.graphics-design",
        "public.app-category.utilities",
        "public.app-category.social-networking",
    ]
    for category in others {
        #expect(!KnownBundles.isGameCategory(category), "expected \(category) to not be a game")
    }
}

@Test func categoryMatchIsCaseAndWhitespaceInsensitive() {
    #expect(KnownBundles.isGameCategory("  PUBLIC.APP-CATEGORY.Action-Games\n"))
}

@Test func categoryMustCarryApplePrefix() {
    // A vendor writing something game-ish but non-standard is not enough to auto-pause.
    #expect(!KnownBundles.isGameCategory("games"))
    #expect(!KnownBundles.isGameCategory("com.example.games"))
    #expect(!KnownBundles.isGameCategory("public.category.games"))
}

@Test func missingOrEmptyCategoryIsNotAGame() {
    #expect(!KnownBundles.isGameCategory(nil))
    #expect(!KnownBundles.isGameCategory(""))
    #expect(!KnownBundles.isGameCategory("   "))
}

// MARK: - Known bundles

@Test func knownLaunchersAreGames() {
    for bundle in ["com.valvesoftware.steam",
                   "com.mojang.minecraftlauncher",
                   "com.epicgames.EpicGamesLauncher",
                   "net.battle.app",
                   "com.gog.galaxy",
                   "com.codeweavers.CrossOver",
                   "com.isaacmarovitz.Whisky",
                   "com.parallels.desktop.console"] {
        #expect(KnownBundles.isGameBundle(bundle), "expected \(bundle) to be a known game bundle")
    }
}

@Test func knownGameHelperBundlesMatch() {
    #expect(KnownBundles.isGameBundle("com.valvesoftware.steam.helper"))
    #expect(KnownBundles.isGameBundle("net.minecraft.launcher"))
}

@Test func ordinaryAppsAreNotGameBundles() {
    for bundle in ["com.apple.dt.Xcode", "com.apple.TextEdit", "com.google.Chrome",
                   "com.figma.Desktop", "com.t3.code", nil] {
        #expect(!KnownBundles.isGameBundle(bundle), "expected \(bundle ?? "nil") to not be a game")
    }
}

// MARK: - Combined rule

@Test func editorInFullscreenIsNotAGame() {
    // The reported bug: an editor fullscreen must not auto-pause.
    #expect(!KnownBundles.isGame(bundleID: "com.t3.code", category: "public.app-category.developer-tools"))
}

@Test func eitherSignalIsEnough() {
    #expect(KnownBundles.isGame(bundleID: "com.example.unknown", category: "public.app-category.action-games"))
    #expect(KnownBundles.isGame(bundleID: "com.valvesoftware.steam", category: nil))
    #expect(!KnownBundles.isGame(bundleID: nil, category: nil))
}
