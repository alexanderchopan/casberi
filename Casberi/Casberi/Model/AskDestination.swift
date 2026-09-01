import Foundation

/// WHO ANSWERS — the ask capsule's own arithmetic (prd §543, 2026-08-31).
///
/// The composer's control row ends in ONE segmented capsule naming every
/// destination a question can go to: this device first, then the agents whose
/// keys are configured. Tapping a segment IS the send to it — there is no
/// separate send button and no selector, which is the whole point: choosing
/// and sending were two controls, and a person could not tell from the screen
/// which one the arrow would use.
///
/// This file is the part that has to be right rather than merely drawn:
/// which segments are shown, in which order, and what the device is called.
/// Foundation-only by design so `scripts/ask-destination-selftest.sh` can
/// compile it WHOLE and unmodified — every failure here renders as a
/// perfectly ordinary capsule (an agent silently missing, two capsules
/// disagreeing about order between opens, a Mac claiming to be an iPhone).
enum AskDestination {

    /// How many AGENT segments fit beside the device one.
    ///
    /// Two, measured rather than chosen: at the shipped chip metrics
    /// (`.label12` + a `DS.Face.badge` mark + 10pt side padding) the device
    /// pill plus two named agents fills the row a 390pt phone leaves after
    /// the lower and mic buttons. Seven providers are configurable, so the
    /// rest have to go somewhere, and `split` is where that is decided.
    static let agentSlots = 2

    /// The device's own raw value in the recency ledger. Deliberately not a
    /// provider raw value and deliberately not spellable as one: it shares
    /// the ledger with them, so it must never collide with a real provider
    /// (`AgentProvider` is a bare-word enum — `anthropic`, `bankr`, …).
    static let deviceRaw = "__device"

    /// The most-recently-asked ledger. Not the keychain and not `AgentKey`'s
    /// `active` pointer: `active` answers "which key does a keyed answer
    /// spend" and moves when a key is SAVED, which is a different question
    /// from "which two agents does this person actually use" — and the
    /// capsule needs the second one or a key pasted months ago outranks the
    /// agent asked ten minutes ago.
    private static let recentKey = "ask.destination.recent"

    /// Bounded because it is a preference, not a history: eight is already
    /// more than the seven providers that exist.
    private static let recentCap = 8

    /// The device segment, then the agents that fit, then the rest.
    ///
    /// Order: most-recently-used first (filtered to what is still
    /// configured), then everything else in the caller's canonical order.
    /// TOTAL and deterministic — no dictionary iteration anywhere — because
    /// a capsule that reshuffles between two opens over identical state
    /// reads as broken, and this row is the one control that must be in the
    /// same place every time to be learnable.
    ///
    /// A raw value in `recent` that is no longer configured is DROPPED, never
    /// shown: a key can be cleared, and a segment for a key that does not
    /// exist is the dead control §83 bans, pointed at a live host.
    static func split(configured: [String], recent: [String],
                      slots: Int = agentSlots) -> (shown: [String], overflow: [String]) {
        guard slots > 0 else { return ([], configured) }
        var ordered: [String] = []
        var seen = Set<String>()
        for raw in recent where configured.contains(raw) && !seen.contains(raw) {
            ordered.append(raw)
            seen.insert(raw)
        }
        for raw in configured where !seen.contains(raw) {
            ordered.append(raw)
            seen.insert(raw)
        }
        guard ordered.count > slots else { return (ordered, []) }
        return (Array(ordered.prefix(slots)), Array(ordered.dropFirst(slots)))
    }

    static func recent(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: recentKey) ?? []
    }

    /// Records an ask. Called on the SEND, never on a mere focus: arming the
    /// field at a destination and actually asking it are different acts, and
    /// promoting on focus would let a stray tap reorder the row.
    static func used(_ raw: String, _ defaults: UserDefaults = .standard) {
        var list = recent(defaults).filter { $0 != raw }
        list.insert(raw, at: 0)
        defaults.set(Array(list.prefix(recentCap)), forKey: recentKey)
    }

    static func forget(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: recentKey)
    }

    /// THE DEVICE NAMES ITSELF — never a hardcoded "iPhone".
    ///
    /// This app ships iPhone, iPad and Mac Catalyst, and `verify.sh` gates on
    /// a Catalyst build every pass; a segment reading "iPhone" on a Mac is a
    /// claim about where the answer runs, made on the one control whose whole
    /// job is to say where the answer runs. Pure over the two platform facts
    /// so the harness can hold all three cases.
    static func deviceLabel(isMac: Bool, isPad: Bool) -> String {
        if isMac { return String(localized: "Mac") }
        return isPad ? String(localized: "iPad") : String(localized: "iPhone")
    }

    /// The device segment's glyph, on the same two facts as the label — so a
    /// Mac can never wear a phone.
    static func deviceGlyph(isMac: Bool, isPad: Bool) -> String {
        if isMac { return "laptopcomputer" }
        return isPad ? "ipad" : "iphone"
    }
}
