import Foundation
import SwiftData
import CryptoKit

/// App Store Connect (2026-08-06, prd §323) — what Apple did to your app,
/// beside what Stripe did to your money and what Sentry did to your crashes.
///
/// This is the seat for the half of shipping that happens on somebody else's
/// desk. You upload a build and then you WAIT: for processing, for a reviewer,
/// for a verdict. None of that waiting has a home — App Store Connect emails
/// some of it, buries the rest behind a login, and tells you nothing at all
/// when a TestFlight build is three days from expiring. Four things land here,
/// and each one is a moment somebody else decided:
///
///   1. **A review verdict.** The flagship, and the row this bridge exists
///      for: a version moving to Rejected, to Approved, to live on the store.
///      The verdict LEADS the title (see `ASCShape.versionTitle`).
///   2. **A customer review.** Real words a real person wrote about your app —
///      the most thing-shaped object App Store Connect has, and the one you
///      would keep even if nothing else here landed.
///   3. **A build finishing processing.** VALID or INVALID. You know you
///      uploaded it; you do not know when Apple finished with it, and INVALID
///      is a wasted afternoon if nobody tells you.
///   4. **A TestFlight build about to expire.** 90 days after upload a build
///      simply stops working for your testers, with no warning anywhere. It
///      lands as a reconciling `dueAt` (the ENSExpiry/Cloudflare shape), so
///      every "what's next" surface in the app already carries it.
///
/// ## What deliberately does NOT land
///
/// Downloads, impressions, units, proceeds, conversion rate, crash counts. All
/// tallies, all forbidden by the module doctrine (§216) for the reason PostHog
/// taught: a number that moves every day is a STATE, and a state updates in
/// place or it buries the feed. Sales and Analytics are also deferred for a
/// second, practical reason — the Sales Reports API answers with a gzipped TSV
/// keyed by a vendor number and lands a day late, and the Analytics API is a
/// request-then-poll job. Neither is a GET that returns news, and both deserve
/// their own pass once this one has been measured.
///
/// A version moving to WAITING_FOR_REVIEW does not land either, nor one you
/// rejected yourself: those are YOUR acts, and you were standing there. The
/// same test that keeps an Apple Wallet charge quiet (§313 — your bank already
/// told you) keeps your own submit quiet here.
///
/// ## Read-only is by CONDUCT, and this is the weakest grade in the catalog
///
/// App Store Connect keys carry a ROLE, not scopes, and **no role is read-only
/// for what this reads.** The narrowest role that can see apps, versions,
/// builds and reviews is Developer — and a Developer key can also upload a
/// build and submit a version. There is no box to tick that would stop it. So
/// this sits below Cursor's tier, which is itself below Privacy.com's: a
/// Cursor key can spend money and write a branch; this one can ship software
/// to the public under your name.
///
/// The promise is therefore kept the only way it can be — by conduct. Every
/// request in this file is a `GET` through `IngestSupport`'s funnel. There is
/// no code here that creates, submits, releases, rejects, removes, replies to
/// a review, or uploads anything. `TokenBridge.canLine` and the catalog copy
/// say so in those words, and **`scripts/appstoreconnect-selftest.sh` fails
/// the build if a write verb ever appears in this file** — because prose is
/// what CLAUDE.md calls memory, and memory lost.
///
/// ## UNMEASURED (2026-08-06)
///
/// No App Store Connect key has ever been given to this app, and the build
/// host has no egress to `api.appstoreconnect.apple.com`. Every field map here
/// comes from Apple's published API reference, not from a live call. Every
/// read is a GET whose failure path returns nil, and every endpoint is read
/// INDEPENDENTLY — a role that can't see reviews 403s that one call and lands
/// versions and builds regardless — so it fails safe and it fails narrowly.
/// Run `-ascProbe YES` against a real key and reconcile what it dumps before
/// trusting any of it. This project already holds such a key (`asc-p8` in the
/// login Keychain, used by `scripts/testflight.sh`), which makes this the
/// first keyed Work bridge here that CAN be measured before it is trusted.
enum ASCAuth {

    /// The private key — an Apple `.p8`, normalized to PEM. This is the slot
    /// `TokenBridge.connected` reads, because it is the one credential whose
    /// presence means anything: a key id with no key is a label.
    static var keyVaultKey: String { TokenBridge.appStoreConnect.tokenKey }

    /// The key ID (10 characters, printed beside the key in App Store
    /// Connect). Not a secret, and stored in the Keychain anyway for Trello's
    /// reason — it is useless apart from the key it names, so it lives beside
    /// it rather than in cleartext UserDefaults.
    static let keyIDVaultKey = "asc.keyid"

    /// The Issuer ID (a UUID). **Empty means an INDIVIDUAL key**, which is not
    /// a fallback but Apple's own discriminator: its token spec says `iss` is
    /// "not used with individual keys" and `sub` is "not used with team keys".
    /// So the presence of an issuer id is exactly what decides which of the
    /// two payloads gets signed — see `ASCJWT.payloadJSON`.
    static let issuerVaultKey = "asc.issuer"

    static var storedKey: String? { TokenVault.get(keyVaultKey) }
    static var storedKeyID: String { TokenVault.get(keyIDVaultKey) ?? "" }
    static var storedIssuer: String { TokenVault.get(issuerVaultKey) ?? "" }

    /// Connected means a key AND the id that names it. `TokenBridge.connected`
    /// only sees the first, so every seat/pass check goes through this: a key
    /// with no id mints a JWT Apple refuses, and a bridge that reads
    /// "connected" while every request 401s is the fake status §83 bans.
    static var configured: Bool {
        storedKey != nil && !storedKeyID.isEmpty
    }

    static func setKeyID(_ id: String) { TokenVault.set(id, for: keyIDVaultKey) }
    static func setIssuer(_ id: String) { TokenVault.set(id, for: issuerVaultKey) }

    /// Drops everything this bridge holds that is not a `Thing` — both
    /// identifiers, the cached token, and every ledger. Called from
    /// `TokenBridge.onRemove` on BOTH callers (unlike Trello's key, which a
    /// re-paste depends on): here a fresh key may name a different Apple
    /// account entirely, and diffing a new account's versions against the old
    /// account's ledger would announce a stranger's rejection as yours.
    static func clear() {
        TokenVault.delete(keyIDVaultKey)
        TokenVault.delete(issuerVaultKey)
        cached = nil
        ASCState.clear()
    }

    // MARK: - The token

    /// The signed JWT, minted at most once per pass and never persisted.
    ///
    /// Apple caps these at twenty minutes and rejects anything longer, so the
    /// lifetime is fifteen — inside the cap with room for a clock this device
    /// and Apple's disagree about, which is a real thing on a phone that has
    /// just come back from airplane mode.
    private static let lifetime: TimeInterval = 15 * 60
    /// Re-mint this long before expiry rather than at it: a pass can run for
    /// several seconds, and a token that expires between the first request and
    /// the fourth would 401 halfway through and read as a refused key.
    private static let renewBefore: TimeInterval = 120

    private static var cached: (token: String, expires: Date)?

    /// Why a token could not be minted. Four causes, four sentences — the
    /// `StripeFetch.validate` rule: collapsing them into "couldn't connect"
    /// leaves the three RECOVERABLE ones looking like a typo, and the fix for
    /// each is different.
    enum MintFailure: Error, Equatable {
        case noKey
        case noKeyID
        /// The pasted text isn't a P-256 private key at all — a `.cer`, a
        /// truncated copy, or the wrong file from the same download.
        case unreadableKey
    }

    /// A bearer token for this pass, or the reason there isn't one.
    ///
    /// Not `async`: signing is a single P-256 operation on ~100 bytes, which
    /// is microseconds. Making it async would put a suspension point in front
    /// of every request for nothing.
    static func token(now: Date = .now) -> Result<String, MintFailure> {
        if let cached, cached.expires.timeIntervalSince(now) > renewBefore {
            return .success(cached.token)
        }
        guard let pem = storedKey else { return .failure(.noKey) }
        let keyID = storedKeyID
        guard !keyID.isEmpty else { return .failure(.noKeyID) }
        guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
            return .failure(.unreadableKey)
        }
        let expires = now.addingTimeInterval(lifetime)
        let input = ASCJWT.signingInput(keyID: keyID, issuerID: storedIssuer,
                                        issuedAt: now, expires: expires)
        // `rawRepresentation` is r‖s, 64 bytes — which is exactly what JWS
        // ES256 specifies. The DER form (`derRepresentation`) is what most
        // crypto libraries hand back by default and it is NOT interchangeable
        // here: Apple would reject every token, with a 401 indistinguishable
        // from a wrong key.
        guard let signature = try? key.signature(for: Data(input.utf8)) else {
            return .failure(.unreadableKey)
        }
        let token = "\(input).\(ASCJWT.base64url(signature.rawRepresentation))"
        cached = (token, expires)
        return .success(token)
    }

    static func header(_ token: String) -> String { "Bearer \(token)" }

    /// Forget the cached token without touching the stored key — for a paste
    /// that replaces the credentials mid-session, where the old token would
    /// otherwise keep working for up to fifteen minutes and hide a bad paste.
    static func forgetToken() { cached = nil }
}

// MARK: - The JWT, minus the signing

/// The parts of the token that are pure Foundation, split from `ASCAuth` so
/// `scripts/appstoreconnect-selftest.sh` can compile and assert them without
/// CryptoKit and without a key. What is left in `ASCAuth` is one call to
/// `P256.Signing.PrivateKey` and one to `signature(for:)`; everything that can
/// silently produce a token Apple refuses — the wrong claim set, an over-long
/// expiry, base64 that isn't URL-safe — is here and is tested.
enum ASCJWT {

    /// Apple's fixed audience. A typo here 401s every request forever.
    static let audience = "appstoreconnect-v1"

    /// RFC 7515's base64url: standard alphabet with `+`→`-`, `/`→`_`, and no
    /// padding. Sending standard base64 produces a token that looks right,
    /// encodes right, and is refused — the failure this function exists to
    /// prevent.
    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64url(json: [String: Any]) -> String {
        // `.sortedKeys` for determinism only — JWS does not care about key
        // order, but a harness that asserts exact bytes does, and a claim set
        // that changes shape between runs is one nobody can test.
        guard let data = try? JSONSerialization.data(withJSONObject: json,
                                                     options: [.sortedKeys]) else { return "" }
        return base64url(data)
    }

    static func headerJSON(keyID: String) -> [String: Any] {
        ["alg": "ES256", "kid": keyID, "typ": "JWT"]
    }

    /// The claim set — and the one branch in this file that is a documented
    /// either/or rather than a preference.
    ///
    /// Apple's token spec: `iss` is "your issuer ID … not used with individual
    /// keys", and `sub` is "not used with team keys; for individual keys, use
    /// the value `user`". They are mutually exclusive, and sending both (or
    /// neither) is a 401 that reads exactly like a wrong key. An empty issuer
    /// id IS the individual case — see `ASCAuth.issuerVaultKey`.
    static func payloadJSON(issuerID: String, issuedAt: Date, expires: Date) -> [String: Any] {
        var claims: [String: Any] = [
            "aud": audience,
            "iat": Int(issuedAt.timeIntervalSince1970),
            "exp": Int(expires.timeIntervalSince1970),
        ]
        let issuer = issuerID.trimmingCharacters(in: .whitespacesAndNewlines)
        if issuer.isEmpty {
            claims["sub"] = "user"
        } else {
            claims["iss"] = issuer
        }
        return claims
    }

    /// `<header>.<payload>` — the bytes that get signed.
    static func signingInput(keyID: String, issuerID: String,
                             issuedAt: Date, expires: Date) -> String {
        let header = base64url(json: headerJSON(keyID: keyID))
        let payload = base64url(json: payloadJSON(issuerID: issuerID,
                                                  issuedAt: issuedAt, expires: expires))
        return "\(header).\(payload)"
    }

    // MARK: - The pasted key

    /// Whatever was pasted, as a PEM CryptoKit will accept — or nil.
    ///
    /// Apple hands you a file, not a string, and by the time its contents
    /// reach a text field they have been through a text editor, a password
    /// manager, or a `cat`. So all three of these must work and mean the same
    /// thing: the whole file including its BEGIN/END markers, the base64 body
    /// alone, and either of those with the line breaks eaten by whatever
    /// carried it.
    ///
    /// It is a NORMALIZER, not a validator: it proves the body is base64 of a
    /// plausible length and re-emits canonical PEM. Whether those bytes are
    /// really a P-256 key is `P256.Signing.PrivateKey`'s answer, and asking it
    /// twice in two places is how the two answers drift.
    static func normalizedPEM(_ pasted: String) -> String? {
        let marker = "-----"
        var body = pasted
        // Take what is BETWEEN the markers when they're present. Splitting on
        // the marker rather than matching "BEGIN PRIVATE KEY" exactly is
        // deliberate: Apple ships `PRIVATE KEY` (PKCS#8) today, and a file that
        // said `EC PRIVATE KEY` would otherwise be rejected here with a
        // "couldn't read the key" that names the wrong problem.
        if body.contains(marker) {
            let parts = body.components(separatedBy: marker)
            // ["", "BEGIN PRIVATE KEY", "<body>", "END PRIVATE KEY", ""]
            guard parts.count >= 4 else { return nil }
            body = parts[2]
        }
        let compact = body.filter { !$0.isWhitespace }
        guard !compact.isEmpty,
              let decoded = Data(base64Encoded: compact) else { return nil }
        // A PKCS#8 P-256 private key is 138 bytes; SEC1 is 121. The window is
        // wide because this is a plausibility check, not a parser — its job is
        // to tell a truncated paste from a key, so that the error message can
        // say "check you copied the whole thing" rather than the parser's
        // silence. A `.cer` or a public key lands inside it and is refused one
        // line later by CryptoKit, which is the right place.
        guard (100...400).contains(decoded.count) else { return nil }

        var lines: [String] = ["-----BEGIN PRIVATE KEY-----"]
        var index = compact.startIndex
        while index < compact.endIndex {
            let end = compact.index(index, offsetBy: 64, limitedBy: compact.endIndex)
                ?? compact.endIndex
            lines.append(String(compact[index..<end]))
            index = end
        }
        lines.append("-----END PRIVATE KEY-----")
        return lines.joined(separator: "\n")
    }
}

// MARK: - What Apple says about a version

/// Every `appStoreVersion` state, and which of them is NEWS.
///
/// Two fields carry this on the wire: `appStoreState`, which Apple deprecated,
/// and `appVersionState`, which replaced it. `ASCFetch` reads the new one and
/// falls back to the old (the Kalshi `yes_bid_dollars` shape) — a rename that
/// empties a room with no error anywhere is this file's likeliest silent
/// failure, and reading both costs nothing.
enum ASCVersionState: String, CaseIterable {
    case prepareForSubmission        = "PREPARE_FOR_SUBMISSION"
    case readyForReview              = "READY_FOR_REVIEW"
    case waitingForReview            = "WAITING_FOR_REVIEW"
    case inReview                    = "IN_REVIEW"
    case pendingContract             = "PENDING_CONTRACT"
    case waitingForExportCompliance  = "WAITING_FOR_EXPORT_COMPLIANCE"
    case pendingDeveloperRelease     = "PENDING_DEVELOPER_RELEASE"
    case pendingAppleRelease         = "PENDING_APPLE_RELEASE"
    case processingForDistribution   = "PROCESSING_FOR_DISTRIBUTION"
    case processingForAppStore       = "PROCESSING_FOR_APP_STORE"
    case readyForDistribution        = "READY_FOR_DISTRIBUTION"
    case readyForSale                = "READY_FOR_SALE"
    case accepted                    = "ACCEPTED"
    case rejected                    = "REJECTED"
    case metadataRejected            = "METADATA_REJECTED"
    case invalidBinary               = "INVALID_BINARY"
    case developerRejected           = "DEVELOPER_REJECTED"
    case developerRemovedFromSale    = "DEVELOPER_REMOVED_FROM_SALE"
    case removedFromSale             = "REMOVED_FROM_SALE"
    case replacedWithNewVersion      = "REPLACED_WITH_NEW_VERSION"
    case notApplicable               = "NOT_APPLICABLE"

    /// The clause that LEADS the row's title, or nil when arriving at this
    /// state is not news.
    ///
    /// Nil for four different reasons, and they are worth keeping straight
    /// because a later pass will be tempted to "fix" one of them:
    ///
    ///   • **It was your own act.** You pressed Submit, so WAITING_FOR_REVIEW
    ///     told you nothing; you pressed Reject, so DEVELOPER_REJECTED told
    ///     you nothing. This is §313's rule (a charge your bank already pushed
    ///     you never notifies) applied to release management.
    ///   • **It is transient.** PROCESSING_* resolves itself in minutes and
    ///     would land a row that is stale before you read it (§216).
    ///   • **It is bookkeeping.** REPLACED_WITH_NEW_VERSION is what happens to
    ///     the old row when the new one ships — the shipping is the news, and
    ///     this is its shadow.
    ///   • **It is a starting position**, not an arrival: PREPARE_FOR_
    ///     SUBMISSION and READY_FOR_REVIEW are where a version sits while you
    ///     are still writing it.
    var verdict: String? {
        switch self {
        // Apple picked it up. This is the one state in the submit half that
        // is THEIR act, and it starts the clock you actually watch.
        case .inReview:                   String(localized: "In review")
        // The three faces of approved. Kept apart rather than collapsed to one
        // word because what happens next differs: one waits on you, one waits
        // on Apple, one is already done.
        case .accepted:                   String(localized: "Approved")
        case .pendingDeveloperRelease:    String(localized: "Approved — yours to release")
        case .pendingAppleRelease:        String(localized: "Approved — Apple is releasing it")
        case .readyForSale, .readyForDistribution:
                                          String(localized: "Live on the App Store")
        // The four verdicts you need to see, and the reason the clause LEADS.
        case .rejected:                   String(localized: "Rejected")
        case .metadataRejected:           String(localized: "Metadata rejected")
        case .invalidBinary:              String(localized: "Invalid binary")
        // Not verdicts, but they block a release just as hard and neither
        // sends you anything.
        case .pendingContract:            String(localized: "Blocked — a contract needs signing")
        case .waitingForExportCompliance: String(localized: "Waiting on export compliance")
        // Apple pulled it. Your own removal is not news (see below).
        case .removedFromSale:            String(localized: "Removed from sale")
        case .prepareForSubmission, .readyForReview, .waitingForReview,
             .developerRejected, .developerRemovedFromSale,
             .processingForDistribution, .processingForAppStore,
             .replacedWithNewVersion, .notApplicable:
                                          nil
        }
    }

    var isNews: Bool { verdict != nil }

    /// Bad news, for the register the sync answers in. The Stripe split: money
    /// arriving rains, money being challenged never does — here a rejection
    /// gets the honest failure tone and says what happened, and an approval
    /// gets the shower.
    var alarming: Bool {
        switch self {
        case .rejected, .metadataRejected, .invalidBinary,
             .pendingContract, .waitingForExportCompliance, .removedFromSale:
            true
        default:
            false
        }
    }

    /// Worth a shower. Deliberately NOT the inverse of `alarming` — IN_REVIEW
    /// is news and is neither: it is a thing you are told, not a thing you
    /// celebrate, and raining on it would spend the gesture that makes an
    /// approval feel like something.
    var celebrates: Bool {
        switch self {
        case .accepted, .pendingDeveloperRelease, .pendingAppleRelease,
             .readyForSale, .readyForDistribution:
            true
        default:
            false
        }
    }

    /// Nil for a value this build has never heard of — which lands NOTHING
    /// rather than a row titled with a guess (the `CursorFetch.status(of:)`
    /// rule). `ASCFetch.diagnose` names it, so a new Apple state surfaces as a
    /// probe line instead of as silence.
    static func parse(_ raw: String?) -> ASCVersionState? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return ASCVersionState(rawValue: raw.uppercased())
    }
}

/// A build's processing state. Only the two TERMINAL ones land: `PROCESSING`
/// is a state you are already watching, and `PROCESSING` → `VALID` is the
/// transition worth a row.
enum ASCBuildState: String {
    case processing = "PROCESSING"
    case failed     = "FAILED"
    case invalid    = "INVALID"
    case valid      = "VALID"

    var terminal: Bool { self != .processing }

    /// The clause that leads. `FAILED` and `INVALID` mean different things to
    /// Apple (one is the upload, one is the binary) and the same thing to you,
    /// so they read the same and the probe keeps them apart.
    var clause: String {
        switch self {
        case .valid:                String(localized: "Ready to test")
        case .invalid, .failed:     String(localized: "Failed processing")
        case .processing:           String(localized: "Processing")
        }
    }

    var alarming: Bool { self == .invalid || self == .failed }

    static func parse(_ raw: String?) -> ASCBuildState? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return ASCBuildState(rawValue: raw.uppercased())
    }
}

// MARK: - Shaping

/// Every title this bridge writes, and nothing else — pure, so the harness can
/// hold it to the one ruling that matters here (§303): `IngestSupport.titleLine`
/// clamps at 80 characters, so anything parked at the END of a title is what
/// the clamp eats. A rejection reading as a success is the fake status §83
/// bans, so the verdict LEADS every row it appears on.
enum ASCShape {

    static let source = "App Store Connect"

    /// `"Rejected · Casberi 1.4"`.
    static func versionTitle(app: String, version: String, state: ASCVersionState) -> String {
        let name = [app, version].filter { !$0.isEmpty }.joined(separator: " ")
        guard let verdict = state.verdict else { return name }
        return name.isEmpty ? verdict : "\(verdict) · \(name)"
    }

    /// `"★★☆☆☆ · Casberi · Crashes on launch"`.
    ///
    /// The rating leads for the version rule's reason, one step stronger: the
    /// whole point of a review row is which ones are bad, and a one-star buried
    /// behind a long app name and a long review title is a one-star you scroll
    /// past. Five glyphs cost five characters.
    static func reviewTitle(rating: Int?, title: String?, app: String) -> String {
        let parts = [stars(rating), app.isEmpty ? nil : app, clean(title)]
        let joined = parts.compactMap { $0 }.joined(separator: " · ")
        // A review with no rating, no title and no resolvable app is not
        // impossible — a nickname-only row from a locale we couldn't read —
        // and an empty title would render as a blank band.
        return joined.isEmpty ? String(localized: "App Store review") : joined
    }

    /// `"★★☆☆☆"`, or nil when the rating is missing or outside Apple's own
    /// 1–5. Nil rather than a clamp: five empty stars for an unreadable
    /// rating is a zero-star review that nobody wrote.
    static func stars(_ rating: Int?) -> String? {
        guard let rating, (1...5).contains(rating) else { return nil }
        return String(repeating: "★", count: rating)
             + String(repeating: "☆", count: 5 - rating)
    }

    /// `"Ready to test · Casberi build 267"`.
    static func buildTitle(app: String, build: String, state: ASCBuildState) -> String {
        "\(state.clause) · \(buildLabel(app: app, build: build))"
    }

    /// `"TestFlight build expires · Casberi build 267"`. The `dueAt` carries
    /// the date, so the title never says one — a date in a title and a
    /// different date on the row is the kind of disagreement nobody notices
    /// and everybody distrusts.
    static func expiryTitle(app: String, build: String) -> String {
        String(localized: "TestFlight build expires")
            + " · \(buildLabel(app: app, build: build))"
    }

    /// `"Casberi build 267"`.
    ///
    /// The MARKETING version ("1.4") is deliberately absent. A build row
    /// carries only its build number; the marketing version lives on its
    /// `preReleaseVersion` relationship, and reaching it means either a second
    /// request per build or an `include=` parameter — and an `include` App
    /// Store Connect doesn't recognise is a 400 that empties the room, which
    /// is the same cliff `ASCFetch`'s no-`fields[…]` rule exists to avoid on
    /// an API this app has never measured. "build 267" is also what TestFlight
    /// itself puts in front of a tester and what a developer says out loud.
    static func buildLabel(app: String, build: String) -> String {
        let number = build.isEmpty ? nil : String(localized: "build \(build)")
        return [app.isEmpty ? nil : app, number].compactMap { $0 }.joined(separator: " ")
    }

    private static func clean(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Where a row opens

    /// App Store Connect's two long-stable section paths. Deliberately not
    /// deeper: the web app's inner routes (a specific review, a specific
    /// submission) have been rewritten more than once, and a link that 404s is
    /// worse than one that needs a scroll. `appstore` holds versions and
    /// reviews; `testflight/ios` holds builds.
    static func versionURL(appID: String) -> String {
        "https://appstoreconnect.apple.com/apps/\(appID)/appstore"
    }

    static func buildURL(appID: String) -> String {
        "https://appstoreconnect.apple.com/apps/\(appID)/testflight/ios"
    }
}

// MARK: - What this device remembers

/// The ledgers — none of them a `Thing`, all of them dropped on disconnect.
///
/// Two of the three exist for the same reason: a version's state and a build's
/// processing state are STATES that this bridge turns into EVENTS by DIFFING.
/// Without a remembered previous value there is no transition, and the first
/// sync of an account with six shipped versions would land six "Live on the
/// App Store" rows dated today — pure backfill wearing news, which is exactly
/// the bug `HyperliquidDeFi.sync` shipped and had to be fixed for.
enum ASCState {

    private static let appsKey     = "asc.apps"
    private static let versionsKey = "asc.versionStates"
    private static let buildsKey   = "asc.buildStates"
    private static let seededKey   = "asc.seeded"
    private static let readKey     = "asc.lastRead"

    /// App id → name, so a review row can say which app without a second read
    /// and the setup screen can list what it can see.
    static var apps: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: appsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: appsKey) }
    }

    /// Version id → the state we last saw it in.
    static var versionStates: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: versionsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: versionsKey) }
    }

    /// Build id → the processing state we last saw it in.
    static var buildStates: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: buildsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: buildsKey) }
    }

    /// Whether a first pass has completed. The gate on the silent seed, and
    /// deliberately NOT `versionStates.isEmpty` — an account whose only app is
    /// brand new has no versions at all, so an emptiness test would keep
    /// re-seeding forever and its first real verdict would be swallowed as
    /// history (the `PostHogMetric.seeded` bug, caught in review there).
    static var seeded: Bool {
        get { UserDefaults.standard.bool(forKey: seededKey) }
        set { UserDefaults.standard.set(newValue, forKey: seededKey) }
    }

    static var lastRead: Date? {
        get { UserDefaults.standard.object(forKey: readKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: readKey) }
    }

    static func clear() {
        let d = UserDefaults.standard
        for key in [appsKey, versionsKey, buildsKey, seededKey, readKey] {
            d.removeObject(forKey: key)
        }
    }
}

// MARK: - The reads

enum ASCFetch {

    static let base = "https://api.appstoreconnect.apple.com/v1"

    /// How many apps one pass will walk. A bound, not a target: each app costs
    /// three requests, so ten apps is thirty-one requests on a foreground
    /// sweep that already has ~45 other bridges to get through. Almost every
    /// account here has one or two.
    static let appCap = 10

    /// Deliberately NO `fields[…]` parameters anywhere in this file.
    ///
    /// Asking App Store Connect for an attribute the account's API version
    /// doesn't serve is a **400**, not a silently-absent field — so a
    /// `fields[appStoreVersions]=appVersionState` written against today's docs
    /// would empty the whole room for anyone on an older shape, with the error
    /// swallowed by `getJSON`'s nil. These payloads are twenty rows at most.
    /// The saving was never worth the cliff.
    ///
    /// `limit`, `sort` and the relationship routes below are all long-stable
    /// and are used.

    /// Every app this key can see. The anchor for everything else — nothing
    /// here is readable without an app id.
    static func apps(token: String) async -> [[String: Any]]? {
        await rows(at: "\(base)/apps?limit=200", token: token)
    }

    static func versions(appID: String, token: String) async -> [[String: Any]]? {
        await rows(at: "\(base)/apps/\(appID)/appStoreVersions?limit=5", token: token)
    }

    static func reviews(appID: String, token: String) async -> [[String: Any]]? {
        await rows(at: "\(base)/apps/\(appID)/customerReviews?limit=20&sort=-createdDate",
                   token: token)
    }

    static func builds(appID: String, token: String) async -> [[String: Any]]? {
        await rows(at: "\(base)/apps/\(appID)/builds?limit=10&sort=-uploadedDate",
                   token: token)
    }

    /// One GET, unwrapped to JSON:API's `data` array.
    ///
    /// Nil is "this read failed", and callers treat each read INDEPENDENTLY on
    /// purpose: an App Store Connect key carries a ROLE, and a role that can
    /// see builds but not customer reviews is an ordinary configuration, not a
    /// broken connection. Failing the whole pass on one 403 would hide three
    /// working reads behind one that was never going to work.
    private static func rows(at url: String, token: String) async -> [[String: Any]]? {
        guard let root = await IngestSupport.getJSON(url, auth: ASCAuth.header(token))
                as? [String: Any] else { return nil }
        return root["data"] as? [[String: Any]]
    }

    // MARK: Field reads

    static func attributes(_ row: [String: Any]) -> [String: Any] {
        row["attributes"] as? [String: Any] ?? [:]
    }

    static func id(_ row: [String: Any]) -> String? {
        guard let id = (row["id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        return id
    }

    /// The version's state, new field first. See `ASCVersionState`'s note: one
    /// of these two is deprecated and the other is recent, so an account can
    /// legitimately serve either.
    static func versionState(_ attributes: [String: Any]) -> ASCVersionState? {
        ASCVersionState.parse(attributes["appVersionState"] as? String)
            ?? ASCVersionState.parse(attributes["appStoreState"] as? String)
    }

    static func string(_ attributes: [String: Any], _ key: String) -> String {
        (attributes[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - The pass

enum ASCIngest {

    @MainActor private static var running = false

    /// The most urgent bad news the last pass landed, or nil. Read by
    /// `AppStoreConnectScreen` so a sync the person asked for answers in the
    /// right register — the `StripeIngest.lastPassAlarm` shape, and for the
    /// same reason: an approval rains, a rejection must never rain.
    @MainActor private(set) static var lastPassAlarm: String?

    /// How close a TestFlight build has to be to its 90-day death before it is
    /// worth a row. Two weeks: long enough to cut a new build and get it
    /// through review, short enough that the row is about this fortnight
    /// rather than a fact you learned at upload. Cloudflare's expiry window
    /// reasoning, in a shorter-lived medium.
    static let expiryWindow: TimeInterval = 14 * 24 * 3600

    /// How many customer reviews a FIRST sync backfills. They land with their
    /// REAL dates and sort back into history, so this is a page of proof for
    /// somebody who just connected, not a day of manufactured urgency — the
    /// Hugging Face split, and the opposite of the version/build ledgers
    /// below, which seed in silence.
    static let firstSightReviews = 20

    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        guard ASCAuth.configured else { return nil }
        running = true
        defer { running = false }
        lastPassAlarm = nil

        guard case .success(let token) = ASCAuth.token() else { return nil }
        guard let appRows = await ASCFetch.apps(token: token) else { return nil }

        var names: [String: String] = [:]
        for row in appRows {
            guard let id = ASCFetch.id(row) else { continue }
            names[id] = ASCFetch.string(ASCFetch.attributes(row), "name")
        }
        ASCState.apps = names

        let firstSight = !ASCState.seeded
        var landed: [Thing] = []
        var versionSeen = ASCState.versionStates
        var buildSeen = ASCState.buildStates
        var celebrating: Set<String> = []
        var alarming: Set<String> = []

        for appID in names.keys.sorted().prefix(ASCFetch.appCap) {
            let app = names[appID] ?? ""
            // The three reads are independent — one 403 (a role that can't see
            // reviews) must not cost the other two, and they have no ordering
            // between them.
            async let versionTask = ASCFetch.versions(appID: appID, token: token)
            async let reviewTask  = ASCFetch.reviews(appID: appID, token: token)
            async let buildTask   = ASCFetch.builds(appID: appID, token: token)
            let (versionRows, reviewRows, buildRows) =
                await (versionTask, reviewTask, buildTask)

            for row in versionRows ?? [] {
                guard let shaped = versionThing(row, appID: appID, app: app,
                                                seen: &versionSeen, firstSight: firstSight)
                else { continue }
                landed.append(shaped.thing)
                if let ref = shaped.thing.sourceRef {
                    if shaped.state.celebrates { celebrating.insert(ref) }
                    if shaped.state.alarming { alarming.insert(ref) }
                }
            }

            let reviews = reviewRows ?? []
            for row in (firstSight ? Array(reviews.prefix(firstSightReviews)) : reviews) {
                guard let thing = reviewThing(row, appID: appID, app: app) else { continue }
                landed.append(thing)
            }

            for row in buildRows ?? [] {
                let shaped = buildThings(row, appID: appID, app: app,
                                         seen: &buildSeen, firstSight: firstSight)
                landed.append(contentsOf: shaped.things)
                if let ref = shaped.alarmRef { alarming.insert(ref) }
            }
        }

        ASCState.versionStates = versionSeen
        ASCState.buildStates = buildSeen
        ASCState.lastRead = .now
        ASCState.seeded = true

        let inserted = insert(landed, context: context)
        for thing in inserted where celebrating.contains(thing.sourceRef ?? "") {
            SourceMoments.shared.fire(thing.title, source: ASCShape.source)
        }
        lastPassAlarm = inserted.first { alarming.contains($0.sourceRef ?? "") }?.title
        return inserted.count
    }

    // MARK: Shaping one row

    /// A version whose state has CHANGED into something worth saying, or nil.
    ///
    /// The ledger is written on every pass whatever the answer — including for
    /// a state that is not news, and including on first sight. Writing it only
    /// when a row lands would mean a version that moved PREPARE → IN_REVIEW →
    /// REJECTED between two foregrounds is remembered as PREPARE, and the next
    /// pass would announce IN_REVIEW after the rejection had already happened.
    @MainActor
    private static func versionThing(_ row: [String: Any], appID: String, app: String,
                                     seen: inout [String: String],
                                     firstSight: Bool) -> (thing: Thing, state: ASCVersionState)? {
        guard let id = ASCFetch.id(row) else { return nil }
        let attributes = ASCFetch.attributes(row)
        guard let state = ASCFetch.versionState(attributes) else { return nil }
        let previous = seen[id]
        seen[id] = state.rawValue
        // First sight seeds in SILENCE. An account with four shipped versions
        // would otherwise land four "Live on the App Store" rows the moment it
        // connected, every one of them months old and all four dated today.
        guard !firstSight, previous != state.rawValue, state.isNews else { return nil }

        let version = ASCFetch.string(attributes, "versionString")
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(
                ASCShape.versionTitle(app: app, version: version, state: state)),
            content: ASCShape.versionURL(appID: appID),
            source: ASCShape.source,
            // `.now`, not the version's `createdDate`: the created date is when
            // you started writing the version, and this row is about what just
            // happened to it. The one place in this file where the event's own
            // moment really is now — Apple publishes no timestamp for a state
            // change, and inventing one from `createdDate` would file a
            // rejection weeks back where nobody would see it.
            capturedAt: .now,
            tags: [String(localized: "Release")],
            // The STATE is in the ref, so each verdict on one version is its
            // own row and a version that is rejected, fixed and approved keeps
            // all three. Keying on the version alone would make the whole
            // history one row that silently rewrote itself.
            sourceRef: "asc:version:\(id):\(state.rawValue)"
        )
        return (thing, state)
    }

    /// A customer review. Nothing to diff — a review either exists or doesn't,
    /// and `sourceRef` dedupe is the whole mechanism.
    @MainActor
    private static func reviewThing(_ row: [String: Any], appID: String, app: String) -> Thing? {
        guard let id = ASCFetch.id(row) else { return nil }
        let attributes = ASCFetch.attributes(row)
        let rating = attributes["rating"] as? Int
        let title = ASCFetch.string(attributes, "title")
        let body = ASCFetch.string(attributes, "body")
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(
                ASCShape.reviewTitle(rating: rating, title: title, app: app)),
            content: ASCShape.versionURL(appID: appID),
            source: ASCShape.source,
            // The review's OWN date — a first sync sorts a year of reviews back
            // into the year they were written.
            capturedAt: IngestSupport.isoDate(attributes["createdDate"]) ?? .now,
            tags: [String(localized: "Review")],
            sourceRef: "asc:review:\(id)"
        )
        // What they actually wrote is the whole reason to keep this row, so it
        // is DISPLAY copy — `enrichedText` is retrieval-only by the 2026-07-15
        // ruling and would make it invisible on every screen (the Cursor
        // summary rule).
        if !body.isEmpty { thing.summary = body }
        // The nickname, so a room can be scoped by reviewer and a search for
        // one finds their words. Never rendered as an author byline: these are
        // display names people chose, not handles that resolve anywhere.
        let nickname = ASCFetch.string(attributes, "reviewerNickname")
        if !nickname.isEmpty { thing.authorHandle = nickname }
        // Territory rides retrieval only. It is genuinely useful to search
        // ("reviews from Japan") and genuinely noise in a title.
        let territory = ASCFetch.string(attributes, "territory")
        if !territory.isEmpty { thing.enrichedText = territory }
        return thing
    }

    /// Up to two rows from one build: the moment it finished processing, and
    /// the deadline it is heading for.
    ///
    /// They are separate rows rather than one because they are different kinds
    /// of thing — one is an event that happened, one is a date that is coming —
    /// and folding the deadline onto the arrival would put a `dueAt` 90 days
    /// out on a row that is otherwise about today.
    @MainActor
    private static func buildThings(_ row: [String: Any], appID: String, app: String,
                                    seen: inout [String: String],
                                    firstSight: Bool) -> (things: [Thing], alarmRef: String?) {
        guard let id = ASCFetch.id(row) else { return ([], nil) }
        let attributes = ASCFetch.attributes(row)
        // A build's `version` attribute is the BUILD NUMBER ("267"), not the
        // marketing version — see `ASCShape.buildLabel` for why the marketing
        // version is not fetched.
        let build = ASCFetch.string(attributes, "version")
        var things: [Thing] = []
        var alarmRef: String?

        if let state = ASCBuildState.parse(attributes["processingState"] as? String) {
            let previous = seen[id]
            seen[id] = state.rawValue
            if !firstSight, previous != state.rawValue, state.terminal {
                let thing = Thing(
                    kind: .link,
                    title: IngestSupport.titleLine(
                        ASCShape.buildTitle(app: app, build: build, state: state)),
                    content: ASCShape.buildURL(appID: appID),
                    source: ASCShape.source,
                    capturedAt: IngestSupport.isoDate(attributes["uploadedDate"]) ?? .now,
                    tags: [String(localized: "Build")],
                    sourceRef: "asc:build:\(id):\(state.rawValue)"
                )
                things.append(thing)
                if state.alarming { alarmRef = thing.sourceRef }
            }
        }

        // The expiry row lands on FIRST SIGHT too, unlike everything else here,
        // and that divergence is the point: a build three days from expiring is
        // exactly what somebody connecting this bridge today needs to be told
        // (the Aave/Morpho risk-crossing precedent — a position already near
        // liquidation when you start watching is news immediately).
        let expired = attributes["expired"] as? Bool ?? false
        if !expired, let expires = IngestSupport.isoDate(attributes["expirationDate"]),
           expires > .now, expires.timeIntervalSinceNow < expiryWindow {
            let thing = Thing(
                kind: .reminder,
                title: IngestSupport.titleLine(
                    ASCShape.expiryTitle(app: app, build: build)),
                content: ASCShape.buildURL(appID: appID),
                source: ASCShape.source,
                capturedAt: .now,
                tags: [String(localized: "Build")],
                sourceRef: "asc:buildexpiry:\(id)"
            )
            // The deadline. `NotifySweep`'s generic `deadlineNear` reads this,
            // so a build dying inside 72 hours reaches the lock screen with no
            // notification code of this bridge's own.
            thing.dueAt = expires
            things.append(thing)
        }
        return (things, alarmRef)
    }

    /// **No `reconcile…` pass, and that is a property rather than an omission.**
    /// Every row here is final the moment it lands: a verdict happened, a
    /// review was written, a build finished, and a build's expiry date is
    /// fixed at upload and never moves. Linear, Trello and Cloudflare all
    /// reconcile because they land rows whose state keeps changing. If a
    /// future pass adds one, something started landing a state.
    @MainActor
    private static func insert(_ incoming: [Thing], context: ModelContext) -> [Thing] {
        let existing = IngestSupport.existingSourceRefs(context, source: ASCShape.source)
        var added: [Thing] = []
        var landed: Set<String> = []
        for item in incoming {
            // `landed` guards against one PASS producing the same ref twice —
            // two apps can't, but a re-read window could, and a duplicate
            // insert is the historical bug class of every bridge here.
            guard let ref = item.sourceRef,
                  !existing.contains(ref), landed.insert(ref).inserted else { continue }
            context.insert(item)
            SpotlightIndex.index([item])
            added.append(item)
        }
        if !added.isEmpty { context.saveHonestly() }
        return added
    }

    // MARK: - Probe

    /// `-ascProbe YES` — the read, phase by phase, with the STORED credentials.
    ///
    /// The `-kalshiBookProbe`/`-cursorProbe` lesson, and this bridge has more
    /// causes than most: an empty App Store Connect room means one of
    ///
    ///   1. no key, or a key with no key id beside it,
    ///   2. a `.p8` that isn't a P-256 key (the wrong file from the download),
    ///   3. a 401 — a wrong issuer id, or the team/individual claim set the
    ///      wrong way round, which is the single likeliest mistake here and is
    ///      indistinguishable from a bad key from the outside,
    ///   4. a 403 on ONE endpoint — a role that can't see customer reviews,
    ///      which is a configuration and not a fault,
    ///   5. an account whose apps have simply had no news (the healthy case),
    ///   6. shape drift — `appVersionState` renamed again, or a state value
    ///      this build has never heard of, which lands nothing and says
    ///      nothing anywhere.
    ///
    /// Only 6 is a bug. One NSLog per line (the `-todayProbe` truncation
    /// lesson), and one `ascRow|` line per row naming the fields every shaping
    /// decision above rests on. Reads only: it does not write the ledgers, so
    /// running it can never swallow the next real sync's news.
    @MainActor
    static func diagnose() async {
        guard ASCAuth.storedKey != nil else {
            NSLog("[Casberi] asc| no key stored — paste one first (-ascKey <p8>)")
            return
        }
        NSLog("[Casberi] asc| keyID=%@ issuer=%@ (%@ key)",
              ASCAuth.storedKeyID.isEmpty ? "MISSING" : "set",
              ASCAuth.storedIssuer.isEmpty ? "empty" : "set",
              ASCAuth.storedIssuer.isEmpty ? "individual" : "team")
        let minted = ASCAuth.token()
        guard case .success(let token) = minted else {
            switch minted {
            case .failure(.noKey):
                NSLog("[Casberi] asc| no key")
            case .failure(.noKeyID):
                NSLog("[Casberi] asc| no key ID — Apple needs it in the token header (-ascKeyID <id>)")
            case .failure(.unreadableKey):
                NSLog("[Casberi] asc| the stored key is not a P-256 private key — wrong file, or a truncated paste")
            case .success:
                break
            }
            return
        }
        NSLog("[Casberi] asc| token minted, %d chars", token.count)

        let (json, status) = await IngestSupport.getJSONStatus(
            "\(ASCFetch.base)/apps?limit=200", auth: ASCAuth.header(token))
        NSLog("[Casberi] asc| GET /v1/apps HTTP %d", status)
        guard status != 401 else {
            NSLog("[Casberi] asc| 401 — Apple refused the token. Check the issuer ID: leave it EMPTY for an individual key, and set it for a team key.")
            return
        }
        guard let root = json as? [String: Any],
              let appRows = root["data"] as? [[String: Any]] else {
            NSLog("[Casberi] asc| no `data` array — unreachable, or the envelope changed")
            return
        }
        NSLog("[Casberi] asc| %d apps visible (walking at most %d)", appRows.count, ASCFetch.appCap)
        if appRows.isEmpty {
            NSLog("[Casberi] asc| the key works and sees no apps — check its role has access to yours")
        }

        var unknownStates: Set<String> = []
        for row in appRows.prefix(ASCFetch.appCap) {
            guard let appID = ASCFetch.id(row) else { continue }
            let app = ASCFetch.string(ASCFetch.attributes(row), "name")
            let versions = await ASCFetch.versions(appID: appID, token: token)
            let reviews  = await ASCFetch.reviews(appID: appID, token: token)
            let builds   = await ASCFetch.builds(appID: appID, token: token)
            // A nil and a zero are different findings — nil is a refused or
            // failed read (usually a role), zero is a real answer.
            NSLog("[Casberi] asc| %@ — versions=%@ reviews=%@ builds=%@",
                  app.isEmpty ? appID : app,
                  versions.map { String($0.count) } ?? "READ FAILED",
                  reviews.map { String($0.count) } ?? "READ FAILED (role can't see reviews?)",
                  builds.map { String($0.count) } ?? "READ FAILED")

            for v in versions ?? [] {
                let a = ASCFetch.attributes(v)
                let raw = (a["appVersionState"] as? String) ?? (a["appStoreState"] as? String) ?? "—"
                let state = ASCFetch.versionState(a)
                if state == nil { unknownStates.insert(raw) }
                NSLog("[Casberi] ascRow| version %@ state=%@ news=%@ title=%@",
                      ASCFetch.string(a, "versionString"),
                      raw,
                      state?.isNews == true ? "YES" : "no",
                      state.map { ASCShape.versionTitle(app: app,
                                                        version: ASCFetch.string(a, "versionString"),
                                                        state: $0) } ?? "(would land nothing)")
            }
            for r in (reviews ?? []).prefix(5) {
                let a = ASCFetch.attributes(r)
                NSLog("[Casberi] ascRow| review rating=%@ body=%d chars title=%@",
                      String(describing: a["rating"] ?? "MISSING"),
                      ASCFetch.string(a, "body").count,
                      ASCShape.reviewTitle(rating: a["rating"] as? Int,
                                           title: ASCFetch.string(a, "title"), app: app))
            }
            for b in (builds ?? []).prefix(5) {
                let a = ASCFetch.attributes(b)
                let expires = IngestSupport.isoDate(a["expirationDate"])
                NSLog("[Casberi] ascRow| build %@ processing=%@ expired=%@ expires=%@ inWindow=%@",
                      ASCFetch.string(a, "version"),
                      ASCFetch.string(a, "processingState"),
                      String(describing: a["expired"] ?? "MISSING"),
                      expires.map { ISO8601DateFormatter().string(from: $0) } ?? "none",
                      (expires.map { $0 > .now && $0.timeIntervalSinceNow < expiryWindow } ?? false)
                        ? "YES" : "no")
            }
        }
        if !unknownStates.isEmpty {
            NSLog("[Casberi] asc| UNKNOWN version states, these land NOTHING: %@",
                  unknownStates.sorted().joined(separator: ","))
        }
        NSLog("[Casberi] asc| seeded=%@ — a first pass lands reviews and expiries only, by design",
              ASCState.seeded ? "yes" : "NO (next sync seeds silently)")
    }
}

// MARK: - The seat

enum ASCWatch {

    static let source = ASCShape.source

    /// Connected while a key AND a key id exist. `TokenBridge.connected` sees
    /// only the key, which is why this asks `ASCAuth.configured` — see its
    /// note: a half-configured bridge that reads "connected" and 401s on every
    /// request is precisely the fake status §83 bans.
    @MainActor
    static func registerBridge(store: BridgeStore) {
        guard ASCAuth.configured else {
            store.remove(TokenBridge.appStoreConnect.bridgeID)
            return
        }
        let apps = ASCState.apps.values.filter { !$0.isEmpty }.sorted()
        let proof: String
        switch apps.count {
        case 0:  proof = String(localized: "Connected")
        case 1:  proof = apps[0]
        case 2:  proof = apps.joined(separator: " · ")
        default: proof = "\(apps[0]) · \(apps[1]) +\(apps.count - 2)"
        }
        store.registerConnected(
            id: TokenBridge.appStoreConnect.bridgeID, name: source,
            proof: proof,
            // The read-only promise has ONE home (`TokenBridge.canLine`) — the
            // PostHog contract. A second copy here would be the only reader of
            // a string nothing else renders, and the two would drift.
            can: [TokenBridge.appStoreConnect.canLine])
    }
}
