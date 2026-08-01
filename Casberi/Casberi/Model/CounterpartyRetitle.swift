import Foundation
import SwiftData

/// Naming an address rewrites the history you already have (2026-08-01).
///
/// **Why this is a file and not a method.** The rewrite lived privately inside
/// `ThingSheetView`, so it ran for exactly ONE of the app's naming doors — the
/// pencil on a transfer's counterparty. Naming the same address from the
/// address card, from the book's omnibox, or by starring it left every landed
/// title still reading `0x9a2E…44b1`, because a title's counterparty clause is
/// baked at ingest (`WalletIngest.counterpartyNames`) and nothing re-ran it.
/// Same act, same address, two different outcomes depending on which door you
/// used — so the rewrite moved here and every door calls it.
///
/// It is also the address book's best moment. A name is not a label on one row:
/// it retitles a year of history at once, and that is the whole argument for
/// naming anything. The `AddressCard` animates exactly this — see
/// `renameCascade` there.
enum CounterpartyRetitle {

    /// Which wallet verbs carry a trailing counterparty clause, and the word
    /// that introduces it. A title whose verb ISN'T here is left alone — that
    /// gate is the whole point (see `retitled`).
    private static let counterpartyClause: [String: String] = [
        "Received": " from ", "Sent": " to ", "Swapped": " on ",
        // The staking verbs (WalletVerbs, 2026-07-21) name the protocol the
        // same way — "Staked 1 ETH with Lido".
        "Staked": " with ", "Unstaked": " from ",
        // Zerion-classified verbs, each with the preposition its own sentence
        // uses. "Burned"/"Minted an NFT" name no venue and so appear nowhere
        // here — nothing to rewrite means the title is left untouched.
        "Claimed": " from ", "Deposited": " into ", "Withdrew": " from ",
        "Minted": " on ", "Bid": " on ",
    ]

    /// Swaps (or strips) a wallet title's trailing counterparty clause.
    ///
    /// Gated on the title's leading VERB, not on finding a delimiter anywhere in
    /// the string. The original wrote the delimiter search as safe because "the
    /// only ' from '/' to '/' on ' in a wallet title is that clause" — true when
    /// transfers were the only things carrying `counterpartyAddress`, and false
    /// since approvals started carrying it too (prd §84, 2026-07-16). Naming an
    /// approval's spender ran the blind search over "Approved Uniswap to spend
    /// unlimited USDC through Permit2", matched the `to` in "to spend", and
    /// saved "Approved Uniswap to Mom" — losing the asset, the amount and the
    /// Permit2 clause, silently and permanently. Fixed 2026-07-21.
    ///
    /// Verbs with no counterparty clause to rewrite (an approval, a "Moved …"
    /// self-transfer named from watched-wallet labels, a "Minted"/"Burned" whose
    /// counterparty is the void) return nil and keep their titles untouched.
    static func retitled(_ title: String, to name: String?) -> String? {
        guard let verb = title.split(separator: " ").first.map(String.init),
              let delim = counterpartyClause[verb] else { return nil }
        if let r = title.range(of: delim, options: .backwards) {
            if let name { return String(title[..<r.upperBound]) + name }
            return String(title[..<r.lowerBound])   // strip the clause
        }
        // No clause yet — a nameless title gains one from its verb.
        guard let name else { return nil }
        return title + delim + name
    }

    /// Rewrites the counterparty clause of every landed Wallet transfer whose
    /// stored counterparty matches — to `name`, or stripped when `name` is nil.
    /// The clause lives twice, and both writes happen here: the title's words,
    /// and `transferCounterparty` (the structured copy TransferStage reads) —
    /// updating one without the other is how a stage would drift from its row.
    ///
    /// Matching goes through `AddressBook.key` rather than a raw `lowercased()`
    /// compare, so it agrees with the book about what one address IS: identical
    /// for hex, and correct for a base58 counterparty, which case-folding would
    /// have quietly merged with a different wallet.
    ///
    /// Returns how many things changed — the caller decides whether that's
    /// worth showing.
    @discardableResult
    @MainActor
    static func apply(counterparty: String, name: String?, in context: ModelContext) -> Int {
        let key = AddressBook.key(for: counterparty)
        let all = (try? context.fetch(
            FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Wallet" }))) ?? []
        var changed = 0
        for thing in all.live {
            guard let stored = thing.counterpartyAddress,
                  AddressBook.key(for: stored) == key else { continue }
            var touched = false
            if let rebuilt = retitled(thing.title, to: name), rebuilt != thing.title {
                thing.title = rebuilt
                touched = true
            }
            if thing.transferCounterparty != name {
                thing.transferCounterparty = name
                touched = true
            }
            if touched { changed += 1 }
        }
        if changed > 0 {
            context.saveHonestly()
            CorpusSignal.shared.bump()   // Home/Feed compose a doc, not a live @Query
        }
        return changed
    }

    /// What this address is really CALLED, or nil.
    ///
    /// The short form is not a name. `WalletStore.add` and `addBulk` both file
    /// a bare address under its own `0x9a2E…44b1` so that every watched wallet
    /// is findable in its own book — a display fallback, not something the
    /// person typed. Feeding it to a rewrite would push a raw hash into
    /// history ("Received 1 ETH from 0x9a2E…44b1") and break the ingest rule
    /// that an unnamed address stays unnamed: the title never carries a hash.
    static func realName(for address: String) -> String? {
        guard let name = WalletIngest.knownLabel(for: address) else { return nil }
        return name == WalletStore.shortAddress(AddressBook.resolvedForm(of: address))
            ? nil : name
    }

    /// The rewrite for whatever the address is called NOW — the book's name if
    /// there is a real one, else whatever else resolves it (a known contract, a
    /// watched handle), else nothing, which strips the clause. The form every
    /// naming door wants: they've just written to the book and want history to
    /// agree with it.
    @discardableResult
    @MainActor
    static func applyCurrentName(for address: String, in context: ModelContext) -> Int {
        apply(counterparty: address, name: realName(for: address), in: context)
    }

    /// Every landed transfer brought in line with the WHOLE book, in one fetch
    /// — for a bulk paste, where calling `applyCurrentName` per address would
    /// re-fetch the corpus once per line.
    @discardableResult
    @MainActor
    static func applyBook(in context: ModelContext) -> Int {
        let all = (try? context.fetch(
            FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Wallet" }))) ?? []
        var names: [String: String?] = [:]   // key → real name, memoized
        var changed = 0
        for thing in all.live {
            guard let stored = thing.counterpartyAddress, !stored.isEmpty else { continue }
            let key = AddressBook.key(for: stored)
            let name: String?
            if let memo = names[key] { name = memo }
            else {
                name = realName(for: stored)
                names[key] = name
            }
            var touched = false
            if let rebuilt = retitled(thing.title, to: name), rebuilt != thing.title {
                thing.title = rebuilt
                touched = true
            }
            if thing.transferCounterparty != name {
                thing.transferCounterparty = name
                touched = true
            }
            if touched { changed += 1 }
        }
        if changed > 0 {
            context.saveHonestly()
            CorpusSignal.shared.bump()
        }
        return changed
    }
}
