import SwiftUI

/// The app's OWN symbols (prd §1016): SF Symbol templates in the asset
/// catalog, for a meaning SF Symbols has no glyph for. `coins.stack` is the
/// first — none of the system's 9,524 names is a coin without a currency sign
/// (measured 2026-09-30), and a sign would name money a test coin is not
/// (§83). Each is drawn in all 27 weight and scale slots, so it takes `.font`
/// weight and size exactly like a system symbol; `scripts/coin-symbol.swift`
/// regenerates the template.
///
/// Every glyph a tile or a row lead draws goes through `Image(dsSymbol:)`,
/// which is the one place that knows a name is ours: `Image(systemName:)`
/// given an asset name draws nothing, silently.
enum DSSymbol {
    static let custom: Set<String> = ["coins.stack"]
}

extension Image {
    init(dsSymbol name: String) {
        if DSSymbol.custom.contains(name) {
            self.init(name)
        } else {
            self.init(systemName: name)
        }
    }
}
