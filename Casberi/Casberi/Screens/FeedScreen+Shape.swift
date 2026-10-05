import SwiftUI
import SwiftData

// The room's shape: which native shape a source takes, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// Is this room's content divided by AUTHOR — the one question the social
    /// face rail asks (prd §362), answered by the room-shaping taxonomy that
    /// already owns it rather than by a second list of source names kept in step
    /// with `Shape` by hand. Internal because `SocialScopeRail` lives in the
    /// shell and must decide whether to draw before any feed exists; `Shape`
    /// itself stays private, since nothing outside this file has business
    /// knowing the other twenty-two cases.
    static func isSocialRoom(_ source: String) -> Bool {
        // ASKED OF `SocialRoom`, NOT OF `Shape` (2026-08-26, prd §489). The
        // rail and the accounts behind it must answer for the same set or the
        // rail draws faces the room cannot filter to — which is exactly what a
        // `Shape`-only answer would have produced the moment Nostr joined
        // `.social` while `SocialRoomSource.accounts` still had two cases.
        // One registry, two readers.
        SocialRoom.hasRoster(source)
    }

    /// Whether a source renders as the PLAIN shape — no bespoke head or
    /// layout of its own — so the demo census can tell "this room leads with
    /// rows because nothing else is defined for it" from a real gap.
    static func rendersPlain(_ source: String) -> Bool { Shape(source: source) == .plain }

    /// The shape a source takes when its chip is in force.
    enum Shape {
        case all, photos, wallet, ledger, calendar, gmail, chat, social, reminders, bookmarks, notes, you, music, media, tokens, snapchat, files, instagram, tiktok, x, appStoreConnect, cardPointers, walletbeat, l2beat, telegram, plain

        /// Rooms whose lead is a GRID of pictures, and which therefore earn the
        /// wide content cap on a regular-width window (2026-08-17).
        ///
        /// Membership is "does this room draw a picture wall", not "does this
        /// room contain images" — `social` and `x` hold plenty of photos but
        /// lead with post cards whose words are the content, and widening those
        /// would stretch a paragraph past the reading measure to no benefit.
        /// The mixed rooms (Files, Snapchat, Instagram) are in because the grid
        /// is what sets their width; `x` stays out because its picture half is
        /// a minority of a room that is overwhelmingly writing.
        var widensForPictures: Bool {
            switch self {
            case .photos, .media, .files, .snapchat, .instagram: return true
            default: return false
            }
        }

        /// Whether this shape can lead with a cover (`ledeListRow`) at all
        /// (prd §906). A QUIET head — one with only its sentence — gives way
        /// to the cover, which carries the sentence as its note (§760); in a
        /// shape with no cover path that hand-off left the room with no
        /// lead of any kind (Railgun with no tokens, CardPointers with no
        /// deadlines). Where nothing can carry the line, the head stands.
        var carriesCover: Bool {
            switch self {
            case .ledger, .calendar, .gmail, .reminders, .tokens,
                 .cardPointers, .walletbeat, .l2beat, .wallet: return false
            default: return true
            }
        }
        init(source: String) {
            switch source {
            case "All":                 self = .all
            case "Photos":              self = .photos
            // Snapchat is the first MIXED room (2026-07-31): memories are
            // pictures and saved chats are conversations, so it can't be
            // `.photos` (that would hide the chats) or `.chat` (that would
            // list the pictures as dated rows, which is exactly what the
            // export already is and what this app exists to beat). It gets
            // its own shape: the memories that have their pixels back as a
            // grid, everything else as rows beneath.
            case "Snapchat":            self = .snapchat
            // The second mixed room (2026-08-02): a connected folder holds
            // images beside PDFs and text files, and `FilesIngest.heal` gives
            // the images real thumbnails + OCR — which `.plain` then rendered
            // as filename rows, pixels stored but never drawn (a user pointing
            // the folder card at a screenshots folder saw a wall of text).
            // Same split as Snapchat: healed images as a grid, the rest as
            // rows.
            case "Files":               self = .files
            // App Store Connect, 2026-08-06 — its own shape for ONE row type:
            // a customer review is somebody else's words about your work, and
            // `.plain` drew it as an 80-character title with the text stored
            // and never rendered (the §313 X finding, one room over). Verdicts
            // and builds keep the band — they are one-line facts, and giving
            // them a card would spend the room's emphasis on the rows that
            // need it least.
            case ASCShape.source:       self = .appStoreConnect
            case "Wallet":              self = .wallet
            // The WALLET-RIDING money rooms (prd §485, 2026-08-26). Both had NO case
            // here, so they fell to `.plain` and drew the band's generic
            // sentence row — in rooms whose every row is a transfer, with the
            // amount and the direction already stamped on it
            // (`transferAmount`/`transferDirection`, since prd §369 and §397)
            // and `BandRow.moneyColumn` already built to read exactly that
            // pair. So the figure sat inside an 80-character sentence, and a
            // column of moves scanned as a column of prose where the wallet
            // room beside them has scanned as a ledger since §158.
            //
            // `.ledger` rather than `.wallet`: that shape carries the wallet
            // room's whole apparatus — its section switcher, its crown, its
            // tiles, its warnings — and these rooms have a head of their own.
            // What they share with it is one row anatomy and one flag.
            //
            // A non-transfer row in these rooms is unaffected by construction:
            // Privacy Pools' proof-required ALERT carries no
            // `transferDirection`, so `moneyAmount` returns nil and it keeps
            // its full sentence. The flag is opt-in per ROW, not per room.
            //
            // GNOSIS PAY IS DELIBERATELY NOT HERE, and the reason is data, not
            // taste: its title states the spend in FIAT ("Spent EUR 42.80 with
            // Gnosis Pay") while its `transferAmount` is the TOKEN amount
            // ("42.80 EURe") — two spellings of one figure — so `titleText`'s
            // strip can never match and the row would print the amount twice,
            // in two units. Its honest column is the fiat one, which means
            // teaching the money column to prefer `priceValue`/`priceCurrency`
            // for a real ISO currency; that changes what §374's mask reads
            // (the trailing SYMBOL of `transferAmount`) and belongs in its own
            // pass rather than riding this one.
            //
            // The LITERALS, like `case "Telegram"` and `case "Instagram"` below
            // — `demo-selftest.py`'s check F reads this switch to prove every
            // shape has a seeded source, and it resolves only three
            // indirections by name.
            case "Railgun", "Privacy Pools": self = .ledger
            case "Calendar", "Cal.com", "Calendly": self = .calendar
            case "Gmail", "iCloud Mail": self = .gmail
            // The keyed seats join the three import sources (prd §839): a
            // conversation you have in the composer lands as a chat thing, so
            // its room is a chat room. No new shape — the anatomy an imported
            // conversation already wears is the one a live conversation wants,
            // and a second shape would be two renderings of one thing.
            case "ChatGPT", "Claude", "Gemini",
                 "Bankr", "Venice", "OpenRouter", "Grok", "NEAR AI",
                 "Muse": self = .chat
            // Posts read as posts in their own room (2026-07-13) — split from
            // .chat: a saved conversation is a snippet row, a post is a card.
            // NOSTR JOINED 2026-08-26 (prd §489) — two years of this room
            // being a room for two of the three networks that land into it.
            // It had no case here at all, so its rows fell to `.plain`'s
            // generic band: no faces above the room, no post cards, no thread
            // folding, no person filter. All of it was already built and
            // already knew about Nostr — `PostCard.author` branches on its hex
            // pubkey to shorten it for display, `SocialThreadCard` does the
            // same, `SocialThread.replies` reads its threads, and
            // `NostrStore.socialAccounts` was drawn on the setup screen. One
            // switch statement never learned the name.
            case "Bluesky", "Nostr": self = .social
            // X, 2026-08-06 — the same ruling as the line above, arriving two
            // years of somebody's writing late. The room had NO case here at
            // all, so it fell to `.plain` and drew a `BandRow` per row: an
            // icon, `titleLine`'s 80-character clamp, a timestamp. In a room
            // whose entire content is sentences written to be read. The words
            // were in the store the whole time and on no screen — a post's on
            // `content`, a liked post's on `enrichedText`, which is
            // retrieval-only by the 2026-07-15 ruling.
            //
            // Its OWN case rather than joining `.social`, because `.social`
            // means something different by a `.link`: there it is an article a
            // post shared (`ReadingRow`), here it is a post somebody else
            // wrote and you liked — a post, and it reads as one. Sharing the
            // case would also hand X's room the Farcaster/Bluesky roster head,
            // which reads its accounts out of `BlueskyStore` for anything that
            // isn't Farcaster.
            // Instagram, 2026-08-18 (prd §395) — the LAST photo app in this
            // app still drawing as text, and the one where it cost most. It
            // had no case here at all, so it fell to `.plain`: a `BandRow` per
            // row, a 26pt leader square and `titleLine`'s 80-character clamp,
            // in a room whose own importer has written 480pt thumbnails since
            // §310 explicitly because "Instagram is a photo app, and its room
            // was a wall of text". The pixels were stored and never drawn at
            // any size worth looking at — the §283 Files failure and the §313 X
            // failure, both again, in the room they were both compared to.
            //
            // Its OWN case rather than joining `.x`: that room's grid holds
            // your own wordless posts alone, and this one has to hold saves
            // that arrived with no picture at all until `InstagramCaptions`
            // fetched one. Sharing the case would also hand this room X's head.
            // The LITERAL, like `case "X"` and `case "Snapchat"` beside it —
            // `demo-selftest.py`'s check F reads this switch to prove every
            // shape has a seeded source, and it resolves exactly two
            // indirections by name (App Store Connect, the media
            // predicate). A third would make this room's shape unverifiable
            // rather than verified, which is the worse half of both options.
            case "Instagram":           self = .instagram
            // TikTok, 2026-08-26 (prd §489) — the SECOND room with no case
            // here, found by auditing the other seven rather than by a report,
            // because nobody had opened it lately. A room of saved videos drew
            // one `BandRow` per row: a 26pt leader square and `titleLine`'s
            // 80-character clamp over what is, before `TikTokImport.fetchFaces`
            // has run, the raw share URL. The cover art the face pass fetches
            // was stored on `previewImageURL` and drawn at no size at all.
            //
            // Its own case rather than joining `.instagram`: that room's rows
            // carry `postText` and read as post cards, and TikTok's carry none
            // (its caption lands on `enrichedText`, retrieval-only) — see
            // `SocialRoom.rowKind` for why that makes a post card dishonest
            // here and a reading row correct.
            // The LITERAL, like `case "Instagram"` above it —
            // `demo-selftest.py`'s check F reads this switch to prove every
            // shape has a seeded source, and it resolves only three
            // indirections by name.
            case "TikTok":              self = .tiktok
            case "X":                   self = .x
            // Telegram, 2026-08-23 (prd §456) — the first room holding BOTH a
            // live drip and an import under one source, so it has the widest
            // row mix in the app: a followed channel's broadcast posts (words,
            // usually a picture), your Saved Messages (mostly bare links), and
            // whole conversations as `.chat` rows.
            //
            // Its own case rather than `.social`: that one is Farcaster and
            // Bluesky, whose roster head reads accounts out of `BlueskyStore`
            // for anything that isn't Farcaster — the same objection that kept
            // X out. And rather than `.chat`: a channel post is not a message,
            // and a room of broadcast posts drawn as chat bubbles is the §313
            // failure wearing the other coat.
            case "Telegram":            self = .telegram
            // CardPointers, 2026-08-26 (prd §487) — the x402 finding again,
            // six rooms later and with the same three symptoms. It had no case
            // here, so `.plain` drew a `BandRow` per offer: one glyph, the
            // `Card · Merchant` title, and a trailing timestamp that is
            // `capturedAt` — which the ingest stamps `.now`, so every row in
            // the room shared one time under one "Today" header. The two facts
            // that make an offer an offer were on the row's own model and on
            // no screen: the terms on `summary` (which `BandRow` never reads)
            // and the deadline on `dueAt` (which only the head drew, for one
            // offer). Its own case rather than `.reminders`, whose band is a
            // one-line fact — an offer is three.
            //
            // The LITERAL, like `case "Telegram"` above it — `demo-selftest.py`'s
            // check F reads this switch to prove every shape has a seeded
            // source, and it resolves only three indirections by name.
            case "CardPointers":        self = .cardPointers
            // The LITERAL, for the same reason as the line above.
            case "Walletbeat":          self = .walletbeat
            // The LITERAL, for the same reason as `case "Walletbeat"` above —
            // `demo-selftest.py`'s check F reads this switch by name.
            case "L2BEAT":              self = .l2beat
            case "Reminders", "Todoist": self = .reminders
            // This case was written 2026-07-13 for a "Safari" bridge that
            // never shipped — Safari and Chrome exports merged into ONE
            // "Bookmarks" offer on 2026-07-28 (prd §224), and the shape below
            // was never rewired to the source that actually landed. Found
            // 2026-08-10: the case had gone fully dead (no bridge ever
            // stamped `source: "Safari"`) while `BookmarksImport.land` had
            // been stamping `.link` things as "Bookmarks" since it shipped,
            // silently falling to `.plain`'s generic band row — exactly the
            // saved-link reading list this shape (`ReadingRow`)
            // was built for, wearing no Safari branding of its own.
            case "Bookmarks":           self = .bookmarks
            // Obsidian joins the notes room — the vault is notes (prd §59).
            // Files LEFT this group on 2026-08-02 (see `.files` above): the
            // excerpt row it shared here draws title + text + time and no
            // image at all, so a connected folder of screenshots rendered as
            // pure text while its thumbnails sat in the store undrawn.
            case "Notes", "Day One", "Apple Journal", "Obsidian": self = .notes
            case "You":                 self = .you
            // Spotify joins Apple Music here (prd §906): it took the `.plain`
            // branch, so its room grouped by day and drew band rows while the
            // other music room grouped by listening session and led with the
            // cover through `MusicRow`. One music, one shape.
            case "Apple Music", "Spotify": self = .music
            // The media room (prd §219, 2026-07-25): art at the medium's own
            // proportions instead of the All feed's 26pt square. Music is NOT
            // here — `MusicRow` has led with the cover since 2026-07-11 and is
            // already this shape by another name.
            //
            // PODCASTS STAYS HERE, decided 2026-08-06 rather than allowed to
            // happen. A per-episode `<itunes:image>` now fills
            // `previewImageURL`, so overnight every episode row carries art
            // where it carried none, and the three precedents for splitting a
            // room off (Snapchat §247, Files §283, X §313) all look like this
            // one from a distance. They are not: each of those was a room whose
            // pixels were STORED AND NEVER DRAWN, or whose rows were the wrong
            // anatomy for what they held. This room was built for art from the
            // day it shipped — `MediaShape.art(for:)` has declared Podcasts
            // `.cover` since §219, and `MediaRow` has drawn `previewImageURL`
            // at 48×48 with the brand glyph standing in on the same 48×48 box.
            // So the geometry does not move: row height, leading box, byline,
            // trailing time are all unchanged, and what changes is the CONTENT
            // of a box the room already reserved. That is a fill, not a
            // re-shape, and a new `Shape` case would be a second mechanism
            // saying what this one already says.
            //
            // Two knock-ons, both already handled where they live, and both
            // reasons NOT to build a mixed grid here: `FeedInsight.mosaic`
            // dedupes tiles by URL, so a show that stamps one cover on every
            // episode can never fill the 4-tile shelf and the head correctly
            // declines it; and `MediaShape.freshness` saturation now reaches
            // podcast art, which is §219's own decay arriving as designed
            // rather than a new behaviour.
            case _ where MediaShape.isMediaFeed(source): self = .media
            case "Markets":             self = .tokens
            default:                    self = .plain
            }
        }
    }
    var shape: Shape { Shape(source: source) }

    /// The design a row draws in. A merged room's own rows take the room's
    /// shape; a folded app's row (prd §1048, step 4) keeps its own where its
    /// own says something the room's does not — CardPointers' offer terms and
    /// deadline. Every other folded row reads as the room's ledger, which is
    /// already how card spends and transfers want to look.
    func rowShape(_ thing: Thing) -> Shape {
        guard RoomAccounts.rides(room: source, source: thing.source) else { return shape }
        // Outside the Wallet a folded app's row keeps its own design: a
        // rating change reads as one in Reading, an article as an article.
        guard source == CategoryFold.walletRoom else { return Shape(source: thing.source) }
        if case .cardPointers = Shape(source: thing.source) { return .cardPointers }
        return shape
    }
}
