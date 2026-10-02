import Foundation

/// The Work room's tiles (prd §1049, built §1057): All, Coming up — every
/// deadline from every seat, soonest first — and Watch, the verb, last.
/// Foundation-only, its conformance beside every other in
/// `ScopeTileGlyphs.swift`.
enum WorkScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, comingUp, watch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return String(localized: "All")
        case .comingUp: return String(localized: "Coming up")
        case .watch:    return String(localized: "Watch")
        }
    }

    var summary: String {
        switch self {
        case .all:      return String(localized: "Everything about what you build")
        case .comingUp: return String(localized: "Deadlines, soonest first")
        case .watch:    return String(localized: "Follow a repo, a package or a model")
        }
    }

    var isVerb: Bool { self == .watch }
}

/// What Watch can follow, each through the watch its seat already has.
enum WorkWatch: String, CaseIterable, Identifiable, Sendable {
    case github = "GitHub", npm, pypi = "PyPI", huggingFace = "Hugging Face"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .github:      return String(localized: "A repo or person on GitHub")
        case .npm:         return String(localized: "A package on npm")
        case .pypi:        return String(localized: "A package on PyPI")
        case .huggingFace: return String(localized: "A model or author on Hugging Face")
        }
    }
}
