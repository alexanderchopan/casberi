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
/// **Two tiers and no more** — the headline row's own `stat24`, carrying the
/// short state, and one paragraph. Wallet's slot passes `reservesHeadline:
/// false`, so the row is drawn here at the chassis' own height rather than
/// left to it, and the two line up with every other scope's headline.
///
/// **No door.** Watching a wallet, editing NFT picks and revoking a grant all
/// live on the cards that have something to act on; an empty scope states a
/// fact and stops.
struct WalletScopeEmptyFigure: View {
    let section: WalletSection
    /// Whether this is filling a SCOPE's figure slot, which is what the two
    /// modifiers below are for: the slot's own horizontal pad, and the
    /// expansion that puts the words at the top of a 300pt box rather than
    /// floating in the middle of it.
    ///
    /// **False on Home's crown (prd §761).** That crown is not in a slot —
    /// §757 dropped `DSRoomSlot`'s floor there, and it never carried the
    /// scope's pad, so keeping either would put these words 16pt right of the
    /// balance they replace and hand back the 300pt box §757 removed, with a
    /// sentence in it.
    var inSlot: Bool = true

    var body: some View {
        // `.home` returned nil for both until §761 and never reached here; it
        // has words now, and this is still the one place they are drawn.
        if let words = section.emptyBody {
            DSEmptyState(headline: section.emptyHeadline.map { Text($0) },
                         words: Text(words), scale: .room)
                .padding(.horizontal, inSlot ? WalletCardStyle.pad : 0)
                .frame(maxWidth: .infinity,
                       maxHeight: inSlot ? .infinity : nil,
                       alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: !inSlot)
        }
    }
}
