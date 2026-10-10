import Foundation

/// A string is its own identity, so a `ForEach`, a `.sheet(item:)` or a
/// `confirmationDialog(presenting:)` can take one directly. It lived at the
/// foot of the Apps screen until that screen was deleted (prd §1234).
extension String: @retroactive Identifiable {
    public var id: String { self }
}
