import Foundation

/// The Media room's tiles (prd §1118; Reading folded in by §1204): All,
/// Play — what you watch, play and listen to, the one square grid (§1055) —
/// Read — what you read and save, as rows — and Subscriptions, every site,
/// channel, show and board you follow. A–Z after All (§995).
/// Foundation-only, its conformance beside every other in
/// `ScopeTileGlyphs.swift`.
enum MediaScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, play, read, subscriptions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:           return String(localized: "All")
        case .play:          return String(localized: "Play")
        case .read:          return String(localized: "Read")
        case .subscriptions: return String(localized: "Subscriptions")
        }
    }

    var summary: String {
        switch self {
        case .all:           return String(localized: "Everything you read, watch and listen to")
        case .play:          return String(localized: "What you watch, play and listen to")
        case .read:          return String(localized: "What you read and save")
        case .subscriptions: return String(localized: "Every site, channel and show you follow")
        }
    }

    var isVerb: Bool { false }
}
