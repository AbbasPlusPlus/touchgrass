// TGMenuBar — the rounded translucent chrome behind the quick panel.
import AppKit

/// Builds the panel's background container: Tahoe glass when we can, a `.popover`
/// visual-effect view otherwise, and flat paper when Reduce Transparency is on.
///
/// The warm paper wash that keeps the material from reading gray is applied on the SwiftUI
/// side (`QuickPanelView`), where it can sit *over* the glass rather than behind it.
enum GlassBackground {

    /// Wraps `content` in a rounded translucent container sized to fill its superview.
    static func container(cornerRadius: CGFloat, content: NSView) -> NSView {
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = makeContainer(cornerRadius: cornerRadius, content: content)
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }

    // MARK: - Private

    private static func makeContainer(cornerRadius: CGFloat, content: NSView) -> NSView {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return makePaper(cornerRadius: cornerRadius, content: content)
        }
        if let glass = makeGlass(cornerRadius: cornerRadius, content: content) {
            return glass
        }
        return makeVisualEffect(cornerRadius: cornerRadius, content: content)
    }

    /// Reduce Transparency: the glass becomes flat paper2, one-for-one.
    ///
    /// An `NSBox` rather than a layer-backed `NSView`: `fillColor` keeps a *dynamic* NSColor
    /// dynamic, where assigning `layer.backgroundColor` would freeze whichever appearance
    /// happened to be current when the panel was built.
    private static func makePaper(cornerRadius: CGFloat, content: NSView) -> NSView {
        let paper = NSBox()
        paper.boxType = .custom
        paper.titlePosition = .noTitle
        paper.borderWidth = 0
        paper.fillColor = .tgPaper2
        paper.cornerRadius = cornerRadius
        paper.contentViewMargins = .zero
        paper.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: paper.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: paper.trailingAnchor),
            content.topAnchor.constraint(equalTo: paper.topAnchor),
            content.bottomAnchor.constraint(equalTo: paper.bottomAnchor),
        ])
        return paper
    }

    /// `NSGlassEffectView` is macOS 26+; the package deploys to 15.0, so on Sequoia this
    /// returns nil and the caller falls through to the `.popover` visual-effect view.
    private static func makeGlass(cornerRadius: CGFloat, content: NSView) -> NSView? {
        guard #available(macOS 26.0, *) else { return nil }
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.style = .regular
        glass.contentView = content
        // NSGlassEffectView reparents `contentView` into its own hierarchy; pin it there so the
        // content fills the glass regardless of how the framework chooses to lay it out.
        if let host = content.superview {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                content.topAnchor.constraint(equalTo: host.topAnchor),
                content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
        }
        return glass
    }

    private static func makeVisualEffect(cornerRadius: CGFloat, content: NSView) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }
}
