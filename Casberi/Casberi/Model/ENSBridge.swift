import Foundation
import SwiftData

/// The ENS seat (2026-08-29, prd §533) — follow a name, and know where it
/// stands. Keyless: ENS's own metadata service answers BY NAME, one GET, no
/// account, no key, no hashing.
///
/// **Why this is a seat at all.** prd §515a's tripwire says a protocol the
/// wallet reads on its own must never also ship as a catalog offer, because
/// the tile then advertises a connect that does not exist. ENS clears it on the
/// one thing the wallet structurally cannot do: `ENSExpiry` reads only names
/// the wallet already SEES — an address you typed as a name, or the primary
/// name an address reverse-resolves to — so there was no way to follow a
/// name you do not own. That act needs somebody to type a name, which is
/// exactly what a seat with `needsSetup` is for.
///
/// **The two halves know each other's spelling, and that is deliberate.** A
/// name found from a watched wallet already has a row under
/// `wallet:ensexpiry:<name>`; following that same name ADOPTS the row rather
/// than landing a second one about the same name in a second room. One name,
/// one row. `ENSExpiry` stands down for any name this seat follows, and does
/// exactly what it always did for the rest — so somebody who never connects
/// this seat sees no change at all, and nothing has to be migrated.
enum ENSWatch {

    /// The source every followed name lands under. Its OWN source, which is
    /// what §515 requires of a seat: five icons resolving to one room is the
    /// defect that ruling removed.
    static let source = "ENS"

    static let seatID = "ens"

    // MARK: - Reading the follow list

    /// Every followed name. The thing IS the watch (the `TokenWatch`/
    /// `StockWatch` precedent) — deleting the row is unfollowing, with no
    /// separate store to drift out of sync with the corpus.
    @MainActor
    static func followed(context: ModelContext) -> [String] {
        Array(Set(rows(context: context).compactMap { $0.sourceRef.flatMap(ENSName.name(fromRef:)) }))
            .sorted()
    }

    /// The follow ROWS, newest first. Scoped to this bridge's source, never a
    /// whole-corpus ref scan.
    @MainActor
    static func rows(context: ModelContext) -> [Thing] {
        let source = source
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source && $0.sourceRef != nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.propertiesToFetch = [\.sourceRef]
        return ((try? context.fetch(descriptor)) ?? [])
            .filter(\.isLive)
            .filter { ($0.sourceRef.flatMap(ENSName.name(fromRef:))) != nil }
    }

    /// Names the WALLET has already found — the `ENSExpiry` rows — that this
    /// seat does not follow yet. What the setup screen offers as one-tap
    /// suggestions.
    ///
    /// Deliberately NOT followed automatically. §515a's complaint was a seat
    /// lighting up for work the app was already doing without asking; a
    /// suggestion is a tap somebody takes (the §513 Altana precedent: offer an
    /// account to watch, never watch one on their behalf). It also costs no
    /// network read — these rows are already in the corpus, so the suggestion
    /// list is a corpus read, not a reverse-resolution pass.
    @MainActor
    static func suggestions(context: ModelContext) -> [String] {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" && $0.sourceRef != nil })
        descriptor.propertiesToFetch = [\.sourceRef]
        let already = Set(followed(context: context))
        let prefix = ENSName.walletRefPrefix
        let names = ((try? context.fetch(descriptor)) ?? [])
            .compactMap(\.sourceRef)
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
        return Array(Set(names).subtracting(already)).sorted()
    }

    // MARK: - Following

    enum FollowOutcome {
        case followed(Thing)
        case adopted(Thing)
        case already
        case invalid
    }

    /// Follows a name. Takes whatever was typed — a bare label, a full name, an
    /// `app.ens.domains` link — and normalizes it, so the ref can never depend
    /// on how somebody happened to write it.
    ///
    /// The row lands with no expiry: the first sweep fills it in. That split is
    /// on purpose (the `StockWatch` shape) — a follow is a tap and must not sit
    /// behind a third party's timeouts, and a name whose metadata read fails
    /// stays followed rather than silently refusing to be added.
    @MainActor
    @discardableResult
    static func follow(_ raw: String, context: ModelContext) -> FollowOutcome {
        guard let name = ENSName.normalized(raw) else { return .invalid }
        let ref = ENSName.ref(for: name)
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == ref }))) ?? 0
        guard existing == 0 else { return .already }

        // ADOPTION. A name the wallet already found keeps its row, its dates
        // and its place in history — it changes rooms, nothing more. Landing a
        // second row instead would leave two rows counting down to one moment,
        // in two rooms, and `ENSExpiry` would go on reconciling the one this
        // seat does not own.
        let walletRef = ENSName.walletRef(for: name)
        if let landed = try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == walletRef })).first, landed.isLive {
            landed.source = source
            landed.sourceRef = ref
            landed.authorHandle = name
            if !landed.tags.contains("Watchlist") { landed.tags.append("Watchlist") }
            context.saveHonestly()
            SpotlightIndex.index([landed])
            return .adopted(landed)
        }

        let thing = Thing(
            kind: .link,
            title: name,
            content: "https://app.ens.domains/name/\(name)",
            source: source,
            capturedAt: .now,
            tags: ["Watchlist"],
            sourceRef: ref
        )
        // The NAME as a stamped field, riding `authorHandle` for the reason
        // `TokenWatch` and `StockWatch` both give for their symbol: a row's
        // subject must be readable without parsing it back out of a localized
        // title (prd §363's rule).
        thing.authorHandle = name
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        return .followed(thing)
    }

    /// Unfollows one name, and takes what it brought with it.
    ///
    /// §286's ruling: disconnecting a bridge doesn't erase what it landed, but
    /// a watchlist is a FOLLOW — once you stop following a name, nothing
    /// explains the renewal notice sitting in your feed about it.
    @MainActor
    static func unfollow(_ name: String, context: ModelContext) {
        let rows = things(about: name, context: context)
        guard !rows.isEmpty else { return }
        SpotlightIndex.remove(ids: rows.map(\.id))
        for row in rows { context.delete(row) }
        ENSState.forget(name)
        context.saveHonestly()
    }

    /// Every row this seat landed about one name — the follow itself, and any
    /// moment stamped with it.
    @MainActor
    private static func things(about name: String, context: ModelContext) -> [Thing] {
        let source = source
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source && $0.sourceRef != nil })
        // Matched in Swift rather than by predicate: a moment's ref carries a
        // trailing epoch (`ens:renewed:<name>:<epoch>`), so this is a prefix
        // test over a small per-source fetch, not a `contains` predicate.
        return ((try? context.fetch(descriptor)) ?? [])
            .filter(\.isLive)
            .filter { row in
                guard let ref = row.sourceRef else { return false }
                return ref == ENSName.ref(for: name)
                    || ref.hasPrefix("ens:renewed:\(name):")
                    || ref.hasPrefix("ens:registered:\(name):")
            }
    }

    /// The Disconnect teardown — every followed name at once.
    @MainActor
    static func unfollowAll(context: ModelContext) {
        let source = source
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        let rows = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
        guard !rows.isEmpty else { return }
        SpotlightIndex.remove(ids: rows.map(\.id))
        for row in rows { context.delete(row) }
        ENSState.forgetAll()
        context.saveHonestly()
    }

    /// Registers (or clears) the seat with the live followed count.
    @MainActor
    static func registerBridge(store: BridgeStore, context: ModelContext) {
        let count = followed(context: context).count
        guard count > 0 else { store.remove(seatID); return }
        store.registerConnected(
            id: seatID, name: "ENS",
            proof: count == 1
                ? String(localized: "1 name followed")
                : String(localized: "\(count) names followed"),
            can: ["Reads when the names you follow expire, and when they're renewed.",
                  "Public data, no account, no key — nothing here registers or renews."])
    }
}

// MARK: - What we read last time

/// One reading per followed name, in UserDefaults (the `ASCState`/`X402State`
/// shape). NOT a `Thing` field, deliberately: a name's expiry is re-read every
/// sweep, and a stored property would be a CloudKit Production deploy for a
/// fact that is never stale for long.
///
/// It exists for one thing a row cannot answer: **what the expiry was LAST
/// time.** A renewal is only detectable as a date that moved, and the row
/// carries the next CLIFF rather than the expiry — so without this, a name
/// renewed for four years would silently update its own countdown and say
/// nothing about the renewal, which is the news.
enum ENSState {

    struct Reading: Codable, Equatable {
        var expiry: Date?
        var registered: Date?
        var isNormalized: Bool = true
        /// The service answered 404: the registrar has no record. Distinct
        /// from `expiry == nil` on a reading that failed — that one is not
        /// written at all.
        var unregistered: Bool = false
        var readAt: Date
    }

    private static let key = "ens.readings"

    static func all() -> [String: Reading] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: Reading].self, from: data)
        else { return [:] }
        return map
    }

    static func reading(_ name: String) -> Reading? { all()[name] }

    static func write(_ name: String, _ reading: Reading) {
        var map = all()
        map[name] = reading
        save(map)
    }

    static func forget(_ name: String) {
        var map = all()
        map.removeValue(forKey: name)
        save(map)
    }

    /// Forgets exactly the named readings — the Walletbeat/Radicle teardown
    /// shape: a dev install may be reading a real name through this same
    /// store, so demo exit takes only the demo's own three by name.
    static func forgetDemo(_ names: [String]) {
        var map = all()
        for name in names { map.removeValue(forKey: name) }
        save(map)
    }

    static func forgetAll() { UserDefaults.standard.removeObject(forKey: key) }

    private static func save(_ map: [String: Reading]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Ingest

enum ENSIngest {

    /// The `.eth` BaseRegistrar — the NFT contract the metadata service keys
    /// on. Shared with `ENSExpiry`, which measured it first.
    static let baseRegistrar = "0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85"

    /// How many names one foreground pass reads. A bound, not a ceiling: names
    /// are read oldest-reading-first, so a long follow list finishes over a few
    /// opens rather than firing thirty requests on one.
    static let perPass = 12

    /// How stale a reading has to be before it is worth re-reading. An expiry
    /// moves when somebody renews, which is a once-a-year event — six hours is
    /// already far tighter than the fact changes, and it keeps a seat with
    /// thirty names from making thirty requests every time the app opens.
    static let readWindow: TimeInterval = 6 * 60 * 60

    @MainActor private static var running = false

    /// Reads each followed name and reconciles its row. Returns the number of
    /// NEW things (moments), or nil if nothing could be read at all — the
    /// "reached?" convention every other bridge here uses, so a network hiccup
    /// never reads as "nothing is expiring".
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard !DemoMode.isActive else { return 0 }
        guard !running else { return 0 }
        running = true
        defer { running = false }

        let names = due(context: context)
        guard !names.isEmpty else { return 0 }

        var added = 0
        var reached = false
        for name in names {
            let (json, status) = await IngestSupport.getJSONStatus(
                "https://metadata.ens.domains/mainnet/\(baseRegistrar)/\(encoded(name))",
                service: "ENS")
            // A 404 is the service SAYING the registrar has no record — the one
            // negative answer it gives (measured 2026-08-29). Any other failure
            // is not knowing, and must never be read as "nobody owns this".
            if status == 404 {
                reached = true
                added += land(name: name, facts: nil, unregistered: true, context: context)
                continue
            }
            guard status == 200, let facts = ENSName.facts(name: name, json: json) else { continue }
            reached = true
            added += land(name: name, facts: facts, unregistered: false, context: context)
        }
        if added > 0 { context.saveHonestly() }
        return reached ? added : nil
    }

    /// The names this pass reads: never-read first, then the stalest, capped.
    @MainActor
    private static func due(context: ModelContext) -> [String] {
        let readings = ENSState.all()
        let now = Date.now
        return ENSWatch.followed(context: context)
            .filter { now.timeIntervalSince(readings[$0]?.readAt ?? .distantPast) >= readWindow }
            .sorted { (readings[$0]?.readAt ?? .distantPast) < (readings[$1]?.readAt ?? .distantPast) }
            .prefix(perPass)
            .map { $0 }
    }

    /// Reconciles one name's row against a fresh reading, and lands a moment
    /// when something really happened. Returns how many things were inserted.
    @MainActor
    private static func land(name: String, facts: ENSName.Facts?, unregistered: Bool,
                             context: ModelContext) -> Int {
        let previous = ENSState.reading(name)
        let expiry = facts?.expiry
        ENSState.write(name, ENSState.Reading(
            expiry: expiry,
            registered: facts?.registered,
            isNormalized: facts?.isNormalized ?? true,
            unregistered: unregistered,
            readAt: .now))

        let ref = ENSName.ref(for: name)
        if let row = try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == ref })).first, row.isLive {
            let title = ENSName.title(name: name, expiry: expiry)
            let cliff = ENSName.nextCliff(expiry: expiry)
            if row.title != title { row.title = title }
            if row.dueAt != cliff { row.dueAt = cliff }
            // The term's start, on the field built for exactly this shape — a
            // date stamped only when it is really known (see `Thing.grantedAt`).
            if let registered = facts?.registered, row.grantedAt != registered {
                row.grantedAt = registered
            }
            retag(row, stage: ENSName.stage(expiry: expiry))
        }

        // FIRST SIGHT IS SILENT. A name followed today whose expiry we have
        // never read is not news about a renewal — it is us catching up. The
        // Peer/Hyperliquid seeding rule: land the state, announce nothing.
        guard let previous else { return 0 }

        var added = 0
        // A RENEWAL is an expiry that moved later. Compared against the stored
        // reading rather than the row, because the row carries the next CLIFF
        // and a name crossing into grace moves that date without anybody
        // renewing anything.
        if let was = previous.expiry, let now = expiry, now > was.addingTimeInterval(60) {
            added += moment(
                ref: "ens:renewed:\(name):\(Int(now.timeIntervalSince1970))",
                name: name,
                title: String(localized: "\(name) was renewed — it expires \(ENSName.dateWord(now))"),
                tag: "Renewed", context: context)
        }
        // A name you were WAITING ON got taken. Never says by whom, and never
        // says it wasn't you: the registrar publishes the registration, not who
        // pressed the button in which app, and naming a stranger on that basis
        // would be a claim we can't support (§83).
        if previous.unregistered, let now = expiry {
            added += moment(
                ref: "ens:registered:\(name):\(Int(now.timeIntervalSince1970))",
                name: name,
                title: String(localized: "\(name) was registered — it expires \(ENSName.dateWord(now))"),
                tag: "Registered", context: context)
        }
        return added
    }

    @MainActor
    private static func moment(ref: String, name: String, title: String, tag: String,
                               context: ModelContext) -> Int {
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == ref }))) ?? 0
        guard existing == 0 else { return 0 }
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(title),
            content: "https://app.ens.domains/name/\(name)",
            source: ENSWatch.source,
            capturedAt: .now,
            tags: [tag],
            sourceRef: ref
        )
        thing.authorHandle = name
        context.insert(thing)
        SpotlightIndex.index([thing])
        return 1
    }

    /// Keeps exactly one stage tag on a follow row. Written as a replace rather
    /// than an append because a name walks the ladder — a row that gathered
    /// `Expiring` and then `Grace` and then `Released` would be filterable as
    /// all three at once, which is three wrong answers and one right one.
    @MainActor
    private static func retag(_ row: Thing, stage: ENSName.Stage) {
        let all = ["Expiring", "Grace", "Released", "Available"]
        var tags = row.tags.filter { !all.contains($0) }
        if let tag = ENSName.tag(for: stage) { tags.append(tag) }
        if row.tags != tags { row.tags = tags }
    }

    private static func encoded(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    }
}
