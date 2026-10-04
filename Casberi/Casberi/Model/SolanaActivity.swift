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

    /// Signatures pulled per wallet on its FIRST pass — matches the EVM path's
    /// `maxCount: 0xa`, and they all ride one batched request anyway.
    private static let signatureLimit = 10

    /// Signatures pulled once a cursor stands: everything since the newest one
    /// the last pass saw, up to this many. A cursor is what makes the window
    /// honest — without one, ten signatures of which six are MENTIONS (fact 1
    /// below) let a wallet named in a busy day's swaps push its own moves past
    /// the window between two refreshes, and they never landed. A gap wider
    /// than this keeps its newest fifty; the transactions ride batches of ten.
    private static let gapLimit = 50
    private static let batchSize = 10

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
    ///
    /// **Measured 2026-10-03 against Jupiter's own router table**
    /// (`lite-api.jup.ag/swap/v1/program-id-to-label`, the venues Jupiter
    /// routes through), and every id read back executable on chain. Names are
    /// the BRAND, never Jupiter's version labels ("Raydium CLMM" is Raydium),
    /// because the tail says where you traded, not which contract. The table
    /// had `CAMMCzo5…` as Orca; it is Raydium's concentrated pools. Not taken
    /// from that table: `SPoo1Ku8…`, which Jupiter labels Sanctum but is the
    /// SPL stake-pool program behind Jito's and most liquid-staking pools — a
    /// JitoSOL deposit "on Sanctum" would be a venue the title invented. The
    /// lending, perps and NFT programs below are not Jupiter venues; their ids
    /// are each protocol's published program, read back executable the same day.
    private static let knownPrograms: [String: String] = [
        // Jupiter: the aggregator, DCA, perps, lend.
        "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4": "Jupiter",
        "JUP4Fb2cqiRUcaTHdrPC8h2gNsA2ETXiPDD33WcGuJB": "Jupiter",
        "DCA265Vj8a9CEuX1eb1LWRnDT7uK6q1xMipnNyatn23M": "Jupiter",
        "PERPHjGBqRHArX4DySjwM6UJHiR3sWAatqfdBS2qQJu": "Jupiter",
        "jup3YeL8QhtSx1e253b2FDvsMNC87fDrgQZivbrndc9":  "Jupiter",
        "jupZ4m2GqUCJ5iueMfzQf8khFfH31d4XAQt3RzCT9Vd":  "Jupiter",
        // Raydium: AMM v4, concentrated, CP, LaunchLab.
        "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8": "Raydium",
        "CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK": "Raydium",
        "CPMMoo8L3F4NbTegBCKVNunggL7H1ZpdTHKxQB5qKP1C": "Raydium",
        "LanMV9sAd7wArD4vJFi2qDdfnVhFxYSUg6eADduJ3uj":  "Raydium",
        // Orca: Whirlpools and the two older swap programs.
        "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc":  "Orca",
        "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP": "Orca",
        "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1": "Orca",
        // Meteora: DLMM, dynamic pools, DAMM v2, the bonding curve.
        "LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo":  "Meteora",
        "Eo7WjKq67rjJQSZxS6z3YkapzY3eMj6Xy8X5EQVn5UaB": "Meteora",
        "cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG":  "Meteora",
        "dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN":  "Meteora",
        // Pump.fun's curve and its AMM, which it brands PumpSwap.
        "pAMMBay6oceH9fJKBRHGP5D4bD4sWpmSwMn52FMfXEA":  "PumpSwap",
        "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P":  "Pump.fun",
        // Order books and the rest of the routed venues.
        "PhoeNiXZ8ByJGLkxNfZRnkUfjvmuYqLR89jjFHGqdXY":  "Phoenix",
        "opnb2LAfJYbRMAHHvqjCwQxanZn7ReEHp1k81EohpZb":  "OpenBook",
        "MNFSTqtC93rEfYHB6hF82sKdZpUDFWkViLByLd1k1Ms":  "Manifest",
        "SSwpkEEcbUqx4vtoEByFjSkhKdCT862DNVb52nZg1UZ":  "Saber",
        "SSwapUtytfBdBn1b9NUGG6foMVPtcWgpRU32HToDUZr":  "Saros",
        "1qbkdrr3z4ryLA7pZykqxvxWPoeifcVKo6ZG9CfkvVE":  "Saros",
        "MoonCVVNZFSYkqNXP6bxHLPL6QQJiMagDL3qcqUQTrG":  "Moonit",
        "boop8hVGQGqehUK2iVEMEnMrL5RbjywRzHKBmBE7ry4":  "Boop.fun",
        // Sanctum: its router, Infinity, and its own single/multi pools.
        "stkitrT1Uoy18Dk1fTrgPw8W6MVzoCfYoAFT4MLsmhq":  "Sanctum",
        "5ocnV1qiCgaQR8Jb8xWnVbApfaygJ8tNoZfgPwsgx9kx": "Sanctum",
        "SP12tWFxD9oJsVWNavTTBZvMbA6gkAmxtVgxdqvyvhY":  "Sanctum",
        "SPMBzsVUuoHA4Jm6KunbsotaahvVikZs1JyTW6iJvbn":  "Sanctum",
        // Staking, lending, perps and NFT markets.
        "MFv2hWf31Z9kbCa1snEPYctwafyhdvnV7FZnsebVacA":  "Marinade",
        "KLend2g3cP87fffoy8q1mQqGKjrxjC8boSyAYavgmjD":  "Kamino",
        "dRiftyHA39MWEi3m9aunc5MzRF1JYuBsbn6VPcn33UH":  "Drift",
        "M2mx93ekt1fmXSVkTrUL9xVFHkmME8HTUi5Cyc5aF7K":  "Magic Eden",
        "TSWAPaqyCSx2KABk68Shruf4rp7CxcNi8hAsbdwmHbN":  "Tensor",
    ]

    /// One asset moving in one transaction, from the owner's point of view.
    /// Negative left, positive arrived.
    struct Leg {
        let mint: String        // `wrappedSOL` stands in for the native coin
        let amount: Double      // already decimal-adjusted
    }

    /// A token account this wallet OWNS was given a delegate in this
    /// transaction (`approve` / `approveChecked`, SPL Token or Token-2022) —
    /// Solana's ERC-20 approval: the delegate may move up to `amountRaw` of
    /// that account's tokens without another signature. Only the owner can
    /// sign one, so unlike EVM's `Approval` log it cannot be faked at a
    /// famous address (`WalletApprovals`' lesson 2 has no Solana twin).
    struct Grant: Equatable {
        /// The token account the delegate may spend from — where its live
        /// state is read back (`standing`).
        let tokenAccount: String
        let delegate: String
        /// nil when neither the instruction nor the balances named it.
        let mint: String?
        /// Base units, as the instruction carried them. `UInt64.max` is the
        /// "unlimited" every wallet means by it.
        let amountRaw: UInt64
        let decimals: Int?

        var unlimited: Bool { amountRaw == UInt64.max }
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
        /// Delegates this wallet granted on its own token accounts. A move
        /// with grants and no legs is still a move: an approval moves nothing
        /// and is the most consequential thing a wallet signs.
        var grants: [Grant] = []

        var gave: [Leg] { legs.filter { $0.amount < 0 } }
        var got: [Leg] { legs.filter { $0.amount > 0 } }
    }

    // MARK: - Fetch

    /// One pass's read of one wallet: its moves, newest first, and the newest
    /// signature that NAMED it at all (failed or not) — the cursor the next
    /// pass reads forward from. `newest` is nil when nothing new was named.
    struct Read {
        let moves: [Move]
        let newest: String?
    }

    /// Every move since `cursor` (the newest signature the last landed pass
    /// saw), or the most recent ten when there is none yet. nil when the RPC
    /// couldn't be reached at all (the caller's honest-failure signal — an
    /// EMPTY read is a real "nothing happened"). One batch failing fails the
    /// read whole, so the caller never advances its cursor past a hole.
    static func moves(address: String, key: String, since cursor: String?) async -> Read? {
        let url = "https://\(network).g.alchemy.com/v2/\(key)"
        guard let named = await signatures(address: address, url: url, until: cursor)
        else { return nil }
        let (sigs, newest) = named
        guard !sigs.isEmpty else { return Read(moves: [], newest: newest) }

        var txs: [(String, [String: Any])] = []
        for start in stride(from: 0, to: sigs.count, by: batchSize) {
            let chunk = sigs[start..<min(start + batchSize, sigs.count)].map(\.0)
            guard let got = await transactions(chunk, url: url) else { return nil }
            txs += got
        }

        let times = Dictionary(sigs.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        let moves: [Move] = txs.compactMap { sig, tx in
            guard let move = derive(tx: tx, signature: sig, address: address,
                                    when: times[sig] ?? .now) else { return nil }
            // Mentions-only: nothing moved and nothing was granted.
            return move.legs.isEmpty && move.grants.isEmpty ? nil : move
        }
        return Read(moves: moves, newest: newest)
    }

    /// The signatures that so much as NAME this address, newest first, with the
    /// block time each carries (so the thing's date needs no second read), and
    /// the newest signature of all — failed ones included, since a cursor only
    /// marks how far the read got. Failed transactions are dropped from the
    /// list — a reverted attempt isn't a story. `until` stops the walk at the
    /// last pass's cursor (exclusive), so a quiet wallet costs one empty answer.
    private static func signatures(address: String, url: String,
                                   until cursor: String?) async -> ([(String, Date)], String?)? {
        var options: [String: Any] = ["limit": cursor == nil ? signatureLimit : gapLimit]
        if let cursor { options["until"] = cursor }
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "getSignaturesForAddress",
            "params": [address, options],
        ]
        guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
              let result = root["result"] as? [[String: Any]] else { return nil }
        let newest = result.first?["signature"] as? String
        let sigs: [(String, Date)] = result.compactMap { row in
            guard row["err"] == nil || row["err"] is NSNull,
                  let sig = row["signature"] as? String else { return nil }
            let t = (row["blockTime"] as? Double).map { Date(timeIntervalSince1970: $0) }
            return (sig, t ?? .now)
        }
        return (sigs, newest)
    }

    // MARK: - Cursor

    /// The newest signature each wallet's last LANDED pass saw, by address
    /// (base58, case kept). Read once per launch into memory, written through
    /// `DefaultsWrite` (prd §721). An entry is only ever advanced by
    /// `WalletIngest.solanaSync`, and only when every move in the read landed
    /// or was ruled not-news — never past a move dropped for want of a name,
    /// which the next pass asks about again.
    private static let cursorKey = "wallet.solana.cursor.v1"
    @MainActor private static var cursors: [String: String] = {
        guard let data = UserDefaults.standard.data(forKey: cursorKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }()

    @MainActor static func cursor(for address: String) -> String? { cursors[address] }

    @MainActor static func advance(_ address: String, to signature: String) {
        guard cursors[address] != signature else { return }
        cursors[address] = signature
        if let data = try? JSONEncoder().encode(cursors) {
            DefaultsWrite.set(data, forKey: cursorKey)
        }
    }

    /// Every signature's full transaction in ONE request — Solana's JSON-RPC
    /// accepts an array of calls and answers with an array of results. This is
    /// the measurement that made the whole feature cheap (10 transactions,
    /// ~0.4s, one round trip).
    ///
    /// **`maxSupportedTransactionVersion` is 1, and 0 was dropping a fifth of
    /// mainnet.** Without the parameter every versioned transaction errors out;
    /// at 0, every VERSION 1 transaction does — an error per entry that the
    /// loop below skips like any other missing result, so the move never
    /// existed. Measured 2026-10-03 over 28 recent blocks: legacy 22,146,
    /// v0 6,593, v1 6,410 (18%). A v1 transaction's jsonParsed shape carries
    /// the same `accountKeys`, balances and instructions `derive` reads. When a
    /// version 2 arrives the same silence returns, so `transactions` logs the
    /// RPC's own refusal rather than swallowing it.
    private static func transactions(_ sigs: [String], url: String) async -> [(String, [String: Any])]? {
        let batch: [[String: Any]] = sigs.enumerated().map { i, sig in
            ["jsonrpc": "2.0", "id": i, "method": "getTransaction",
             "params": [sig, ["encoding": "jsonParsed", "maxSupportedTransactionVersion": 1]]]
        }
        guard let results = await IngestSupport.postJSONArray(url, body: batch) else { return nil }
        var out: [(String, [String: Any])] = []
        for entry in results {
            if let error = entry["error"] as? [String: Any] {
                NSLog("SolanaActivity: getTransaction refused — %@",
                      (error["message"] as? String) ?? "\(error)")
                continue
            }
            guard let id = entry["id"] as? Int, id < sigs.count,
                  let tx = entry["result"] as? [String: Any] else { continue }
            out.append((sigs[id], tx))
        }
        return out
    }

    // MARK: - Derive

    /// Turns one raw transaction into what it did to THIS wallet — the whole
    /// interpretation layer, and the part with no EVM equivalent to lean on.
    static func derive(tx: [String: Any], signature: String,
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
                    venue: venue(inner: inner, meta: meta), legs: legs,
                    grants: signed ? grants(inner: inner, meta: meta, keys: keys, owner: address) : [])
    }

    /// The SPL programs whose `approve` makes a delegate — Token and
    /// Token-2022, which share the instruction (jsonParsed names both).
    private static let tokenPrograms: Set<String> = ["spl-token", "spl-token-2022"]

    /// Every delegate this owner granted in the transaction, top-level or
    /// inner. `approveChecked` names its mint and decimals; plain `approve`
    /// does not, so those are read off the balances the runtime recorded for
    /// the same token account. A later `revoke` of the same account in the
    /// same transaction cancels the grant — some programs approve a delegate
    /// for one hop and clear it before returning.
    private static func grants(inner: [String: Any], meta: [String: Any],
                               keys: [[String: Any]], owner: String) -> [Grant] {
        var instructions = (inner["instructions"] as? [[String: Any]]) ?? []
        for set in (meta["innerInstructions"] as? [[String: Any]]) ?? [] {
            instructions += (set["instructions"] as? [[String: Any]]) ?? []
        }
        // Mint and decimals by token account, off the recorded balances.
        var mintOf: [String: (mint: String, decimals: Int?)] = [:]
        for raw in [meta["preTokenBalances"], meta["postTokenBalances"]] {
            for entry in (raw as? [[String: Any]]) ?? [] {
                guard let index = entry["accountIndex"] as? Int,
                      let account = keys[safe: index]?["pubkey"] as? String,
                      let mint = entry["mint"] as? String else { continue }
                let decimals = (entry["uiTokenAmount"] as? [String: Any])?["decimals"] as? Int
                mintOf[account] = (mint, decimals)
            }
        }
        var out: [String: Grant] = [:]   // by token account: the last word wins
        for ix in instructions {
            guard let program = ix["program"] as? String, tokenPrograms.contains(program),
                  let parsed = ix["parsed"] as? [String: Any],
                  let type = parsed["type"] as? String,
                  let info = parsed["info"] as? [String: Any],
                  info["owner"] as? String == owner,
                  let account = info["source"] as? String else { continue }
            switch type {
            case "approve", "approveChecked":
                let tokenAmount = info["tokenAmount"] as? [String: Any]
                guard let delegate = info["delegate"] as? String,
                      let rawString = (tokenAmount?["amount"] as? String) ?? (info["amount"] as? String),
                      let raw = UInt64(rawString), raw > 0 else { continue }
                let known = mintOf[account]
                out[account] = Grant(tokenAccount: account, delegate: delegate,
                                     mint: (info["mint"] as? String) ?? known?.mint,
                                     amountRaw: raw,
                                     decimals: (tokenAmount?["decimals"] as? Int) ?? known?.decimals)
            case "revoke":
                out[account] = nil
            default:
                continue
            }
        }
        return out.values.sorted { $0.tokenAccount < $1.tokenAccount }
    }

    /// The grants among these that STILL stand — the token account's live
    /// delegate is the one granted, with something left to spend. One batched
    /// read (`getMultipleAccounts`), asked only when a pass found grants.
    /// nil when the RPC couldn't answer: the caller holds them for the next
    /// pass rather than landing a grant it could not confirm, or dropping one.
    static func standing(_ grants: [Grant], key: String) async -> Set<String>? {
        let accounts = Array(Set(grants.map(\.tokenAccount))).sorted()
        guard !accounts.isEmpty else { return [] }
        let url = "https://\(network).g.alchemy.com/v2/\(key)"
        var live: Set<String> = []
        for start in stride(from: 0, to: accounts.count, by: 100) {
            let chunk = Array(accounts[start..<min(start + 100, accounts.count)])
            let body: [String: Any] = [
                "jsonrpc": "2.0", "id": 1, "method": "getMultipleAccounts",
                "params": [chunk, ["encoding": "jsonParsed"]],
            ]
            guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
                  let result = root["result"] as? [String: Any],
                  let values = result["value"] as? [Any], values.count == chunk.count
            else { return nil }
            for (account, value) in zip(chunk, values) {
                guard let value = value as? [String: Any],
                      let data = value["data"] as? [String: Any],
                      let parsed = data["parsed"] as? [String: Any],
                      let info = parsed["info"] as? [String: Any],
                      let delegate = info["delegate"] as? String,
                      let left = (info["delegatedAmount"] as? [String: Any])?["amount"] as? String,
                      left != "0" else { continue }
                // The account and its delegate together: a grant re-pointed at
                // someone else since is not the grant this row would describe.
                live.insert(account + ":" + delegate)
            }
        }
        return live
    }

    /// "Approved …C4xN to spend unlimited USDC" — `WalletApprovals.title`'s
    /// sentences, word for word and through the same catalog keys, so a grant
    /// reads the same whichever chain made it. The asset falls back to the
    /// mint's short form rather than dropping the row: a grant is the one
    /// story that must land even when it cannot be named.
    @MainActor
    static func grantTitle(_ grant: Grant, symbols: [String: String]) -> String {
        // The book by its own key, never `WalletIngest.knownLabel`: that
        // lowercases for hex, and base58's case IS the address.
        let spender = AddressBook.shared.name(for: grant.delegate)
            ?? WalletStore.shortAddress(grant.delegate)
        let asset = grant.mint.flatMap { symbols[$0] }
            ?? grant.mint.map(WalletStore.shortAddress)
            ?? String(localized: "a token")
        let via = ""
        if grant.unlimited {
            return String(localized: "Approved \(spender) to spend unlimited \(asset)\(via)")
        }
        if let decimals = grant.decimals {
            let amount = WalletIngest.format(Double(grant.amountRaw) / pow(10, Double(decimals)))
            return String(localized: "Approved \(spender) to spend \(amount) \(asset)\(via)")
        }
        return String(localized: "Approved \(spender) to spend \(asset)\(via)")
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

        var answered = Set<String>()
        for chunk in stride(from: 0, to: wanted.count, by: 8).map({
            Array(wanted[$0..<min($0 + 8, wanted.count)])
        }) {
            let query = chunk.joined(separator: ",")
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let rows = await IngestSupport.getJSON(
                    "https://lite-api.jup.ag/tokens/v2/search?query=\(encoded)") as? [[String: Any]]
            else { continue }
            answered.formUnion(chunk)
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
        // Every mint Jupiter ANSWERED about is now settled — a hit caches its
        // symbol, a miss caches the miss. A chunk that never answered caches
        // nothing: a network blip is not a verdict that the mint has no name,
        // and with the activity cursor a move dropped for want of one is asked
        // about again only if the next pass can still name it.
        for mint in wanted where answered.contains(mint) { symbolCache[mint] = out[mint] }
        return out
    }

    // MARK: - Story

    /// What a move says, structured — the title PLUS the parts it was built
    /// from (2026-07-16), so the landed thing carries direction/amount/venue
    /// as data and `TransferStage` stops re-deriving facts from a sentence.
    struct Story {
        let title: String
        /// `"sent"`/`"received"` — nil for a swap (two legs, no single
        /// direction; swaps keep the standard sheet layout).
        let direction: String?
        /// The named amount the title leads with — `"0.5 SOL"`; nil for a swap.
        let amount: String?
        /// The program the move rode (`"Jupiter"`) — the title's " on …" tail.
        let venue: String?
    }

    /// The story a move earns, or nil when we can't tell it honestly.
    ///
    /// Naming is a gate, not a decoration: the design law says a title never
    /// wears a raw hash, and a mint IS a hash. A leg we can't name kills the
    /// whole story rather than printing `Received 1000000 GjWRMFCec…`.
    static func story(for move: Move, symbols: [String: String]) -> Story? {
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
            return Story(title: "Swapped \(a) → \(b)\(tail)",
                         direction: nil, amount: nil, venue: move.venue)
        }
        if let back = got.first {
            guard let a = name(back) else { return nil }
            return Story(title: "Received \(a)\(tail)",
                         direction: "received", amount: a, venue: move.venue)
        }
        if let out = gave.first {
            guard let a = name(out) else { return nil }
            return Story(title: "Sent \(a)\(tail)",
                         direction: "sent", amount: a, venue: move.venue)
        }
        return nil
    }

    /// Just the sentence — what the `-solActivityProbe` log line reads.
    static func title(for move: Move, symbols: [String: String]) -> String? {
        story(for: move, symbols: symbols)?.title
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
