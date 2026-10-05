import Foundation

/// Where a row came from — the ONLY hierarchy the All feed applies
/// (prd §378). Provenance, never predicted interest: each tier is a
/// one-sentence fact about the row's origin, so the feed can be skimmed
/// without anything being ranked, reordered or scored.
enum FeedTier {
    /// A deliberate act of yours — a screenshot, a voice note, anything from
    /// You.
    case made
    /// A row where you are the SUBJECT: consent waiting on you, money moving,
    /// a clock of yours. Not "important" — a fact about the row.
    case concerns
    /// Everything that simply arrived: posts, articles, drops, trending. The
    /// only tier that recedes.
    case arrived
}

/// The feed's provenance tier (prd §378), as a pure function over `Thing`.
///
/// This file held the All feed's FOLD decisions — strip or sentence, the
/// threshold, the clock carve-out — until prd §1103 put every app under its
/// own header with its newest thing, which left nothing to fold. The tier is
/// what outlived them: `FeedRow` still stores whether a row arrived on its
/// own, and the feed still recedes those rows (`isQuiet`).
enum FeedFold {
    static func tier(_ t: Thing) -> FeedTier {
        if t.kind == .screenshot || t.kind == .voice
            || t.source == "You" { return .made }
        if t.kind == .approval || t.kind == .transaction
            || t.kind == .event || t.kind == .reminder
            || t.dueAt != nil || t.isFlagged { return .concerns }
        return .arrived
    }
}
