import Foundation
import SwiftData
#if canImport(FinanceKit) && !targetEnvironment(macCatalyst)
import FinanceKit
#endif

/// APPLE WALLET (2026-08-06, prd §313) — Apple Card, Apple Cash and Savings,
/// read on device through FinanceKit.
///
/// The entitlement (`com.apple.developer.financekit`) was granted by Apple on
/// 2026-08-06 for this exact bundle id, against a request that described this
/// bridge. **What that request promised is now a contract**, and every clause
/// of it is implemented here or in `AppleWalletScreen`:
///   • read-only — transactions and balances, nothing else, no writes exist;
///   • nothing leaves the device, ever, for any reason;
///   • never sold, never used for marketing or personalization;
///   • a setup screen that says all of the above BEFORE anything is requested;
///   • a one-tap disconnect that stops reading and DELETES what landed.
/// If a future change breaks one of those, it breaks the entitlement's terms,
/// not just a preference. `disconnect(context:)` is the load-bearing one — it
/// must keep deleting rows, or the promise is false the first time someone
/// takes us up on it.
///
/// ## Why this seat is worth its cost
///
/// It is the only source in this app that sees a MERCHANT NAME. The chain
/// carries an amount and a moment and nothing else (`GnosisPayBridge`'s stated
/// ceiling), Privacy.com carries a card descriptor, a wallet transfer carries
/// an address. FinanceKit carries "Blue Bottle Coffee". Every card in
/// `AppleWalletRoom` is built on that one field.
///
/// ## The module doctrine, applied
///
/// A charge IS a thing here, unlike Stripe where an individual charge is a
/// tally wearing a currency symbol (prd §250). The difference is whose money
/// it is: Stripe reads a merchant's firehose of strangers paying them, this
/// reads YOUR spending, and the precedent is `GnosisPayBridge` /
/// `PrivacyBridge`, which have landed individual purchases since they shipped.
///
/// But charges never NOTIFY (prd §313 ruling, and the same call the wallet
/// seats shipped): your bank already pushed you that notification, and a second
/// one from us is noise wearing our icon. The room speaks only when something
/// CHANGED — a recurring price rose, a subscription stopped, a payment is due —
/// and those are `AppleWalletRoom`'s job, not this file's.
///
/// §216 splits the two reads: transactions are EVENTS (read every pass,
/// unwindowed), balances are STATE (behind `balanceWindow`, because a
/// ten-minute-old balance is dated, not wrong).
///
/// ## What it cannot do, stated so the copy can't drift
///
/// - **US only.** Apple Card, Apple Cash and Savings exist nowhere else, so
///   this seat is empty for most of the world by construction, not by failure.
/// - **No categories.** `merchantCategoryCode` is on the wire and deliberately
///   unused: an MCC is a payment-network billing code, not a description of
///   what you bought, and rendering "5812" as "Restaurants" is a guess we'd be
///   stating as a fact. Merchant names are better data anyway.
/// - **Not a statement.** Pending authorizations are shown and never counted;
///   `AppleWalletRoom` says so on the card.
///
/// ## UNVERIFIED against real data, and structurally so
///
/// **No simulator ships FinanceKit data.** `FinanceStore.isDataAvailable`
/// answers false there, so every path below takes its unavailable branch and a
/// sim sweep exercises none of this. This is the on-device-model situation
/// exactly (prd §282), and it has the same answer: the pure judgement lives in
/// `AppleWalletRoom` (Foundation-only) and is compiled WHOLE and mutation-tested
/// by `scripts/applewallet-selftest.sh`; everything here fails safe (a throw or
/// an unavailable framework yields zero rows, never a wrong one). The read
/// itself has only ever been checked against the SDK's own interface — verify
/// on a real device with a real Apple Card before trusting any number.
enum AppleWalletBridge {

    static let seatID = "applewallet"
    static let sourceName = "Apple Wallet"

    /// §216: balances are a STATE. Ten minutes, matching `HoldingsCache`.
    static let balanceWindow: TimeInterval = 600
    /// First sight reaches back this far. Long enough for `AppleWalletRoom` to
    /// find a cadence (it needs three charges, and a monthly subscription needs
    /// ~90 days to show three), short enough that a first connect isn't a
    /// multi-year import wearing today's date.
    static let backfillDays = 180
    /// Rows landed per pass. A card can post a lot in a day; this is a
    /// runaway guard, not a window.
    static let maxPerPass = 500

    /// How far back of ALREADY-SEEN history every pass re-reads, so a pending
    /// authorization can be healed once it settles.
    ///
    /// **This constant is a bug fix, and the bug it fixes was invisible.** The
    /// cursor is the newest `transactionDate` already landed, and the query
    /// asked for `transactionDate > cursor` — but a pending authorization
    /// lands wearing today's date, which is at or below the cursor the same
    /// pass then writes. So it was excluded from every subsequent read, the
    /// heal path in `land` could never fire for it, and it stayed "Pending ·"
    /// forever: its settled amount never arrived, it was never counted, and
    /// the card's "N pending charges aren't counted" note grew by one more
    /// permanent row each time. Nothing errored, and the room rendered
    /// perfectly the whole time — it just quietly undercounted for life.
    ///
    /// Seven days clears the window a card issuer takes to settle an
    /// authorization (typically 1–3, longer for hotels, fuel and car hire).
    /// Re-reading is free: `land` dedupes on `sourceRef`, so a row already
    /// settled costs one dictionary lookup and lands nothing.
    ///
    /// It is a FLOOR, not the whole rule — `pendingFloor` widens the window to
    /// cover the oldest row still pending, because a fixed offset from a cursor
    /// that advances daily strands exactly the long holds (hotel, car hire)
    /// that take longest to settle.
    static let healbackDays = 7

    /// How far back the window may be dragged by a still-pending row. Bounds
    /// the read for a corpus holding a permanently-stuck authorization — see
    /// the phantom-pending ceiling on `pendingFloor`.
    static let maxHealbackDays = 90

    // MARK: - Stored state (UserDefaults — no new `Thing` field, no CloudKit deploy)

    private static let connectedKey = "applewallet.connected"
    private static let cursorKey = "applewallet.cursor"
    private static let balanceKey = "applewallet.balances"
    private static let balanceAtKey = "applewallet.balancesAt"
    private static let dueKey = "applewallet.dues"

    static var connected: Bool {
        get { UserDefaults.standard.bool(forKey: connectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: connectedKey) }
    }

    /// The newest `transactionDate` already landed. Advanced only AFTER rows
    /// are in the context — moving it first would skip a spending window
    /// forever on a crash (the `StripeBridge` cursor rule).
    static var cursor: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: cursorKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: cursorKey) }
    }

    /// Per-account balance snapshot, `name → "formatted"`. Display only.
    static var balances: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: balanceKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: balanceKey) }
    }

    static var balancesAt: Date? {
        let t = UserDefaults.standard.double(forKey: balanceAtKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Payment due dates keyed by account name — read from FinanceKit's own
    /// `nextPaymentDueDate`, never inferred. `AppleWalletRoomSource` turns
    /// these into the clock rail.
    static var dues: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: dueKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: dueKey) }
    }

    // MARK: - Availability

    /// Whether this device can serve financial data at all. False on every
    /// simulator, false outside the US in practice, false below iOS 17.4.
    static var isSupported: Bool {
        #if canImport(FinanceKit) && !targetEnvironment(macCatalyst)
        if #available(iOS 17.4, *) {
            return FinanceStore.isDataAvailable(.financialData)
        }
        #endif
        return false
    }

    // MARK: - Connect

    enum ConnectOutcome: Equatable {
        case connected(landed: Int)
        case denied
        case unavailable
        case failed(String)

        /// What the setup screen says. Four outcomes get four sentences,
        /// because "denied" and "unavailable" are different problems and only
        /// one of them is fixable by the person reading it (`StripeBridge`'s
        /// four-failures rule).
        var line: String {
            switch self {
            case .connected(let n):
                return n == 0
                    ? String(localized: "Connected. Nothing to bring in yet — new activity will land here.")
                    : String(localized: "Connected. \(n) in.")
            case .denied:
                return String(localized: "Access wasn't granted. You can turn it on in Settings › Privacy & Security › Financial Data.")
            case .unavailable:
                return String(localized: "This iPhone can't share financial data. Apple Card, Apple Cash and Savings are US-only, and this needs iOS 17.4 or later.")
            case .failed(let why):
                return String(localized: "Couldn't read your card: \(why)")
            }
        }
    }

    /// Ask for access, then do a first read. The ONLY place authorization is
    /// requested — a refresh must never re-present the prompt (the Contacts
    /// rule), so `refresh` checks status and returns rather than asking.
    @MainActor
    static func connect(context: ModelContext, store: BridgeStore? = nil) async -> ConnectOutcome {
        #if canImport(FinanceKit) && !targetEnvironment(macCatalyst)
        guard #available(iOS 17.4, *), FinanceStore.isDataAvailable(.financialData) else {
            return .unavailable
        }
        do {
            let status = try await FinanceStore.shared.requestAuthorization()
            guard status == .authorized else { return .denied }
            connected = true
            let landed = await refresh(context: context, store: store) ?? 0
            return .connected(landed: landed)
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }

    /// Stop reading and DELETE what landed. The entitlement request promised
    /// this verb by name; it is not a preference toggle.
    ///
    /// Deletes rows by `source`, drops every stored snapshot, and clears the
    /// cursor so a later reconnect backfills cleanly rather than resuming from
    /// a date whose rows are gone.
    @MainActor
    @discardableResult
    static func disconnect(context: ModelContext) -> Int {
        connected = false
        cursor = nil
        balances = [:]
        dues = [:]
        UserDefaults.standard.removeObject(forKey: balanceAtKey)
        let name = sourceName
        let fetch = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == name })
        let rows = (try? context.fetch(fetch)) ?? []
        for row in rows { context.delete(row) }
        try? context.save()
        return rows.count
    }

    // MARK: - Refresh

    /// One pass. Returns the number of rows landed, or nil when the read
    /// couldn't run at all — the two are different and the screen says so.
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext, store: BridgeStore? = nil) async -> Int? {
        #if canImport(FinanceKit) && !targetEnvironment(macCatalyst)
        guard connected, #available(iOS 17.4, *),
              FinanceStore.isDataAvailable(.financialData) else { return nil }
        // Never re-ask here. A refresh runs only when access is already
        // granted; asking on a background pass would put a system prompt in
        // front of someone who didn't tap anything.
        guard let status = try? await FinanceStore.shared.authorizationStatus(),
              status == .authorized else { return nil }

        let accounts = (try? await FinanceStore.shared.accounts(query: AccountQuery())) ?? []
        var names: [UUID: String] = [:]
        for account in accounts { names[account.id] = account.displayName }
        await readBalances(accounts: accounts)

        // The read window starts BEFORE the cursor, so pending rows landed on
        // an earlier pass are seen again and healed when they settle — and it
        // reaches back far enough to cover the oldest row STILL pending, not
        // merely a fixed number of days. Only the first sight reaches all the
        // way back to `backfillDays`.
        let firstSight = Date().addingTimeInterval(-Double(backfillDays) * 86_400)
        let since = cursor.map { c in
            min(c.addingTimeInterval(-Double(healbackDays) * 86_400),
                pendingFloor(context: context))
        } ?? firstSight
        let query = TransactionQuery(
            sortDescriptors: [SortDescriptor(\Transaction.transactionDate, order: .reverse)],
            predicate: #Predicate { $0.transactionDate > since },
            limit: maxPerPass)
        guard let txns = try? await FinanceStore.shared.transactions(query: query) else { return nil }

        let landed = land(txns, accountNames: names, context: context)
        landDueRows(context: context)
        try? context.save()
        // After the save, so the pass reads a corpus including what just
        // landed — a price rise is only visible once its charge is a row.
        landChanges(context: context)
        try? context.save()

        // Cursor last, and only over rows we actually saw.
        if let newest = txns.map(\.transactionDate).max() {
            cursor = max(newest, cursor ?? .distantPast)
        }
        store?.registerConnected(
            id: seatID, name: sourceName,
            proof: landed == 0 ? String(localized: "Up to date")
                               : String(localized: "\(landed) in"),
            can: [String(localized: "Read your card activity")])
        return landed
        #else
        return nil
        #endif
    }

    // MARK: - Landing

    #if canImport(FinanceKit) && !targetEnvironment(macCatalyst)
    @available(iOS 17.4, *)
    @MainActor
    private static func readBalances(accounts: [Account]) async {
        if let at = balancesAt, Date().timeIntervalSince(at) < balanceWindow { return }
        var out: [String: String] = [:]
        var due: [String: Double] = [:]
        for account in accounts {
            let query = AccountBalanceQuery(
                predicate: #Predicate { $0.accountID == account.id })
            if let balance = (try? await FinanceStore.shared.accountBalances(query: query))?.first,
               let text = format(balance) {
                out[account.displayName] = text
            }
            // The one real deadline this source hands over. Never inferred —
            // `AppleWalletRoom`'s rail sorts a payment above any recurring date
            // we computed ourselves, and that ordering is only honest because
            // this number is Apple's, not ours.
            if case .liability(let liability) = account,
               let date = liability.creditInformation.nextPaymentDueDate {
                due[account.displayName] = date.timeIntervalSince1970
            }
        }
        if !out.isEmpty { balances = out }
        dues = due
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: balanceAtKey)
    }

    @available(iOS 17.4, *)
    private static func format(_ balance: AccountBalance) -> String? {
        let amount: CurrencyAmount
        switch balance.currentBalance {
        case .available(let b): amount = b.amount
        case .booked(let b): amount = b.amount
        case .availableAndBooked(let available, _): amount = available.amount
        @unknown default: return nil
        }
        return AppleWalletRoom.money(NSDecimalNumber(decimal: amount.amount).doubleValue,
                                     amount.currencyCode)
    }

    /// Turn transactions into rows, deduped on `sourceRef`.
    ///
    /// A pending row that later POSTS is healed in place rather than landed
    /// twice — FinanceKit keeps the same `id` across that transition, and the
    /// amount can change when it settles, so the row is rewritten from the
    /// settled facts. Without this a card room would carry both halves of every
    /// purchase for a week.
    @available(iOS 17.4, *)
    @MainActor
    private static func land(_ txns: [Transaction], accountNames: [UUID: String],
                             context: ModelContext) -> Int {
        let name = sourceName
        let fetch = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == name })
        let existing = (try? context.fetch(fetch)) ?? []
        var byRef: [String: Thing] = [:]
        for row in existing where row.sourceRef != nil { byRef[row.sourceRef!] = row }

        var landed = 0
        for txn in txns {
            let ref = "applewallet:txn:\(txn.id.uuidString)"
            let amount = NSDecimalNumber(decimal: txn.transactionAmount.amount).doubleValue
            let currency = txn.transactionAmount.currencyCode
            let raw = merchantLabel(txn)
            let merchant = AppleWalletRoom.normalizeMerchant(raw)
            let isRefund = txn.creditDebitIndicator == .credit
            let settled = txn.status == .booked
            let title = rowTitle(merchant: merchant, amount: amount, currency: currency,
                                 isRefund: isRefund, isSettled: settled)

            if let row = byRef[ref] {
                // Heal: a pending row that posted, or an amount that moved.
                // Reachable only because `refresh` re-reads `healbackDays` of
                // already-seen history — see that constant for the bug this
                // path silently had until then.
                if row.title != title {
                    row.title = title
                    row.priceValue = amount
                    row.priceCurrency = currency
                    row.transferCounterparty = merchant
                    row.transferAmount = AppleWalletRoom.money(amount, currency)
                    row.tags = tags(isRefund: isRefund, isSettled: settled)
                    row.capturedAt = txn.postedDate ?? txn.transactionDate
                }
                continue
            }
            let thing = Thing(kind: .transaction,
                              title: title,
                              content: "",
                              source: sourceName,
                              capturedAt: txn.postedDate ?? txn.transactionDate,
                              sourceRef: ref)
            thing.transferCounterparty = merchant
            thing.transferDirection = isRefund ? "received" : "sent"
            thing.transferAmount = AppleWalletRoom.money(amount, currency)
            thing.priceValue = amount
            thing.priceCurrency = currency
            thing.tags = tags(isRefund: isRefund, isSettled: settled)
            // The account, plus the descriptor AS THE BANK WROTE IT when
            // normalization changed it. `enrichedText` is retrieval-only by the
            // 2026-07-15 ruling, so neither is ever displayed — but both are
            // searchable, which is the point: after `normalizeMerchant` turns
            // "SQ *BLUE BOTTLE" into "Blue Bottle", searching the string that
            // is actually on your statement must still find the row.
            // The account as DATA too (prd §369, 2026-08-12), not only inside
            // the joined `enrichedText` blob below. The receipt's "on Apple
            // Card, ending 4821" line needs the account name on its own; taking
            // it back out of that blob would mean splitting a joined string and
            // guessing which component is which, which is the prose-parsing this
            // pass exists to stop. `authorHandle` had no other writer for this
            // source, and it is an existing field — no CloudKit deploy.
            thing.authorHandle = accountNames[txn.accountID]
            var enriched = accountNames[txn.accountID].map { [$0] } ?? []
            if merchant != raw { enriched.append(raw) }
            if !enriched.isEmpty { thing.enrichedText = enriched.joined(separator: " · ") }
            context.insert(thing)
            byRef[ref] = thing
            landed += 1
        }
        return landed
    }

    /// The merchant, or the transaction's own description when Apple has no
    /// merchant for it (transfers, interest, payments). Never an MCC.
    @available(iOS 17.4, *)
    static func merchantLabel(_ txn: Transaction) -> String {
        if let m = txn.merchantName, !m.trimmingCharacters(in: .whitespaces).isEmpty {
            return m
        }
        let d = txn.transactionDescription.trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? String(localized: "Card transaction") : d
    }
    #endif

    // MARK: - Shaping (pure — compiled by the harness)

    /// The row's title. The MERCHANT LEADS, and any abnormal state leads the
    /// merchant.
    ///
    /// `IngestSupport.titleLine` clamps at 80 characters, so anything trailing
    /// is exactly what the clamp eats — and a refund reading as a purchase is
    /// the §83 fake-status ban with a minus sign. Same ruling as
    /// `CursorBridge`'s "Failed ·" lead and `PagerDutyBridge`'s "Resolved
    /// after".
    static func rowTitle(merchant: String, amount: Double, currency: String,
                         isRefund: Bool, isSettled: Bool) -> String {
        let money = AppleWalletRoom.money(abs(amount), currency)
        if isRefund { return String(localized: "Refunded · \(merchant) · \(money)") }
        if !isSettled { return String(localized: "Pending · \(merchant) · \(money)") }
        return "\(merchant) · \(money)"
    }

    /// Facet tags (§308's vocabulary) so a card room can be narrowed the way
    /// every import room can. `Pending` is a tag rather than a title-only fact
    /// because "what hasn't posted yet" is a real question.
    static func tags(isRefund: Bool, isSettled: Bool) -> [String] {
        var out = ["Card"]
        if isRefund { out.append("Refund") }
        if !isSettled { out.append("Pending") }
        return out
    }

    /// The oldest still-pending row's date, less a day, or `.distantFuture`
    /// when nothing is pending (so `min` leaves the window alone).
    ///
    /// **`healbackDays` alone is a grace period bolted onto the same bug.**
    /// The cursor is the newest date ever seen, so on a card in daily use it
    /// advances every day and a fixed 7-day offset walks forward with it. A
    /// hotel hold placed on day D is outside the window by day D+8 and settles
    /// on day D+10 — never re-read, stuck as `Pending ·` forever, exactly the
    /// failure the heal-back exists to prevent. The window has to be anchored
    /// to what is actually unresolved, not to how long we guessed that takes.
    ///
    /// **Stated ceiling: a released authorization is never pruned.** An issuer
    /// that drops a hold (petrol, hotel) simply stops returning it, and nothing
    /// here deletes a row FinanceKit no longer mentions — a reconcile pass
    /// would have to distinguish "gone" from "outside this page", and
    /// `maxPerPass` truncation makes that unsafe to guess at. So a dropped hold
    /// stays as a phantom pending row, uncounted, and drags this floor with it;
    /// `maxHealbackDays` is what stops it dragging forever. Fix it by measuring
    /// what FinanceKit really does with a released hold on a real device — it
    /// is not knowable from the SDK's interface.
    @MainActor
    private static func pendingFloor(context: ModelContext) -> Date {
        let name = sourceName
        let fetch = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == name })
        let rows = (try? context.fetch(fetch)) ?? []
        let pending = rows.filter { $0.isLive && $0.tags.contains("Pending") }
        guard let oldest = pending.map(\.capturedAt).min() else { return .distantFuture }
        let bound = Date().addingTimeInterval(-Double(maxHealbackDays) * 86_400)
        return max(oldest.addingTimeInterval(-86_400), bound)
    }

    // MARK: - What changed, as rows

    /// Land the two judgements that are NEWS: a recurring price that rose, and
    /// a subscription that stopped charging.
    ///
    /// **Why these leave the room.** `AppleWalletRoom` computes both for its
    /// head, and a head only speaks while you're standing in front of it — so
    /// before this, "Netflix went up 16%" was visible only to someone who
    /// opened the Apple Wallet room and looked at the subline, which is
    /// precisely the fact nobody goes looking for because nobody knows to.
    /// Landing them puts each in the feed, in the corpus a year later, and in
    /// reach of `NotifySweep`. It is the PostHog precedent exactly (prd §223:
    /// a milestone and a silence land as things while the metric curve does
    /// not), and it does not touch §313's ruling that a CHARGE never notifies:
    /// your bank told you about the charge and told you nothing about the
    /// delta.
    ///
    /// **Backfill can't fake urgency.** Each row is stamped with when it
    /// really happened — a creep at the raised charge's own date, a silence at
    /// the date it missed — so a first connect that reaches back six months
    /// sorts its findings into history rather than into today. `NotifySweep`
    /// only considers rows inside its 36-hour news window, which means that
    /// stamping is also what decides, for free and correctly, that a rise
    /// found on first connect is never announced while tomorrow's is.
    @MainActor
    private static func landChanges(context: ModelContext) {
        let name = sourceName
        let fetch = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == name })
        let existing = (try? context.fetch(fetch)) ?? []
        let refs = Set(existing.compactMap(\.sourceRef))
        let spends = AppleWalletRoomSource.spends(from: existing)
        guard !spends.isEmpty else { return }
        let now = Date()
        let series = AppleWalletRoom.recurringSeries(spends, now: now)

        // EVERY fresh rise, not just the largest: the card shows one because a
        // list of price changes is a bill, but the corpus must hold both when
        // two subscriptions went up in the same month.
        for creep in AppleWalletRoom.creeps(series, now: now) {
            let ref = AppleWalletRoom.creepRef(creep)
            guard !refs.contains(ref) else { continue }
            let thing = Thing(kind: .note,
                              title: AppleWalletRoom.creepLine(creep),
                              content: "",
                              source: sourceName,
                              capturedAt: creep.at,
                              sourceRef: ref)
            thing.tags = ["Card", "Price rise"]
            thing.transferCounterparty = creep.merchant
            thing.priceValue = creep.now
            thing.priceCurrency = creep.currency
            context.insert(thing)
        }

        for silence in AppleWalletRoom.silences(series, now: now) {
            let ref = AppleWalletRoom.silenceRef(silence)
            guard !refs.contains(ref) else { continue }
            let thing = Thing(kind: .note,
                              title: AppleWalletRoom.silenceTitle(silence),
                              content: "",
                              source: sourceName,
                              capturedAt: AppleWalletRoom.silenceOccurredAt(silence),
                              sourceRef: ref)
            thing.tags = ["Card", "Silence"]
            thing.transferCounterparty = silence.merchant
            context.insert(thing)
        }

        reconcileSilences(existing, series: series, context: context)
    }

    /// Remove a landed "stopped charging you" row once that subscription has
    /// charged again.
    ///
    /// **A silence row is the one thing this bridge lands that can become
    /// FALSE.** A creep is a fact about two charges and stays true forever; a
    /// payment due date is superseded by the next statement. But "Spotify
    /// stopped charging you" is a claim about the future, and a subscription
    /// that paused for six weeks — a failed card, a plan change — and then
    /// resumed leaves the corpus asserting something that isn't so, retrievable
    /// and searchable, with nothing to correct it. `silences` stops REPORTING
    /// the merchant the moment a new charge lands, which fixes the card and
    /// does nothing for the row.
    ///
    /// Deleting rather than rewriting, because there is no true sentence left
    /// to write: the outage it described didn't turn into something else, it
    /// turned out not to be one. Deleting an upstream-contradicted row is the
    /// same verb every bridge's heal pass already uses.
    @MainActor
    private static func reconcileSilences(_ existing: [Thing],
                                          series: [AppleWalletRoom.Series],
                                          context: ModelContext) {
        var lastCharge: [String: Date] = [:]
        for s in series {
            let key = AppleWalletRoom.merchantKey(s.merchant)
            lastCharge[key] = max(lastCharge[key] ?? .distantPast, s.last.date)
        }
        for row in existing where row.isLive && row.tags.contains("Silence") {
            guard let ref = row.sourceRef,
                  let lastSeen = AppleWalletRoom.silenceLastSeen(fromRef: ref),
                  let merchant = row.transferCounterparty,
                  let charged = lastCharge[AppleWalletRoom.merchantKey(merchant)],
                  charged > lastSeen else { continue }
            context.delete(row)
        }
    }

    /// The payment-due row — a reconciling `dueAt` thing, the ENSExpiry shape.
    /// Keyed by account AND date so a new statement lands a new row while the
    /// old one is superseded rather than duplicated.
    static func dueRef(account: String, date: Date) -> String {
        "applewallet:due:\(account):\(Int(date.timeIntervalSince1970))"
    }

    @MainActor
    private static func landDueRows(context: ModelContext) {
        let name = sourceName
        let fetch = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == name })
        let existing = (try? context.fetch(fetch)) ?? []
        let refs = Set(existing.compactMap(\.sourceRef))
        for (account, stamp) in dues {
            let date = Date(timeIntervalSince1970: stamp)
            guard date > Date().addingTimeInterval(-86_400 * 7) else { continue }
            let ref = dueRef(account: account, date: date)
            guard !refs.contains(ref) else { continue }
            let thing = Thing(kind: .reminder,
                              title: String(localized: "\(account) payment due"),
                              content: "",
                              source: sourceName,
                              capturedAt: .now,
                              sourceRef: ref)
            thing.dueAt = date
            thing.tags = ["Card", "Payment"]
            context.insert(thing)
        }
    }
}
