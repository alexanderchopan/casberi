import UIKit

/// The Mac menu bar's SYSTEM half (2026-07-31) — the two things SwiftUI's
/// `Commands` layer verifiably cannot reach, both recorded as verified-live
/// dead ends in `CasberiApp.swift` on 2026-07-28 and left untried until now.
///
/// **1. ⌘F was unreachable.** A custom "Find…" declared in `Commands` compiles
/// and silently never fires: Mac Catalyst synthesizes its own Find submenu
/// (Find… / Find & Replace / Find Next / Find Previous) and keeps the whole
/// thing permanently DISABLED in an app with no `NSTextFinder`-compatible text
/// view — but the key equivalent is still claimed, so ⌘F did nothing at all.
/// Removing that menu hands the shortcut back, and the app's own Find (§215's
/// deterministic door, promoted out of the risen composer on 2026-07-30 for
/// being undiscoverable) finally answers the one keystroke every Mac user
/// tries first.
///
/// **2. Four dead controls sat in the File menu.** Duplicate / Move / Rename… /
/// Export As… are synthesized for document-based apps; this app has no document
/// model, so none of them can do anything — the honesty law ("no dead controls,
/// no fake status") broken by scaffolding rather than by us, but broken in our
/// own menu bar all the same. They are not reachable through `CommandGroup` at
/// any placement; `UIMenuBuilder` is the only door.
///
/// **Both identifiers are MEASURED, not guessed** (Mac Catalyst, 2026-07-31 —
/// see the probe below). That distinction earned its keep immediately: the
/// first cut matched File's children on the substrings "duplicate/move/rename/
/// export" and would have removed nothing, because the four live inside a
/// group called `com.apple.menu.document` whose own identifier contains none of
/// those words. What the File menu actually holds:
///
///     com.apple.menu.new-item                     → New Thing… (ours, ⌘N)
///     com.apple.menu.open                         → Open… · Open Recent
///     com.apple.menu.close                        → Close
///     com.apple.swiftui.synthesized.importExport  → (empty)
///     com.apple.menu.document                     → Duplicate · Move · Rename… · Export As…
///
/// Only `com.apple.menu.document` is removed, and only after reading what was
/// inside it. The empty SwiftUI group renders nothing and is left alone; the
/// Open group is left alone too, deliberately — "Open Recent" is a system
/// affordance, not something this pass measured a verdict on.
#if targetEnvironment(macCatalyst)
extension AppDelegate {

    /// Catalyst's document scaffolding, holding the four verbs an app with no
    /// document model can never perform.
    private static let documentMenu = UIMenu.Identifier("com.apple.menu.document")

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        // Only the menu BAR. Context menus and the responder chain's own
        // builds come through here too, and neither has a File menu to edit.
        guard builder.system == .main else { return }

        // ⌘F, reclaimed. The app's own Find is added by `CasberiApp.commands`
        // in the Edit menu; SwiftUI installs that during this same build and
        // it lives in a different menu, so removing `.find` cannot take it too.
        builder.remove(menu: .find)
        builder.remove(menu: Self.documentMenu)

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "macMenuProbe") { dumpMenus(builder) }
        #endif
    }

    #if DEBUG
    /// `-macMenuProbe YES` — the menu-bar probe, in the launch-arg style every
    /// other hook in this app uses.
    ///
    /// It also writes a FILE, which no sibling probe does, and that is measured
    /// rather than decorative: a Catalyst app's `NSLog` could not be read back
    /// from the unified log on this host at all (`log show` returned nothing
    /// for the process at any level, launched either through `open` or
    /// directly), and the menu bar is precisely the surface no screenshot-free
    /// check can otherwise see. It lands in the app's own container:
    ///
    ///     ~/Library/Containers/com.casberi.app/Data/tmp/casberi-menu-dump.txt
    ///
    /// Read it after a launch to re-measure this file's two claims — that
    /// `com.apple.menu.document` still holds the four dead verbs, and that the
    /// system Find menu is gone while our own "Find…" stands in Edit — and to
    /// see whether the walk commands are live, since `canWalk` renders as
    /// `[disabled]` here. One line per row, never one joined `NSLog`: that is
    /// the `-todayProbe` truncation lesson.
    private func dumpMenus(_ builder: UIMenuBuilder) {
        let menus: [UIMenu.Identifier] = [
            .file, .edit, UIMenu.Identifier("com.apple.menu.view"),
        ]
        var lines: [String] = []
        for id in menus {
            guard let menu = builder.menu(for: id) else { continue }
            lines.append(id.rawValue)
            for child in menu.children {
                lines.append("  \(Self.identifier(of: child)) — \(child.title)")
                guard let sub = child as? UIMenu else { continue }
                for grand in sub.children {
                    lines.append("      · \(Self.identifier(of: grand)) — "
                                 + grand.title + Self.enabledNote(grand))
                }
            }
        }
        for line in lines { NSLog("[Casberi] macMenu| %@", line) }
        try? lines.joined(separator: "\n")
            .write(toFile: NSTemporaryDirectory() + "casberi-menu-dump.txt",
                   atomically: true, encoding: .utf8)
    }

    /// Whether a leaf item is greyed. `attributes` lives on the concrete leaf
    /// types (`UIAction`, `UICommand` — which `UIKeyCommand` and SwiftUI's own
    /// menu items subclass), never on the `UIMenuElement` base, so both are
    /// asked. This is the line that answers "does the walk actually work":
    /// `canWalk` false renders Next/Previous Item disabled, which is also the
    /// state that hands ↑/↓ back to whatever should have them.
    private static func enabledNote(_ element: UIMenuElement) -> String {
        let disabled = (element as? UIAction)?.attributes.contains(.disabled)
            ?? (element as? UICommand)?.attributes.contains(.disabled)
        return disabled == true ? " [disabled]" : ""
    }

    /// A menu element's own identifier, whichever kind it is. Catalyst nests
    /// most File children as inline `UIMenu` groups rather than bare actions,
    /// so both cases have to be read. DEBUG-only, like its one caller.
    private static func identifier(of element: UIMenuElement) -> String {
        if let menu = element as? UIMenu { return menu.identifier.rawValue }
        if let action = element as? UIAction { return action.identifier.rawValue }
        return ""
    }
    #endif
}
#endif
