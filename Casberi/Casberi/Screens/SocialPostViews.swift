import SwiftUI
import SwiftData

/// The social post's own read (2026-07-16) — what a cast/post shows once it's
/// more than a row. Before this, a post's sheet rendered its `content` through
/// the chat path, and a post's content is its PERMALINK: the sheet showed a URL
/// in a speech bubble, and the words of anything longer than the 80-character
/// title were simply absent from the app.
///
/// The words themselves are the sheet's HERO (ThingSheetView draws `postText`
/// in the title slot — a post is prose, and prose is the point). What's left is
/// everything around them: the pictures, the post it quotes, and how it landed.
/// Source-neutral throughout — Bluesky and Farcaster answer the same shapes, so
/// nothing here learns a network's name.
struct SocialPostContent: View {
    let thing: Thing

    /// The counts, the likers and the provenance sentence LEFT this view on
    /// 2026-08-12 (prd §363) for `SocialReceptionCard`, which the sheet draws
    /// below the words. Three reasons, and the third is the real one:
    ///
    /// - they were three glyph-led monospace numbers UNDER the photos, i.e.
    ///   the least prominent thing on a screen opened to read exactly them;
    /// - the likers roll (§330) rendered in the feed row and not here at all,
    ///   so the sheet you opened to find out who liked your post was the one
    ///   surface that wouldn't say;
    /// - this view is reached only for a post that HAS a body to draw, and the
    ///   reception is true of every social shape — a save, a follower, an
    ///   archived like. Owning it here would have meant three copies.
    ///
    /// What is left is what a post's body actually is: its pictures, and the
    /// post it quotes.
    private var images: [String] {
        // Posts landed before `imageURLs` existed carry only the row's single
        // thumb — show that rather than nothing, until a refresh heals them.
        thing.imageURLs.isEmpty
            ? [thing.previewImageURL].compactMap { $0 } : thing.imageURLs
    }

    var body: some View {
        // A CHILD of ThingSheetView (whose init/body guard the deleted-model
        // case) — but SwiftUI can re-render a child on the model's own
        // observation before the parent re-evaluates its guard, so this reads
        // `thing`'s stored props (likeCount, imageURLs, quote…) independently.
        // Bluesky/Farcaster run their OWN foreground delete-sync heals that can
        // remove an open post, so guard here too: reading a tombstoned model's
        // stored property traps (2026-07-24). `isLive` is safe on a tombstone.
        if !thing.isLive {
            Color.clear
        } else {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            photos
            if let quote = thing.quote {
                SocialQuoteCard(card: quote, source: thing.source)
            }
            if let rest = SocialSheet.threadRest(enriched: thing.enrichedText,
                                                 words: SocialSheetSource.words(for: thing),
                                                 count: thing.messageCount) {
                SocialThreadRest(parts: rest, total: thing.messageCount ?? 0)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        }
    }

    /// One picture fills the width, the way a screenshot's does — it IS the
    /// post. Several ride a strip that scrolls sideways inside its own lane, so
    /// a four-photo post keeps all four and the page never scrolls horizontally.
    @ViewBuilder private var photos: some View {
        if images.isEmpty, let data = thing.previewImageData,
           let stored = UIImage(data: data) {
            // A picture the app already HOLDS rather than fetches (prd §363,
            // catching the sheet up with `PostCard`'s own 2026-08-06 fix). An
            // IMPORT has no URL to give — `ImportMedia` decodes the archive's
            // file to a thumbnail inside the folder grant, because there is no
            // second chance at a folder somebody has stopped granting — so an
            // X post's picture is BYTES, and every branch below asks for a URL.
            // The §283 failure exactly: pixels stored, never drawn.
            Image(uiImage: stored)
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                // A poster frame is a still, and this is the largest a stored
                // one is ever drawn (2026-08-18, prd §396) — so it is the one
                // place a video passing for a photograph misleads most. There
                // is no player: the archive folder is a temporary scoped pick
                // and the mp4 is not ours to keep, which is why the mark is
                // cornered and the door is the sheet's own "On X" verb.
                .overlay(alignment: .bottomLeading) {
                    if thing.tags.contains("Video") {
                        VideoMark(size: 26).padding(DS.Space.s2)
                    }
                }
        } else if images.count == 1 {
            SocialPhoto(urlString: images[0], height: 280)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if images.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(images, id: \.self) { url in
                        SocialPhoto(urlString: url, height: 200, width: 200)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// THE REST OF A SELF-THREAD (prd §363) — the posts that continued the one
/// you're reading, under it, in reading type.
///
/// A quiet card rather than the post's own display tier: these are the same
/// person still talking, so they are the post's continuation, not four more
/// posts competing with it. The count is the archive's own
/// (`Thing.messageCount`) and it counts the WHOLE chain, head included, which
/// is why the header says "N posts" rather than numbering what's drawn.
///
/// Liveness: holds plain strings, sliced off a live model by the caller, so
/// there is no model here to tombstone.
struct SocialThreadRest: View {
    let parts: [String]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("The rest of the thread · \(total) posts")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(ProseLinks.rendered(part))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

/// A post's picture at reading size — RemoteImageLoader does the fetch, decode,
/// and downsample (a wall of full-res post images would otherwise decode at
/// display size on every pass). A dead URL renders nothing rather than a gray
/// hole: no image is better than a broken one (the RemoteThumb ruling).
struct SocialPhoto: View {
    let urlString: String
    var height: CGFloat
    var width: CGFloat? = nil
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Color.clear
                    .frame(width: width, height: height)
                    .overlay(Image(uiImage: image).resizable().scaledToFill())
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            } else if !failed {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.fillFaint)
                    .frame(width: width, height: height)
            }
        }
        .task(id: urlString) { await load() }
    }

    private func load() async {
        // The strip renders at most 280pt; ask for 2× that in pixels so it
        // stays sharp on a 3× screen without holding a full-res decode.
        switch await RemoteImageLoader.load(urlString: urlString, targetSide: 560) {
        case .image(let ui, _): image = ui
        case .dead:             failed = true
        case .transientFailure: break   // retry on the next appearance
        }
    }
}

/// The post this post QUOTES — both networks' signature form, dropped at ingest
/// until 2026-07-16, so a quote-post read as a bare, contextless line. A
/// recessed card inside the body: a smaller face, the handle, the words. In
/// the SHEET a tap walks into it in-app (its own thread, its own quote); in a
/// feed row it is a read with no door of its own — see `walkable`.
struct SocialQuoteCard: View {
    let card: SocialCard
    let source: String
    /// Whether the card is a DOOR (the sheet) or just context (a feed row).
    ///
    /// A walkable card carries its own `.sheet` presentation. That is correct
    /// inside `ThingSheetView`, which is already a presented sheet with its
    /// own presentation context — and wrong inside a `List` row, where the
    /// modifier competes with `FeedScreen`'s single `.sheet(item: $feedSheet)`
    /// for the same presenting controller and tears the thing sheet back down
    /// mid-transition (see `ReplyingToRow` for the whole diagnosis; the same
    /// 2026-07-27 pass grew both). In a row the quote stays a read: the row's
    /// one tap opens the thing, and the walk is a tap away inside it.
    var walkable = true
    @State private var walking = false

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                if let avatar = card.avatarURL {
                    RemoteThumb(urlString: avatar, size: DS.Face.badge, fallback: source, circular: true)
                } else {
                    BridgeIcon(name: source, size: DS.Face.badge, circular: true)
                }
                Text("@\(SocialThread.shortHandle(card.handle))")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                Spacer(minLength: 0)
            }
            Text(card.text)
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                // A quote is context, not the point — it shows enough to
                // know what's being answered and stops. The tap has the rest.
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s3)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    var body: some View {
        if walkable {
            Button { walking = true } label: { cardBody }
                .buttonStyle(.plain)
                .sheet(isPresented: $walking) {
                    SocialPostSheet(post: card, source: source)
                }
        } else {
            // No tap target of its own — the row's tap owns the whole card.
            cardBody.allowsHitTesting(false)
        }
    }
}

// `SocialEngagementLine` — the glyph-led monospace row of three counts that
// lived here from 2026-07-16 — was DELETED on 2026-08-12 (prd §363), not
// deprecated: `SocialReceptionCard` states the same numbers with their nouns
// written out, above the fold, beside the likers' names. Two views drawing one
// fact is how a screen starts contradicting itself, and `BridgeFooterNote`'s
// ruling stands — a replaced component goes, or it comes back under a new
// name. Its honesty rule came with it: a count the network didn't report has
// no cell, because an absent number and a reported zero are different facts.

/// A post opened IN-APP (2026-07-16) — the thread walker. Tapping a reply used
/// to kick you to the browser, which ended the session in Casberi and made the
/// Replies section a preview of somewhere else. Now a reply, or a quoted post,
/// opens here: its face, its words, its own replies — and those push again, so
/// a conversation can be walked as deep as it goes without leaving.
///
/// A walked post is NOT a thing: it isn't in the corpus, it earns no row, and
/// nothing about it is saved. It's a read, which is why it needs no consent —
/// the same standing the Replies section already had.
struct SocialPostSheet: View {
    let post: SocialCard
    let source: String
    /// The walk. The stack owns it, so every post in the thread — however deep
    /// — pushes onto the same path and the back chevron unwinds it.
    @State private var path: [SocialCard] = []

    var body: some View {
        NavigationStack(path: $path) {
            SocialPostThread(post: post, source: source, open: { path.append($0) })
                .navigationDestination(for: SocialCard.self) { card in
                    SocialPostThread(post: card, source: source, open: { path.append($0) })
                }
        }
        .presentationDetents([.medium, .large])
        .dsMacPageSheet()
        .presentationDragIndicator(.visible)
        .dsSheetCorner()
        .dsInk()
    }
}

/// One post in the walker: who, the words, its replies. The ink ground paints
/// INSIDE the scroll container — a layer behind a NavigationStack never shows
/// through its opaque backing (the gotcha this codebase already paid for).
struct SocialPostThread: View {
    let post: SocialCard
    let source: String
    /// Where a tapped reply goes — the enclosing stack pushes it.
    var open: (SocialCard) -> Void
    @State private var replies: [SocialReply] = []
    @State private var profile: SocialProfile?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Button {
                    profile = SocialProfile(source: source, handle: post.handle,
                                            displayName: nil, bio: nil,
                                            avatarURL: post.avatarURL)
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        if let avatar = post.avatarURL {
                            RemoteThumb(urlString: avatar, size: DS.Face.row, fallback: source,
                                        circular: true)
                        } else {
                            BridgeIcon(name: source, size: DS.Face.row, circular: true)
                        }
                        Text("@\(SocialThread.shortHandle(post.handle))")
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(post.text)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = post.url.flatMap(URL.init) {
                    Button { openURL(url) } label: {
                        Text("Open on \(source)")
                            .dsText(.callout15).foregroundStyle(DS.tint)
                    }
                    .buttonStyle(.plain)
                }
                if !replies.isEmpty {
                    SocialRepliesSection(replies: replies, source: source, open: open)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        // The ink GROUND, not black: this is the pushed destination, whose
        // `presentationBackground` stopped applying the moment it was pushed,
        // so it repaints the ground itself — and since 2026-08-12 that ground
        // follows the theme.
        .background(DS.inkGround)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $profile) { p in
            SocialProfileCard(profile: p)
        }
        .task {
            guard let ref = post.ref else { return }
            replies = await SocialThread.replies(source: source, ref: ref, handle: post.handle)
        }
    }
}

/// The conversation under a post — read-only context in the spec table's quiet
/// clothes: a face, the handle, the words. The header counts the thread
/// ("Replies · 8"), the rows arrive one after another (the feed's stagger). A
/// tap on a reply WALKS INTO it (2026-07-16, was: opened the browser); a tap on
/// its face opens the person. Shared by the thing sheet and the walker, so a
/// reply reads the same however deep you are.
struct SocialRepliesSection: View {
    let replies: [SocialReply]
    let source: String
    /// Where a tapped reply goes. The thing sheet opens the walker; the walker
    /// pushes onto its own stack. The section doesn't know or care which.
    var open: (SocialCard) -> Void
    @State private var profile: SocialProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // Honest count: the fetch caps at replyCap, so a thread AT the cap
            // may hold more — say "8+", never a false total (honesty rule).
            Text(replies.count < SocialThread.replyCap
                 ? "Replies · \(replies.count)"
                 : "Replies · \(replies.count)+")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            ForEach(Array(replies.enumerated()), id: \.element.id) { i, reply in
                row(reply).staggerIn(index: min(i, 8))
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .sheet(item: $profile) { p in
            SocialProfileCard(profile: p)
        }
    }

    @ViewBuilder
    private func row(_ reply: SocialReply) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            avatarButton(reply)
            // The words open the reply's own thread. A reply with no protocol
            // ref (nothing to read a thread by) stays plain text rather than
            // wearing a tap that would go nowhere — no dead controls.
            if reply.ref != nil {
                Button { open(reply.card) } label: { words(reply) }
                    .buttonStyle(.plain)
            } else {
                words(reply)
            }
            Spacer(minLength: 0)
        }
    }

    /// The face — tappable into the profile card only for the sources it
    /// actually supports (Watch, "elsewhere" search). GitHub's comment
    /// thread rides this same section (2026-07-16) but isn't a social
    /// source (`SocialThread.isSocial`); its avatar stays a plain icon
    /// rather than opening a card whose only verb (Watch) can never
    /// succeed and would flash a fabricated "Already watching" (honesty
    /// rule — no dead controls, no fake status).
    @ViewBuilder
    private func avatarButton(_ reply: SocialReply) -> some View {
        if SocialThread.isSocial(source) {
            Button {
                profile = SocialProfile(source: source, handle: reply.handle,
                                        displayName: nil, bio: nil, avatarURL: reply.avatarURL)
            } label: { avatarIcon(reply) }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open profile for \(reply.handle)"))
        } else {
            avatarIcon(reply)
        }
    }

    @ViewBuilder
    private func avatarIcon(_ reply: SocialReply) -> some View {
        if let avatar = reply.avatarURL {
            RemoteThumb(urlString: avatar, size: DS.Face.badge, fallback: source, circular: true)
        } else {
            BridgeIcon(name: source, size: DS.Face.badge, circular: true)
        }
    }

    private func words(_ reply: SocialReply) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("@\(SocialThread.shortHandle(reply.handle))")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            Text(reply.text)
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
    }
}

/// The person behind a face (2026-07-16) — reached by tapping any avatar: a
/// row's author, a reply's author, a quoted post's author. Face, name, bio, and
/// ONE real verb: Watch. That's what turns a mention or a reply from a dead end
/// into a door — someone talks to you, you tap them, you watch them, and their
/// posts land from then on. The same tap the setup screen's finder offers,
/// available wherever a person appears.
///
/// The card fetches the profile itself: the tap only knows a handle, and both
/// bridges cache profiles per launch, so opening one for someone already in
/// your feed costs nothing.
struct SocialProfileCard: View {
    let profile: SocialProfile
    @Environment(\.modelContext) private var modelContext
    /// OPTIONAL on purpose (2026-07-16). This card opens from anywhere a face
    /// appears — a feed row's sheet, a reply, a quote, a deep link — and those
    /// sheets are presented from view chains that sit OUTSIDE RootShell's
    /// `.environment(chrome)`. A non-optional `@Environment(ShellChrome.self)`
    /// TRAPS when the object isn't in scope, so the first deep link to this
    /// card crashed the app on presentation. Optional resolves to nil instead.
    ///
    /// Losing the toast where chrome is absent costs nothing the person needs:
    /// the Watch row itself flips to "Watching @x" — the card states its own
    /// outcome, which is the real confirmation. The toast is the echo.
    @Environment(ShellChrome.self) private var chrome: ShellChrome?
    @State private var loaded: SocialProfile?
    @State private var watched = false
    @State private var elsewhere: [UserSearch.Hit] = []
    @State private var searchedElsewhere = false
    /// Who-they-follow (prd §169), reached from here now — the ledger rework
    /// (prd §184) moved every per-account action off the setup screen's row
    /// and onto this card, which every account face taps into.
    @State private var followImport: FollowImportTarget?

    /// The fetched profile once it lands, else what the tap already knew — so
    /// the card is never empty while the network answers.
    private var shown: SocialProfile { loaded ?? profile }

    /// The bridge behind this profile's source — nil for a source that isn't
    /// a name-only handle bridge (shouldn't happen; the card only ever opens
    /// for Farcaster/Bluesky people).
    private var bridge: HandleBridge? { HandleBridge(rawValue: profile.source) }

    /// This person's Likes/Mentions switches, read straight off the
    /// @Observable store so a tap re-renders with nothing to keep in step.
    private var watchChips: [SocialWatch] {
        guard let bridge else { return [] }
        let key = bridge.normalize(profile.handle)
        return bridge.socialAccounts.first(where: { $0.key == key })?.watches ?? []
    }

    var body: some View {
        // Ink (2026-07-24, user: "farcaster and bluesky when you tap a face"
        // [aren't ink-colored]): this card is a detail surface reached from
        // ink-black hosts — the thread walker (`SocialPostSheet`), a feed
        // row's thing sheet, a deep link — and DSTray's own adaptive default
        // read as a shade off beside them, same bug class `dsInk()` fixed for
        // the wallet "Worth a look" tray.
        DSTray(title: shown.title, height: 560, ink: true) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                header
                if let bio = shown.bio, !bio.isEmpty {
                    Text(bio)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                watchRow
                if watched {
                    switchesSection
                    if profile.source == "Farcaster" {
                        walletRow
                    }
                    followRow
                }
                elsewhereSection
                Spacer(minLength: 0)
            }
        }
        .task {
            watched = SocialPeople.isWatched(handle: profile.handle, source: profile.source)
            loaded = await SocialPeople.profile(handle: profile.handle, source: profile.source)
        }
        .sheet(item: $followImport) { target in
            FollowImportSheet(source: target.source, handle: target.handle) { added in
                guard added > 0 else { return }
                Task { await SocialPeople.sync(source: target.source, context: modelContext) }
            }
        }
    }

    /// The switches themselves, plus the bridge's own explanation of what
    /// each does — moved here verbatim from the setup screen's row footer
    /// (prd §184), since the switches live only here now.
    @ViewBuilder private var switchesSection: some View {
        if !watchChips.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(watchChips) { watch in watchChipButton(watch) }
                }
                if let footer = bridge?.watchFooter {
                    Text(LocalizedStringKey(footer))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
            }
        }
    }

    /// A lit-or-quiet capsule: on wears the tint, off stays gray — the same
    /// anatomy the setup screen's row used to wear directly.
    private func watchChipButton(_ watch: SocialWatch) -> some View {
        Button {
            guard let bridge else { return }
            let key = bridge.normalize(profile.handle)
            bridge.setWatch(watch.kind, !watch.on, for: key)
            DSHaptic.tap()
            if !watch.on { Task { await SocialPeople.sync(source: profile.source, context: modelContext) } }
        } label: {
            Text(LocalizedStringKey(watch.label))
                .dsText(.label12)
                .foregroundStyle(watch.on ? DS.tint : DS.textTertiary)
                .padding(.horizontal, DS.Space.s3)
                .frame(height: 28)
                .background(watch.on ? DS.tintDim : DS.gray100, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Their follow graph as a picker (prd §169/§184) — moved here from the
    /// setup row it used to sit beside.
    private var followRow: some View {
        Button {
            followImport = FollowImportTarget(source: shown.source, handle: shown.handle)
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "person.2")
                    .dsGlyph(14)
                    .foregroundStyle(DS.textSecondary)
                Text("Who they follow")
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: DS.Space.s3) {
            if let avatar = shown.avatarURL {
                RemoteThumb(urlString: avatar, size: DS.Face.shelf, fallback: shown.source, circular: true)
            } else {
                BridgeIcon(name: shown.source, size: DS.Face.shelf, circular: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(shown.shortHandle)")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                Text(shown.source)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    /// One verb. Watching already? The row says so and does nothing — a second
    /// Watch would be a dead control on the one person it can never apply to.
    @ViewBuilder private var watchRow: some View {
        if watched {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "checkmark")
                    .dsGlyph(14)
                    .foregroundStyle(DS.confirm)
                Text("Watching @\(shown.shortHandle)")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        } else {
            Button {
                watch()
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "eye")
                        .dsGlyph(14)
                        .foregroundStyle(DS.textSecondary)
                    Text("Watch @\(shown.shortHandle)")
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.s3)
                .background(DS.fillFaint,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The wallet↔Farcaster join, here as well as on the setup row — you meet
    /// someone in a thread, you can watch what they hold. Watch-only, so
    /// peeking is legitimate (the standing wallet ruling).
    private var walletRow: some View {
        Button {
            watchWallet()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "wallet.pass")
                    .dsGlyph(14)
                    .foregroundStyle(DS.textSecondary)
                Text("Watch their wallet")
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Are they on the other network too?" — a SEARCH, never a claim. Nothing
    /// links a Farcaster username to a Bluesky handle, so asserting a match
    /// would be a guess wearing a fact's clothes. The card runs the same
    /// people-search the setup field runs and hands over the hits; which one is
    /// really them — if any — is the person's call, and their tap watches it.
    @ViewBuilder private var elsewhereSection: some View {
        if let other = SocialPeople.otherSource(profile.source) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if !searchedElsewhere {
                    Button {
                        findElsewhere()
                    } label: {
                        HStack(spacing: DS.Space.s2) {
                            Image(systemName: "magnifyingglass")
                                .dsGlyph(14)
                                .foregroundStyle(DS.textSecondary)
                            Text("Look for them on \(other)")
                                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(DS.Space.s3)
                        .background(DS.fillFaint,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                         style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if elsewhere.isEmpty {
                    Text("No \(other) account by that name.")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                } else {
                    Text("\(other) accounts by that name — tap to watch one.")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                    ForEach(elsewhere) { hit in
                        BridgeSearchResultRow(
                            imageURL: hit.avatarURL, fallbackIcon: other,
                            title: hit.displayName,
                            subtitle: "@\(SocialThread.shortHandle(hit.handle))",
                            action: { watchElsewhere(hit, on: other) })
                    }
                }
            }
        }
    }

    private func watch() {
        guard SocialPeople.watch(shown) else {
            chrome?.flash(String(localized: "Already watching @\(shown.shortHandle)."))
            watched = true
            return
        }
        watched = true
        chrome?.flash(String(localized: "Watching @\(shown.shortHandle)."), tone: .success)
        Task { await SocialPeople.sync(source: shown.source, context: modelContext) }
    }

    private func watchWallet() {
        Task {
            let verified = await FarcasterIngest.verifiedEthAddresses(username: shown.handle)
            let already = Set(WalletStore.shared.addresses.map { $0.address.lowercased() })
            guard let address = verified.first(where: { !already.contains($0) }) else {
                if verified.isEmpty {
                    chrome?.flash(String(localized: "No verified wallet for @\(shown.shortHandle)."), tone: .failure)
                } else {
                    chrome?.flash(String(localized: "Already watching @\(shown.shortHandle)'s wallet."))
                }
                return
            }
            // The watch cap, worded at this door too (prd §170): the wallet
            // still gets NAMED — the light tier is unlimited — so the person
            // keeps something rather than bouncing off a silent refusal.
            switch WalletStore.shared.outcome(ofAdding: address, label: "@\(shown.handle)") {
            case .added:
                chrome?.flash(String(localized: "Watching @\(shown.shortHandle)'s wallet."), tone: .success)
            case .limitReached:
                AddressBook.shared.setName("@\(shown.handle)", for: address,
                                           provenance: shown.source, kind: .wallet)
                chrome?.flash(String(localized: "Watching \(WalletStore.watchLimit) wallets already — saved @\(shown.shortHandle) to your address book instead."))
            case .alreadyWatching, .invalid:
                chrome?.flash(String(localized: "Already watching @\(shown.shortHandle)'s wallet."))
            }
        }
    }

    private func findElsewhere() {
        Task {
            elsewhere = await SocialPeople.findElsewhere(profile.handle, from: profile.source)
            searchedElsewhere = true
        }
    }

    private func watchElsewhere(_ hit: UserSearch.Hit, on other: String) {
        let picked = SocialProfile(source: other, handle: hit.handle,
                                   displayName: hit.displayName, bio: nil,
                                   avatarURL: hit.avatarURL, fid: hit.fid)
        guard SocialPeople.watch(picked) else {
            chrome?.flash(String(localized: "Already watching that account."))
            return
        }
        chrome?.flash(String(localized: "Watching @\(picked.shortHandle) on \(other)."), tone: .success)
        Task { await SocialPeople.sync(source: other, context: modelContext) }
    }
}
