import SwiftUI
import SwiftData

/// The catalog's prediction-market connect page (prd §234, amended 2026-07-29
/// — user: *"the connect page should be ONLY about connecting… it's like
/// yes or no. Do you wanna follow Kalshi prediction markets, or yes or no
/// do you wanna follow Polymarket prediction markets — also on both their
/// pages"*).
///
/// §234 already put the book, the browse, and every receipt in the ROOM
/// (`PredictionRoomBook`). This is the second half of that ruling reaching
/// the connect page itself: it had drifted into showing the room's button
/// ("Open the Kalshi room") and, before that, the Following/Resolved lists —
/// both are markets, and markets are the room's job. The connect page asks
/// exactly one thing, twice: follow this exchange's markets, yes or no.
///
/// **Both questions on both pages, by design.** It's the only place a
/// single-venue user learns the OTHER venue exists at all — the disagreement
/// between two independent crowds is the one comparison neither exchange's
/// own app can ever show, and today nothing in the catalog mentions it.
/// `ownVenue` only decides ORDER (this screen's own question leads); the
/// content and the wiring are identical either way, so `KalshiScreen` and
/// `PolymarketScreen` can't drift from each other.
struct PredictionVenueConnect: View {
    let ownVenue: PredictionSource

    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    /// Which venue's OFF-switch is mid-confirmation — at most one dialog at
    /// a time, so a single piece of state covers both rows.
    @State private var confirming: PredictionSource? = nil

    private var otherVenue: PredictionSource { ownVenue == .kalshi ? .polymarket : .kalshi }

    private func connected(_ v: PredictionSource) -> Bool {
        store.bridges.contains { $0.id == v.refPrefix && $0.status == .connected }
    }

    private func followedCount(_ v: PredictionSource) -> Int {
        let name = v.rawValue
        return (try? modelContext.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == name }))) ?? 0
    }

    /// The OTHER exchange's short differentiator — new information the
    /// header didn't already say (the header's blurb IS this screen's own
    /// venue's tagline, so repeating it on the own-venue row would be the
    /// exact redundancy `BridgeSetupHeader` was built to avoid).
    ///
    /// It says WHAT the other exchange is and stops there — the reason to
    /// keep both is the companion block's one job, and carrying a second
    /// half here ("— see where its odds differ") both duplicated it and
    /// wrapped this row to three lines.
    private func hint(_ v: PredictionSource) -> String {
        switch v {
        case .kalshi: String(localized: "CFTC-regulated event exchange")
        case .polymarket: String(localized: "Onchain, with real price history")
        }
    }

    var body: some View {
        Section {
            VStack(spacing: 0) {
                venueRow(ownVenue, subtitle: nil)
                venueRow(otherVenue, subtitle: hint(otherVenue))
            }
            .dsListCardRow()
            .listRowSeparator(.hidden)
            .confirmationDialog(confirmTitle, isPresented: Binding(
                get: { confirming != nil }, set: { if !$0 { confirming = nil } }
            ), titleVisibility: .visible) {
                if let v = confirming {
                    Button("Keep its things") { disconnect(v, purge: false) }
                    Button("Remove its things too", role: .destructive) { disconnect(v, purge: true) }
                    Button("Cancel", role: .cancel) { confirming = nil }
                }
            } message: {
                if let v = confirming {
                    Text(confirmMessage(v))
                }
            }
            companion
        } footer: {
            // One gray sentence for the whole screen (DSSlab's companion
            // rule) — the two venues' honesty notes collapsed into one,
            // rather than a paragraph per exchange.
            // Lede then detail (2026-07-31) — the promise steps up to the tier
            // the step lines use; the sourcing keeps the quiet one. Written
            // inline rather than as `BridgeFooterNote` because that component
            // IS a Section and this is a Section's own `footer:` closure.
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Read-only: nothing here ever places a trade.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No account, no key — both exchanges' odds are public.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Color.clear)
        }
    }

    private var confirmTitle: String {
        guard let v = confirming else { return "" }
        return String(localized: "Stop following \(v.rawValue)?")
    }

    private func confirmMessage(_ v: PredictionSource) -> String {
        let n = followedCount(v)
        return n == 0
            ? String(localized: "Its chip leaves your feed.")
            : (n == 1
               ? String(localized: "Its chip leaves your feed. The market you followed stays unless you remove it.")
               : String(localized: "Its chip leaves your feed. The \(n) markets you followed stay unless you remove them."))
    }

    @ViewBuilder
    private func venueRow(_ v: PredictionSource, subtitle: String?) -> some View {
        HStack(spacing: DS.Space.s3) {
            BridgeIcon(name: v.rawValue, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Follow \(v.rawValue) prediction markets")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Space.s2)
            Toggle("", isOn: Binding(
                get: { connected(v) },
                set: { on in on ? follow(v) : requestUnfollow(v) }
            ))
            .labelsHidden().tint(DS.tint)
        }
        .padding(.vertical, DS.Space.s2)
    }

    /// The card's ONE companion block, and the answer to *why both* — which
    /// nothing on this screen said until 2026-07-29 (the other venue's row
    /// carried "see where its odds differ" as a 13pt fragment, which reads
    /// as a description of that exchange, not as a reason to keep two).
    ///
    /// One slot, not two stacked wells: before you say yes it's the pitch,
    /// after it's the direction. The pitch is stated the way the room's own
    /// disagreement card behaves (prd §235) — the GAP is the fact, and it's
    /// never judged: no side called right, nothing suggesting a trade.
    private var companion: some View {
        let live = [ownVenue, otherVenue].filter(connected)
        // Both icons ONLY in the nothing-connected pitch, where the line
        // claims no strip and the pair is pure illustration. The moment one
        // venue is live these icons mean "this is in your feed strip", so
        // showing the OFF venue's icon beside that sentence would be status
        // it hasn't earned.
        let icons = live.isEmpty ? [ownVenue, otherVenue] : live
        return HStack(alignment: .top, spacing: DS.Space.s3) {
            HStack(spacing: -6) {
                ForEach(icons, id: \.self) { v in
                    BridgeIcon(name: v.rawValue, size: 22, circular: true)
                        .overlay(Circle().strokeBorder(DS.gray100, lineWidth: 1.5))
                }
            }
            Text(companionLine(live))
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.s3)
        .background(DS.surfaceWell, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.top, DS.Space.s1)
        .dsListCardRow()
        // Design law: no hairlines, zero exceptions — a second row in this
        // Section otherwise draws the List's own separator above it.
        .listRowSeparator(.hidden)
    }

    /// Plain by ruling (user, 2026-07-29: *"clear and direct and eli5"* —
    /// the first draft was five wrapped lines of argument, the second still
    /// too flowery). Short sentences, full stops instead of em-dashes, and
    /// the reason stated as the concrete thing you GET ("two prices for the
    /// same question"), never as a claim about crowds or reads.
    ///
    /// That one phrase is repeated verbatim across the two unfinished
    /// states on purpose: it's the whole answer to *why both*, and a person
    /// meets it in whichever state they land in.
    private func companionLine(_ live: [PredictionSource]) -> String {
        switch live.count {
        case 2:
            let names = live.map(\.rawValue).joined(separator: " and ")
            return String(localized: "\(names) are both in your feed strip. Tap a chip to browse markets. When the two prices differ, you'll see by how much.")
        case 1:
            let missing = live[0] == ownVenue ? otherVenue : ownVenue
            return String(localized: "\(live[0].rawValue) is in your feed strip. Tap its chip to browse markets. Add \(missing.rawValue) to see two prices for the same question.")
        default:
            return String(localized: "Follow both to see two prices for the same question.")
        }
    }

    private func follow(_ v: PredictionSource) {
        DSHaptic.tap()
        registerPredictionBridge(source: v.rawValue, id: v.refPrefix, store: store, context: modelContext)
    }

    /// A switched-off toggle is a disconnect, so it asks what disconnect
    /// asks (`BridgeDisconnectSection`'s own keep-or-purge choice) rather
    /// than silently dropping markets already followed — it just doesn't
    /// `dismiss()`, since this page never leaves when a switch flips off
    /// (there is a second, still-live question sitting right beside it).
    private func requestUnfollow(_ v: PredictionSource) {
        confirming = v
    }

    private func disconnect(_ v: PredictionSource, purge: Bool) {
        if purge {
            let name = v.rawValue
            let doomed = ((try? modelContext.fetch(FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> { $0.source == name }))) ?? [])
            SpotlightIndex.remove(ids: doomed.map(\.id))
            for thing in doomed { modelContext.delete(thing) }
            modelContext.saveHonestly()
        }
        store.remove(v.refPrefix)
        DSHaptic.tap()
        confirming = nil
    }
}
