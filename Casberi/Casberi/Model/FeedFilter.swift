import Foundation
import Observation

/// Feed's filter state, shared. `source` is the pager's selection — the chip
/// strip's whole job.
///
/// `tag` is the AGENT's filter, not the person's (ruling 2026-08-01): an ask
/// that names a kind ("show my links") lands the feed filtered to it via
/// `NavigateCommand` → `RootShell.navigate`, and `casberi://feed/type/<Tag>`
/// drives the same state for internal/debug use. What it no longer has is a
/// control of its own — the "× Links" chip is gone (user: "i do not want to
/// see the x chips those are supposed to be internal only"). So nothing here
/// asks the person to manage a filter: the day-section header names it, and
/// ANY source chip tap clears it, a re-tap of the current source included.
/// Keep it that way — a `tag` that outlives a source switch reads as a
/// broken room, not a filter (it showed up once as "No wallet yet.").
@Observable
final class FeedFilter {
    // `.shared` DELETED (multi-window, 2026-08-02) — per-window now, held by
    // `SceneState`. Two windows showing two different sources is the whole
    // point of a second window.

    /// Content-first landing (reverted 2026-07-28: §131's amendment that made
    /// this persist "wherever you left it" is undone per user feedback — the
    /// app always opens on "All" now).
    var source = "All"
    var tag = "All"

    // Per-window now, so the init is reachable — the `private` here was
    // the singleton's own guard against a second instance, and a second
    // instance is exactly what a second window is.
    init() {}

    func clear() { source = "All"; tag = "All" }
}
