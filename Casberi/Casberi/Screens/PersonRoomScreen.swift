import SwiftUI
import SwiftData

/// The person room (item 2 of the 2026-07-27 social enrichment pass) —
/// everything Casberi holds about ONE person in one chronology: their own
/// posts. The onchain half — a Farcaster account's verified addresses and
/// their wallet's moves — went with the Farcaster seat (prd §1110).
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
    /// Your years with this person, when the corpus can describe them
    /// (2026-08-18, prd §396). X only: it is the one source here whose rows
    /// name somebody you never watched and never will be able to.
    @State private var xPerson: XPerson?
    @State private var loading = true
    @State private var sheetThing: Thing?

    /// How far the window has been opened, in `RowWindow` steps.
    ///
    /// **THE ROOM WAS UNBOUNDED, AND THIS SHEET IS WHERE BUILD 539 DIED (prd
    /// §657).** `posts` is every row the corpus holds about one person — an X
    /// archive lands 10,000 posts (§307) and a decade of conversation with one
    /// correspondent is a large fraction of them — and all of it was drawn into
    /// ONE `List` section, inside a sheet a finger can drag. `RowWindow`'s doc
    /// carries the stack; the short of it is that UIKit re-runs a sheet's whole
    /// `List` update synchronously on every drag offset, SwiftUI resolves each
    /// row's index by a linear walk, and backgrounded that render gets ~16% of
    /// a core against a ten-second wall.
    ///
    /// MONOTONIC for the life of the screen — the feed's own ruling
    /// (`FeedScreen.windowSteps`). It is a CAP, so a wider window still draws
    /// at most `budget` rows.
    @State private var windowSteps = 0

    private var shown: SocialProfile { loaded ?? profile }

    var body: some View {
        // ONE READ OF THE ROOM'S ARRAY FOR THE WHOLE BODY (prd §646's rule,
        // applied here for §657). `posts` holds raw model refs from a manual
        // fetch, so `.live` is its handoff guard (liveness corollary 4, build
        // 177). Bound once, then answered from: the rows, the opener and the
        // empty state all read this one value.
        let window = RowWindow.slice(posts.live, steps: windowSteps)
        return List {
            Section {
                header
                if let bio = shown.bio, !bio.isEmpty {
                    Text(bio)
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
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
                        .dsText(.subhead12)
                        .foregroundStyle(DS.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.s4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !loading && window.shown.isEmpty {
                Text("Nothing here yet.")
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
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
                RemoteThumb(urlString: avatar, size: DS.Face.shelf, fallback: profile.source, circular: true)
            } else {
                BridgeIcon(name: profile.source, size: DS.Face.shelf, circular: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(shown.title).dsText(.heading17).foregroundStyle(DS.textPrimary)
                Text("@\(shown.shortHandle) · \(profile.source)")
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, DS.Space.s2)
    }

    /// Their rhythm (item 8 of the 2026-07-27 polish pass) — a person you've
    /// watched for months has a shape: when they post, when they went quiet.
    /// The exact read `ContributionYear` already performs for
    /// GitHub and for the room itself, scoped down to one person's own
    /// `posts` instead of the whole room's `visible`. No new data, just a
    /// read — same 4-active-day floor `calendarHeatmapSection` uses, so a
    /// person with only a couple of posts doesn't draw a mostly-empty grid.
    @ViewBuilder private var cadenceSection: some View {
        // Fourteen weeks: a social feed is a rolling recent sample, so a full
        // year would be one bright smudge (the room registry this read its
        // width from was deleted in prd §832).
        let columns = 14
        let year = ContributionYear.from(dates: posts.map(\.capturedAt), columns: columns)
        if year.activeDays >= 4 {
            CalendarHeatmapHero(
                title: String(localized: "Their posting rhythm"),
                subtitle: "\(year.total.formatted()) \(year.total == 1 ? "post" : "posts")",
                year: year, minColumns: columns)
            .padding(.top, DS.Space.s1)
        }
    }

    private func row(for thing: Thing) -> some View {
        PostCard(thing: thing)
    }

    /// This person's own posts (a plain equality fetch — the
    /// `.contains`-on-array crash class doesn't apply, there's no array
    /// here), then their profile. The room works for anyone whose face you
    /// tapped, not only people you've formally watched.
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
        loaded = await SocialPeople.profile(handle: handle, source: src)
        loading = false
    }
}
