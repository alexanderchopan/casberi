import Foundation

/// WHERE A RECEIVED NFT CAME FROM (2026-08-26, prd §481) — the rule that
/// decides whether an NFT arriving at a watched wallet is an event worth a row.
///
/// ## The gap this closes, and why it is a gap rather than an oversight
///
/// `WalletIngest.refresh` has dropped junk NFTs since 2026-07-15 by asking
/// whether the wallet actually HOLDS the collection above Alchemy's own
/// `isSpam` classification — the sibling of the dust floor that drops junk
/// ERC-20s. That rule catches a spam NFT *transferred* to you and structurally
/// cannot catch one *minted* to you:
///
/// - a mint puts the piece in your wallet, so the "do you hold it" arm passes
///   by construction; and
/// - the only thing left is `isSpam`, which is a REPUTATION signal on a
///   contract that is usually minutes old.
///
/// So the filter's evidence arrives after the event does. Every spam mint is a
/// first offence.
///
/// ## The axis that works: who signed the transaction
///
/// A mint you performed is one you signed. A mint pushed at you is sent by
/// somebody else. On the TRANSFER record the two are identical — both arrive
/// from the void — and one level up, at the TRANSACTION, they are completely
/// different.
///
/// This is not a new principle here. It is the anchor `WalletSafety`
/// already turns on: *"addresses THIS wallet has sent to are the unambiguous
/// trust anchor — never the received side, which is exactly what a poisoner
/// controls."* A spammer controls what they send you. They cannot make you
/// sign.
///
/// ## Why NOT a dollar floor, which is the obvious idea
///
/// §387 already ruled it out for the shelf — *"a floor is a bid on the thinnest
/// book in this app, it moves without you, and it would be a number people
/// believe (§83) beside art somebody keeps for reasons that aren't the
/// number."* Two more reasons are specific to the event list:
///
/// 1. **It fails by construction on the case it is aimed at.** A collection
///    minted an hour ago has no floor — that is what "new" means — so a dollar
///    rule reads a mint you just performed and a spam drop as the same thing,
///    and hides the one you cared about. Silently.
/// 2. **It is the only rule a spammer can buy past.** A wash-traded floor costs
///    a few dollars and defeats it permanently.
///
/// The token side gets away with `WalletIngest.holdingFloor` because a fungible
/// token has a real price from a real pool. An NFT floor is not that number.
///
/// ## DROP, never flag
///
/// `FeedFold.tier` puts `isFlagged` in `.concerns`, the feed's HIGHEST tier —
/// so flagging a spam mint would promote it to sit beside a dispute deadline
/// and a pending approval. Dropping is also what the received side already does
/// by rule; flagging is the SENT-side pattern, and only because dropping there
/// would eat real history (`WalletSafety.flagFakeTransfer`).
///
/// ## Foundation-only BY DESIGN
///
/// No SwiftData, no SwiftUI, no network, no `UserDefaults` — so
/// `scripts/wallet-nft-selftest.sh` compiles this file WHOLE and unmodified,
/// alongside the two Foundation-only files it leans on (`WalletVerbs.isVoid`,
/// `NFTPickKey.make`). Those are USED rather than mirrored: a copied void-address
/// set or a second key format is exactly the drift this project keeps paying for.
enum WalletNFTOrigin {

    /// What to do with one received NFT leg.
    ///
    /// Three cases rather than two because the answer legitimately depends on a
    /// fact we have not read yet, and the caller must be able to tell "keep it"
    /// apart from "keep it unless a receipt says otherwise". `askWhoSent` is
    /// what bounds the reads: it is returned ONLY after every free rung has
    /// declined, so the number of receipts a pass buys is exactly the number of
    /// NFT rows that would otherwise reach the feed.
    enum Verdict: Equatable {
        /// Lands as a row.
        case keep
        /// Never lands. The received side's own rule since 2026-07-15.
        case drop
        /// Undecidable from what is already in memory — read the transaction's
        /// receipt and ask again with `signed:` filled in.
        case askWhoSent
    }

    /// The facts about one received NFT leg this rule reads. A value type with
    /// no model in it, so the harness can build one.
    struct Leg: Equatable {
        /// Alchemy network id — "eth-mainnet", "base-mainnet", …
        let network: String
        /// The transfer's category, as the fetch layer reports it.
        let category: String
        /// The collection's contract, lowercased. nil for a native coin, which
        /// can never be an NFT and is kept for that reason alone.
        let contract: String?
        /// The address the piece came FROM — the void for a mint.
        let counterparty: String?
    }

    static func isNFT(_ category: String) -> Bool {
        category == "erc721" || category == "erc1155"
    }

    /// The pick/verification key for a leg — `NFTPickKey`'s own format, called
    /// rather than re-spelled so a pick made in the picker and a pick read here
    /// can never disagree about the same collection (the 2026-08-15 lesson: a
    /// checksummed key never matches a lowercased one, and every tap looks
    /// ignored forever).
    static func key(for leg: Leg) -> String? {
        guard let contract = leg.contract else { return nil }
        return NFTPickKey.make(network: leg.network, contract: contract)
    }

    /// - Parameters:
    ///   - ownedContracts: the wallet's non-spam held collections on this
    ///     chain, or **nil when the read failed** — the nil is load-bearing and
    ///     is why every arm below fails OPEN.
    ///   - picked: the collections chosen for the shelf (§387), as pick keys.
    ///   - verified: the collections OpenSea has safelisted, as pick keys.
    ///   - knownGood: addresses this wallet has SENT to.
    ///   - signed: whether the wallet sent the transaction this leg rode in on;
    ///     nil when no receipt has been read for it yet.
    static func verdict(_ leg: Leg,
                        ownedContracts: Set<String>?,
                        picked: Set<String>,
                        verified: Set<String>,
                        knownGood: Set<String>,
                        signed: Bool?) -> Verdict {
        // 1. This rule speaks about NFTs and nothing else. An ERC-20 has its own
        //    filter (the dust floor) and a native coin has none by design.
        guard isNFT(leg.category) else { return .keep }
        // 2. No contract to judge. Fails open, like every arm below.
        guard let key = key(for: leg) else { return .keep }

        // --- the free keeps, all three from state already in memory ----------
        //
        // These run BEFORE the 2026-07-15 drop, which is a deliberate widening:
        // each is positive evidence that this collection is one the person has
        // something to do with, and evidence beats a vendor's classification.
        // All three can only ever ADD a row, never remove one, so the direction
        // is the safe one.

        // 3. A PICK OVERRIDES THE VENDOR'S GUESS — §387's own words, applied to
        //    the feed rather than the shelf. Honouring `isSpam` over a
        //    collection somebody explicitly chose would silently drop the
        //    arrivals of the one collection they told us they care about.
        if picked.contains(key) { return .keep }

        // 4. OpenSea has safelisted the collection. Its ABSENCE proves nothing
        //    (most legitimate collections are not safelisted), so this is a
        //    keep-only rung and must never be inverted into a drop.
        if verified.contains(key) { return .keep }

        // 5. It came from an address this wallet has SENT to — a friend who
        //    gifts you a piece is usually somebody you have transacted with.
        //
        //    THE VOID IS EXCLUDED, and this is the sharpest edge in the file: a
        //    wallet that has ever burned anything by sending to `0x…0000` or
        //    `0x…dEaD` has the void in its known-good set, and without this
        //    guard EVERY mint — which is by definition a transfer from the void
        //    — would be kept. That is the whole rule switched off, by a burn
        //    somebody did once, with nothing on screen to say so.
        if let counterparty = leg.counterparty, !WalletVerbs.isVoid(counterparty),
           knownGood.contains(counterparty.lowercased()) { return .keep }

        // --- the 2026-07-15 rule, unchanged ---------------------------------
        //
        // 6. A received NFT whose contract is not among the wallet's non-spam
        //    holdings on this chain was an airdrop pushed at you. A nil set
        //    means the read FAILED, so a network hiccup can never become a
        //    silent spam filter.
        if let ownedContracts, !ownedContracts.contains(leg.contract ?? "") { return .drop }

        // --- the new rule ---------------------------------------------------
        //
        // 7. We hold it and nothing above vouched for it. Did you send the
        //    transaction it arrived in?
        //
        //    A cheaper signal was considered and REFUSED: "did this same
        //    transaction also move something OUT of the wallet?" is free and
        //    catches every paid mint — but a contract can emit a Transfer event
        //    claiming the wallet sent something it never sent, which is the
        //    exact attack `WalletSafety.flagFakeTransfer` exists for. A signal a
        //    spammer can forge is worse than no signal, because it looks like
        //    one. The receipt is the un-forgeable answer.
        switch signed {
        case .none:        return .askWhoSent
        case .some(false): return .drop
        case .some(true):  return .keep
        }
    }
}
