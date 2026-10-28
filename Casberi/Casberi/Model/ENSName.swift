import Foundation

/// A followed ENS name and the ladder it walks (2026-08-29, prd §534).
///
/// `ENSExpiry` has read expiry since 2026-07-21, for names the wallet already
/// SEES — a watched address typed as a name, or the primary name an address
/// reverse-resolves to. There has never been a way to follow a name you do not
/// own: a friend's, a brand's, or the one you are waiting on. That act is what
/// earns ENS a catalog seat at all (prd §515a: a protocol the wallet reads on
/// its own must never also ship as an offer), so the seat is the FOLLOW, and
/// this file is the part of it that can be proven.
///
/// Foundation-only by design, so `scripts/ens-selftest.sh` compiles it WHOLE
/// and unmodified. Nothing here fetches; every function is a pure read of a
/// name, a date, or a payload somebody else fetched.
///
/// **THE LADDER IS THE FEATURE.** Every other deadline in this app knows one
/// moment. A `.eth` name knows four, and the third and fourth are the ones no
/// wallet tells you about:
///
///   1. it expires;
///   2. for `graceDays` after that it is in GRACE: nobody else can register
///      it, and it can still be renewed — so a just-lapsed name is the most
///      actionable state there is, not the least. **Renewing is
///      PERMISSIONLESS** (measured 2026-08-31 by reading the deployed
///      controller: `renew` has no owner check at all), so the restriction in
///      this window is on RE-REGISTRATION, not on renewal. Saying "only the
///      owner can renew" — which this file did until §540 — is wrong, and
///      wrong in the direction that talks somebody out of an act they could
///      have taken;
///   3. at grace end it is RELEASED and anyone may register it, for
///      `premiumDays` at a decaying premium;
///   4. after that it is an ordinary name at an ordinary price.
///
/// A row therefore carries the NEXT cliff as its `dueAt` rather than the expiry
/// forever — which is what `ENSExpiry` did, leaving a lapsed name sitting
/// ninety days overdue against a date that had stopped being the question. The
/// generic `deadlineNear` notification path reads `dueAt` and nothing else, so
/// stepping it is also what makes the lock screen fire at the right moments
/// with no notification code of this seat's own (the `ENSExpiry`/Altana shape).
enum ENSName {

    // MARK: - The ladder's constants

    /// The grace period after a name's expiry, in which nobody else can
    /// register it and anyone can still renew it — which depends on whether
    /// its owner has moved it to ENSv2 (prd §1585, MEASURED 2026-10-28).
    ///
    /// **An unmigrated name keeps v1's 90 days from its v1 expiry.**
    /// `ETHRenewerV1.GRACE_PERIOD` answers 90 days and a second, counted from
    /// the v1 date, and ENS's own Explorer shows that date as "Expires"
    /// (vitalik.eth: Jan 30, 2048). **A migrated name gets 28 days from its
    /// ENSv2 expiry** (`ETHRegistrar.GRACE_PERIOD`). ENSv2 set every v2 expiry
    /// to the v1 one plus `migrationBonus`, so both end grace on the same day
    /// (62 + 28 = 90); what differs is the date a name stops working, and the
    /// metadata service reports the ENSv2 one for both (see `facts`).
    static let unmigratedGraceDays = 90
    static let migratedGraceDays = 28

    static func graceDays(migrated: Bool) -> Int {
        migrated ? migratedGraceDays : unmigratedGraceDays
    }

    /// What ENSv2's activation added to every v1 name's expiry: exactly 62
    /// days, measured on vitalik.eth, nick.eth, casberi.eth and
    /// accountless.eth (v2 expiry minus `BaseRegistrar.nameExpires`).
    static let migrationBonus: TimeInterval = 62 * 86_400

    /// Whether an expiry that moved from `was` to `now` moved by ENSv2's
    /// bonus rather than by anybody renewing. A migrated name's reading
    /// stored before the activation comes back exactly 62 days later on its
    /// next read, and calling that a renewal lands "was renewed" on it. A
    /// real renewal is bought in whole 365-day years, so it never lands on 62
    /// days to the minute.
    static func isMigrationBonus(from was: Date, to now: Date) -> Bool {
        abs(now.timeIntervalSince(was) - migrationBonus) < 60
    }

    /// The days ENSv2 re-stamped every name's "Registration Date" and
    /// "Created Date" with the moment it was copied into the new registry
    /// (2026-10-03 to 10-04 on every name sampled 2026-10-28, vitalik.eth's
    /// 2017 registration included). A date inside this window is that copy,
    /// not a term's start, so it is dropped: no window beats one that begins
    /// in October 2026 for a name held since 2017.
    static let reservationWindow = Date(timeIntervalSince1970: 1_790_812_800)   // 2026-10-01
        ..< Date(timeIntervalSince1970: 1_793_059_200)                           // 2026-10-27, activation

    static func isReservationStamp(_ date: Date) -> Bool { reservationWindow.contains(date) }

    /// After release a temporary premium decays to nothing over three weeks.
    /// DOC-DERIVED, never measured here: this project can't make a name lapse,
    /// so nothing on this host can watch a premium decay. It is used only to
    /// decide which SENTENCE a released name wears — never to quote a price,
    /// which would be a number people believe (§83) about a market nobody here
    /// can read.
    static let premiumDays = 21

    /// How near an expiry has to be before a row starts saying so. Without a
    /// horizon every followed name would wear a deadline in 2048 and the
    /// "Coming up" lane would sort on it forever — a deadline is news when it
    /// is near and noise when it isn't (`ENSExpiry`'s own ruling, kept).
    static let horizonDays = 90

    // MARK: - Reading what somebody typed

    /// The `ens:name:` ref a followed name lands under. Built here and never
    /// spelled by hand anywhere else — a prefix re-typed beside its builder is
    /// where the producer and the consumer start disagreeing (prd §311, and
    /// `ref-shape-audit.py` exists because of it).
    static func ref(for name: String) -> String { "ens:name:\(name)" }

    static let refPrefix = "ens:name:"

    /// The name behind a followed row's ref, or nil for any other row.
    static func name(fromRef ref: String) -> String? {
        guard ref.hasPrefix(refPrefix) else { return nil }
        let name = String(ref.dropFirst(refPrefix.count))
        return name.isEmpty ? nil : name
    }

    /// What `ENSExpiry` lands under, so a name found from a watched wallet can
    /// be ADOPTED by the seat rather than landing a second row about the same
    /// name in a second room. One name, one row — the whole reason the two
    /// halves have to know each other's spelling.
    static let walletRefPrefix = "wallet:ensexpiry:"

    static func walletRef(for name: String) -> String { "\(walletRefPrefix)\(name)" }

    /// A typed name, normalized — or nil when it is not a name this seat can
    /// stand behind.
    ///
    /// Accepts a bare label (`vitalik` → `vitalik.eth`), because the field asks
    /// for a name and typing the suffix is a chore; and an `app.ens.domains`
    /// link, because a name arrives pasted at least as often as it arrives
    /// typed. Both resolve to the same normalized form, so the ref cannot
    /// depend on how somebody happened to write it.
    ///
    /// **`.eth`, second level, and nothing else — each refusal is a fact, not
    /// fussiness.** A DNS-imported name (`.com`, `.xyz`) expires with its DNS
    /// registration, somewhere no ENS read can see, so a countdown on one would
    /// be invented. A subname (`sub.vitalik.eth`) has no registrar record of
    /// its own — its lifetime is its parent's to manage — and the metadata
    /// service answers 404 for one (measured 2026-08-29), which is
    /// indistinguishable from a name nobody has registered. Refusing at the
    /// field is the honest place: the alternative is a followed row that can
    /// never say anything.
    static func normalized(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }

        // A PASTED LINK, in either of ENS's two forms. MEASURED 2026-08-31:
        // `app.ens.domains/vitalik.eth` answers 200 and is the canonical form
        // today, while the older `app.ens.domains/name/vitalik.eth` answers a
        // 301 to it — so both are in circulation and both must resolve to the
        // same name here, or the ref would depend on the age of the link
        // somebody happened to copy.
        //
        // **Only ENS's OWN host, and that is the security half.** Taking the
        // last path component of any URL would accept
        // `evil.example/vitalik.eth` as a name — harmless in itself, but it
        // teaches the field to read strangers' URLs, and this seat's whole job
        // is telling somebody a name is safe to care about.
        if s.contains("/") {
            var rest = s
            for scheme in ["https://", "http://"] where rest.hasPrefix(scheme) {
                rest = String(rest.dropFirst(scheme.count))
            }
            var parts = rest.split(separator: "/", omittingEmptySubsequences: true)
            guard let host = parts.first,
                  host == "app.ens.domains" || host == "ens.domains"
            else { return nil }
            parts.removeFirst()
            // `/name/<name>` and `/<name>` both end at the name; anything
            // deeper (`/vitalik.eth/details`) names a page, not a name, and
            // its first component is still the name.
            if parts.first == "name" { parts.removeFirst() }
            guard let first = parts.first else { return nil }
            s = String(first.split(separator: "?").first ?? "")
        }
        guard !s.isEmpty else { return nil }

        // Nothing that would make the name something other than one label.
        // The name is percent-encoded before it reaches a URL, so this is not
        // the encoder's job it is doing — it is refusing input that is not a
        // name at all (the §519 GitHub rule: a login is validated because it is
        // interpolated into a path, and `/` or `..` reaching one addresses an
        // endpoint nobody asked for).
        guard !s.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "\\" || $0 == "@" || $0 == "#" }),
              !s.contains("..") else { return nil }

        if !s.contains(".") { s += ".eth" }
        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 2, labels[1] == "eth", !labels[0].isEmpty else { return nil }
        return s
    }

    /// The registrar label — everything before `.eth`. What an on-chain
    /// `nameExpires(labelhash)` read would hash, and what the room shows when
    /// a name is the row's subject rather than its title.
    static func label(of name: String) -> String? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1] == "eth", !parts[0].isEmpty else { return nil }
        return String(parts[0])
    }

    /// The `.eth` BaseRegistrar — the NFT contract the metadata service keys
    /// on. Since ENSv2's activation (2026-10-27) it is owned by `ETHRenewerV1`
    /// and still holds every unmigrated name's expiry.
    static let baseRegistrar = "0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85"

    /// The registrar's token id for a name: `keccak256(label)` as 0x-hex.
    ///
    /// **THE METADATA SERVICE STOPPED TAKING NAMES (measured 2026-10-27, the
    /// day ENSv2 activated).** `…/<registrar>/vitalik.eth` answers 400
    /// "Invalid token id" for every name; the labelhash answers 200 with the
    /// same "Expiration Date", and an unregistered labelhash still answers
    /// 404. A name-keyed read failed SILENTLY — no row ever got a date.
    static func labelhash(of name: String) -> String? {
        guard let label = label(of: name) else { return nil }
        return "0x" + Keccak256.hexString(Keccak256.hash(Array(label.utf8)))
    }

    /// The metadata service's page for a `.eth` name, keyed by labelhash.
    static func metadataURL(for name: String) -> String? {
        labelhash(of: name).map { "https://metadata.ens.domains/mainnet/\(baseRegistrar)/\($0)" }
    }

    // MARK: - The ladder

    enum Stage: String {
        /// Registered, and its expiry is further out than the horizon.
        case active
        /// Registered, expiring inside the horizon.
        case expiring
        /// Lapsed, inside the grace period — protected from re-registration,
        /// and still renewable by anyone (§540).
        case grace
        /// Released, inside the premium window — anyone can register it.
        case premium
        /// Released, at ordinary price.
        case released
        /// No registration at all: nobody holds it.
        case unregistered
    }

    /// Where a name stands. `expiry` nil means the registrar has no record —
    /// which this seat only ever concludes from an explicit 404, never from a
    /// read that failed (a service hiccup reported as "nobody owns this" is the
    /// most expensive wrong answer this file could give).
    ///
    /// `migrated` picks the grace period (`graceDays(migrated:)`). Every caller
    /// with a reading passes `reading.migrated`; the default is the unmigrated
    /// case, which is most names and every reading stored before ENSv2.
    static func stage(expiry: Date?, migrated: Bool = false, now: Date = .now) -> Stage {
        guard let expiry else { return .unregistered }
        if now < expiry {
            guard let horizon = date(byAddingDays: horizonDays, to: now) else { return .active }
            return expiry <= horizon ? .expiring : .active
        }
        guard let graceEnd = graceEnd(expiry: expiry, migrated: migrated) else { return .grace }
        if now < graceEnd { return .grace }
        guard let premiumEnd = date(byAddingDays: premiumDays, to: graceEnd) else { return .released }
        return now < premiumEnd ? .premium : .released
    }

    /// When the grace period ends — the moment the name stops being protected
    /// and anyone can register it.
    static func graceEnd(expiry: Date, migrated: Bool = false) -> Date? {
        date(byAddingDays: graceDays(migrated: migrated), to: expiry)
    }

    /// When the premium decays away.
    static func premiumEnd(expiry: Date, migrated: Bool = false) -> Date? {
        graceEnd(expiry: expiry, migrated: migrated).flatMap { date(byAddingDays: premiumDays, to: $0) }
    }

    /// The next moment this name's standing CHANGES — what a row carries as
    /// its `dueAt`, and therefore what the generic deadline notification and
    /// the "Coming up" lane both sort on.
    ///
    /// nil once there is nothing ahead: a released name at ordinary price, and
    /// a name nobody has registered, both have no next moment. Returning a
    /// stale date there would keep a row in a deadline lane forever about
    /// something that has finished happening.
    static func nextCliff(expiry: Date?, migrated: Bool = false, now: Date = .now) -> Date? {
        guard let expiry else { return nil }
        switch stage(expiry: expiry, migrated: migrated, now: now) {
        case .active, .expiring: return expiry
        case .grace:            return graceEnd(expiry: expiry, migrated: migrated)
        case .premium:          return premiumEnd(expiry: expiry, migrated: migrated)
        case .released, .unregistered: return nil
        }
    }

    // MARK: - Words

    /// The row's title. No "in N days" anywhere in it, for `ENSExpiry`'s own
    /// recorded reason: a stored title starts lying the next morning.
    ///
    /// The tense follows the stage rather than the date, and that distinction
    /// is the whole of `grace` — a name inside its grace period has already
    /// lapsed, it just hasn't been released yet, so "expires" would be the
    /// present tense about something that already happened.
    static func title(name: String, expiry: Date?, migrated: Bool = false, now: Date = .now) -> String {
        switch stage(expiry: expiry, migrated: migrated, now: now) {
        case .unregistered:
            return String(localized: "\(name) — nobody has registered it")
        case .active, .expiring:
            guard let expiry else { return name }
            return String(localized: "\(name) expires \(dateWord(expiry, from: now))")
        case .grace:
            guard let expiry, let end = graceEnd(expiry: expiry, migrated: migrated) else { return name }
            return String(localized: "\(name) expired \(dateWord(expiry, from: now)) — it can still be renewed until \(dateWord(end, from: now))")
        case .premium:
            guard let expiry, let end = graceEnd(expiry: expiry, migrated: migrated) else { return name }
            return String(localized: "\(name) was released \(dateWord(end, from: now)) — anyone can register it")
        case .released:
            return String(localized: "\(name) is free to register")
        }
    }

    /// "Mar 4" for a date inside a year of now, "Mar 2048" beyond it. A
    /// day-and-month alone is ambiguous at ENS's timescales — plenty of names
    /// are registered for decades, and "expires Mar 4" about 2048 reads as
    /// next week.
    static func dateWord(_ date: Date, from now: Date = .now) -> String {
        let year: TimeInterval = 365 * 24 * 60 * 60
        if abs(date.timeIntervalSince(now)) < year {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }

    /// The tag a followed row wears beside `Watchlist` — the stage as one
    /// word, so `Retriever`'s facet filter can narrow "expiring names" without
    /// any reader parsing a title back out (prd §363's rule, one category over).
    static func tag(for stage: Stage) -> String? {
        switch stage {
        case .active:       return nil        // the ordinary state names nothing
        case .expiring:     return "Expiring"
        case .grace:        return "Grace"
        case .premium, .released: return "Released"
        case .unregistered: return "Available"
        }
    }

    // MARK: - What the metadata service says

    /// The facts ENS's own metadata service carries for a name. MEASURED
    /// 2026-08-29 against `vitalik.eth`, `nick.eth` and `casberi.eth`: every
    /// one of these fields was on the wire, and an unregistered name and a
    /// subname both answer **404 with `{"message":"No results found."}`**.
    ///
    /// `Registration Date` is the one worth calling out. prd §404 states, as
    /// the reason the Altana key card is special, that "ENS knows when a name
    /// expires and not when it was registered" — that is now measurably false,
    /// so a followed name can draw a real window with both ends and a marker
    /// where now sits, which is what §534's second goal spends it on.
    struct Facts: Equatable {
        let name: String
        /// Epoch milliseconds on the wire (`ENSExpiry` measured this; reading
        /// it as seconds puts every expiry in 1970 and makes every name
        /// permanently, silently overdue).
        ///
        /// The date the name STOPS WORKING, which for an unmigrated name is
        /// not the date on the wire (prd §1585): the service reports the
        /// ENSv2 expiry, its v1 date plus `migrationBonus`, and the v1 date is
        /// the one ENS's own Explorer and app show.
        let expiry: Date?
        /// "Migration Status" is `migrated`: the owner moved the name to
        /// ENSv2, so its expiry is the ENSv2 one and its grace 28 days.
        let migrated: Bool
        /// When the CURRENT term began — not when the name first existed.
        let registered: Date?
        /// When the name was first created, which for a long-held name is
        /// years before its current term.
        let created: Date?
        /// ENSIP-15 normalization. `false` means the name contains characters
        /// that do not normalize — i.e. it is a LOOKALIKE of some other name,
        /// which is `AddressSafety`'s concern arriving as a name instead of an
        /// address.
        let isNormalized: Bool
    }

    /// Parses the metadata payload. Pure, so the harness can hold a real
    /// captured response and assert against it.
    ///
    /// A missing attribute yields nil for that field rather than a default —
    /// an absent expiry must never read as an expiry of zero, which `stage`
    /// would place in 1970 and call released.
    static func facts(name: String, json: Any?) -> Facts? {
        guard let root = json as? [String: Any] else { return nil }
        // The service echoes the name it answered for. Trust OURS: the request
        // is built from the normalized form, and taking the payload's spelling
        // would let a service-side alias re-key a row we have already landed.
        let attributes = (root["attributes"] as? [[String: Any]]) ?? []
        func date(_ trait: String) -> Date? {
            for attribute in attributes where attribute["trait_type"] as? String == trait {
                if let ms = attribute["value"] as? Double, ms > 0 {
                    return Date(timeIntervalSince1970: ms / 1000)
                }
            }
            return nil
        }
        // Only an explicit "unmigrated" moves the date back. A payload without
        // the attribute predates ENSv2, when the wire's date was the v1 one.
        let status = attributes.first { $0["trait_type"] as? String == "Migration Status" }?["value"] as? String
        let wire = date("Expiration Date")
        return Facts(name: name,
                     expiry: status == "unmigrated" ? wire?.addingTimeInterval(-migrationBonus) : wire,
                     migrated: status == "migrated",
                     registered: date("Registration Date").flatMap { isReservationStamp($0) ? nil : $0 },
                     created: date("Created Date").flatMap { isReservationStamp($0) ? nil : $0 },
                     // Absent reads as normalized: the service states the flag
                     // for every name it knows, so a missing key is a payload
                     // we don't understand, and warning about a lookalike on
                     // that basis would cry wolf on every name at once.
                     isNormalized: (root["is_normalized"] as? Bool) ?? true)
    }

    // MARK: - Private

    private static func date(byAddingDays days: Int, to date: Date) -> Date? {
        Calendar.current.date(byAdding: .day, value: days, to: date)
    }
}
