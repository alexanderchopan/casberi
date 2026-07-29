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
    private func hint(_ v: PredictionSource) -> String {
        switch v {
        case .kalshi: String(localized: "CFTC-regulated event exchange — see where its odds differ")
        case .polymarket: String(localized: "Onchain, with real price history — see where its odds differ")
        }
    }

    var body: some View {
        Section {
            VStack(spacing: 0) {
                venueRow(ownVenue, subtitle: nil)
                venueRow(otherVenue, subtitle: hint(otherVenue))
            }
            .dsListCardRow()
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
            if connected(ownVenue) || connected(otherVenue) {
                teach
            }
        } footer: {
            // One gray sentence for the whole screen (DSSlab's companion
            // rule) — the two venues' honesty notes collapsed into one,
            // rather than a paragraph per exchange.
            Text("No account, no key — both exchanges' odds are public. Read-only: nothing here ever places a trade.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
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
            : String(localized: "Its chip leaves your feed. The \(n) market\(n == 1 ? "" : "s") you followed \(n == 1 ? "stays" : "stay") unless you remove \(n == 1 ? "it" : "them").")
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

    /// Taught only once at least one venue is live — pointing at the actual
    /// chip(s) in the actual strip, rather than naming a destination with a
    /// word ("room") that exists nowhere else a person can read.
    private var teach: some View {
        let live = [ownVenue, otherVenue].filter(connected)
        let names = live.map(\.rawValue).joined(separator: " and ")
        return HStack(alignment: .top, spacing: DS.Space.s3) {
            HStack(spacing: -6) {
                ForEach(live, id: \.self) { v in
                    BridgeIcon(name: v.rawValue, size: 22, circular: true)
                        .overlay(Circle().strokeBorder(DS.gray100, lineWidth: 1.5))
                }
            }
            Text(live.count > 1
                 ? "\(names) are both in your feed strip — tap a chip to browse every open market and follow the ones you want."
                 : "\(names) is in your feed strip — tap its chip to browse every open market and follow the ones you want.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.s3)
        .background(DS.surfaceWell, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.top, DS.Space.s1)
        .dsListCardRow()
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
