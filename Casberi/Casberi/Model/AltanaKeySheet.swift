import Foundation

/// THE CREDENTIAL SHEET (2026-08-18, prd §404) — what opening a key row shows.
///
/// Until this, an Altana row was a `.link` kind, so its sheet was the generic
/// one: a title, a timestamp and a door. That is exactly the situation §363
/// found for money — a category with real structure falling through
/// `ThingContent`'s `default:` branch — and the fix is the same shape: one
/// anatomy, assembled from stamped facts, never parsed back out of the title.
///
/// ## The window is the hero, and it is the one thing nothing else can draw
///
/// Every other deadline in this app knows one end. ENS knows when a name
/// expires and not when it was registered; `ASCRoom` knows a build dies in 90
/// days and had to gate its runway on "a transition this device watched",
/// because Apple publishes no start. The keystore publishes BOTH — `getKey`
/// carries the registration, `getExpiry` the expiry — so this sheet can draw a
/// real window with a real marker in it, dated at each end, on first sight and
/// on every device. That is why the window leads rather than the id.
///
/// ## What the sheet ASKS that the row cannot
///
/// A row records the EVENT of a key existing. Only a fresh read says whether
/// it is still true, which is `WalletPrepare`'s ruling for approvals (§112)
/// applied to credentials: one `isValidKey` on open, settling in after the
/// sheet mounts. A revoked key then says so plainly instead of sitting there
/// looking live.
///
/// ## Three readings the registry gives away for free
///
/// - **The signature count.** The nonce was always read and always collapsed
///   to a Bool. "Signed 47 times" and "registered 62 days ago, never used" are
///   different credentials, and only the number can tell them apart.
/// - **The curve.** Testing the public key against two curve equations names
///   it in a word a person already has — a wallet key or a passkey (§404).
/// - **"Also signs for."** A key id derives from its public key, so the SAME
///   credential registered on several watched wallets is detectable by plain
///   id equality. One passkey controlling three accounts is a single point of
///   failure, and no surface anywhere shows it — Altana's own explorer is
///   account-scoped. Factual only, no inference (`AddressConnections`' rule).
///
/// Foundation-only so the harness compiles it as shipped.
enum AltanaKeySheet {

    /// What a live re-check found. `checking` is the mounted state, so the
    /// sheet never claims a status it has not yet asked for.
    /// What the registry says about this key RIGHT NOW.
    ///
    /// `seeded` is the demo's state and exists for one reason: the demo
    /// reaches nothing (`AltanaKeystore.liveState` returns early), so saying
    /// "checked just now" there would claim an action that did not happen —
    /// §83 in miniature, inside the one experience someone judges the app by.
    /// The seeded keys really are active, so the state is true; only the
    /// clause about having just checked is dropped.
    enum LiveState: Equatable { case checking, active, seeded, revoked, unreadable }

    struct Model: Equatable {
        let keyID: String
        /// The wallet this key signs for, lowercased hex.
        let address: String
        let isRoot: Bool
        let registeredAt: Date?
        let expiry: Date?
        let signatureCount: Int
        let chainLabel: String?
        let curve: AltanaKeystore.Curve
        /// OTHER watched wallets this same key id is registered on.
        let alsoSignsFor: [String]
        var live: LiveState = .checking

        var expired: Bool {
            guard let expiry else { return false }
            return expiry <= Date.now
        }
    }

    /// `altana:key:<chain-slug>:<address>:<keyid>` → its parts.
    ///
    /// Refuses anything else rather than guessing — an event row
    /// (`altana:event:…`) is not a credential and must not open this sheet.
    static func parse(ref: String) -> (address: String, keyID: String)? {
        let parts = ref.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5, parts[0] == "altana", parts[1] == "key" else { return nil }
        guard AltanaKeystore.normalizedAddressBody(parts[3]) != nil,
              AltanaKeystore.normalizedKeyIDBody(parts[4]) != nil else { return nil }
        return (parts[3].lowercased(), parts[4].lowercased())
    }

    /// The sheet's model, composed from the snapshot the sweep already wrote.
    ///
    /// nil when the ref does not name a credential, or when the key is no
    /// longer in the snapshot at all — which happens after a revocation, and
    /// is correct: the row stays in the corpus as a record, and the sheet
    /// falls back to the generic one rather than drawing a window for a
    /// credential that no longer exists.
    static func compose(ref: String, readings: [AltanaKeystore.Reading]) -> Model? {
        guard let (address, keyID) = parse(ref: ref) else { return nil }
        // Compare NORMALIZED bodies, never the raw strings. A ref carries
        // whatever `AltanaKeystore.ref` was handed, and a stored key id is
        // 0x-prefixed — so a raw comparison matches only while both sides
        // happen to agree about the prefix, and fails silently (an empty
        // sheet, no error) the moment one of them doesn't.
        let wantKey = AltanaKeystore.normalizedKeyIDBody(keyID)
        let wantAddr = AltanaKeystore.normalizedAddressBody(address)
        func sameKey(_ id: String) -> Bool { AltanaKeystore.normalizedKeyIDBody(id) == wantKey }
        func sameAddr(_ a: String) -> Bool { AltanaKeystore.normalizedAddressBody(a) == wantAddr }

        guard let reading = readings.first(where: { sameAddr($0.address) }),
              let key = reading.keys.first(where: { sameKey($0.id) })
        else { return nil }

        let others = readings
            .filter { !sameAddr($0.address) }
            .filter { $0.keys.contains { sameKey($0.id) } }
            .map { $0.address.lowercased() }
            .sorted()

        return Model(keyID: keyID, address: address, isRoot: key.isRoot,
                     registeredAt: key.registeredAt, expiry: key.expiry,
                     signatureCount: key.signatureCount,
                     chainLabel: key.chainLabel, curve: key.curve,
                     alsoSignsFor: others)
    }

    // MARK: - Copy

    /// The heading. A grant DURATION when both ends are known ("24-hour key"),
    /// because that is the most concrete thing we can call it; otherwise the
    /// role, which is always true.
    static func title(_ m: Model) -> String {
        if !m.isRoot, let registered = m.registeredAt, let expiry = m.expiry,
           expiry > registered,
           let phrase = AltanaRoom.grantPhrase(seconds: expiry.timeIntervalSince(registered)) {
            return phrase
        }
        return m.isRoot ? String(localized: "Root key") : String(localized: "Session key")
    }

    /// Curve · chain — and deliberately NOT the role (§406). The title always
    /// carries it: "Root key" and "Session key" say it outright, and a grant
    /// phrase ("30-day key") implies a session by definition, so the old
    /// "Session key · Passkey · BNB Smart Chain" said the role twice on two
    /// adjacent lines. Empty when neither half could be read; the view skips
    /// an empty line rather than reserving one.
    static func subtitle(_ m: Model) -> String {
        var parts: [String] = []
        if let curve = m.curve.label { parts.append(curve) }
        if let chain = m.chainLabel { parts.append(chain) }
        return parts.joined(separator: " · ")
    }

    /// What the live check says, in the sheet's own voice.
    static func liveLine(_ m: Model) -> String {
        switch m.live {
        case .checking:   String(localized: "Checking with the registry…")
        case .active:     String(localized: "Still active — checked just now")
        case .seeded:     String(localized: "Active")
        case .revoked:    String(localized: "Revoked — this key can no longer sign")
        case .unreadable: String(localized: "Couldn’t reach the registry just now")
        }
    }

    /// The registration, as its own fact row — ONLY when the grant window is
    /// not drawn (§407a). A session's window already states "Granted Aug 14",
    /// so repeating it here would be §406's duplicate; a ROOT draws no window,
    /// and with the card's rows retired this line is the one place its date
    /// survives. nil too when the date was never witnessed — "registered
    /// today" must never stand in for "we don't know".
    static func registeredLine(_ m: Model) -> String? {
        let windowDrawn = m.registeredAt != nil && m.expiry != nil
        guard !windowDrawn, let registered = m.registeredAt else { return nil }
        return registered.formatted(date: .abbreviated, time: .omitted)
    }

    /// The usage reading. Never "0 times" — a credential that has never signed
    /// deserves the sentence that says so, and the age is the part that makes
    /// it worth noticing.
    static func usageLine(_ m: Model, now: Date = .now) -> String {
        guard m.signatureCount > 0 else {
            // The age rides along ONLY when the grant window above is not
            // drawn (§406): with the window there, "Registered 4 days ago"
            // duplicated the Granted date sitting two rows up. A root key has
            // no window, so its age still lives here — the one place it shows.
            let windowDrawn = m.registeredAt != nil && m.expiry != nil
            guard !windowDrawn else { return String(localized: "Never used") }
            guard let registered = m.registeredAt else {
                return String(localized: "Has never signed")
            }
            let days = max(0, Int(now.timeIntervalSince(registered) / 86_400))
            return days == 0
                ? String(localized: "Registered today, never used")
                : String(localized: "Registered \(days) days ago, never used")
        }
        return m.signatureCount == 1
            ? String(localized: "Signed once")
            : String(localized: "Signed \(m.signatureCount) times")
    }

    /// "14 hours in · 10 hours left", or nil when either end is unknown.
    ///
    /// Elapsed AND remaining, never a percentage: a percentage of a grant
    /// nobody chose the length of means nothing, while "10 hours left" is the
    /// thing somebody would act on.
    static func windowLine(_ m: Model, now: Date = .now) -> String? {
        guard let registered = m.registeredAt, let expiry = m.expiry, expiry > registered
        else { return nil }
        if expiry <= now { return String(localized: "Expired") }
        return String(localized: "\(span(now.timeIntervalSince(registered))) in · \(span(expiry.timeIntervalSince(now))) left")
    }

    /// A rough human span — the biggest unit that is still true.
    static func span(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s >= 86_400 { let d = Int(s / 86_400); return d == 1 ? String(localized: "1 day") : String(localized: "\(d) days") }
        if s >= 3_600 { let h = Int(s / 3_600); return h == 1 ? String(localized: "1 hour") : String(localized: "\(h) hours") }
        let m = Int(s / 60)
        return m == 1 ? String(localized: "1 minute") : String(localized: "\(m) minutes")
    }

    /// 0…1 through the grant, for the window's marker. nil when unknowable.
    static func progress(_ m: Model, now: Date = .now) -> Double? {
        guard let registered = m.registeredAt, let expiry = m.expiry else { return nil }
        let total = expiry.timeIntervalSince(registered)
        guard total > 0 else { return nil }
        return min(1, max(0, now.timeIntervalSince(registered) / total))
    }

    /// The tidy-up sentence, shown only for a key that is past its expiry and
    /// still listed. Stated as a fact, never as a warning — an expired key is
    /// safe, it is just untidy.
    static func tidyNote(_ m: Model) -> String? {
        guard m.expired else { return nil }
        return String(localized: "The registry still lists it. An expired key can’t act, but it stays in your key list until it’s removed on Altana.")
    }

    /// The scope ceiling — said on every session key, because a sheet that
    /// showed a deadline and nothing else would imply we knew what the key
    /// could do. A root key's authority is not scoped, so it says nothing.
    static func scopeCeiling(_ m: Model) -> String? {
        m.isRoot ? nil
                 : String(localized: "Only a key’s deadline is published, never its scope.")
    }
}
