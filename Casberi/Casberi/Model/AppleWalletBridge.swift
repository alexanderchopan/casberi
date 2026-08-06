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

        let since = cursor ?? Date().addingTimeInterval(-Double(backfillDays) * 86_400)
        let query = TransactionQuery(
            sortDescriptors: [SortDescriptor(\Transaction.transactionDate, order: .reverse)],
            predicate: #Predicate { $0.transactionDate > since },
            limit: maxPerPass)
        guard let txns = try? await FinanceStore.shared.transactions(query: query) else { return nil }

        let landed = land(txns, accountNames: names, context: context)
        landDueRows(context: context)
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
            let merchant = merchantLabel(txn)
            let isRefund = txn.creditDebitIndicator == .credit
            let settled = txn.status == .booked
            let title = rowTitle(merchant: merchant, amount: amount, currency: currency,
                                 isRefund: isRefund, isSettled: settled)

            if let row = byRef[ref] {
                // Heal: a pending row that posted, or an amount that moved.
                if row.title != title {
                    row.title = title
                    row.priceValue = amount
                    row.priceCurrency = currency
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
            if let account = accountNames[txn.accountID] {
                thing.enrichedText = account
            }
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
