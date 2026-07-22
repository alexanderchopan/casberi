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

        let key = AddressBook.key(for: address)
        let all = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" }))) ?? []
        let count = all.filter {
            ($0.counterpartyAddress).map { AddressBook.key(for: $0) == key } ?? false
        }.count
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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Name this address?")
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
            Text(reason)
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s2) {
                Button {
                    DSHaptic.tap()
                    onName()
                } label: {
                    Text("Name it")
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.s2)
                        .background(DS.tint, in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                                  style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    DSHaptic.tap()
                    onDismiss()
                } label: {
                    Text("Not now")
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.s2)
                        .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                                       style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, DS.Space.s1)
        }
        .padding(DS.Space.s3)
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
    }

    /// The fact that earns the prompt. Says what the address IS when the chain
    /// already told us — a contract you've used twice is a different sentence
    /// from a person you've paid twice.
    private var reason: String {
        let what = kind.label?.lowercased() ?? String(localized: "address")
        return String(localized: "A \(what) you've now dealt with \(count) times. A name here retitles every transaction with it — past and future — and adds it to your address book.")
    }
}
