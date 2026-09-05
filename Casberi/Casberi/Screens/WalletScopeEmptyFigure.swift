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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let headline = section.emptyHeadline {
                Text(headline)
                    .dsText(.stat24)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .frame(height: DSRoomChassis.headlineRow, alignment: .leading)
            }
            if let words = section.emptyBody {
                Text(words)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, WalletCardStyle.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
