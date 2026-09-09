import SwiftUI
import UIKit

/// The app-switcher / lock-screen cover (goal 6): leaving the app must not leak
/// the corpus into the snapshot iOS takes on the way out.
///
/// **A UIWindow, NOT `.redacted` ON THE SHELL (2026-09-05).** This was
/// `RootShell`'s `.redacted(reason: redactNow ? .placeholder : [])`, applied to
/// `shellBase` — the root of the whole app — and flipped in
/// `handleDeactivation`. `RedactionReasons` is an environment value, so setting
/// it at the root invalidates EVERY view in the tree, and the resulting
/// full-graph update lands in the exact `CATransaction` UIKit commits to take
/// the snapshot. Foreground that is merely slow; backgrounded it is fatal, and
/// it reached two devices:
///
///   • build 521, 2026-09-05 22:29 — `0x8BADF00D`, scene-update watchdog,
///     "exhausted real (wall clock) time allowance of 10.00 seconds", main
///     thread inside `-[UIApplication _createSnapshotContextForScene:…]` →
///     `CA::Transaction::commit` → `ViewRendererHost.render` →
///     `ForEachChild.updateValue()` → `AG::LayoutDescriptor::Compare` eight
///     frames deep → `String._unconditionallyBridgeFromObjectiveC`.
///   • build 511, 2026-09-05 00:07 — the same watchdog on the same device, same
///     full-graph update (`AG::Subgraph::update`), flushed by the ordinary
///     update sequence rather than the snapshot context.
///
/// **The 10 seconds is wall clock, and a backgrounded app is throttled.** Both
/// reports say so in their own CPU statistics: 10.279s of application CPU at
/// **16%**, and 7.723s at **13%**. So a render that costs a second and a half
/// of CPU — which a feed of up to `allRoomFetchLimit` rows plainly can, since
/// `FeedRow`'s payloads carry SwiftData-backed strings that AttributeGraph
/// bridges out of Objective-C one at a time to diff them — takes more than ten
/// seconds of wall clock in the background and the watchdog kills it. Making
/// the render faster would raise the corpus size at which this happens; it
/// would not change that it happens. Not rendering at all does.
///
/// A window costs one view and touches the app's SwiftUI graph not at all, and
/// it is strictly the safer hide as well. `.redacted(.placeholder)` blanks Text
/// and shapes but **not Image**, so every image view had to opt out by hand
/// (`PhotoWell`, `PhotoViewer`, and `GenRenderer`'s echo picture all read
/// `\.redactionReasons` for exactly that reason) and any new one leaked by
/// default. It also could not cover a PRESENTED sheet reliably — and the
/// thing sheet is where a screenshot is shown full-bleed. An opaque window at
/// `.alert + 1` is above the root view, above every sheet, above the composer.
///
/// Those `\.redactionReasons` readers are deliberately left in place: they are
/// correct under any redaction and cost one environment read, and deleting them
/// would make re-introducing a redaction anywhere a silent leak.
///
/// **PER SCENE, and the first cut of this file got that wrong.** The app
/// declares `UIApplicationSupportsMultipleScenes`, so there can be two windows
/// each with their own `RootShell`. A single process-wide cover placed on
/// "whichever scene has a key window" is the accessor `SceneState` documents a
/// ruling against (2026-08-02), and it fails both ways here: backgrounding one
/// iPad window would cover the OTHER, still-visible one — with no way back,
/// since that window's `handleActivation` never fires while it stays active —
/// and two windows leaving together would cover one of them twice and the
/// other never. `RootShell` already reads its OWN scene off its own `UIWindow`
/// (`WindowSceneReader`); the cover is keyed on it.
@MainActor
enum PrivacyCover {
    private static var windows: [ObjectIdentifier: UIWindow] = [:]
    /// Bumped per scene by every `show`. A fade started by `hide` captures it
    /// and declines to tear anything down if it has moved — see `hide`.
    private static var generations: [ObjectIdentifier: Int] = [:]

    /// Up on the FIRST frame, never animated. The snapshot is taken
    /// immediately after the scene resigns active, so a fade in would be
    /// photographed half-transparent.
    ///
    /// `scene` is the caller's OWN window scene. It is optional only because
    /// `RootShell` resolves it on its probe's `didMoveToWindow`, which is not
    /// ordered against the scene-phase observer — and a nil there covers EVERY
    /// connected scene rather than guessing one. Over-covering is
    /// self-correcting (each window's own `RootShell` lowers its own cover on
    /// its own activation); guessing is the bug this file's header describes.
    static func show(on scene: UIWindowScene?) {
        let targets = scene.map { [$0] }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for target in targets { raise(on: target) }
    }

    /// Returning crossfades back to the corpus (§14), matching the 0.2s
    /// ease-out the redaction used to clear with. A nil scene lowers every
    /// cover, the mirror of `show`'s fallback.
    static func hide(on scene: UIWindowScene?) {
        let keys = scene.map { [ObjectIdentifier($0)] } ?? Array(windows.keys)
        for key in keys { lower(key) }
    }

    private static func raise(on scene: UIWindowScene) {
        prune()
        let key = ObjectIdentifier(scene)
        generations[key, default: 0] &+= 1
        if let existing = windows[key] {
            // A leave landing inside a previous return's fade — take the SAME
            // window back at full alpha rather than stacking a second one at
            // the same window level, where the two would order undefined and
            // the snapshot could catch a half-transparent cover over content.
            existing.layer.removeAllAnimations()
            existing.alpha = 1
            existing.isHidden = false
            return
        }
        let host = UIHostingController(rootView: CoverContent())
        host.view.backgroundColor = .clear
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.isUserInteractionEnabled = false
        w.rootViewController = host
        w.isHidden = false
        w.layoutIfNeeded()
        windows[key] = w
    }

    private static func lower(_ key: ObjectIdentifier) {
        guard let w = windows[key] else { return }
        // The window stays REACHABLE through the fade, so a leave inside those
        // 200ms reclaims it (above) instead of raising a second one. The token
        // is what keeps that safe: `removeAllAnimations` fires this completion
        // with `finished == false`, and without it the reclaimed cover would be
        // torn down by the fade it just interrupted.
        let token = generations[key] ?? 0
        UIView.animate(withDuration: 0.2, delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            w.alpha = 0
        } completion: { _ in
            guard generations[key] == token, windows[key] === w else { return }
            w.isHidden = true
            w.rootViewController = nil
            windows[key] = nil
            generations[key] = nil
        }
    }

    /// A scene that disconnects while covered leaves an entry behind holding
    /// the last strong reference to a window nothing can ever show again.
    private static func prune() {
        for (key, w) in windows where w.windowScene == nil {
            windows[key] = nil
            generations[key] = nil
        }
    }

    /// The cover itself: the themed page the app already stands on, and the
    /// mark. Opaque by construction — `DSPageBackground` paints `DS.themedPage`
    /// edge to edge — so there is nothing to see through and no per-view
    /// hiding to get wrong.
    ///
    /// 96, not 56 (user, 2026-09-08: "on the load screen there is a small
    /// octopus, should it be larger?"). 56 is the intro cover's size, where
    /// the mark is a signature above a headline and the tiles are the moment;
    /// here it stands ALONE on an empty page, and 56 is smaller than the ~60pt
    /// app icon the person just tapped in the switcher, so it read as a lost
    /// glyph rather than the brand. 96 is the size at which a lone mark
    /// carries a page without becoming a poster. The two covers deliberately
    /// do NOT share a size — different jobs.
    private struct CoverContent: View {
        var body: some View {
            ZStack {
                DSPageBackground()
                CasberiMark(size: 96)
            }
            .ignoresSafeArea()
        }
    }
}
