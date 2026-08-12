import Foundation
import SwiftData

/// The receipt's reading half (prd §369, 2026-08-12) — a landed `Thing` turned
/// into `MoneyReceipt.Facts`, with every judgement left on the other side of
/// the line.
///
/// The split is `GnosisPayRoomSource`'s, and it earns itself the same way:
/// everything that could be wrong while still rendering perfectly — a sentence
/// claiming a network the row never carried, a "biggest yet" that isn't, an
/// amount whose unit was mistaken for part of the number — lives in
/// `MoneyReceipt`/`MoneyCommentary`, which the harness compiles whole.
///
/// This file's own job is resolution: turning a stored hex into the name the
/// person gave it, a content URL into a chain name, and a counterparty into the
/// history you share. None of that is judgement; all of it needs `Thing`,
/// `WalletStore` or a `ModelContext`.
enum MoneyReceiptSource {

    /// The receipt for a thing, or nil when this isn't one we draw.
    ///
    /// `safe` is threaded in rather than fetched here: `ThingSheetView` already
    /// runs `SafeBridge.check` once per open, and a second live read for the
    /// same answer would be a request bought twice.
    @MainActor
    static func receipt(for thing: Thing,
                        safe: SafeBridge.Check? = nil) -> MoneyReceipt? {
        guard thing.isLive, thing.kind == .transaction else { return nil }
        return MoneyReceipt.compose(facts(for: thing, safe: safe))
    }

    /// The ONLY place a `Thing` is read for the receipt.
    @MainActor
    static func facts(for thing: Thing,
                      safe: SafeBridge.Check? = nil) -> MoneyReceipt.Facts {
        var f = MoneyReceipt.Facts(source: thing.source, title: thing.title)
        f.content = thing.content
        f.sourceRef = thing.sourceRef
        f.capturedAt = thing.capturedAt
        f.direction = thing.transferDirection
        f.amount = thing.transferAmount
        f.counterparty = thing.transferCounterparty
        f.venue = thing.transferVenue
        f.usd = thing.transferUSD
        f.counterpartyAddress = thing.counterpartyAddress
        f.walletAddress = thing.walletAddress
        f.priceValue = thing.priceValue
        f.priceCurrency = thing.priceCurrency
        f.tags = thing.tags
        f.authorHandle = thing.authorHandle
        f.myLabel = walletLabel(thing.walletAddress)
        f.partyLabel = thing.counterpartyAddress
            .flatMap { WalletIngest.knownLabel(for: $0) } ?? thing.transferCounterparty
        f.network = WalletIngest.chainName(forContent: thing.content)
        if MoneyReceipt.split(thing.transferAmount).unit == "BTC" {
            f.settling = BitcoinBridge.isSettling(address: thing.walletAddress,
                                                  ref: thing.sourceRef)
        }
        if case .pending(let have, let required)? = safe?.status {
            f.signaturesHave = have
            f.signaturesNeed = required
        }
        return f
    }

    /// The person's own name for the watched wallet this touched.
    ///
    /// Never "You" (user, 2026-07-23: "we don't know it is 'you', we only know
    /// it is the address used or followed") — every watched wallet is read-only,
    /// so nothing here distinguishes the person's own wallet from a public
    /// address they track. `TransferStageView.youLabel`'s rule, kept when that
    /// view retired, including its `scopeMatches` fix: a thing stamps the
    /// RESOLVED hex while a wallet is watched under whatever spelling it was
    /// added with, so a plain `==` misses every ENS-watched wallet.
    @MainActor
    static func walletLabel(_ stored: String?) -> String? {
        guard let stored, !stored.isEmpty else { return nil }
        guard let watched = WalletStore.shared.addresses.first(where: {
            WalletStore.shared.scopeMatches(stored, scope: $0.address)
        }) else { return WalletStore.shortAddress(stored) }
        if !watched.label.isEmpty { return watched.label }
        return ENS.isHexAddress(watched.address)
            ? WalletStore.shortAddress(watched.address) : watched.address
    }

    // MARK: - Commentary

    /// What the app says about this receipt, or nil when it has nothing true to
    /// add. **nil is the healthy answer for most rows** — a first transfer with
    /// somebody, a one-off merchant, a swap whose legs won't divide.
    @MainActor
    static func commentary(for thing: Thing, in context: ModelContext,
                           safe: SafeBridge.Check? = nil) -> MoneyCommentary? {
        guard thing.isLive else { return nil }
        switch thing.source {
        case "Wallet":         return walletCommentary(thing, context)
        case "Apple Wallet", "Gnosis Pay", "ether.fi", "Privacy":
            return merchantCommentary(thing, context)
        case "Privacy Pools":  return poolsCommentary(thing)
        case "Peer", "Railgun":
            // Their payoff fact is a sentence the bridge already wrote (prd
            // §237, §268). Shown as itself rather than re-parsed into a chart.
            return storedNote(thing)
        case "Safe":           return safeCommentary(thing, safe)
        default:               return nil
        }
    }

    @MainActor
    private static func walletCommentary(_ thing: Thing,
                                         _ context: ModelContext) -> MoneyCommentary? {
        // A swap states its rate — the one thing a trade is for, and pure
        // arithmetic on the two legs `SwapStage` has parsed since 2026-07-21.
        if let swap = SwapStage(thing) {
            return MoneyCommentary.rate(out: swap.outAmount, into: swap.inAmount)
        }
        if MoneyReceipt.split(thing.transferAmount).unit == "BTC",
           BitcoinBridge.isSettling(address: thing.walletAddress, ref: thing.sourceRef) {
            return MoneyCommentary.settling(need: BitcoinBridge.settledConfirmations)
        }
        guard let cp = thing.counterpartyAddress, !cp.isEmpty else { return nil }
        let party = WalletIngest.knownLabel(for: cp)
            ?? thing.transferCounterparty ?? WalletStore.shortAddress(cp)
        // Through `AddressActivity` — the one definition of address activity —
        // then narrowed to Wallet transfers, the only rows "with you" is true of.
        let transfers = AddressActivity.history(for: cp, in: context)
            .live
            .filter { $0.source == "Wallet" && $0.transferAmount != nil }
            .sorted { $0.capturedAt < $1.capturedAt }
        var unit: String?
        var mixed = false
        var signed: [(Double, Bool)] = []
        for row in transfers {
            let parts = MoneyReceipt.split(row.transferAmount)
            guard let value = MoneyCommentary.number(parts.number) else { continue }
            if let unit, parts.unit != unit { mixed = true }
            if unit == nil { unit = parts.unit }
            signed.append((value, row.transferDirection == "received"))
        }
        // Height means quantity, so a mixed-token history draws no bars — it
        // still gets its sentence, which is the half that was always true.
        return MoneyCommentary.history(party: party,
                                       unit: mixed ? nil : unit,
                                       signed: signed)
    }

    @MainActor
    private static func merchantCommentary(_ thing: Thing,
                                           _ context: ModelContext) -> MoneyCommentary? {
        guard let merchant = thing.transferCounterparty, !merchant.isEmpty,
              let currency = thing.priceCurrency,
              thing.priceValue != nil else { return nil }
        let source = thing.source
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source })
        descriptor.fetchLimit = 3000
        // One currency only. A total across currencies is the exact failure
        // `Corpus.cardSpendSources` documents; a BOARD across them is the same
        // error one step earlier, since the bar heights would not compare.
        let spends = ((try? context.fetch(descriptor)) ?? [])
            .live
            .filter {
                $0.transferCounterparty == merchant && $0.priceCurrency == currency
                    && !$0.tags.contains("Refund")
            }
            .sorted { $0.capturedAt < $1.capturedAt }
            .compactMap(\.priceValue)
            .map(abs)
        return MoneyCommentary.merchant(name: merchant, values: spends,
                                        currency: currency)
    }

    @MainActor
    private static func poolsCommentary(_ thing: Thing) -> MoneyCommentary? {
        // Tags are stamped structurally by the bridge, so the rung is read and
        // never inferred from a localized title.
        let tags = thing.tags
        let rung: MoneyCommentary.Rung
        if tags.contains("Approved") || tags.contains("Cleared") { rung = .cleared }
        else if tags.contains("Proof") || tags.contains("POI") { rung = .needsProof }
        else if tags.contains("Pending") { rung = .screening }
        else { return storedNote(thing) }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: thing.capturedAt),
            to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return MoneyCommentary.ladder(rung: rung, since: thing.capturedAt,
                                      days: max(0, days))
    }

    @MainActor
    private static func safeCommentary(_ thing: Thing,
                                       _ safe: SafeBridge.Check?) -> MoneyCommentary? {
        guard case .pending(let have, let required)? = safe?.status else { return nil }
        let signed = safe?.roster.filter(\.signed).map(\.displayName) ?? []
        let head: String
        if signed.isEmpty {
            head = String(localized: "\(have) of \(required) signatures so far.")
        } else if signed.count == 1 {
            head = String(localized: "\(signed[0]) has signed.")
        } else {
            head = String(localized: "\(signed.dropLast().joined(separator: ", ")) and \(signed[signed.count - 1]) have signed.")
        }
        return .note(headline: head,
                     subline: String(localized: "Signing happens in your Safe app — never here."))
    }

    /// The bridge's own sentence, where one exists. `enrichedText` is
    /// retrieval-only by the 2026-07-15 ruling; these three sources are the
    /// standing exception `ThingContent` already carved, for the same reason —
    /// the sentence IS the payoff, and it was previously drawn as a grey
    /// paragraph above a raw URL.
    @MainActor
    private static func storedNote(_ thing: Thing) -> MoneyCommentary? {
        guard let text = thing.enrichedText?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return .note(headline: text, subline: nil)
    }

    // MARK: - Probe

    /// `-receiptProbe "<title prefix>"`'s lines. One NSLog per line at the call
    /// site (the `-todayProbe` truncation lesson).
    ///
    /// It exists because **an absent receipt has six causes and only two are
    /// bugs**: the source isn't in `MoneyReceipt.sources`; the thing isn't
    /// `.transaction`; the bridge stamped no direction/amount so the receipt
    /// correctly leads with its title; the commentary declined because the claim
    /// wasn't true (a first transfer, a one-off merchant); a resolution came
    /// back empty (no watched wallet matched, so no wallet name for the
    /// sentence); or the compose chain drifted. Only the last two are defects,
    /// and from outside all six render as "it looks plain".
    @MainActor
    static func probeLines(for thing: Thing, in context: ModelContext) -> [String] {
        var out: [String] = []
        guard thing.isLive else { return ["receipt| thing is gone"] }
        let f = facts(for: thing)
        out.append("receipt| title=\(thing.title)")
        out.append("receipt| source=\(thing.source) kind=\(thing.kind.rawValue) drawn=\(MoneyReceipt.sources.contains(thing.source))")
        out.append("receipt| stamped dir=\(f.direction ?? "—") amount=\(f.amount ?? "—") party=\(f.counterparty ?? "—") venue=\(f.venue ?? "—")")
        out.append("receipt| resolved wallet=\(f.myLabel ?? "—") counterparty=\(f.partyLabel ?? "—") network=\(f.network ?? "—")")
        guard let receipt = MoneyReceipt.compose(f) else {
            out.append("receipt| NO RECEIPT — source not in MoneyReceipt.sources")
            return out
        }
        out.append("receipt| subject=\(describe(receipt.subject)) mine=\(receipt.mine ?? "—") hue=\(receipt.hue)")
        out.append("receipt| lead=\(receipt.lead) party=\(receipt.party ?? "—")")
        if let amount = receipt.amount {
            out.append("receipt| amount=\(amount.number) unit=\(amount.unit ?? "—") tone=\(amount.tone)")
        } else {
            out.append("receipt| amount=NONE (no stamped figure — leads with its title)")
        }
        out.append("receipt| secondary=\(receipt.secondary ?? "—")")
        out.append("receipt| sentence=\(receipt.sentence)")
        out.append("receipt| stamp=\(receipt.stamp?.word ?? "—") finality=\(receipt.finality)")
        if let says = commentary(for: thing, in: context) {
            out.append("receiptSays| \(says.headline)")
            if case .history(_, let sub, let series) = says {
                out.append("receiptSays| sub=\(sub ?? "—") series=\(series.count) bars")
            } else if case .merchant(_, let sub, let values) = says {
                out.append("receiptSays| sub=\(sub ?? "—") values=\(values.count)")
            }
        } else {
            out.append("receiptSays| none — nothing true to add (usual for a first transfer or a one-off merchant)")
        }
        return out
    }

    private static func describe(_ subject: MoneyReceipt.Subject) -> String {
        switch subject {
        case .address(let a): return "address(\(WalletStore.shortAddress(a)))"
        case .asset(let a):   return "asset(\(a))"
        case .named(let n):   return "named(\(n))"
        case .absent(let r):  return "void(\(r))"
        }
    }
}
