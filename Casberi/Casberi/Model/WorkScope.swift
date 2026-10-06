import Foundation

/// The Work room's tiles (prd §1049, built §1057): All, Coming up — every
/// deadline from every seat, soonest first — and Watching: every repo,
/// package, model and author you watch, with Watch something as its first
/// row (prd §1118; it was the verb Watch).
/// Foundation-only, its conformance beside every other in
/// `ScopeTileGlyphs.swift`.
enum WorkScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, comingUp, watch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return String(localized: "All")
        case .comingUp: return String(localized: "Coming up")
        case .watch:    return String(localized: "Watching")
        }
    }

    var summary: String {
        switch self {
        case .all:      return String(localized: "Everything about what you build")
        case .comingUp: return String(localized: "Deadlines, soonest first")
        case .watch:    return String(localized: "Every repo, package and model you watch")
        }
    }

    var isVerb: Bool { false }
}
