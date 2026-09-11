import Foundation

/// Whether the app DRAWS the ask (prd §697b, 2026-09-11).
///
/// **Deprecated, not deleted** (user: *"the chat feature sucks. no one will
/// use it"*, *"i really think it is a wasted feature, and if Apple on device
/// gets more intelligence then it is worth it but i feel like it is hurting
/// us"*, *"we just feature flag it and if we want it later use it but for now,
/// deprecate"*). The retrieval, the composer, the brief, the kept asks and the
/// keyed agents all stay in the tree and stay compiled — what goes is every
/// surface that offers them, because a door that opens nothing is the dead
/// control §83 bans and a half-hidden feature is worse than an absent one.
///
/// **One flag, read everywhere, so the app cannot be half-deprecated.** The
/// failure this shape prevents is the one that shipped the quick action for
/// eleven days (§377): a feature reachable by five doors, four of them turned
/// off. `ask-deprecation-audit.py` is the mechanical half — it sweeps for a
/// raiser that forgot to ask.
///
/// In `Shared/` because the widget extension reads it too: the ask widgets are
/// gone from the bundle, and the gate that keeps them gone has to be visible
/// from both targets.
///
/// **What this does NOT govern: the COMPOSER, which is also the capture
/// surface.** Typed text never saves (2026-07-13), but paste, mic and drop
/// all land there, and ⌘N is the Mac's door to it — so the composer stays
/// reachable and keeps compiling. What this flag removes from it is the ASK
/// affordances: the launcher chips, the kept-ask pills, the brief.
///
/// **Nor the keyed agents' own doors.** "Ask Bankr" on a CONNECTED Bankr seat
/// still raises the composer, and deliberately: a key the person went and got
/// is not a feature being pushed at them, and a seat whose whole function is
/// asking would otherwise become a dead room (user, 2026-09-11: *"they may
/// have bankr installed but thats it"*).
///
/// **What this does NOT govern.** The keyed agent SEATS in the Agents category
/// (Bankr, Venice, OpenRouter, Grok, and the ChatGPT/Claude/Gemini imports)
/// are bridges: they land things, draw rooms and are connected in the
/// catalogue like every other seat. Nothing here touches them — a person with
/// Bankr connected keeps exactly what they had.
enum AskSurface {
    /// False since 2026-09-11. Flip to true to bring every ask surface back;
    /// nothing else has to change, which is the point of the flag.
    static let enabled = false
}
