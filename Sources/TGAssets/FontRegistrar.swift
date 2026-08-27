// TGAssets — registers the bundled Fraunces variable font (SIL OFL; license alongside the TTF).
// Registration is process-wide: call once at startup and every module can use the family by name.

import CoreText
import Foundation

public enum TGAssets {
    public static let serifFamily = "Fraunces"

    private static var registered = false

    public static func registerFonts() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.module.url(forResource: "Fraunces", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
