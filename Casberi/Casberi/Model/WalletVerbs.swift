import Foundation

/// Reading a transaction's SHAPE as a verb (2026-07-21).
///
/// `alchemy_getAssetTransfers` hands back movements, not intent — no calldata,
/// no method selector, no logs. So everything here decodes from what a movement
/// already carries: which contract the wallet met, which direction the value
/// went, and whether the other side was the zero address. That is narrow on
/// purpose. It is also enough for the four shapes below, which today land as
/// either a bare movement or — worse — a swap sentence that reads as nonsense
/// ("Swapped 0.5 ETH → 0.5 WETH on WETH" is a wrap).
///
/// The honesty contract, inherited from `WalletIngest.knownContracts` and
/// `MorphoDeFi`'s own decoder: **a verb is only ever claimed when the shape is
/// unambiguous.** Every function here returns nil rather than guess, and nil
/// means the caller writes exactly the title it writes today. Partial coverage
/// is the expected steady state, never a half-sentence.
///
/// Deliberately NOT decoded, because transfer data alone can't tell them apart
/// from what they resemble: claiming rewards (a received-only leg from a
/// protocol is equally a withdrawal), bridging (a send with no matching receive
/// is equally a payment), and ENS registration vs renewal (same contract, same
/// direction, and the name itself lives in calldata we never fetch). Those need
/// a log read, which is a separate cost decision — see `WalletApprovals` for the
/// per-chain public-RPC shape that would carry it.
enum WalletVerbs {

    // MARK: - Venues

    /// What a canonical contract IS, when knowing that turns a movement into a
    /// verb. Separate from `WalletIngest.knownContracts` (which answers "what do
    /// I CALL this address" for a counterparty clause) because that table's job
    /// is naming and this one's is grammar — Uniswap belongs there and not here,
    /// since a router meeting is already told correctly as a swap.
    struct Venue {
        let name: String
        let kind: Kind
        enum Kind {
            /// The chain's own wrapped-native contract — meeting it with the
            /// native coin on one side is a wrap or an unwrap, never a trade.
            case wrappedNative
            /// A liquid-staking token you mint by sending the native coin
            /// straight to the token contract.
            case liquidStaking
        }
    }

    /// Canonical, publicly verifiable deployments only — a wrong verb is worse
    /// than no verb, and unlike a wrong NAME a wrong verb misstates what the
    /// person did with their money. Every address below was verified live on
    /// 2026-07-21 by `eth_call`ing `symbol()`/`name()` on a public mainnet RPC;
    /// re-verify before adding to this table, never paste from a block explorer
    /// search result.
    ///
    /// Keyed lowercased. Wrapped natives repeat across chains at one address on
    /// the OP stack (Base, Optimism), which is why the table is chain-agnostic —
    /// the same reasoning `knownContracts` records.
    static let venues: [String: Venue] = [
        // Wrapped natives. symbol()/name() verified: WETH / "Wrapped Ether".
        "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": Venue(name: "WETH", kind: .wrappedNative),
        "0x4200000000000000000000000000000000000006": Venue(name: "WETH", kind: .wrappedNative),
        "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270": Venue(name: "WMATIC", kind: .wrappedNative),
        // Lido. You mint stETH by sending ETH to the stETH contract itself, so
        // the staking meeting IS a meeting with the token — which is what makes
        // this decodable without calldata. symbol()/name() verified: stETH /
        // "Liquid staked Ether 2.0", wstETH / "Wrapped liquid staked Ether 2.0".
        "0xae7ab96520de3a18e5e111b5eaab095312d7fe84": Venue(name: "Lido", kind: .liquidStaking),
        "0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0": Venue(name: "Lido", kind: .liquidStaking),
        // Rocket Pool's rETH is deliberately ABSENT despite being verified
        // (rETH / "Rocket Pool ETH"): you deposit through RocketDepositPool, not
        // through the token, so a meeting with rETH is a trade on a DEX far more
        // often than a stake. Keying it here would make the common case lie.
    ]

    /// The addresses a token comes from when it is minted and goes to when it is
    /// burned. `0x…dEaD` is a convention rather than a protocol rule, but it is
    /// universal enough that treating a send to it as a burn is safe — nothing
    /// else sends value there on purpose.
    static let voidAddresses: Set<String> = [
        "0x0000000000000000000000000000000000000000",
        "0x000000000000000000000000000000000000dead",
    ]

    static func isVoid(_ address: String?) -> Bool {
        guard let address else { return false }
        return voidAddresses.contains(address.lowercased())
    }

    // MARK: - Two-legged shapes

    /// A decoded sentence, plus the venue name its trailing clause shows (when
    /// it has one) — so the caller can keep `Thing.transferCounterparty` in
    /// agreement with the words. Writing one without the other is how a stage
    /// drifts from its row, which `ThingSheetView.retitleWalletThings` already
    /// records as a lesson.
    struct Decoded {
        let title: String
        /// nil when the verb names no venue at all ("Wrapped 0.5 ETH") — there
        /// is no clause for a rename to rewrite, and no name for a stage to show.
        let venueName: String?
    }

    /// The verb for a matched send+receive on one hash, or nil to let the caller
    /// write its usual "Swapped out → in" sentence.
    ///
    /// `counterparty` is the contract both legs met (the router slot in
    /// `WalletIngest.swapThing`); `nativeSymbol` is the chain's own coin, which
    /// is what distinguishes a wrap from a trade between two wrapped assets.
    static func pairVerb(counterparty: String?,
                         sentAsset: String, sentAmount: String,
                         receivedAsset: String, receivedAmount: String,
                         nativeSymbol: String) -> Decoded? {
        guard let counterparty, let venue = venues[counterparty.lowercased()] else { return nil }
        let native = nativeSymbol.uppercased()
        let sentIsNative = sentAsset.uppercased() == native
        let receivedIsNative = receivedAsset.uppercased() == native
        // Exactly one side native, or the shape isn't the one we think it is —
        // a wrapped-native contract can also be met by a plain ERC-20 transfer.
        guard sentIsNative != receivedIsNative else { return nil }

        switch venue.kind {
        case .wrappedNative:
            // The wrapped and native amounts are 1:1 by construction, so the
            // sentence names one amount and the native asset either way. No
            // venue clause: "Wrapped 0.5 ETH on WETH" says the same word twice.
            return Decoded(title: sentIsNative
                ? String(localized: "Wrapped \(amountClause(sentAmount, sentAsset))")
                : String(localized: "Unwrapped \(amountClause(receivedAmount, receivedAsset))"),
                           venueName: nil)
        case .liquidStaking:
            // Unlike a wrap, the two amounts genuinely differ (a share price
            // sits between them), so each direction names its OWN side: what
            // you put in when staking, what you got back when unstaking.
            return Decoded(title: sentIsNative
                ? String(localized: "Staked \(amountClause(sentAmount, sentAsset)) with \(venue.name)")
                : String(localized: "Unstaked \(amountClause(receivedAmount, receivedAsset)) from \(venue.name)"),
                           venueName: venue.name)
        }
    }

    // MARK: - One-legged shapes

    /// The verb for a single leg whose other side is the void — a mint when the
    /// wallet received from nowhere, a burn when it sent to nowhere. Needs no
    /// table at all, which is why it is the broadest-coverage rule here: it
    /// works on every chain, for every collection and token, forever.
    ///
    /// `asset` is the RAW symbol and may be nil. That distinction is the whole
    /// reason this takes an optional: `WalletIngest`'s own `asset` local falls
    /// back to the CHAIN's symbol when the transfer reports none, which is
    /// correct for a native coin and a lie for anything else — an NFT contract
    /// with no `symbol()` came through as "ETH" and this function dutifully
    /// wrote "Minted ETH #160" (caught on-sim 2026-07-21 against a real wallet).
    /// A nameless NFT says so; a nameless token declines the verb entirely,
    /// since "Minted 500" names nothing a person could act on.
    ///
    /// Returns nil for native-coin legs (a chain's own coin is not minted to you
    /// by a transfer) and for any leg whose counterparty is a real address.
    static func voidVerb(received: Bool, counterparty: String?, category: String,
                         asset: String?, amount: String, tokenID: String?) -> String? {
        guard isVoid(counterparty) else { return nil }
        let isNFT = category == "erc721" || category == "erc1155"
        guard isNFT || category == "erc20" else { return nil }
        let name = asset.flatMap { $0.isEmpty ? nil : $0 }

        if isNFT {
            // A collection symbol plus its token number is how an NFT is named
            // everywhere else in the app. With no symbol, the id alone would be
            // "#160 of what?" — so the nameless case drops it and says the one
            // true thing instead.
            guard let name else {
                return received ? String(localized: "Minted an NFT")
                                : String(localized: "Burned an NFT")
            }
            let piece = tokenID.map { "\(name) #\($0)" } ?? name
            return received
                ? String(localized: "Minted \(piece)")
                : String(localized: "Burned \(piece)")
        }
        guard let name else { return nil }
        return received
            ? String(localized: "Minted \(amountClause(amount, name))")
            : String(localized: "Burned \(amountClause(amount, name))")
    }

    // MARK: - Zerion's own classification

    /// The verb for a TWO-legged transaction Zerion classified — a deposit, a
    /// withdrawal or a claim that moved value both ways on one hash.
    ///
    /// This exists because swap-folding runs first and is shape-based: any hash
    /// that both sends and receives two different assets becomes "Swapped A → B".
    /// That is right for a trade and wrong for everything else that happens to
    /// look like one — a vault deposit hands you a receipt token, so supplying
    /// 1,265,457 USDT to earn yield rendered as "Swapped 1,265,457 USDT →
    /// 1,265,456 USDe" (measured on-sim 2026-07-21 against a real lender; Zerion
    /// called all nine of them deposits).
    ///
    /// Which side the sentence names is the decision each verb turns on: a
    /// deposit is about what you PUT IN, a withdrawal and a claim about what
    /// you GOT BACK. The receipt token on the other side is an implementation
    /// detail of the protocol, not the story.
    static func pairOperationVerb(operation: String?,
                                  sentAsset: String, sentAmount: String,
                                  receivedAsset: String, receivedAmount: String,
                                  venueName: String?) -> Decoded? {
        guard let operation else { return nil }
        let sent = amountClause(sentAmount, sentAsset)
        let got = amountClause(receivedAmount, receivedAsset)

        func decoded(_ verb: String, _ clause: String) -> Decoded {
            guard let venueName else { return Decoded(title: verb, venueName: nil) }
            return Decoded(title: verb + clause + venueName, venueName: venueName)
        }

        switch operation {
        case "deposit":  return decoded(String(localized: "Deposited \(sent)"), " into ")
        case "withdraw": return decoded(String(localized: "Withdrew \(got)"), " from ")
        case "claim":    return decoded(String(localized: "Claimed \(got)"), " from ")
        // "trade" is the one this function deliberately declines: swap-folding's
        // two-sided sentence already says more than any single-sided verb could.
        default:         return nil
        }
    }

    /// The verb for a leg whose transaction Zerion already classified — the
    /// primary decoder on the live path (2026-07-21), because intent read from
    /// the source beats intent inferred from a contract table.
    ///
    /// Only the operations that BEAT the sentence `WalletIngest` would otherwise
    /// write are mapped. `send`/`receive`/`trade` already have correct handling
    /// (the last through swap-folding), `approve`/`revoke` are `WalletApprovals`'
    /// own surface with far more detail than a leg carries, and `execute` is
    /// Zerion's word for "a contract call we didn't classify" — adopting it would
    /// replace a true sentence with a vaguer one.
    ///
    /// Each verb is gated on the direction that makes it true, so the OTHER leg
    /// of the same transaction can't wear it: a deposit's refund leg is not a
    /// deposit, and labelling both would double-count the story.
    static func operationVerb(operation: String?, received: Bool,
                              asset: String, amount: String,
                              venueName: String?) -> Decoded? {
        guard let operation else { return nil }
        let what = amountClause(amount, asset)

        func decoded(_ verb: String, _ clause: String) -> Decoded {
            guard let venueName else { return Decoded(title: verb, venueName: nil) }
            return Decoded(title: verb + clause + venueName, venueName: venueName)
        }

        switch (operation, received) {
        case ("claim", true):
            return decoded(String(localized: "Claimed \(what)"), " from ")
        case ("deposit", false):
            // Staking lives here — Zerion has no "stake" type, so a Lido deposit
            // and a lending-pool supply are the same word. "Deposited … into" is
            // true of both; a verb that guessed between them would not be.
            return decoded(String(localized: "Deposited \(what)"), " into ")
        case ("withdraw", true):
            return decoded(String(localized: "Withdrew \(what)"), " from ")
        case ("mint", true):
            return decoded(String(localized: "Minted \(what)"), " on ")
        case ("burn", false):
            return Decoded(title: String(localized: "Burned \(what)"), venueName: nil)
        case ("bid", false):
            return decoded(String(localized: "Bid \(what)"), " on ")
        default:
            return nil
        }
    }

    /// Alchemy reports an NFT's id as a hex string (`"0x01a4"`). Decimal is what
    /// every marketplace shows, so it is what the title says — but an id can be
    /// a full 32-byte word (some collections hash their ids), and a 78-digit
    /// number in a feed row is noise, so anything implausibly long is dropped
    /// rather than printed.
    static func decimalTokenID(_ raw: Any?) -> String? {
        guard let hex = (raw as? String)?.lowercased(), hex.hasPrefix("0x") else {
            return (raw as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        let digits = String(hex.dropFirst(2))   // past "0x", not past "0"
        guard !digits.isEmpty, digits.allSatisfy(\.isHexDigit) else { return nil }
        // Trim leading zeros before measuring — "0x0000…01" is id 1, not a hash.
        let trimmed = String(digits.drop(while: { $0 == "0" }))
        if trimmed.isEmpty { return "0" }
        guard trimmed.count <= 12, let value = UInt64(trimmed, radix: 16) else { return nil }
        return String(value)
    }

    /// "0.5 ETH", or bare "ETH" when the amount didn't parse — the same
    /// degradation `WalletIngest.thing(from:)` already applies to a transfer
    /// whose value is missing.
    private static func amountClause(_ amount: String, _ asset: String) -> String {
        amount.isEmpty ? asset : "\(amount) \(asset)"
    }
}
