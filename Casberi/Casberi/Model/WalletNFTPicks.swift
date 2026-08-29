import Foundation

/// THE NFT PICK BOOK (2026-08-15, prd §387) — which collections a watched
/// wallet has asked to see, and nothing else.
///
/// Foundation-only BY DESIGN so `scripts/wallet-nft-selftest.sh` can compile it
/// WHOLE and unmodified. Every network read, every view and the UserDefaults
/// mirror live in `WalletNFTShelf`; this file is the arithmetic those depend on
/// and is the only place a pick's identity is decided.
///
/// ## Why picks at all
///
/// The wallet NFT shelf shipped once (§72/§124a) and was cut on 2026-07-19 as
/// one of the two biggest credit sinks on the wallet path — `getNFTsForOwner`
/// fanned per wallet × per chain on every foreground, for a strip nobody used.
/// It comes back inverted: nothing is shown until somebody names a collection,
/// so the recurring read is bounded by a choice rather than by what an airdrop
/// pushed at you. That is the follow-import ruling (prd §87) in a second place
/// — when the honest alternative is a firehose, a picker is correct, with
/// nothing preselected and the person's taps deciding.
///
/// ## The collection is the unit
///
/// §240 recorded it and it holds: a pick names a CONTRACT, never a token id.
/// "Show my Squiggles" is a sentence someone means; "show Squiggle #4132 and
/// #7781 but not #221" is filing, which §178/§229 retired and which nobody
/// does. Per-piece trimming inside a picked collection is a later question, not
/// a v1 one.

/// A pick's identity: one collection on one chain.
///
/// Network-qualified because a contract address is only unique WITHIN a chain —
/// the same address on Ethereum and Base is two different collections, and
/// folding them would show pieces the wallet doesn't hold. Lowercased on the
/// way in: these are EVM addresses, whose case is an EIP-55 checksum and not
/// identity (the same normalisation `heldPricedContracts` makes, for the same
/// reason). There is no Solana arm — Alchemy's NFT API is EVM-only, which is
/// why a Solana-only wallet contributes no collections rather than an empty
/// list that reads as "you hold nothing".
enum NFTPickKey {
    static func make(network: String, contract: String) -> String {
        "\(network)|\(contract.lowercased())"
    }

    /// nil for anything that isn't a well-formed key — a stored book is decoded
    /// from UserDefaults, so a truncated or hand-edited value must not resolve
    /// to a plausible-looking half.
    ///
    /// `omittingEmptySubsequences: false` is deliberate and load-bearing.
    /// Swift's default is TRUE, which silently collapses "|0xabc" to a
    /// one-element array — so the emptiness guard below would be dead code and
    /// the rejection would rest on a stdlib default rather than on anything
    /// written here. Spelled out, the guard is the thing doing the work and the
    /// harness can prove it. (Caught by that harness's own mutation pass, which
    /// survived until this was made explicit.)
    static func split(_ key: String) -> (network: String, contract: String)? {
        let parts = key.split(separator: "|", maxSplits: 1,
                              omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }
}

/// One collection a wallet holds, as the picker draws it.
///
/// `isSpam` is Alchemy's own flag and is used for ORDER ALONE — never to hide,
/// and never shown as a label. Two reasons, and they are different: the user's
/// ruling ("i'd rather let user pick which nfts to show than hide a bunch in
/// 'junk'"), and §83 — the flag is a third party's guess, so printing "spam"
/// beside somebody's collection states a guess as a fact on the one screen
/// where they are deciding what they care about. Sorting is reversible and
/// costs nothing when it's wrong; a label isn't and doesn't.
struct NFTCollection: Identifiable, Sendable, Equatable {
    /// Alchemy network id — "eth-mainnet", "base-mainnet", …
    let network: String
    /// Lowercased contract address.
    let contract: String
    let name: String
    /// nil when the collection has no artwork we can draw. Kept rather than
    /// dropped: a nameless, imageless collection is still one the person may
    /// recognise by count, and dropping it would make the picker quietly
    /// disagree with the wallet.
    let imageURL: String?
    /// How many pieces of it the wallet holds.
    ///
    /// SHOWN on every cell, and deliberately NOT what the list is ranked by
    /// (2026-08-15, see `NFTCollectionOrder`).
    let count: Int
    let isSpam: Bool
    /// Whether OpenSea has SAFELISTED the collection
    /// (`openSeaMetadata.safelistRequestStatus`, 2026-08-26, prd §481).
    ///
    /// Read for the feed's NFT-origin rule, where it can only ever ADD a row:
    /// safelisting is positive evidence, and its ABSENCE is no evidence at all
    /// (most legitimate collections are not safelisted). Deliberately drawn
    /// NOWHERE in the picker — §387 ruled that a third party's classification
    /// may order that list and never label it, and a "verified" badge beside
    /// somebody's own collection states a guess as a fact (§83) just as loudly
    /// as a "spam" one does.
    ///
    /// Defaulted so the memberwise init keeps working for any caller that has
    /// no opinion; the one real call site fills it in.
    var isVerified: Bool = false
    /// Where this collection sat in the chain's own response — 0 is the most
    /// recently transferred.
    ///
    /// Alchemy serves `getContractsForOwner` in `transferTime` order and
    /// publishes NO timestamp on the contract itself (measured 2026-08-15:
    /// `orderBy=transferTime` answers 200 and returns the same order as the
    /// default). So this is a RANK, not a date, and it is exact only WITHIN a
    /// chain — the six chains are read separately and nothing relates their
    /// positions to each other. That limit is why the sort it drives is called
    /// "Recent" rather than "Newest": the app should not imply a precision the
    /// API never gave it.
    var arrival: Int = 0

    var id: String { NFTPickKey.make(network: network, contract: contract) }
}

/// How many pieces of a collection a wallet holds, read out of Alchemy's
/// `getContractsForOwner` — MEASURED 2026-08-15 against a real wallet, after the
/// doc-derived first cut shipped visible garbage (`count=-1486618624`).
///
/// Three findings, and the ranking one matters most:
///
/// 1. **`numDistinctTokensOwned` is the right field, not `totalBalance`.**
///    Measured on one contract: `totalBalance` 912, `numDistinctTokensOwned` 80.
///    `totalBalance` sums ERC-1155 QUANTITIES, so a wallet holding 80 different
///    pieces reads as 912 — and since the picker ranks on this number, an
///    edition somebody holds many copies of would outrank the collection they
///    actually collect. The picker's question is "how many pieces", which is the
///    distinct count.
/// 2. **Both fields are JSON STRINGS** (`"912"`), not numbers — so a bare
///    `as? Int` yields nil and every collection silently falls back to 1,
///    flattening the whole ranking.
/// 3. **Some chains answer with a huge JSON NUMBER**, and `as? Int` on an
///    `NSNumber` backed by a large `Double` truncates to nonsense (the negative
///    count above). A value that cannot be a real holding is treated as
///    UNKNOWN rather than believed.
enum NFTCountField {
    /// The largest plausible holding. A real collector's biggest position is
    /// thousands; a spam contract answering with a token-decimals-scaled
    /// balance is billions. Above this the number is not a count of anything.
    static let ceiling = 10_000_000

    /// String first, because that is what the API actually sends.
    static func parse(_ raw: Any?) -> Int? {
        if let s = raw as? String, let n = Int(s) { return sane(n) }
        if let n = raw as? Int { return sane(n) }
        // Only a Double that is exactly integral and inside the ceiling — the
        // truncation case above enters here, and must not survive it.
        if let d = raw as? Double, d.isFinite, d == d.rounded(),
           d >= 0, d <= Double(ceiling) { return sane(Int(d)) }
        return nil
    }

    private static func sane(_ n: Int) -> Int? {
        (n > 0 && n <= ceiling) ? n : nil
    }

    /// The count for one contract payload, preferring distinct pieces.
    ///
    /// Falls back to 1, never 0: a collection the read RETURNED is one the
    /// wallet holds, and a 0 would sort a real collection below every other as
    /// if it were the least held.
    static func count(distinct: Any?, total: Any?) -> Int {
        parse(distinct) ?? parse(total) ?? 1
    }
}

/// How the picker is ordered (user's ruling, 2026-08-15).
///
/// `name` is the default and `recent` is the sorter beside it. Count is
/// deliberately NOT an option — see `NFTCollectionOrder`.
enum NFTSort: String, CaseIterable, Sendable {
    case name
    case recent
}

enum NFTCollectionOrder {
    /// The picker's order, in TWO BANDS: everything Alchemy does not flag, then
    /// everything it does. The chosen sort applies inside each band.
    ///
    /// **The band is the part doing the work, and it is measured**: on one page
    /// of a real wallet, 81 of 100 contracts were `isSpam`. Without the band, an
    /// A–Z list is 81% airdrops and the collections somebody actually wants are
    /// scattered through them. Nothing is hidden and everything stays pickable —
    /// the flag reaches ORDER alone, never a filter and never a label (§83, and
    /// the user's "no junk fold" ruling).
    ///
    /// **Count was the original rank and is now shown but never ranked on.** The
    /// first live run refuted the reasoning behind it: "holding forty of
    /// something means you chose it" is exactly backwards on a wallet people
    /// airdrop AT, and the picker led with 2,001 Chicky Runners. Count survives
    /// on each cell as a FACT, which is where it was always honest.
    ///
    /// TOTAL by construction under either sort — the id tiebreak is what makes
    /// it so, and it matters here more than on any room card, because this is a
    /// list somebody returns to in order to change a decision they made against
    /// the previous ordering.
    static func sorted(_ collections: [NFTCollection],
                       by sort: NFTSort = .name) -> [NFTCollection] {
        collections.sorted { a, b in
            if a.isSpam != b.isSpam { return !a.isSpam }
            switch sort {
            case .name:
                let byName = a.name.localizedCaseInsensitiveCompare(b.name)
                if byName != .orderedSame { return byName == .orderedAscending }
            case .recent:
                // Lower arrival is more recent. Only meaningful within a chain
                // (see `NFTCollection.arrival`), so ties across chains fall
                // through to name — which keeps the order total and stops two
                // chains' #0 from swapping places between opens.
                if a.arrival != b.arrival { return a.arrival < b.arrival }
                let byName = a.name.localizedCaseInsensitiveCompare(b.name)
                if byName != .orderedSame { return byName == .orderedAscending }
            }
            return a.id < b.id
        }
    }
}

/// Every wallet's picks, as one value.
///
/// A value type rather than a store so the whole of the pick arithmetic is
/// testable without UserDefaults, a run loop or a main actor — `WalletNFTShelf`
/// owns exactly one of these and persists it.
struct NFTPickBook: Codable, Equatable, Sendable {
    /// Watched wallet address (lowercased) → the pick keys chosen for it.
    ///
    /// Keyed per WALLET, not globally, because the same person can watch a
    /// personal wallet and a shared one and mean different things by each; and
    /// because forgetting a wallet must forget its picks without touching
    /// anybody else's.
    private(set) var byWallet: [String: Set<String>]

    init(byWallet: [String: Set<String>] = [:]) {
        self.byWallet = byWallet
    }

    /// Wallet addresses are EVM/Solana strings arriving from several call sites
    /// (a watch list entry, a probe argument, a resolved ENS name). Normalising
    /// HERE rather than at each caller is what keeps `toggle` and `isPicked`
    /// from silently disagreeing about the same wallet.
    private static func walletKey(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func isPicked(wallet: String, collection: String) -> Bool {
        byWallet[Self.walletKey(wallet)]?.contains(collection) ?? false
    }

    func picks(wallet: String) -> Set<String> {
        byWallet[Self.walletKey(wallet)] ?? []
    }

    /// Toggles one collection for one wallet and returns whether it is now ON.
    ///
    /// Empties are PRUNED rather than left as an empty set: `hasPicks` and the
    /// shelf's own "is there anything to draw" test both read this map, and a
    /// wallet holding an empty set would answer "yes, picks exist" for a wallet
    /// whose every pick was just cleared.
    @discardableResult
    mutating func toggle(wallet: String, collection: String) -> Bool {
        let key = Self.walletKey(wallet)
        var set = byWallet[key] ?? []
        let nowOn: Bool
        if set.contains(collection) {
            set.remove(collection)
            nowOn = false
        } else {
            set.insert(collection)
            nowOn = true
        }
        if set.isEmpty { byWallet.removeValue(forKey: key) } else { byWallet[key] = set }
        return nowOn
    }

    mutating func clear(wallet: String) {
        byWallet.removeValue(forKey: Self.walletKey(wallet))
    }

    /// Drops every wallet that is no longer watched.
    ///
    /// Called when the watch list changes, so unwatching a wallet and watching
    /// it again does not silently restore picks made in a previous life — and
    /// so the book cannot grow forever behind a 5-wallet cap.
    mutating func retain(wallets: [String]) {
        let keep = Set(wallets.map(Self.walletKey))
        byWallet = byWallet.filter { keep.contains($0.key) }
    }

    /// STRICT — `byWallet.isEmpty`, not "every entry happens to be empty".
    ///
    /// That is only correct because `toggle`, `clear` and `retain` all prune,
    /// so a key existing means it really has picks; and spelling it strictly is
    /// what makes that invariant observable, and therefore defensible by the
    /// harness. The forgiving version (`allSatisfy { $0.value.isEmpty }`) reads
    /// as more robust and is worse: it silently tolerates the broken state
    /// instead of failing on it, so nothing can tell the two apart.
    ///
    /// `WalletNFTStore.persist` reads it to remove the stored key entirely when
    /// the last pick goes, rather than leaving `{}` behind.
    var isEmpty: Bool { byWallet.isEmpty }

    func hasPicks(wallet: String) -> Bool { !picks(wallet: wallet).isEmpty }

    /// The picked contracts for one wallet on one chain — the narrow read's
    /// whole argument list.
    ///
    /// Sorted so the request URL for an unchanged set of picks is byte-identical
    /// between calls; the shelf's cache is keyed on it, and a set's iteration
    /// order is not stable, so an unsorted list would miss its own cache at
    /// random and re-buy a read it already had.
    func contracts(wallet: String, network: String) -> [String] {
        picks(wallet: wallet)
            .compactMap { NFTPickKey.split($0) }
            .filter { $0.network == network }
            .map(\.contract)
            .sorted()
    }

    /// Every chain this wallet has a pick on — so the shelf asks the two or
    /// three chains that can answer instead of all five.
    func networks(wallet: String) -> [String] {
        Set(picks(wallet: wallet).compactMap { NFTPickKey.split($0)?.network }).sorted()
    }
}

/// THE SHELF'S GRID (prd §514, 2026-08-28, user: *"if a user picks more than 4
/// to show can we make the slot in the wallet that shows 4 resize to show five
/// or six somehow? maybe we show them in tiles in a three by three grid"*).
///
/// The quad was fixed at 2x2 / four cells, so a wallet with six picked
/// collections saw four pieces and nothing said the other two existed inside
/// the drawing — §307's silent-truncation shape, in a slot whose whole job is
/// to be the reading. The grid gets DENSER instead of taller.
///
/// **The SLOT does not resize, and that is the answer to the literal ask.**
/// `DSRoomChassis.visualSlot` is the fixed box every scope's figure draws into
/// (§483) — Holdings' treemap, Risk's strip and this share it, and a room whose
/// figure box changes height per scope is the reflow §483 spent its whole
/// ruling avoiding. What changes is how the box is divided.
///
/// **Two densities and no more.** 2x2 up to four, 3x3 past it. A fourth column
/// puts the cell under 90pt wide inside a 210pt box, which is a contact sheet
/// rather than a shelf, and the list below already carries every piece — so
/// past nine the drawing stops and the rows do the work, exactly as they did
/// past four.
///
/// Foundation-only, in this file rather than beside the view, because it is
/// arithmetic that renders plausibly when it is wrong: a row of two under a row
/// of three reads as a feature, and a cell side that ignores the gaps overflows
/// a fixed box and gets clipped.
enum NFTGrid {
    /// The most cells the drawing will ever hold — three squared.
    static let maxCells = 9

    /// How many across, for a given number of pieces to show.
    ///
    /// Counts the pieces AVAILABLE, not the pieces drawn, so the density is
    /// decided before the cap is applied — deriving it from the capped list
    /// would make five pieces ask for three columns and then be handed nine
    /// cells' worth of them, which is the same number by luck rather than by
    /// rule.
    static func columns(available: Int) -> Int { available > 4 ? 3 : 2 }

    /// How many the drawing shows. Squared rather than `columns * rows`
    /// because the rows follow from the count.
    static func cap(available: Int) -> Int {
        let c = columns(available: available)
        return c * c
    }

    /// The shown pieces in rows of `columns`.
    ///
    /// Generic over the element so the harness can prove the chunking with
    /// plain integers — the pairing is the one piece of arithmetic here that
    /// can be wrong in a way that still renders (three pieces as 2+1 versus
    /// 1+2, which puts the odd cell in the wrong corner).
    static func rows<T>(_ shown: [T], columns: Int) -> [[T]] {
        guard columns > 0 else { return [] }
        return stride(from: 0, to: shown.count, by: columns).map {
            Array(shown[$0..<min($0 + columns, shown.count)])
        }
    }

    /// How many empty cells the LAST row needs so its art stays the same size
    /// as every other row's.
    ///
    /// Without it a final row of one draws a single cell across the full width
    /// under a row of three, which reads as a feature ("this one is bigger")
    /// rather than as the end of a list.
    static func padding(lastRow count: Int, columns: Int) -> Int {
        guard columns > 0, count > 0, count < columns else { return 0 }
        return columns - count
    }

    /// One cell's side, along either axis: the box, less every gap between the
    /// cells, divided by them.
    ///
    /// The gaps are `n - 1`, not `n`. Spelling it `box / n - gap` is the error
    /// that renders — the grid overflows a fixed box by one gap and the last
    /// row is clipped, which is what the wider gap had just been fixed for.
    static func side(box: CGFloat, gap: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return (box - gap * CGFloat(count - 1)) / CGFloat(count)
    }
}
