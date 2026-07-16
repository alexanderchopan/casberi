import Foundation

/// Solana activity (2026-07-16, prd §86) — the wallet bridge's non-EVM half,
/// and the thing prd §85 deliberately left unbuilt. `alchemy_getAssetTransfers`
/// has no Solana equivalent, so this rebuilds the same story from the calls
/// Solana does offer.
///
/// It is CHEAPER than the EVM path, not dearer (the assumption that killed it
/// the first time round, measured 2026-07-16 and wrong): Solana's JSON-RPC
/// takes an ARRAY of calls, so one `getSignaturesForAddress` plus ONE batched
/// `getTransaction` returns ten whole transactions in a single ~0.4s request.
/// Two requests per wallet, against the EVM path's ten (five chains × two
/// directions).
///
/// The hard part was never fetching — it's deciding what's NEWS. Three
/// measured facts shape every rule below:
///
/// 1. **`getSignaturesForAddress` returns MENTIONS, not transfers.** This is
///    the real asymmetry with EVM, where `getAssetTransfers` only ever hands
///    back actual movement. Six of toly.sol's ten most recent signatures moved
///    nothing whatsoever for the owner — the wallet is merely named in someone
///    else's PumpSwap buy. They are dropped by having no legs at all.
/// 2. **The native balance delta is contaminated by fees and rent.** A wallet
///    that sent 299.9 USDC shows a −0.002064 SOL delta, which is not a SOL
///    send: it is the fee plus one rent-exempt token account. Add the fee back
///    (when this wallet paid it) and the remainder lands on EXACTLY 0.000000000
///    for a fee-only transaction, and EXACTLY 0.00203928 — the rent-exempt
///    minimum — for one that opened an account. `nativeNoiseFloor` is what
///    separates that mechanical residue from intent.
/// 3. **Signing is Solana's from/to.** Solana has no from/to for the EVM spam
///    rule to key on, but it has signers, and they carry the same meaning: a
///    transaction you SIGNED is one you did (EVM's "sent" — always news), and
///    one you didn't is something that happened to you (EVM's "received" —
///    filtered). Every one of toly.sol's ten was unsigned by him; every one of
///    Binance's eight was signed. The mapping held on both.
enum SolanaActivity {

    static let network = "solana-mainnet"
    private static let wrappedSOL = "So11111111111111111111111111111111111111112"

    /// Signatures pulled per wallet per pass — matches the EVM path's
    /// `maxCount: 0xa`, and they all ride one batched request anyway.
    private static let signatureLimit = 10

    /// Below this, a native SOL delta is mechanical residue rather than a move:
    /// the fee (~0.000005–0.000035) plus, when a transaction opens a token
    /// account, the rent-exempt minimum (0.00203928). Reporting either as
    /// "Sent 0.002 SOL" over a transaction whose real story is "Sent 299.9
    /// USDC" would be a lie in the title. Not a value judgment — the value
    /// judgment is `dustFloorUSD`, and it applies only to passive receipts.
    private static let nativeNoiseFloor = 0.005

    /// A PASSIVE native receipt under this is dust, not news — pump.fun creator
    /// fees land at ~$0.43 a piece, constantly, and would bury a feed. Mirrors
    /// `WalletIngest.holdingFloor` on purpose: the same line that decides a
    /// position isn't worth a treemap cell decides a windfall isn't worth a
    /// thing. Never applies to something you signed — that you did on purpose,
    /// however small, exactly as the EVM path lands any send.
    private static let dustFloorUSD = 1.99

    /// The venues we can name — Solana's answer to `WalletIngest.knownContracts`
    /// (the "no router-table analog" claim was wrong; program ids ARE the
    /// analog, and the logs even name the instruction). A swap through an
    /// unknown program still lands, just without the " on X" tail: the title
    /// never invents a venue it can't prove.
    private static let knownPrograms: [String: String] = [
        "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4": "Jupiter",
        "JUP4Fb2cqiRUcaTHdrPC8h2gNsA2ETXiPDD33WcGuJB": "Jupiter",
        "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8": "Raydium",
        "CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK": "Orca",
        "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc":  "Orca",
        "pAMMBay6oceH9fJKBRHGP5D4bD4sWpmSwMn52FMfXEA":  "PumpSwap",
        "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P":  "Pump.fun",
        "MFv2hWf31Z9kbCa1snEPYctwafyhdvnV7FZnsebVacA":  "Marinade",
    ]

    /// One asset moving in one transaction, from the owner's point of view.
    /// Negative left, positive arrived.
    struct Leg {
        let mint: String        // `wrappedSOL` stands in for the native coin
        let amount: Double      // already decimal-adjusted
    }

    /// One transaction that actually did something to this wallet.
    struct Move {
        let signature: String
        let when: Date
        /// True when the wallet signed — it did this, rather than had it done
        /// to it. Solana's stand-in for the EVM path's `received == false`.
        let signed: Bool
        let venue: String?
        let legs: [Leg]

        var gave: [Leg] { legs.filter { $0.amount < 0 } }
        var got: [Leg] { legs.filter { $0.amount > 0 } }
    }

    // MARK: - Fetch

    /// Every recent move for one Solana address, newest first, or nil when the
    /// RPC couldn't be reached at all (the caller's honest-failure signal —
    /// an EMPTY array is a real "nothing happened").
    static func moves(address: String, key: String) async -> [Move]? {
        let url = "https://\(network).g.alchemy.com/v2/\(key)"
        guard let sigs = await signatures(address: address, url: url) else { return nil }
        guard !sigs.isEmpty else { return [] }
        guard let txs = await transactions(sigs.map(\.0), url: url) else { return nil }

        let times = Dictionary(sigs.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        return txs.compactMap { sig, tx in
            guard let move = derive(tx: tx, signature: sig, address: address,
                                    when: times[sig] ?? .now) else { return nil }
            return move.legs.isEmpty ? nil : move   // mentions-only: nothing moved
        }
    }

    /// The signatures that so much as NAME this address, newest first, with the
    /// block time each carries (so the thing's date needs no second read).
    /// Failed transactions are dropped here — a reverted attempt isn't a story.
    private static func signatures(address: String, url: String) async -> [(String, Date)]? {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "getSignaturesForAddress",
            "params": [address, ["limit": signatureLimit]],
        ]
        guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
              let result = root["result"] as? [[String: Any]] else { return nil }
        return result.compactMap { row in
            guard row["err"] == nil || row["err"] is NSNull,
                  let sig = row["signature"] as? String else { return nil }
            let t = (row["blockTime"] as? Double).map { Date(timeIntervalSince1970: $0) }
            return (sig, t ?? .now)
        }
    }

    /// Every signature's full transaction in ONE request — Solana's JSON-RPC
    /// accepts an array of calls and answers with an array of results. This is
    /// the measurement that made the whole feature cheap (10 transactions,
    /// ~0.4s, one round trip). `maxSupportedTransactionVersion: 0` is required
    /// or every versioned transaction — which is most of them now — errors out.
    private static func transactions(_ sigs: [String], url: String) async -> [(String, [String: Any])]? {
        let batch: [[String: Any]] = sigs.enumerated().map { i, sig in
            ["jsonrpc": "2.0", "id": i, "method": "getTransaction",
             "params": [sig, ["encoding": "jsonParsed", "maxSupportedTransactionVersion": 0]]]
        }
        guard let results = await IngestSupport.postJSONArray(url, body: batch) else { return nil }
        var out: [(String, [String: Any])] = []
        for entry in results {
            guard let id = entry["id"] as? Int, id < sigs.count,
                  let tx = entry["result"] as? [String: Any] else { continue }
            out.append((sigs[id], tx))
        }
        return out
    }

    // MARK: - Derive

    /// Turns one raw transaction into what it did to THIS wallet — the whole
    /// interpretation layer, and the part with no EVM equivalent to lean on.
    private static func derive(tx: [String: Any], signature: String,
                               address: String, when: Date) -> Move? {
        guard let meta = tx["meta"] as? [String: Any],
              let message = tx["transaction"] as? [String: Any],
              let inner = message["message"] as? [String: Any],
              let keys = inner["accountKeys"] as? [[String: Any]] else { return nil }

        let mine = keys.first { $0["pubkey"] as? String == address }
        let signed = (mine?["signer"] as? Bool) ?? false
        let index = keys.firstIndex { $0["pubkey"] as? String == address }

        var legs: [Leg] = []

        // The native leg, fee-corrected. `accountKeys[0]` pays, so only then is
        // the fee this wallet's — add it back to recover what was INTENDED,
        // and drop what's left if it's only fee/rent residue.
        if let index, let pre = (meta["preBalances"] as? [Double])?[safe: index],
           let post = (meta["postBalances"] as? [Double])?[safe: index] {
            let fee = ((meta["fee"] as? Double) ?? 0) / 1e9
            let raw = (post - pre) / 1e9
            let intent = raw + (index == 0 ? fee : 0)
            if abs(intent) >= nativeNoiseFloor { legs.append(Leg(mint: wrappedSOL, amount: intent)) }
        }

        // The token legs, straight from the balances the runtime itself
        // recorded either side of the transaction — exact, and free of the fee
        // contamination the native leg has to be cleaned of.
        let pre = ownedBalances(meta["preTokenBalances"], owner: address)
        let post = ownedBalances(meta["postTokenBalances"], owner: address)
        for mint in Set(pre.keys).union(post.keys) {
            let delta = (post[mint] ?? 0) - (pre[mint] ?? 0)
            if abs(delta) > 1e-9 { legs.append(Leg(mint: mint, amount: delta)) }
        }

        return Move(signature: signature, when: when, signed: signed,
                    venue: venue(inner: inner, meta: meta), legs: legs)
    }

    /// A `mint → uiAmount` map of the token accounts THIS owner holds in the
    /// transaction. The `owner` field is what scopes it: a transaction touches
    /// many token accounts and only some are ours.
    private static func ownedBalances(_ raw: Any?, owner: String) -> [String: Double] {
        guard let entries = raw as? [[String: Any]] else { return [:] }
        var out: [String: Double] = [:]
        for entry in entries {
            guard entry["owner"] as? String == owner,
                  let mint = entry["mint"] as? String,
                  let amount = entry["uiTokenAmount"] as? [String: Any] else { continue }
            // uiAmount is null for a zero balance — that's 0, not "unknown".
            out[mint] = (amount["uiAmount"] as? Double) ?? 0
        }
        return out
    }

    /// The venue, when a program we know ran. Checked against the top-level
    /// programs invoked; nil when nothing recognisable did.
    private static func venue(inner: [String: Any], meta: [String: Any]) -> String? {
        var ids: [String] = []
        if let instructions = inner["instructions"] as? [[String: Any]] {
            ids += instructions.compactMap { $0["programId"] as? String }
        }
        if let innerSets = meta["innerInstructions"] as? [[String: Any]] {
            for set in innerSets {
                guard let list = set["instructions"] as? [[String: Any]] else { continue }
                ids += list.compactMap { $0["programId"] as? String }
            }
        }
        return ids.compactMap { knownPrograms[$0] }.first
    }

    // MARK: - Naming

    /// `mint → symbol`, from Jupiter's keyless token search — one call for
    /// every mint in the pass (comma-separated; 8 in, 8 out, measured).
    ///
    /// Why Jupiter and not something already wired up: Alchemy doesn't serve
    /// Metaplex DAS (`getAsset` returns "Unable to complete request"), and
    /// Dexscreener — which the Tokens bridge does use — fails on exactly the
    /// mints that matter. It never names USDC at all (USDC is a pair's QUOTE,
    /// and only base tokens carry a symbol), and it named wrapped SOL "FOGO",
    /// because SVM forks reuse mint addresses and its pair list spans chains.
    /// Jupiter answered all four correctly, decimals included. Measured
    /// 2026-07-16 — re-measure before swapping it out.
    /// Cached per launch INCLUDING misses — a wallet trades the same two or
    /// three mints all day, and an unnameable one must not cost a lookup every
    /// foreground forever. The same bargain `ENS.reverseName` struck for
    /// counterparties, for the same reason.
    @MainActor private static var symbolCache: [String: String?] = [:]

    @MainActor
    static func symbols(for mints: [String]) async -> [String: String] {
        let unique = Array(Set(mints)).sorted()   // sorted: a stable request order
        guard !unique.isEmpty else { return [:] }
        var out: [String: String] = [:]
        var wanted: [String] = []
        for mint in unique {
            if let cached = symbolCache[mint] {
                if let cached { out[mint] = cached }
            } else {
                wanted.append(mint)
            }
        }
        guard !wanted.isEmpty else { return out }

        for chunk in stride(from: 0, to: wanted.count, by: 8).map({
            Array(wanted[$0..<min($0 + 8, wanted.count)])
        }) {
            let query = chunk.joined(separator: ",")
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let rows = await IngestSupport.getJSON(
                    "https://lite-api.jup.ag/tokens/v2/search?query=\(encoded)") as? [[String: Any]]
            else { continue }
            for row in rows {
                guard let id = row["id"] as? String,
                      let symbol = (row["symbol"] as? String), !symbol.isEmpty else { continue }
                // Keyed by the mint the ANSWER carries, never the one we asked
                // for: this is Jupiter's `search`, not a lookup, so an unknown
                // mint can come back matched to some other token by name. Keying
                // off the response means such a stray simply never matches the
                // leg we were naming, and the move drops rather than wearing a
                // stranger's ticker.
                out[id] = symbol
            }
        }
        // Every mint we asked about is now settled — a hit caches its symbol, a
        // miss caches the miss.
        for mint in wanted { symbolCache[mint] = out[mint] }
        return out
    }

    // MARK: - Story

    /// The title a move earns, or nil when we can't tell it honestly.
    ///
    /// Naming is a gate, not a decoration: the design law says a title never
    /// wears a raw hash, and a mint IS a hash. A leg we can't name kills the
    /// whole title rather than printing `Received 1000000 GjWRMFCec…`.
    static func title(for move: Move, symbols: [String: String]) -> String? {
        func name(_ leg: Leg) -> String? {
            guard let symbol = symbols[leg.mint] else { return nil }
            return "\(WalletIngest.format(abs(leg.amount))) \(symbol)"
        }
        let gave = move.gave.sorted { abs($0.amount) > abs($1.amount) }
        let got = move.got.sorted { abs($0.amount) > abs($1.amount) }
        let tail = move.venue.map { " on \($0)" } ?? ""

        // Both sides move: one trade, not two half-stories — the same fold the
        // EVM path does with its send+receive legs on a shared hash.
        if let out = gave.first, let back = got.first {
            guard let a = name(out), let b = name(back) else { return nil }
            return "Swapped \(a) → \(b)\(tail)"
        }
        if let back = got.first {
            guard let a = name(back) else { return nil }
            return "Received \(a)\(tail)"
        }
        if let out = gave.first {
            guard let a = name(out) else { return nil }
            return "Sent \(a)\(tail)"
        }
        return nil
    }

    /// Whether a move is news for this wallet — Solana's spam rule.
    ///
    /// Signed means you did it: news, at any size, exactly as the EVM path
    /// lands any send. Unsigned means it happened TO you, and gets the same
    /// two guards EVM's receives get — a value floor for the native coin
    /// (creator-fee dust) and, for a token, the wallet's own priced holdings
    /// (`heldPriced`): a token you don't actually hold was pushed at you, not
    /// chosen by you. `heldPriced` nil means the holdings read FAILED — fail
    /// open and land it, the way the EVM arm does, rather than silently
    /// swallowing real activity over a hiccup.
    static func isNews(_ move: Move, heldPriced: Set<String>?, solPrice: Double?) -> Bool {
        if move.signed { return true }
        // Value LEFT a wallet that didn't sign for it — a delegated transfer,
        // and the most alarming thing a wallet can do. Always news, and checked
        // BEFORE the arrivals: a version of this that fell through to the got
        // loop would drop the whole move whenever a scrap of change happened to
        // come back alongside, silently swallowing the outgoing leg.
        if !move.gave.isEmpty { return true }
        for leg in move.got {
            if leg.mint == wrappedSOL {
                guard let solPrice else { return true }   // no price → don't judge
                if leg.amount * solPrice >= dustFloorUSD { return true }
            } else if let heldPriced {
                if heldPriced.contains(leg.mint) { return true }
            } else {
                return true   // holdings unread → fail open
            }
        }
        return false
    }

    /// SOL's price, for the passive-dust floor. Cached per launch — a floor
    /// doesn't need tick accuracy, and this must not cost a call per wallet.
    @MainActor private static var cachedSOL: (price: Double, at: Date)?

    @MainActor
    static func solPrice(key: String) async -> Double? {
        if let cachedSOL, cachedSOL.at.timeIntervalSinceNow > -900 { return cachedSOL.price }
        let body: [String: Any] = [
            "addresses": [["network": network, "address": wrappedSOL]],
        ]
        guard let root = await IngestSupport.postJSON(
                "https://api.g.alchemy.com/prices/v1/\(key)/tokens/by-address", body: body) as? [String: Any],
              let data = root["data"] as? [[String: Any]],
              let prices = data.first?["prices"] as? [[String: Any]],
              let raw = prices.first?["value"],
              let price = (raw as? Double) ?? Double(raw as? String ?? "")
        else { return nil }
        cachedSOL = (price, .now)
        return price
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
