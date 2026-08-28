// TGAssets — registers the bundled Fraunces variable font (SIL OFL; license alongside the TTF).
// Registration is process-wide: call once at startup and every module can use the family by name.
//
// Deliberately does NOT use SwiftPM's generated `Bundle.module`: that accessor looks next to the
// executable and at the developer's absolute build path, then `fatalError`s. Inside a .app the
// resource bundle lives in Contents/Resources, so the accessor crashed on every Mac except the
// one the app was built on. If the font can't be found we simply skip registration — the UI
// falls back to the system serif rather than failing to launch.

import CoreText
import Foundation

public enum TGAssets {
    public static let serifFamily = "Fraunces"

    private static var registered = false
    private static let bundleName = "TouchGrass_TGAssets.bundle"

    public static func registerFonts() {
        guard !registered else { return }
        registered = true
        guard let url = fontURL() else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Search order: the app's Contents/Resources, the main bundle root (bare-executable layouts),
    /// and the directory next to the executable (SwiftPM `.build/<config>/` for demos and tests).
    private static func fontURL() -> URL? {
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent(bundleName)) }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName))
        if let exe = Bundle.main.executableURL {
            candidates.append(exe.deletingLastPathComponent().appendingPathComponent(bundleName))
        }
        for candidate in candidates {
            if let bundle = Bundle(url: candidate),
               let url = bundle.url(forResource: "Fraunces", withExtension: "ttf") {
                return url
            }
        }
        return nil
    }
}
