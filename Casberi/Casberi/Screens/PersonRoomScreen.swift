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
    /// Your years with this person, when the corpus can describe them
    /// (2026-08-18, prd §396). X only: it is the one source here whose rows
    /// name somebody you never watched and never will be able to.
    @State private var xPerson: XPerson?
    @State private var loading = true
    @State private var sheetThing: Thing?
    @State private var filter: Filter = .all

    /// How far the window has been opened, in `RowWindow` steps.
    ///
    /// **THE ROOM WAS UNBOUNDED, AND THIS SHEET IS WHERE BUILD 539 DIED (prd
    /// §657).** `merged` is every row the corpus holds about one person — an X
    /// archive lands 10,000 posts (§307) and a decade of conversation with one
    /// correspondent is a large fraction of them — and all of it was drawn into
    /// ONE `List` section, inside a sheet a finger can drag. `RowWindow`'s doc
    /// carries the stack; the short of it is that UIKit re-runs a sheet's whole
    /// `List` update synchronously on every drag offset, SwiftUI resolves each
    /// row's index by a linear walk, and backgrounded that render gets ~16% of
    /// a core against a ten-second wall.
    ///
    /// MONOTONIC for the life of the screen, and it deliberately does NOT reset
    /// when `filter` changes — the feed's own ruling (`FeedScreen.windowSteps`):
    /// a window that collapses under the person would undo their scrolling
    /// every time they glanced at the Onchain slice. It is a CAP, so a wider
    /// window still draws at most `budget` rows of whichever slice is showing.
    @State private var windowSteps = 0

    /// The merged, sorted room — built when its INPUTS change, not on every
    /// body pass (`/code-review` finding, 2026-09-08, prd §657).
    ///
    /// `merged` concatenates two arrays, filters both `.live` and sorts the
    /// result on `capturedAt`. Sorting is n log n COMPARISONS, each one a
    /// stored-property read on a live SwiftData model — at the ten thousand
    /// rows an X archive lands (§307) that is well over a hundred thousand
    /// property accesses, and a body evaluation is exactly what a sheet drag
    /// causes per offset change. So `RowWindow` bounded the term SwiftUI
    /// spends (the list diff, now constant) and left this one growing with the
    /// corpus on the very same path. Both terms are bounded now: this is
    /// rebuilt on the three events that can change it (each fetch landing, and
    /// a filter change), and the body reads it.
    ///
    /// HELD RAW MODEL REFS, so `.live` is spelled AT THE HANDOFF in `body`
    /// (liveness corollary 4, build 177): a delete-sync heal can tombstone a
    /// row while this room is open, and the cache is deliberately behind the
    /// store between rebuilds.
    @State private var mergedRows: [Thing] = []

    private enum Filter: String, CaseIterable {
        case all = "Everything", posts = "Posts", chain = "Onchain"
    }

    private var shown: SocialProfile { loaded ?? profile }

    /// Newest first, whichever slice the segmented picker asks for. Merging
    /// happens here (not at fetch time) so switching tabs never re-queries.
    private var merged: [Thing] {
        // `.live` at the boundary (build 177's lesson): `posts` and
        // `transactions` are @State-held raw refs from a manual fetch, so a
        // delete-sync heal can tombstone one while this room is open — and
        // `.all` reads `capturedAt` off them right here, to sort. Spelled out
        // per branch rather than shadowed once above: a shadowing rebind hides
        // the guard from the liveness audit, which reads these lines.
        switch filter {
        case .all:   return (posts.live + transactions.live)
                        .sorted { $0.capturedAt > $1.capturedAt }
        case .posts: return posts.live
        case .chain: return transactions.live
        }
    }

    var body: some View {
        // ONE READ OF THE ROOM'S ARRAY FOR THE WHOLE BODY (prd §646's rule,
        // applied here for §657). `mergedRows` is the memoised merge — see its
        // own note for why the sort must not run per body pass — and `.live`
        // is its handoff guard. Bound once, then answered from: the rows, the
        // opener and the empty state all read this one value.
        let window = RowWindow.slice(mergedRows.live, steps: windowSteps)
        return List {
            Section {
                header
                if let bio = shown.bio, !bio.isEmpty {
                    Text(bio)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let xPerson {
                    // X's own head, in place of the rhythm grid below
                    // (2026-08-18, prd §396). `FeedHeatmap.label(for: "X")`
                    // is "Your X year", which titles a ROOM and would be a
                    // wrong sentence over one person — and a trailing-twelve-
                    // months grid over a relationship that ended in 2019 is
                    // an empty square. The card says the span instead.
                    XPersonCard(person: xPerson, handle: profile.handle)
                        .padding(.top, DS.Space.s1)
                } else {
                    cadenceSection
                }
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
            ForEach(window.shown.keyed) { item in
                if item.thing.isLive {
                    row(for: item.thing)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init(top: DS.Space.s1, leading: DS.Space.s4,
                                             bottom: DS.Space.s1, trailing: DS.Space.s4))
                        .contentShape(Rectangle())
                        .onTapGesture { sheetThing = item.thing }
                        .dsTapCard()
                }
            }

            // A TAP, never an appearance trigger — the feed's `olderRow`
            // records the measurement: `List` realizes rows ahead of the
            // viewport, so growing on `.onAppear` re-renders, appears again and
            // runs away. A tap fires once per request and cannot feed its own
            // trigger.
            if window.more {
                Button {
                    // Silent unless this presentation carries a listener —
                    // `DSHaptic` is a counter bump on a shared bus and the
                    // mapping is a VIEW modifier, so a sheet covers the one
                    // `RootShell` mounts. The `.person` route attaches
                    // `DSHapticSink` for exactly this call (`Haptics.swift`,
                    // and `RootShell.rootPresented`'s own note); PUSHED, this
                    // room is already under the shell's copy.
                    DSHaptic.tap()
                    withAnimation(DS.Motion.standard) { windowSteps += 1 }
                } label: {
                    Text("Show older")
                        .dsText(.subhead13)
                        .foregroundStyle(DS.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.s4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !loading && window.shown.isEmpty {
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
        // The picker swaps WHICH rows are merged, so the cache is rebuilt —
        // `windowSteps` deliberately is not reset (see its own note).
        .onChange(of: filter) { _, _ in mergedRows = merged }
        .task { await load() }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: DS.Space.s3) {
            if let avatar = shown.avatarURL, !avatar.isEmpty {
                RemoteThumb(urlString: avatar, size: DS.Face.shelf, fallback: profile.source, circular: true)
            } else {
                BridgeIcon(name: profile.source, size: DS.Face.shelf, circular: true)
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
        // X JOINS DIFFERENTLY, and it has to (2026-08-18, prd §396). The
        // equality fetch below asks "what did they write", which for every
        // network here is the whole of what the corpus holds about somebody.
        // An X archive is YOUR side: their handle sits on `parent` for a reply
        // you sent, inside the words of a post that names them, and on
        // `authorHandle` only for the posts of theirs you liked — so an
        // `authorHandle` fetch would answer with the likes alone and miss the
        // decade of conversation, which is the reading this room exists for.
        //
        // One unscoped fetch of the room, narrowed in Swift: `parent` is a
        // transformable attribute and a `#Predicate` cannot reach inside one,
        // and a `.contains` on an array attribute CRASHES at runtime inside
        // CoreData (CLAUDE.md's own note). It runs once per screen open.
        if src == XPersonSource.source {
            let descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> { $0.source == "X" })
            let room = (try? modelContext.fetch(descriptor)) ?? []
            posts = XPersonSource.rows(room, handle: handle)
            xPerson = XPersonSource.compose(room, handle: handle)
        } else {
            let postDescriptor = FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> { $0.authorHandle == handle && $0.source == src })
            posts = ((try? modelContext.fetch(postDescriptor)) ?? [])
                .sorted { $0.capturedAt > $1.capturedAt }
        }
        // Draw what we have before the awaits below — the posts are the room
        // for every source but Farcaster, and this is where they used to
        // appear when the body merged for itself.
        mergedRows = merged

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
                mergedRows = merged
            }
        }

        loaded = await profileFetch
        loading = false
    }
}
