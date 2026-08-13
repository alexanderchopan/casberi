import Foundation
import Observation

/// What the agent already knew last time it was open.
///
/// WHY THIS EXISTS OUTSIDE THE VIEW. `RootShell` renders the composer as
/// `if composerOpen { agentSurface }`, so the whole `Composer` is CREATED on
/// every raise and DESTROYED on every lower. Everything it held in `@State`
/// went with it — including the composed board and the corpus counters behind
/// the ask chips — so each open rebuilt both from nothing: a full-corpus fetch
/// (~761ms measured on 13,412 rows, one uninterruptible call on the main actor
/// during the rise animation) and a fresh panel composition (~1.6s).
///
/// That is what "the agent is laggy opening" was. Not the first open — every
/// open, identically, forever.
///
/// Two caches, and they are cached for different reasons:
///
///   • `board` is EXPENSIVE and slow-changing. Showing the previous one
///     immediately and swapping when the new one lands is the same
///     "kick async, repaint on arrival" shape `HomeInsightStore` uses. Without
///     it the bento skeleton is what you see on every single open.
///   • `facts` exists because the two "Show <tag>" chips need a whole-corpus
///     walk that nothing else on the open path needs: `tags` is a
///     transformable array, so it can be neither predicated nor counted in
///     SQL, while every other counter could be a `fetchCount` or a
///     date-predicated read.
///
/// The freshness cost is one open — a chip count or a figure can be one
/// arrival behind until the refresh lands, which `Composer.composeBoard` does
/// on every open behind the board. That is the same trade the debounced feed
/// and the scoped brief's partial already make, and being one behind is a
/// different thing from being wrong.
///
/// Process-wide rather than per-window: which chips the agent offers is a fact
/// about the corpus, not about a window (`ChipMemory` and `KeptAskStore` are
/// process-wide for the same reason). A second window opening the agent should
/// see what the first one already computed, not pay for it again.
@MainActor
@Observable
final class AgentOpenCache {
    static let shared = AgentOpenCache()

    /// The last composed board. Empty means never composed on this launch,
    /// which is the one open that shows the skeleton.
    var board = AgentPanel.Composition()

    /// The last corpus-wide chip counters, or nil if never computed. Nil is
    /// the one open that pays the full walk.
    var facts: Composer.CorpusScan?

    private init() {}
}
