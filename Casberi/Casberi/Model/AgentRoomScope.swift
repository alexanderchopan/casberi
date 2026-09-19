import Foundation

/// The two halves of an agent's room (prd §840): the conversations you have
/// HAD, and the one you are having.
///
/// **A MODE, not a kind of row — which is why it is not a `RoomKindTile`.**
/// That enum's own rule is that a tile is a kind of row read off the row's ref
/// or tags, and that a room with fewer than two kinds draws no tiles at all
/// (§815). An agent room has exactly one kind of row — a conversation — so by
/// that rule it would draw nothing forever. What the second tile holds is not
/// a different kind of row, it is not a row: it is the live surface. Putting
/// it in `RoomKindTile` would have made that enum mean two things, so this is
/// its own conformer instead, which `DSTileScope` already expects — the
/// catalogue screen, Privy and Privacy Pools each bring their own.
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
    case chat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:  return String(localized: "All")
        case .chat: return String(localized: "Chat")
        }
    }

    /// Read by VoiceOver and the tooltip (`DSSectionScope`). It does NOT name
    /// the agent: the room already does, and a summary that interpolated it
    /// would be a second string saying what the head says — §799's rule about
    /// asking who draws a string before writing another one.
    var summary: String {
        switch self {
        case .all:  return String(localized: "Conversations you have had")
        case .chat: return String(localized: "Ask something now")
        }
    }
}
