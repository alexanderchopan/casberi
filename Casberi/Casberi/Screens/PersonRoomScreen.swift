import SwiftUI
import SwiftData

/// The person room (item 2 of the 2026-07-27 social enrichment pass) —
/// everything Casberi holds about ONE person, joined into one chronology:
/// their own posts, and — for a Farcaster account with a verified onchain
/// address — their wallet's moves. Nowhere else in the app can put a
/// person's words beside their money.
///
/// The quick-glance `SocialProfileCard` tray keeps every entry point it
/// already has (a post's face, a reply, `casberi://person/…`) — this is the
/// fuller destination the social roster (item 5, `SocialRosterHero`) pushes
/// into. Deliberately additive: no existing sheet-presentation call site was
/// touched to build this, since each opens from a different view chain
/// (`SocialProfileCard`'s own doc comment notes several sit outside
/// `RootShell`'s environment) and migrating all of them is a separate,
/// riskier change from adding a new door.
struct PersonRoomScreen: View {
    let profile: SocialProfile
    @Environment(\.modelContext) private var modelContext

    @State private var loaded: SocialProfile?
    @State private var posts: [Thing] = []
    @State private var transactions: [Thing] = []
    @State private var verifiedAddresses: [String] = []
    @State private var loading = true
    @State private var sheetThing: Thing?
    @State private var filter: Filter = .all

    private enum Filter: String, CaseIterable {
        case all = "Everything", posts = "Posts", chain = "Onchain"
    }

    private var shown: SocialProfile { loaded ?? profile }

    /// Newest first, whichever slice the segmented picker asks for. Merging
    /// happens here (not at fetch time) so switching tabs never re-queries.
    private var merged: [Thing] {
        switch filter {
        case .all:   return (posts + transactions).sorted { $0.capturedAt > $1.capturedAt }
        case .posts: return posts
        case .chain: return transactions
        }
    }

    var body: some View {
        List {
            Section {
                header
                if let bio = shown.bio, !bio.isEmpty {
                    Text(bio)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                cadenceSection
                if !transactions.isEmpty {
                    filterPicker
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: DS.Space.s2, leading: DS.Space.s4,
                                 bottom: DS.Space.s2, trailing: DS.Space.s4))

            // A manual fetch, not a `@Query` — DERIVED, so `ForEach` keys off
            // `.keyed` and each row reads `$0.thing`, never the raw array's
            // own `Thing.id` (the ForEach-identity crash class, CLAUDE.md).
            ForEach(merged.keyed) { item in
                if item.thing.isLive {
                    row(for: item.thing)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init(top: DS.Space.s1, leading: DS.Space.s4,
                                             bottom: DS.Space.s1, trailing: DS.Space.s4))
                        .contentShape(Rectangle())
                        .onTapGesture { sheetThing = item.thing }
                }
            }

            if !loading && merged.isEmpty {
                Text("Nothing here yet.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .dsPageBackground()
        .scrollContentBackground(.hidden)
        .navigationTitle(shown.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetThing) { thing in ThingSheetView(thing: thing) }
        .task { await load() }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: DS.Space.s3) {
            if let avatar = shown.avatarURL, !avatar.isEmpty {
                RemoteThumb(urlString: avatar, size: 56, fallback: profile.source, circular: true)
            } else {
                BridgeIcon(name: profile.source, size: 56, circular: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(shown.title).dsText(.heading17).foregroundStyle(DS.textPrimary)
                Text("@\(shown.shortHandle) · \(profile.source)")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, DS.Space.s2)
    }

    /// Their rhythm (item 8 of the 2026-07-27 polish pass) — a person you've
    /// watched for months has a shape: when they post, when they went quiet.
    /// The exact read `FeedHeatmap`/`ContributionYear` already perform for
    /// GitHub and for the room itself, scoped down to one person's own
    /// `posts` instead of the whole room's `visible`. No new data, just a
    /// read — same 4-active-day floor `calendarHeatmapSection` uses, so a
    /// person with only a couple of posts doesn't draw a mostly-empty grid.
    @ViewBuilder private var cadenceSection: some View {
        let label = FeedHeatmap.label(for: profile.source)
        let columns = label?.columns ?? 14
        let year = ContributionYear.from(dates: posts.map(\.capturedAt), columns: columns)
        if year.activeDays >= 4 {
            CalendarHeatmapHero(
                title: label?.title ?? String(localized: "Their posting rhythm"),
                subtitle: label.map { FeedHeatmap.subtitle($0, total: year.total) }
                    ?? "\(year.total.formatted()) \(year.total == 1 ? "post" : "posts")",
                year: year, minColumns: columns)
            .padding(.top, DS.Space.s1)
        }
    }

    private var filterPicker: some View {
        Picker("", selection: $filter) {
            ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.top, DS.Space.s1)
    }

    @ViewBuilder
    private func row(for thing: Thing) -> some View {
        if thing.kind == .transaction {
            BandRow(thing: thing, moneyColumn: true)
        } else {
            PostCard(thing: thing)
        }
    }

    /// Two independent reads: this person's own posts (a plain equality
    /// fetch — the `.contains`-on-array crash class doesn't apply, there's
    /// no array here), and, for Farcaster, their verified addresses'
    /// transactions among things the wallet bridge already landed. Resolves
    /// addresses even for someone NOT in `FarcasterStore`'s watched list —
    /// the room works for anyone whose face you tapped, not only people
    /// you've formally watched.
    private func load() async {
        let handle = profile.handle
        let src = profile.source
        let postDescriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.authorHandle == handle && $0.source == src })
        posts = ((try? modelContext.fetch(postDescriptor)) ?? [])
            .sorted { $0.capturedAt > $1.capturedAt }

        async let profileFetch = SocialPeople.profile(handle: handle, source: src)

        if src == "Farcaster" {
            var addrs = FarcasterStore.shared.accounts
                .first(where: { $0.username == handle })?.verifiedAddresses ?? []
            if addrs.isEmpty, let fid = await FarcasterIngest.fid(forName: handle) {
                addrs = await FarcasterIngest.verifiedEthAddresses(fid: fid)
            }
            verifiedAddresses = addrs
            if !addrs.isEmpty {
                let addressSet = Set(addrs)
                // Same proven-safe shape `WalletScreen`/`WalletApprovals` use
                // (`source == "Wallet"`) — filtering to `.transaction` and
                // matching the address set happens in Swift after the fetch.
                let walletDescriptor = FetchDescriptor<Thing>(
                    predicate: #Predicate<Thing> { $0.source == "Wallet" })
                let landed = (try? modelContext.fetch(walletDescriptor)) ?? []
                transactions = landed.filter { t in
                    t.kind == .transaction &&
                        ((t.walletAddress.map { addressSet.contains($0.lowercased()) } ?? false)
                         || (t.counterpartyAddress.map { addressSet.contains($0.lowercased()) } ?? false))
                }.sorted { $0.capturedAt > $1.capturedAt }
            }
        }

        loaded = await profileFetch
        loading = false
    }
}
