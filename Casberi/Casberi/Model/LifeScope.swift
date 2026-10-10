import Foundation

/// The Life room's tiles (prd §1231): All, and Subscriptions — every
/// mailing list that writes to you. Mail moved into Life with Files and
/// Contacts when Day became the calendar and to-dos alone, and the lists
/// came with it. Foundation-only, its conformance beside every other in
/// `ScopeTileGlyphs.swift`.
enum LifeScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, subscriptions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .subscriptions: return String(localized: "Subscriptions")
        }
    }

    var summary: String {
        switch self {
        case .all: return String(localized: "Everything you made, kept or did")
        case .subscriptions: return String(localized: "The newsletters and lists that write to you")
        }
    }
}
