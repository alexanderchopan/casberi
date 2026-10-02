import Foundation

/// The two halves of an agent's room (prd §840): the conversations you have
/// HAD, and the one you are having.
///
/// **A MODE, not a kind of row.** The kind tiles (§815, deleted with the
/// rooms that wore them, prd §1059) were kinds of row read off the row's ref
/// or tags. What the second tile holds is not a different kind of row, it is
/// not a row: it is the live surface — so this is its own conformer, which
/// `DSTileScope` already expects; the catalogue screen, Privy and Privacy
/// Pools each bring their own.
///
/// **All is first and the room opens on it** (§815's rule, which is about
/// tiles and does hold here): you arrive to see what you asked, and reach for
/// the live half deliberately. The reverse would open a keyboard every time
/// somebody tapped the agent's chip to look something up.
///
/// Foundation-only — the conformance lives in `ScopeTileGlyphs.swift` beside
/// every other one, so a `swiftc` harness can compile this file whole.
enum AgentRoomScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    /// New (§1054; Chat until then): start a conversation.
    case new

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:  return String(localized: "All")
        // In the Agents room it starts a conversation with the agent the
        // menu picked, which lands as a row there (§1049, §1054).
        case .new:  return String(localized: "New")
        }
    }

    /// Read by VoiceOver and the tooltip (`DSSectionScope`). It does NOT name
    /// the agent: the room already does, and a summary that interpolated it
    /// would be a second string saying what the head says — §799's rule about
    /// asking who draws a string before writing another one.
    var summary: String {
        switch self {
        case .all:  return String(localized: "Conversations you have had")
        case .new:  return String(localized: "Start a conversation")
        }
    }
}
