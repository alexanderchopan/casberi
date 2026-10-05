import SwiftUI

/// A BILLER'S PAGE in Addresses (prd §1106): how it bills you, in place of
/// the address rows a person or a wallet draws. Relationship facts only —
/// how often, when next, what pays it, since when — and no money: the
/// address book is a people screen and the Wallet holds the figures (user,
/// 2026-08-21). The charges themselves are the sheet's "With you" rows.
struct BillerFacts: View {
    let biller: Billers.Biller
    @Environment(\.openURL) private var openURL

    var body: some View {
        let item = biller.item
        VStack(spacing: 0) {
            if let cadence = cadenceWord(item.cadenceDays) {
                fact(String(localized: "Bills"), cadence)
            }
            if !biller.subscription, item.cadenceDays != nil {
                // A moving bill (power, water) — the one thing that tells it
                // from a subscription, said without the figure.
                fact(String(localized: "Amount"), String(localized: "Varies"))
            }
            if let next = item.next {
                fact(nextLabel, next.formatted(.dateTime.month(.wide).day()))
            }
            if let pays = item.paysWith {
                fact(String(localized: "Pays with"), pays)
            }
            if let since = item.since {
                fact(String(localized: "Since"), since.formatted(.dateTime.month(.wide).year()))
            }
            if let site = item.site, let url = URL(string: "https://\(site)") {
                DSDoorRow(icon: "arrow.up.right", title: Text("Manage on \(site)")) { openURL(url) }
            }
        }
    }

    /// A subscription renews; a bill with no known cadence is a dated charge
    /// (Rocket Money's); a moving bill's next date is arithmetic off its
    /// cadence, so it says so.
    private var nextLabel: String {
        if biller.item.cadenceDays == nil { return String(localized: "Next charge") }
        return biller.subscription ? String(localized: "Renews") : String(localized: "Expected")
    }

    private func cadenceWord(_ days: Int?) -> String? {
        guard let days else { return nil }
        if days >= Subscriptions.yearlyFromDays { return String(localized: "Yearly") }
        if Subscriptions.monthlyDays.contains(days) { return String(localized: "Monthly") }
        return String(localized: "Every \(days) days")
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text(verbatim: label).dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: value).dsText(.body17).foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, DS.Space.s2)
        .frame(minHeight: AddressesSection.rowPitch)
        .accessibilityElement(children: .combine)
    }
}
