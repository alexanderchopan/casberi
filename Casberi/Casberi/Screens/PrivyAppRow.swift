import SwiftUI

/// A Privy app wallet in the feed (prd §803e) — the mockup's row: the app's
/// own logo, when you last used it, and what its wallet holds.
///
/// ONE ANATOMY (prd §744): the logo is the 26pt lead, the money trails the
/// title at `price17` (§764), and the line says what the lead cannot. The app's
/// facts come from `PrivyHomeStore` by the row's ref — a dictionary lookup,
/// never a walk (§626). An app not read yet trails its time instead of a
/// figure it does not have (§83).
///
/// Guards its own body: a leaf re-evaluates on the model's own observation
/// (corollary 5).
struct PrivyAppRow: View {
    let thing: Thing
    /// A cross-source room (All, Pinned) names the source on the line.
    var sourceBadge = false

    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        let store = PrivyHomeStore.shared
        let ref = thing.sourceRef ?? ""
        let app = store.byRef[ref]
        let usd = store.usd(ref)
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil

        DSFeedRow(name: app?.name ?? thing.title, nameLines: 1,
                  line: DSFeed.line(sourceBadge ? PrivyHomeFeed.source : nil,
                                    PrivyHomeFeed.lastUsed(app?.lastActiveAt, now: .now)
                                        ?? app.map(PrivyHomeFeed.line) ?? thing.content)) {
            PrivyAppMark(logoURL: app?.logoURL)
        } trailing: {
            if let usd, usd >= PrivyHomeFeed.fundedFloor {
                Text(verbatim: mask ?? PrivyHomeFeed.usd(usd))
                    .dsText(.price17)
                    .monospacedDigit()
                    .foregroundStyle(DS.textPrimary)
            } else {
                LiveTimeText(date: thing.capturedAt)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken(app, usd: usd, mask: mask)))
    }

    private func spoken(_ app: PrivyHomeFeed.App?, usd: Double?, mask: String?) -> String {
        let name = app?.name ?? thing.title
        let used = PrivyHomeFeed.lastUsed(app?.lastActiveAt, now: .now)
        let money = usd.flatMap { $0 >= PrivyHomeFeed.fundedFloor ? (mask ?? PrivyHomeFeed.usd($0)) : nil }
        return [name, money, used].compactMap { $0 }.joined(separator: ", ")
    }
}
