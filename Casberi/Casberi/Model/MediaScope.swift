import Foundation

/// The Media room's tiles (prd §1118): All, the one square grid (§1055), and
/// Subscriptions — every channel, show and board you follow, with Track a
/// subscription first, and the Twitch channels your account follows.
/// Foundation-only, its conformance beside every other in
/// `ScopeTileGlyphs.swift`.
enum MediaScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, subscriptions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:           return String(localized: "All")
        case .subscriptions: return String(localized: "Subscriptions")
        }
    }

    var summary: String {
        switch self {
        case .all:           return String(localized: "Everything you follow, play and listen to")
        case .subscriptions: return String(localized: "Every channel and show you follow")
        }
    }

    var isVerb: Bool { false }
}
