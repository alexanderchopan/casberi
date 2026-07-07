import Foundation

/// Pinned projects (S21) — the one ordering hand the person has over the
/// computed clusters: a pinned project sorts first in the Home map. Names,
/// not ids, because the cluster IS its tag.
enum ProjectPins {
    private static let key = "projects.pinned"

    static var all: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func contains(_ name: String) -> Bool {
        all.contains(name)
    }

    static func toggle(_ name: String) {
        var pins = all
        if !pins.insert(name).inserted { pins.remove(name) }
        UserDefaults.standard.set(Array(pins).sorted(), forKey: key)
    }
}
