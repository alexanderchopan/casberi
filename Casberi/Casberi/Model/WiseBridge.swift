import Foundation
import SwiftData

/// WISE (2026-09-16, prd §778) — the multi-currency account, read with a
/// personal API token the person mints for themselves.
///
/// ## Why this one passes §278's test when Plaid does not
///
/// Wise issues the credential to the PERSON, in their own settings, scoped to
/// their own account, and it can be minted **read-only**. That is the
/// Bitrefill / Privacy.com / Readwise shape exactly: the phone talks straight
/// to `api.transferwise.com` carrying the person's own token, nothing
/// authenticates as Casberi, and there is no per-user cost to anybody. §278's
/// refusal was never about aggregators being difficult — it was about whose
/// identity is on the request.
///
/// ## What it reads, and the ceiling it stops at
///
/// Three reads, in order: `GET /v1/profiles` resolves which profile the token
/// belongs to (personal first — see `resolveProfile`), `GET /v4/profiles/{id}/
/// balances?types=STANDARD` reads what is held, and `GET /v1/transfers`
/// reads the money that MOVED.
///
/// **Card spending is NOT here, and that is a real ceiling rather than an
/// omission.** A Wise card purchase lives in the balance STATEMENT
/// (`/v1/profiles/{id}/balance-statements/{balanceId}/statement.json`), and
/// that endpoint is SCA-protected for any profile registered in the UK or the
/// EEA: Wise answers 403 with a one-time token in an `x-2fa-approval` header,
/// and clearing it means signing that token with an RSA private key whose
/// public half the person has uploaded to Wise by hand. That is a buildable
/// thing — an on-device RSA keypair, a PEM the person pastes into Wise, and a
/// signed retry — and it is deliberately NOT built today rather than
/// half-built: an untestable signing path behind a PEM-paste step, on a build
/// host with no Wise token, would ship as a control nobody can prove works.
/// The account page says so in its own words. Transfers and balances need no
/// SCA, which is why they are what this seat is.
///
/// ## The module doctrine, applied
///
/// A transfer IS a `Thing` — money moving is the standing exception (Apple
/// Wallet, Gnosis Pay, Privacy.com), and a transfer is the clearest
/// case of it. A BALANCE is a state (§216): it composes into `WiseStanding`,
/// written by the same pass that reads it, and never lands as a row.
///
/// A transfer's STATUS changes after it lands — `processing` becomes
/// `outgoing_payment_sent`, or `bounced_back` — so this bridge reconciles
/// already-landed rows on every pass (`heal`). That is Linear's and Trello's
/// shape and it exists for their exact reason: dedupe never revisits a known
/// ref, so a row's first sight would otherwise be frozen as its final word,
/// and a bounced transfer would read as sent forever.
///
/// ## Nothing here can move money
///
/// Wise's send flow is `POST /v1/quotes` → `POST /v1/transfers` →
/// `POST /v1/transfers/{id}/payments`, and every one of those is a write this
/// file does not contain. A read-only token cannot issue them at all; a
/// read-write token could, which is why the setup copy tells the person to
/// mint the read-only grade. Do not add a POST to this file — it would make
/// the page's own promise false.
///
/// ## UNMEASURED (2026-09-16)
///
/// No Wise token has ever been given to this app and the build host has no
/// egress to `api.transferwise.com`. The shapes below are taken from Wise's
/// own published API reference — `/v1/profiles` returning `[{id, type,
/// details}]`, `/v1/transfers` returning a bare array with `sourceValue`,
/// `sourceCurrency`, `targetValue`, `targetCurrency`, `status`, `created` and
/// a nested `details.reference`, `/v4/…/balances` returning `amount.value`
/// beside `reservedAmount`/`cashAmount`/`totalWorth` — read, not remembered.
/// `created` arrives as `"2018-12-16 15:25:51"`, which is NOT ISO 8601, which
/// is why `WiseFetch.date` exists rather than `IngestSupport.isoDate` alone.
/// Every parse fails to nil, so a drift lands nothing rather than something
/// wrong, and `-wiseProbe YES` names which link broke in one launch.
enum WiseAuth {

    /// The personal API token — the slot `TokenBridge.connected` reads.
    static var tokenVaultKey: String { TokenBridge.wise.tokenKey }
    /// The profile the token was resolved against. Not a secret (an integer
    /// id), but it lives beside the token so a Remove takes both — `JiraAuth`'s
    /// shape.
    static let profileVaultKey = "wise.profileid"
    private static let profileNameKey = "wise.profilename"

    static var storedToken: String? {
        TokenVault.get(tokenVaultKey).flatMap { $0.isEmpty ? nil : $0 }
    }
    static var storedProfileID: String? {
        TokenVault.get(profileVaultKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var profileName: String? {
        UserDefaults.standard.string(forKey: profileNameKey)
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Connected means a token AND a resolved profile. A token alone can be
    /// stored and still read nothing — every balance and transfer call is
    /// per-profile — so gating on the token alone would be a seat reading
    /// "connected" while every pass returns empty, which is §83's fake status.
    static var configured: Bool { storedToken != nil && storedProfileID != nil }

    static func setProfile(id: String, name: String?) {
        TokenVault.set(id, for: profileVaultKey)
        if let name, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: profileNameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: profileNameKey)
        }
    }

    /// Drops the token, the profile and every reading taken with them. On a
    /// reconnect as well as a Remove: a second token may belong to a different
    /// Wise account, and carrying the old profile's balances into it would
    /// show somebody else's money under a fresh connection.
    static func clear() {
        TokenVault.delete(tokenVaultKey)
        TokenVault.delete(profileVaultKey)
        UserDefaults.standard.removeObject(forKey: profileNameKey)
        WiseState.clear()
    }
}

// MARK: - The payload

struct WiseProfile: Equatable {
    var id: String
    /// "personal" or "business".
    var type: String
    var name: String?
}

struct WiseBalance: Equatable {
    var id: String
    var currency: String
    /// The spendable amount — `amount.value`, not `totalWorth`, which folds
    /// in what is reserved and what is invested. A balance a person cannot
    /// spend is not the number they mean by "what's in my account".
    var value: Double?
    var name: String?
    /// "STANDARD" or "SAVINGS" — the jar distinction Wise's own app draws.
    var type: String?
}

struct WiseTransfer: Equatable {
    var id: String
    var status: String
    var reference: String?
    var sourceValue: Double?
    var sourceCurrency: String?
    var targetValue: Double?
    var targetCurrency: String?
    var created: Date?
}

// MARK: - The reads

enum WiseFetch {

    static let api = "https://api.transferwise.com"

    /// Rows per transfers call. A runaway guard, not a window — the window is
    /// `createdDateStart`.
    static let pageLimit = 100

    private static func bearer(_ token: String) -> String { "Bearer \(token)" }

    /// The profiles this token can see, WITH the HTTP status beside them.
    ///
    /// The status is here because the connect screen has to tell a token Wise
    /// REFUSED (401) from a Wise it could not reach (0) — two causes that
    /// would otherwise render as one "check the token", one of which is the
    /// person's fault and one of which is not. `getJSONStatus` reports a
    /// transport failure as 0, which is exactly the distinction.
    static func profilesWithStatus(token: String) async -> (profiles: [WiseProfile]?, status: Int) {
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(api)/v1/profiles", auth: bearer(token), service: WiseShape.source)
        guard status == 200, let rows = json as? [[String: Any]] else { return (nil, status) }
        return (rows.compactMap(profile), status)
    }

    /// The profiles alone, for callers with nothing to say about the status.
    static func profiles(token: String) async -> [WiseProfile]? {
        await profilesWithStatus(token: token).profiles
    }

    /// The profile this seat reads: the PERSONAL one where there is one, else
    /// the first. A token that can see a business profile too is common (a
    /// freelancer's Wise account), and reading the business one by accident
    /// would put a company's money in somebody's personal feed.
    static func resolveProfile(_ profiles: [WiseProfile]) -> WiseProfile? {
        profiles.first { $0.type.lowercased() == "personal" } ?? profiles.first
    }

    static func balances(token: String, profileID: String) async -> [WiseBalance]? {
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(api)/v4/profiles/\(profileID)/balances?types=STANDARD",
            auth: bearer(token), service: WiseShape.source)
        guard status == 200, let rows = json as? [[String: Any]] else { return nil }
        return rows.compactMap(balance)
    }

    /// Transfers created since `since`. Wise wants
    /// `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` and is inclusive of the date given.
    static func transfers(token: String, profileID: String, since: Date)
        async -> [WiseTransfer]? {
        let start = requestDate.string(from: since)
        let url = "\(api)/v1/transfers?profile=\(profileID)&offset=0&limit=\(pageLimit)"
            + "&createdDateStart=\(start)"
        let (json, status) = await IngestSupport.getJSONStatus(
            url, auth: bearer(token), service: WiseShape.source)
        guard status == 200, let rows = json as? [[String: Any]] else { return nil }
        return rows.compactMap(transfer)
    }

    // MARK: Parsing

    static func profile(_ row: [String: Any]) -> WiseProfile? {
        guard let id = identifier(row["id"]) else { return nil }
        let details = row["details"] as? [String: Any]
        let first = details?["firstName"] as? String
        let last = details?["lastName"] as? String
        let business = details?["name"] as? String
        let personal = [first, last].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let name = personal.isEmpty ? business : personal
        return WiseProfile(id: id,
                           type: (row["type"] as? String) ?? "",
                           name: name.flatMap { $0.isEmpty ? nil : $0 })
    }

    static func balance(_ row: [String: Any]) -> WiseBalance? {
        guard let id = identifier(row["id"]) else { return nil }
        let amount = row["amount"] as? [String: Any]
        let currency = (amount?["currency"] as? String)
            ?? (row["currency"] as? String) ?? ""
        return WiseBalance(id: id,
                           currency: currency,
                           value: number(amount?["value"]),
                           name: (row["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                           type: row["type"] as? String)
    }

    static func transfer(_ row: [String: Any]) -> WiseTransfer? {
        guard let id = identifier(row["id"]) else { return nil }
        let details = row["details"] as? [String: Any]
        let reference = (details?["reference"] as? String) ?? (row["reference"] as? String)
        return WiseTransfer(
            id: id,
            status: (row["status"] as? String) ?? "",
            reference: reference.flatMap {
                $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0
            },
            sourceValue: number(row["sourceValue"]),
            sourceCurrency: row["sourceCurrency"] as? String,
            targetValue: number(row["targetValue"]),
            targetCurrency: row["targetCurrency"] as? String,
            created: date(row["created"]))
    }

    /// An id that may arrive as a JSON number or as a string. Wise sends
    /// integers; a string is accepted because an id read as a `Double` and
    /// printed back would become "1.5574445e+07" and dedupe against nothing.
    static func identifier(_ raw: Any?) -> String? {
        if let i = raw as? Int { return String(i) }
        if let s = (raw as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            return s
        }
        if let d = raw as? Double, d == d.rounded(), d.magnitude < 9e15 {
            return String(Int(d))
        }
        return nil
    }

    static func number(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespaces),
              !s.isEmpty else { return nil }
        return Double(s)
    }

    /// Wise's `created` is `"2018-12-16 15:25:51"` — a space, no `T`, no zone
    /// — which `ISO8601DateFormatter` refuses outright. Other Wise fields DO
    /// arrive as ISO, so both are tried, ISO first.
    static func date(_ raw: Any?) -> Date? {
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespaces),
              !s.isEmpty else { return nil }
        if let iso = IngestSupport.isoDate(s) { return iso }
        return spaced.date(from: s)
    }

    private static let spaced: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let requestDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f
    }()
}

// MARK: - Shaping (pure — compiled whole by the harness)

enum WiseShape {
    static let source = "Wise"

    static func ref(transfer id: String) -> String { "wise:transfer:\(id)" }

    /// Wise's transfer lifecycle, reduced to the three facts a row needs.
    enum Stage: Equatable {
        case sent
        case pending
        /// The money came back or never left — bounced, refunded, cancelled.
        case returned
    }

    static func stage(_ status: String) -> Stage {
        switch status.lowercased() {
        case "outgoing_payment_sent": return .sent
        case "bounced_back", "funds_refunded", "cancelled", "charged_back": return .returned
        default: return .pending
        }
    }

    /// The row's title. Any abnormal state LEADS, for
    /// `AppleWalletBridge.rowTitle`'s reason: `IngestSupport.titleLine` clamps
    /// at 80 characters and eats the end, so a bounced transfer reading as a
    /// completed one is §83's fake status with the evidence clipped off.
    ///
    /// The two sides are both shown when they differ, because a conversion is
    /// most of what a Wise transfer IS — "£100.00 → €113.79" says something
    /// neither half says alone. A same-currency send draws one amount.
    static func rowTitle(_ transfer: WiseTransfer) -> String {
        let amounts = amountLine(transfer)
        let reference = transfer.reference.map { " · \($0)" } ?? ""
        switch stage(transfer.status) {
        case .sent:     return String(localized: "Sent · \(amounts)\(reference)")
        case .pending:  return String(localized: "Sending · \(amounts)\(reference)")
        case .returned: return String(localized: "Returned · \(amounts)\(reference)")
        }
    }

    /// "£100.00 → €113.79", or one side when the other is missing or the same
    /// currency. Never a converted figure this bridge computed itself.
    static func amountLine(_ transfer: WiseTransfer) -> String {
        let from = money(transfer.sourceValue, transfer.sourceCurrency)
        let to = money(transfer.targetValue, transfer.targetCurrency)
        guard let from else { return to ?? String(localized: "Transfer") }
        guard let to, transfer.sourceCurrency != transfer.targetCurrency else { return from }
        return "\(from) → \(to)"
    }

    static func money(_ value: Double?, _ currency: String?) -> String? {
        guard let value, let currency, currency.count == 3 else { return nil }
        return AppleWalletRoom.money(value, currency)
    }

    static func tags(_ transfer: WiseTransfer) -> [String] {
        var out = [String(localized: "Transfer")]
        switch stage(transfer.status) {
        case .sent:     break
        case .pending:  out.append(String(localized: "Pending"))
        case .returned: out.append(String(localized: "Returned"))
        }
        return out
    }

    /// What the seat proves it is reading: the balances, largest first, up to
    /// three, then "+N more". nil when nothing has been read yet.
    static func balanceLine(_ standing: WiseStanding) -> String? {
        let priced = standing.balances.filter { $0.value != nil && $0.currency.count == 3 }
        guard !priced.isEmpty else { return nil }
        let sorted = priced.sorted { ($0.value ?? 0) > ($1.value ?? 0) }
        let shown = sorted.prefix(3).compactMap { money($0.value, $0.currency) }
        guard !shown.isEmpty else { return nil }
        let rest = sorted.count - shown.count
        return rest > 0
            ? String(localized: "\(shown.joined(separator: " · ")) +\(rest) more")
            : shown.joined(separator: " · ")
    }
}

// MARK: - Standing (a STATE, §216 — never a row)

struct WiseStanding: Codable, Equatable {
    struct Balance: Codable, Equatable {
        var id: String
        var currency: String
        var value: Double?
        var name: String?
    }

    var profileName: String?
    var balances: [Balance] = []
    var lastRead: Date?

    static let empty = WiseStanding()
}

enum WiseState {
    private static let standingKey = "wise.standing"
    private static let cursorKey = "wise.cursor"

    static var standing: WiseStanding {
        get {
            guard let data = UserDefaults.standard.data(forKey: standingKey),
                  let value = try? JSONDecoder().decode(WiseStanding.self, from: data)
            else { return .empty }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: standingKey)
        }
    }

    /// The newest transfer creation date landed. The window reaches BACK from
    /// it, so it is a floor for the read rather than the read itself.
    static var cursor: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: cursorKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: cursorKey) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: standingKey)
        UserDefaults.standard.removeObject(forKey: cursorKey)
    }
}

// MARK: - The pass

enum WiseIngest {

    /// First sight reaches back this far.
    static let backfillDays = 180
    /// How far back of already-seen history every pass re-reads, so a transfer
    /// whose STATUS moved is healed. Wide because Wise's slow states are
    /// slow: a bounced payment can come back a week after it was sent.
    static let healbackDays = 14

    @MainActor private static var running = false
    @MainActor private(set) static var lastPassFailure: String?

    /// One pass. Returns rows landed, or nil when the read could not run at
    /// all — the two are different and the screen says so.
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        guard let token = WiseAuth.storedToken,
              let profileID = WiseAuth.storedProfileID else { return nil }
        running = true
        defer { running = false }

        let since = WiseState.cursor
            .map { $0.addingTimeInterval(-Double(healbackDays) * 86_400) }
            ?? Date().addingTimeInterval(-Double(backfillDays) * 86_400)

        async let balancesTask = WiseFetch.balances(token: token, profileID: profileID)
        async let transfersTask = WiseFetch.transfers(token: token, profileID: profileID,
                                                      since: since)
        let (balances, transfers) = await (balancesTask, transfersTask)

        guard let transfers else {
            lastPassFailure = String(localized: "Wise refused that token, or couldn't be reached.")
            return nil
        }
        lastPassFailure = nil

        var standing = WiseState.standing
        standing.profileName = WiseAuth.profileName
        standing.lastRead = .now
        if let balances {
            standing.balances = balances.map {
                .init(id: $0.id, currency: $0.currency, value: $0.value, name: $0.name)
            }
        }
        WiseState.standing = standing

        let stored = IngestSupport.thingsByRef(context, source: WiseShape.source)
        var seen = Set(stored.keys)
        var landed = 0
        // A heal writes without landing, so "did anything change" is not the
        // same question as "did anything arrive" — and a save on a pass that
        // changed nothing is a write the foreground sweep pays for on every
        // activation.
        var changed = false
        var newest = WiseState.cursor

        for transfer in transfers {
            let ref = WiseShape.ref(transfer: transfer.id)
            if let row = stored[ref] {
                if heal(row, transfer: transfer) { changed = true }
                continue
            }
            guard seen.insert(ref).inserted else { continue }
            let thing = shape(transfer, ref: ref, moment: transfer.created ?? .now)
            context.insert(thing)
            SpotlightIndex.index([thing])
            landed += 1
            changed = true
            if let created = transfer.created, newest == nil || created > newest! {
                newest = created
            }
        }

        if let newest { WiseState.cursor = newest }
        if changed { context.saveHonestly() }
        return landed
    }

    @MainActor
    private static func shape(_ transfer: WiseTransfer, ref: String, moment: Date) -> Thing {
        let thing = Thing(kind: .transaction,
                          title: IngestSupport.titleLine(WiseShape.rowTitle(transfer)),
                          content: "",
                          source: WiseShape.source,
                          capturedAt: moment,
                          tags: WiseShape.tags(transfer),
                          sourceRef: ref)
        apply(transfer, to: thing)
        return thing
    }

    /// Everything a row carries beyond its title, in one place so the landing
    /// and the heal can never disagree about what a row holds.
    @MainActor
    private static func apply(_ transfer: WiseTransfer, to thing: Thing) {
        thing.transferDirection = WiseShape.stage(transfer.status) == .returned
            ? "received" : "sent"
        // The SOURCE side is the money that left this person's account, which
        // is the number every spend total in this app wants. The target side
        // is what the recipient got, at a rate this bridge did not set.
        if let value = transfer.sourceValue, let currency = transfer.sourceCurrency,
           currency.count == 3 {
            thing.priceValue = value
            thing.priceCurrency = currency
            thing.transferAmount = AppleWalletRoom.money(value, currency)
        }
        // `enrichedText` is retrieval-only by the 2026-07-15 ruling, so none of
        // this is drawn — it is what makes a transfer findable by the
        // reference the person typed, or by the currency pair.
        var enriched: [String] = []
        if let reference = transfer.reference { enriched.append(reference) }
        if let from = transfer.sourceCurrency, let to = transfer.targetCurrency, from != to {
            enriched.append("\(from) \(to)")
        }
        if let name = WiseAuth.profileName { enriched.append(name) }
        thing.enrichedText = enriched.isEmpty ? nil : enriched.joined(separator: " · ")
    }

    /// A transfer whose status moved after it landed. Linear's and Trello's
    /// shape: dedupe never revisits a known ref, so without this a row's first
    /// sight is frozen as its last word and a bounced payment reads as sent
    /// forever.
    @MainActor
    @discardableResult
    private static func heal(_ row: Thing, transfer: WiseTransfer) -> Bool {
        guard row.isLive else { return false }
        let title = IngestSupport.titleLine(WiseShape.rowTitle(transfer))
        let tags = WiseShape.tags(transfer)
        guard row.title != title || row.tags != tags else { return false }
        row.title = title
        row.tags = tags
        apply(transfer, to: row)
        return true
    }
}

// MARK: - The seat

enum WiseWatch {
    @MainActor
    static func registerBridge(store: BridgeStore) {
        guard WiseAuth.configured else {
            store.remove(TokenBridge.wise.bridgeID)
            return
        }
        let standing = WiseState.standing
        let proof = WiseShape.balanceLine(standing)
            ?? standing.profileName
            ?? String(localized: "Connected")
        store.registerConnected(
            id: TokenBridge.wise.bridgeID, name: WiseShape.source,
            proof: proof)
    }
}

// MARK: - Probe

extension WiseFetch {

    /// `-wiseProbe YES` — the read, link by link, with the STORED token. An
    /// empty Wise room has several causes that render as one nothing: no
    /// token, a refused token, a token whose profile never resolved, a genuinely
    /// quiet account, or shape drift in a doc-derived field map. Only the last
    /// is a bug, and this tells them apart in one launch.
    ///
    /// It never prints the token, a balance, or a transfer amount — what a
    /// probe needs is shapes and statuses.
    static func probe() async {
        guard let token = WiseAuth.storedToken else {
            NSLog("[Casberi] wiseProbe: no stored token (connect via -tokenBridge \"Wise:<token>\")")
            return
        }
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(api)/v1/profiles", auth: "Bearer \(token)", service: WiseShape.source)
        guard status == 200 else {
            NSLog("[Casberi] wiseProbe: profiles HTTP %d (401 wrong or revoked token · 0 unreachable)",
                  status)
            return
        }
        let rows = (json as? [[String: Any]]) ?? []
        let parsed = rows.compactMap(profile)
        NSLog("[Casberi] wiseProbe: profiles HTTP 200 · %d profiles · types=%@",
              parsed.count, parsed.map(\.type).joined(separator: ","))
        guard let chosen = resolveProfile(parsed) else {
            NSLog("[Casberi] wiseProbe: no profile resolved — nothing else can be read")
            return
        }
        let (balanceJSON, balanceStatus) = await IngestSupport.getJSONStatus(
            "\(api)/v4/profiles/\(chosen.id)/balances?types=STANDARD",
            auth: "Bearer \(token)", service: WiseShape.source)
        let balanceRows = (balanceJSON as? [[String: Any]]) ?? []
        NSLog("[Casberi] wiseBalances| HTTP %d · %d balances · fields={%@}",
              balanceStatus, balanceRows.count,
              balanceRows.first.map { Array($0.keys).sorted().joined(separator: ",") } ?? "—")
        let since = Date().addingTimeInterval(-90 * 86_400)
        let (transferJSON, transferStatus) = await IngestSupport.getJSONStatus(
            "\(api)/v1/transfers?profile=\(chosen.id)&offset=0&limit=\(pageLimit)"
                + "&createdDateStart=\(requestDate.string(from: since))",
            auth: "Bearer \(token)", service: WiseShape.source)
        let transferRows = (transferJSON as? [[String: Any]]) ?? []
        NSLog("[Casberi] wiseTransfers| HTTP %d · %d transfers · fields={%@}",
              transferStatus, transferRows.count,
              transferRows.first.map { Array($0.keys).sorted().joined(separator: ",") } ?? "—")
        for row in transferRows.prefix(10) {
            let parsedRow = transfer(row)
            NSLog("[Casberi] wiseTransfer| status=%@ created=%@ pair=%@→%@ reference=%@",
                  parsedRow?.status ?? "—",
                  parsedRow?.created == nil ? "unparsed" : "parsed",
                  parsedRow?.sourceCurrency ?? "—",
                  parsedRow?.targetCurrency ?? "—",
                  parsedRow?.reference == nil ? "absent" : "present")
        }
    }
}
