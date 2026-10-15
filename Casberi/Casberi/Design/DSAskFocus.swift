import SwiftUI

/// THE PAGE'S ONE ASK TAKES THE KEYBOARD (prd §1302, user, 2026-10-14: "so
/// what did we do here today? … only specific ones, not sort of a rule or
/// template for others?", then "yes" to making it one).
///
/// A connect page that asks for one thing — a key to paste, a handle, an
/// address — focuses that field as it opens, so typing or pasting is the first
/// act and never a tap first. `AccountPage` hands one of these to its act
/// while the app is not connected and its mode is `.pasteKey` or `.noAccount`
/// (never `.signIn`: a keyboard over a Sign in tile hides the act); the first
/// `DSSlabField` to appear claims it, so a page with a key and a secret
/// focuses the key alone. Return submits every slab field already
/// (`onSubmit(action)`), so the keyboard's Go is the field's button.
final class DSAskFocus {
    var claimed = false
}

extension EnvironmentValues {
    /// Set by `AccountPage` on an act that asks for a field (prd §1302).
    @Entry var dsAskFocus: DSAskFocus? = nil
}
