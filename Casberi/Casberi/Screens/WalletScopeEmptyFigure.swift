import SwiftUI

/// **A WALLET SCOPE WITH NOTHING IN IT TEACHES WHAT IT WOULD HOLD (prd §611,
/// §610's ruling carried to the wallet room).**
///
/// Until §611 a scope the wallet had nothing for was dropped from the strip,
/// so this view had no reason to exist; now every scope is a chip on every
/// wallet, and the five standing scopes — Holdings, Positions, NFTs, Risk,
/// Permissions — draw this in the slot when their own render gate says there
/// is nothing to draw (`FeedScreen.walletScopeIsEmpty`). Activity keeps
/// `WalletFlowEmptyFigure`, which knows WHICH of three things is true of the
/// window; this knows only that the scope is empty, and says what it is for.
///
/// **The short state over the skeleton** — the headline row's own `stat24`.
/// `emptyBody` rides `words:`, which §769 made VoiceOver's value alone, and
/// §799 cut to one clause. Wallet's slot passes `reservesHeadline: false`, so
/// the row is drawn here at the chassis' own height rather than left to it,
/// and it lines up with every other scope's headline.
///
/// **No door.** Watching a wallet, editing NFT picks and revoking a grant all
/// live on the cards that have something to act on; an empty scope states a
/// fact and stops.
struct WalletScopeEmptyFigure: View {
    let section: WalletSection
    /// Whether to take the SCOPE SLOT's own horizontal pad.
    ///
    /// **False on Home's crown (prd §761).** Every scope's figure draws inside
    /// `WalletCardStyle.pad`; Home's crown does not — it sets no horizontal
    /// padding of its own and inherits the chassis's inset — so the slot form
    /// would set these words 16pt right of the balance they stand in for.
    ///
    /// It does NOT switch the height. `DSRoomSlot`'s 300pt box is back on Home
    /// (§760, reversing §757's drop) so that every room's lead is one height,
    /// and this fills it like any other scope's empty state: top-aligned, in
    /// the box, at the same rung.
    var padded: Bool = true

    var body: some View {
        // `.home` returned nil for both until §761 and never reached here; it
        // has words now, and this is still the one place they are drawn.
        if let words = section.emptyBody {
            DSEmptyState(headline: section.emptyHeadline.map { Text($0) },
                         words: Text(words), scale: .room(section.skeleton))
                .padding(.horizontal, padded ? WalletCardStyle.pad : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

