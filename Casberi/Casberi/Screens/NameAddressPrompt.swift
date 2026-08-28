import SwiftUI
import SwiftData

/// The second-encounter nudge (prd §169, 2026-07-21) — the book's third door,
/// and the only one that speaks first.
///
/// The rule it keeps: **once is noise, twice is a relationship.** An address
/// you've transacted with a single time is a stranger and naming it is busywork;
/// the same address a second time is a counterparty you'll meet again, and a
/// name there retitles the whole history at once. So the prompt appears only
/// from the second landed transfer onward, only when the address has no name,
/// and never again once declined for that address.
enum AddressNudge {
    /// How many encounters before we say anything.
    static let threshold = 2
    private static func key(_ address: String) -> String {
        "wallet.nameNudge.declined.\(AddressBook.key(for: address))"
    }

    /// "Not now" is remembered per address, forever. A nudge that returns on
    /// every visit is nagging, and the door stays open anyway — the pencil on
    /// the counterparty's own face never goes away.
    static func decline(_ address: String) {
        UserDefaults.standard.set(true, forKey: key(address))
    }

    static func declined(_ address: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(address))
    }

    /// The nudge for this sheet, or nil. Counts landed transfers carrying the
    /// same counterparty — a plain model read, no network.
    @MainActor
    static func prompt(for thing: Thing, context: ModelContext)
        -> (address: String, count: Int, kind: AddressBook.Kind)? {
        guard thing.source == "Wallet",
              let address = thing.counterpartyAddress, !address.isEmpty,
              AddressBook.shared.name(for: address) == nil,
              !declined(address)
        else { return nil }
        // A counterparty the app can already name for itself (a known router,
        // a reverse-resolved ENS) doesn't need one from the person — the row
        // already reads as words, so a prompt would be asking for busywork.
        guard WalletIngest.knownLabel(for: address) == nil else { return nil }

        // NEVER solicit a name for an address that impersonates one you
        // already know (2026-08-01). This prompt is the app's only place that
        // ASKS for a name, and a name is the most dangerous thing you can give
        // a poisoning address: `WalletIngest.knownLabel` and
        // `counterpartyNames` both put the person's own label ABOVE every
        // resolver, deliberately — so one tap here would turn a flagged
        // attacker into "Mom" across every title, row and answer in the app.
        //
        // The attack fits this prompt's own trigger perfectly: poisoners send
        // several dust transfers, so `threshold` is trivially met, and they
        // have no `knownLabel` by construction. Both tests are cheap and
        // deterministic — the flag `WalletSafety` already stamped at ingest,
        // and the book's own record of what this address is pretending to be.
        // The `"spam"` flag earns its seat here for the same reason: a fake
        // transfer event names an attacker's address as your counterparty, and
        // a wallet gets dozens of them, so `threshold` is met just as trivially
        // — offering to NAME that address would file the attacker in the book
        // under a name you chose.
        guard !thing.hasSecurityFlag("poisoning"), !thing.hasSecurityFlag("spam"),
              AddressBook.shared.lookalikes(of: address).isEmpty
        else { return nil }

        // Counted through the ONE definition of activity (`AddressActivity`),
        // the same one the address card's "Your history together" states — a
        // second count here could tell you "4 times" while the card said 12.
        let count = AddressActivity.counts(in: context)[AddressBook.key(for: address)] ?? 0
        guard count >= threshold else { return nil }
        return (address, count, AddressBook.shared.entry(for: address)?.kind ?? .unknown)
    }
}

/// The prompt itself — a card in the thing sheet, in the app's own
/// verb-then-outcome grammar. States the fact that earns it ("you've dealt
/// with this address N times"), states what a name would do, and offers
/// exactly two ways out.
struct NameAddressPrompt: View {
    let address: String
    let count: Int
    let kind: AddressBook.Kind
    let onName: () -> Void
    let onDismiss: () -> Void

    // A NUDGE, not a headline (2026-07-23; user: the screen read as "vibe
    // coded") — the old card wore a heading, a three-line paragraph, and two
    // full-width buttons, which made a tertiary prompt the loudest block on
    // the sheet, louder than the transaction it sat under. One title line,
    // one short fact, two compact controls — the primary a small tinted
    // capsule, the decline a plain word — so the card reads as an aside.
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Name this address?")
                .dsText(.body17).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
            Text(reason)
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s4) {
                Button {
                    DSHaptic.tap()
                    onName()
                } label: {
                    // The system's own small primary (2026-08-28). This was a
                    // hand-rolled `Text` in a filled capsule with its own
                    // padding — the shape `Chip` already is, three rows below
                    // an `AgentKeyPicker` that draws real ones.
                    Chip(text: String(localized: "Name it"), style: .primary)
                }
                .buttonStyle(PressSpring())
                Button {
                    DSHaptic.tap()
                    onDismiss()
                } label: {
                    Text("Not now")
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(.top, DS.Space.s1)
        }
        .padding(DS.Space.s3)
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
    }

    /// The fact that earns the prompt — one sentence now; what a name does
    /// ("retitles its transactions") is the half worth saying, and the
    /// address-book mechanics ride along without being narrated.
    private var reason: String {
        let what = kind.label?.lowercased() ?? String(localized: "address")
        // "A contract" / "A safe" read fine; only the "address" default
        // needs the vowel-sound article ("A address" — caught 2026-07-23).
        let article = what.first.map { "aeiou".contains($0) } == true
            ? String(localized: "an") : String(localized: "a")
        return String(localized: "You've dealt with this \(what) \(count) times — \(article) name retitles all its transactions.")
    }
}
