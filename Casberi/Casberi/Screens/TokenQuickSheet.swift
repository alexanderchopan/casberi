import SwiftUI
import SwiftData

/// A tapped holdings cell (2026-07-14). Cells whose token is already on the
/// watchlist open their thing sheet — this route covers the rest: the same
/// native chart, its identity resolved live, and one real verb (Watch) so a
/// holding you keep tapping is one tap from joining the watchlist. Ink like
/// the thing sheet — it IS a token read, just for a token that isn't a
/// thing yet.
struct TokenQuickRoute: Identifiable, Equatable {
    let chain: String
    let address: String
    /// The ticker the holdings cell already knew, carried through so the
    /// sheet names the token before (and without) a live resolve. Never
    /// part of `id` — identity is chain+address alone.
    var symbol: String? = nil
    /// Which watched wallets hold this token, biggest stake first (2026-07-21,
    /// prd §155) — carried in from the COMBINED treemap, whose merged cells
    /// would otherwise lose the "whose is it" the per-wallet maps got for free.
    /// Empty everywhere else; never part of `id` — identity is chain+address.
    var holders: [WalletPortfolio.Holder] = []
    var id: String { "\(chain):\(address.lowercased())" }

    func withHolders(_ holders: [WalletPortfolio.Holder]) -> TokenQuickRoute {
        var copy = self
        copy.holders = holders
        return copy
    }

    /// Parses a GenTagMap cell's "@token:chain:address[:symbol]" sentinel, or nil.
    static func from(sentinel name: String) -> TokenQuickRoute? {
        guard name.hasPrefix("@token:") else { return nil }
        let parts = name.dropFirst("@token:".count)
            .split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        let symbol = parts.count >= 3 && !parts[2].isEmpty ? parts[2] : nil
        return TokenQuickRoute(chain: parts[0], address: parts[1], symbol: symbol)
    }

    /// The watched thing this route points at, when the token is on the
    /// watchlist — the shared half of every holdings-cell tap handler
    /// (Home, Feed, Wallet), so the watched-vs-held decision and the
    /// "tokens:" ref format live in exactly one place.
    @MainActor
    func watchedThing(in context: ModelContext) -> Thing? {
        let ref = "tokens:\(id)"
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        d.fetchLimit = 1
        return ((try? context.fetch(d)) ?? []).first
    }
}

struct TokenQuickSheet: View {
    let route: TokenQuickRoute
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    /// Resolved identity, live from the same search that powers watching.
    @State private var resolved: TokenWatch.Resolved?
    @State private var watchedTitle: String?
    @State private var washPoured = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.Space.s2) {
                    BridgeIcon(name: "Tokens", size: 18, circular: true)
                    Text("Token · held in a watched wallet")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s6)
                Text(headerTitle)
                    .dsText(.heading34).foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s3)
                TokenChartView(chain: route.chain, address: route.address) {
                    // No pool anywhere (dead/illiquid) — say so; the door out
                    // is the explorer link, honestly labeled.
                    if let url = URL(string: "https://dexscreener.com/\(route.chain)/\(route.address)") {
                        Link(destination: url) {
                            HStack(spacing: DS.Space.s2) {
                                Text("No live price for this token — view on Dexscreener")
                                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DS.textTertiary)
                            }
                            .padding(DS.Space.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.fillFaint,
                                        in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                             style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s3)
                heldInSection
                watchRow
                    .padding(.top, DS.Space.s6)
            }
            .padding(.bottom, DS.Space.s6)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            // The thing sheet's own wash, in Tokens' hue — same recipe.
            if let hue = DS.washHue(for: "Tokens") {
                LinearGradient(stops: [
                    .init(color: hue, location: 0),
                    .init(color: hue, location: 0.3),
                    .init(color: hue.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 300)
                    .opacity(washPoured ? 1 : 0)
                    .offset(y: washPoured ? 0 : -140)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .onAppear {
                        if reduceMotion { washPoured = true } else {
                            withAnimation(.easeOut(duration: 0.35).delay(0.05)) {
                                washPoured = true
                            }
                        }
                    }
            }
        }
        .dsInk()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
        .task {
            // The address IS the query — but the SAME address can be a
            // different token on another chain (the OP-stack WETH predeploy,
            // bridged deployments), so only the hit on this cell's own chain
            // counts. No chain match → no identity and no Watch verb; the
            // chart still draws (honest: we know the route, not the name).
            resolved = await TokenWatch.search(route.address)
                .first { $0.id == route.id }
        }
    }

    private var shortAddress: String { WalletStore.shortAddress(route.address) }

    /// A live resolve gives us `Name · $SYMBOL`; before it lands we still
    /// show the ticker the holding carried in; only a token with neither
    /// (no cell symbol, unresolved) falls back to the short address.
    private var headerTitle: String {
        if let resolved { return "\(resolved.name) · $\(resolved.symbol)" }
        if let symbol = route.symbol { return "$\(symbol)" }
        return shortAddress
    }

    /// "Held in" — which watched wallets hold this token, in their own face
    /// colors (2026-07-21, prd §155). Only with MORE THAN ONE holder: naming
    /// the single wallet a position sits in says nothing the screen you tapped
    /// from didn't already say.
    @ViewBuilder private var heldInSection: some View {
        if route.holders.count > 1 {
            // The room's shared row anatomy (prd §212) — same face mark, same
            // rounded title, same trailing money as the wallet feed's own
            // rows, so a holding read here and a holding read there are
            // visibly the same kind of statement.
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                WalletSectionLabel(title: String(localized: "Held in"))
                ForEach(route.holders) { holder in
                    WalletRow(mark: .face(holder.address), title: holder.label) {
                        WalletRowValue(value: TokenStats.compact(holder.usd))
                    }
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s6)
        }
    }

    /// One real verb: Watch. Once it lands (or the token was already
    /// watched), the row states the fact instead — never a dead control.
    @ViewBuilder private var watchRow: some View {
        if let watchedTitle {
            HStack(spacing: DS.Space.s4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.confirm)
                    .frame(width: 26, alignment: .center)
                Text("Watching \(watchedTitle)")
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s4)
        } else if let resolved {
            Button {
                DSHaptic.tap()
                if let thing = TokenWatch.add(resolved, context: modelContext) {
                    DSHaptic.success()
                    watchedTitle = thing.title
                    TokenWatch.registerBridge(store: store, context: modelContext)
                } else {
                    watchedTitle = "\(resolved.name) · $\(resolved.symbol)"
                }
            } label: {
                HStack(spacing: DS.Space.s4) {
                    Image(systemName: "eye")
                        .font(.system(size: 18))
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 26, alignment: .center)
                    Text("Watch this token")
                        .dsText(.heading17).foregroundStyle(DS.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
