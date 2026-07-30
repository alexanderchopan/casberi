import Foundation
import SwiftData

/// The kind of a thing. Build brief §3 — v1 kinds; the schema leaves room for
/// the Alice kinds (job, run, output, skill) as load on this same model.
enum ThingKind: String, Codable, CaseIterable {
    // v1 (Bob)
    case note, screenshot, chat, event, link, reminder, mail, file, voice
    // A person from Contacts — a search-only reference thing (2026-07-12): it
    // rides the corpus for lookup and the answer path, and stays out of the
    // feed so hundreds of names never bury the day's real captures.
    case contact
    // Alice load (declared now; unused until bridges prove writes)
    case job, run, output, skill
    // S10 — an agent's ask, waiting on the person. The thing IS the consent
    // surface: Approve/Deny are its verbs.
    case approval
    // Onchain — a wallet's activity lands as a thing (Zerion read bridge). A
    // swap, send, or receive is a discrete event, so it fits the feed; holdings
    // and portfolio value are synthesis, not things.
    case transaction
    // Shopping (2026-07-14) — a product you follow or watch: a Shopify store's
    // new drop, a barcode you scanned, a page you're watching for a price drop.
    // A discrete item with a price and a store, so it fits the feed like a link
    // does; its own kind gives shopping a bag glyph and a "Products" pile.
    case product
    // HomeKit (2026-07-17) — a home accessory's live state (a lock, a door, a
    // sensor). Search-only, like Contacts: HomeKit has no historical-event
    // API, so a home's accessories land as a handful of reference things kept
    // current in place, not a growing feed of "the same door again."
    case accessory

    /// Set form for treemap cells ("Events" is the pile; "Event" is the thing).
    var typeTagPlural: String {
        switch self {
        case .mail, .voice: return typeTag          // uncountables stay
        default:            return typeTag + "s"
        }
    }

    /// The type tag assigned at ingestion (brief §3 — tags: type tags).
    var typeTag: String {
        switch self {
        case .note:       return "Note"
        case .screenshot: return "Screenshot"
        case .chat:       return "Chat"
        case .event:      return "Event"
        case .link:       return "Link"
        case .reminder:   return "Reminder"
        case .mail:       return "Mail"
        case .file:       return "File"
        case .voice:      return "Voice"
        case .job:        return "Job"
        case .run:        return "Run"
        case .output:     return "Output"
        case .skill:      return "Skill"
        case .approval:   return "Approval"
        case .transaction: return "Transaction"
        case .contact:    return "Contact"
        case .product:    return "Product"
        case .accessory:  return "Accessory"
        }
    }
}

/// Which corpus things surface (2026-07-12). Some sources live in the corpus
/// for search, Spotlight, and the answer path ONLY — never as feed rows,
/// source chips, or Home synthesis. Contacts is the first: a big address book
/// would bury the day's real captures. One rule, read by every surface that
/// shows the corpus, so a search-only source is declared in exactly one place.
enum Corpus {
    static let searchOnlySources: Set<String> = ["Contacts", "HomeKit"]

    /// The things a surface (Feed, Home) should show — the corpus minus the
    /// search-only sources.
    static func surfaced(_ things: [Thing]) -> [Thing] {
        things.filter { !searchOnlySources.contains($0.source) }
    }

    /// Is there ANY surfaced thing — without building the surfaced array.
    /// `surfaced(...).isEmpty` allocates a full filtered copy of the whole
    /// corpus just to ask a yes/no; the feed body did that twice per eval for
    /// its empty-state branch, on every one of the hundreds of context merges
    /// a cold CloudKit import fires (PERF 2026-07-29). `contains` short-
    /// circuits on the first surfaced thing — which, since search-only sources
    /// are rare, is almost always the very first element.
    static func hasSurfaced(_ things: [Thing]) -> Bool {
        things.contains { !searchOnlySources.contains($0.source) }
    }
}

/// A mark on a thing. Things enter unmarked (`none`); inference proposes through
/// `suggested`, one tap admits. Build brief §3.
enum Mark: String, Codable, CaseIterable {
    case none, todo, doing, done, saved, suggested
}

/// Provenance travels with every thing (brief §3). For Bob most fields are nil;
/// for Alice `agent` / `run` / `machine` make "which agent broke the build" a
/// query (PRD S2).
struct Provenance: Codable, Hashable {
    var app: String
    var agent: String?
    var run: String?
    var machine: String?
}

/// A post referenced BY a thing — the cast it quotes, or the cast it replies
/// under (2026-07-16). One shape for both: a face, a handle, the words, and
/// the permalink a tap follows. Stored as a Codable value on the model, the
/// way `Provenance` is — a quote is one compound fact, not four loose columns.
///
/// `text` is the referenced post's FULL text, not a title line: the card that
/// renders it clamps at read time (a quote is context, so it shows a few lines
/// and stops), and clamping at ingest would throw away words the sheet may
/// later want.
struct SocialCard: Codable, Hashable, Identifiable {
    /// Computed, so it never enters the encoded form — the protocol ref when
    /// there is one, else whatever else distinguishes this card.
    var id: String { ref ?? url ?? "\(handle):\(text)" }

    var handle: String
    var text: String
    var avatarURL: String?
    /// The web permalink — what Open follows.
    var url: String?
    /// The PROTOCOL ref, in `Thing.sourceRef` form ("fc:<hash>",
    /// "bsky:<at-uri>") — what reading this post's own replies needs, so a tap
    /// can walk the thread in-app. The web permalink can't stand in: a
    /// Farcaster one carries only the first 10 characters of the hash.
    var ref: String? = nil
}

/// The one container. Notes, screenshots, chats, events, links — and later
/// jobs, runs, outputs, skills — all land here as a `Thing` (PRD S1).
///
/// CloudKit compatibility (M1): every stored property carries a default value
/// and no property is a `@Attribute(.unique)` — SwiftData's CloudKit mirroring
/// requires both (a unique constraint has no CloudKit equivalent; a defaultless
/// non-optional can't be reconciled). The custom `init` still sets everything;
/// the defaults exist for the schema, not for callers.
@Model
final class Thing {
    var id: UUID = UUID()
    var kind: ThingKind = ThingKind.note
    var title: String = ""
    var content: String = ""
    /// The app or surface the thing came from — "Calendar", "ChatGPT", "You".
    var source: String = "You"
    var createdAt: Date = Date.now
    var capturedAt: Date = Date.now
    var mark: Mark = Mark.none
    /// Type + project + user tags (brief §3). Project membership rides a tag.
    var tags: [String] = []
    var provenance: Provenance = Provenance(app: "You")
    /// Stable identifier in the source system (PHAsset id, message id, URL) —
    /// ingestion (and CloudKit merge) dedupes on it.
    var sourceRef: String? = nil
    /// Voice audio, stored by the model itself (externalStorage keeps the
    /// bytes beside the store, and CloudKit mirroring carries them as a
    /// CKAsset — the M1 sync half of voice notes).
    @Attribute(.externalStorage) var audio: Data? = nil
    /// A remote thumbnail for the feed row — a Pinterest pin's image, an Apple
    /// Music album cover — captured at ingest so the row shows it without a
    /// per-row LinkPresentation fetch
    /// (the detail sheet still does the full preview). Optional + default nil
    /// keeps CloudKit mirroring happy; it's set after init, so the initializer
    /// and its callers are untouched.
    var previewImageURL: String? = nil
    /// A screenshot's own picture, saved small into the corpus so the row
    /// survives the Photos original being deleted (2026-07-10) — the
    /// voice-audio pattern: externalStorage keeps the bytes beside the
    /// store, CloudKit mirrors them as a CKAsset. nil for everything else,
    /// and for screenshots from before this field until the heal sweep
    /// reaches them.
    @Attribute(.externalStorage) var previewImageData: Data? = nil
    /// The onchain address a Wallet transaction came from — lets a row say
    /// which watched wallet it belongs to when more than one is watched
    /// (2026-07-09). Optional + default nil keeps CloudKit mirroring happy;
    /// nil for every non-Wallet thing.
    var walletAddress: String? = nil
    /// The OTHER side of a Wallet transaction, lowercased hex (2026-07-15) — who
    /// it came from when received, where it went when sent. The title names this
    /// counterparty when it resolves to something (a watched wallet, a known
    /// contract, ENS, or a name the person gave it), but the raw hex was
    /// discarded after the title was written, so the thing sheet had nothing to
    /// bind a "name this address" verb to. Persisting it lets the person label a
    /// counterparty from the sheet (CounterpartyLabels), enriching future
    /// transfers. Optional + default nil keeps CloudKit mirroring happy; nil for
    /// native-coin transfers with no counterparty and every non-Wallet thing.
    var counterpartyAddress: String? = nil
    /// A Wallet transfer's direction as DATA — `"sent"` or `"received"`
    /// (2026-07-16). The stage (`TransferStage`) used to parse the verb back
    /// out of the title sentence; the title stays the display string, this is
    /// the fact it was built from. A raw string, not an enum, so an unknown
    /// future value from a newer synced device degrades to the title-parse
    /// fallback instead of failing the decode. Optional + default nil keeps
    /// CloudKit mirroring happy; nil for swaps and self-moves (two legs, no
    /// single direction), for every non-Wallet thing, and for transfers
    /// landed before this field — those keep parsing the title.
    var transferDirection: String? = nil
    /// The moved amount as the title leads with it — `"0.9962 ETH"` (just
    /// `"ETH"` when the value was unreadable, mirroring the title). Set
    /// beside `transferDirection`; same nils.
    var transferAmount: String? = nil
    /// The venue a Solana move rode (`"Jupiter"`) — a WHERE, not a who: the
    /// program that executed it, never a renameable counterparty (that clause
    /// lives in `transferCounterparty` and `counterpartyAddress`). nil for
    /// EVM transfers (their " on …" clause is the counterparty) and
    /// everything else.
    var transferVenue: String? = nil
    /// The counterparty's display name as the title carries it — `"Uniswap"`,
    /// `"Mom"`, a swap's router (2026-07-16). Exactly two writers, the same
    /// two that write the title's clause: ingest (the resolved name, nil when
    /// nameless) and the rename flow (`retitleWalletThings` sets this beside
    /// the rewritten title), so the field can never trail a rename. nil for
    /// every non-Wallet thing and for transfers landed before this field —
    /// those parse the title.
    var transferCounterparty: String? = nil
    /// The wallet safety signals on a landed transfer — a comma-joined SET,
    /// read through `securityFlags`/`hasSecurityFlag`, never compared as a
    /// whole string.
    ///
    /// `"poisoning"` (2026-07-20): an incoming transfer whose counterparty
    /// address fuzzily mimics one this wallet has actually sent to (same
    /// leading/trailing hex, different address), the address-poisoning scam's
    /// whole mechanism. `"symbol"` (2026-07-21, prd §160): the transferred
    /// token's SYMBOL is a confusable copy of a well-known one ("ÚЅDС" for
    /// USDC) — see `SymbolConfusables`. Either way the thing still lands
    /// honestly as a transfer; a flag only adds the warning.
    ///
    /// It became a set the day the second flag existed: one transfer can be
    /// both a lookalike address AND a lookalike symbol, and a single-valued
    /// field would have silently dropped whichever arrived second.
    ///
    /// A raw string, not an enum, so an unknown future value from a newer
    /// synced device degrades to "no warning shown" instead of failing the
    /// decode. Optional + default nil keeps CloudKit mirroring happy; nil for
    /// every non-Wallet thing and for every transfer that isn't flagged.
    /// Stays a String rather than becoming an array because CHANGING this
    /// property's type is the breaking kind of change that would need a
    /// `ThingSchemaVN` stage; a comma-joined set needs none. (Adding a new
    /// optional property, like `spoofedSymbol` below, needs none either —
    /// SwiftData infers it. See `ThingSchemaVersioning`.)
    var securityFlag: String? = nil

    /// The offending symbol exactly as the chain reported it, recorded when
    /// the `"symbol"` flag is set (2026-07-21, prd §160).
    ///
    /// Stored rather than re-derived because ingest is the only place that
    /// holds GROUND TRUTH: it flags from the raw symbol string, while a
    /// surface can only re-scan the rendered title, where the symbol sits
    /// beside a counterparty name and a venue that may themselves be
    /// non-ASCII. Re-parsing prose to recover a fact we had in hand is how
    /// the warning ends up naming the wrong token. An additive optional needs
    /// no migration stage; the text scan survives only as the fallback for
    /// transfers that landed before this field existed.
    var spoofedSymbol: String? = nil

    /// The flags on this thing, split out of the stored string. Empty when
    /// nothing is flagged — so a caller never has to reason about nil.
    var securityFlags: [String] {
        (securityFlag ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    /// Whether ANY signal is present — the question the row badge and the
    /// sheet's warning stack ask. A non-nil-but-empty string reads as
    /// unflagged here, which is why surfaces ask this instead of `!= nil`.
    var isFlagged: Bool { !securityFlags.isEmpty }

    /// Whether one named signal is present. Every surface asks this rather
    /// than comparing `securityFlag` to a literal — the comparison that was
    /// correct while exactly one flag existed and silently wrong after.
    /// Fast path first: this runs in feed row bodies, where the answer is
    /// almost always "nothing is flagged".
    func hasSecurityFlag(_ name: String) -> Bool {
        guard let raw = securityFlag, !raw.isEmpty else { return false }
        return raw.split(separator: ",").contains { $0 == name }
    }

    /// Adds a signal, idempotently. Order is insertion order and no surface
    /// depends on it; re-flagging never duplicates.
    func addSecurityFlag(_ name: String) {
        let current = securityFlags
        guard !current.contains(name) else { return }
        securityFlag = (current + [name]).joined(separator: ",")
    }

    /// The account a social post came from — the Bluesky/Farcaster handle
    /// that authored it. When more than one account of a source is watched,
    /// the row leads with that author's avatar and names them, the way a
    /// Wallet row names which address it came from (2026-07-10). Optional +
    /// default nil keeps CloudKit mirroring happy; nil for everything else.
    var authorHandle: String? = nil
    /// That author's avatar URL — loaded into the row's leading slot (as a
    /// circle) only when more than one account is watched. nil keeps the
    /// source glyph.
    var authorAvatarURL: String? = nil
    /// A sentence-embedding vector of the thing's title+body, packed as Float32
    /// bytes — the on-device semantic index (2026-07-12), so the answer path can
    /// retrieve by MEANING, not just shared words. Derived by a lazy foreground
    /// sweep (`EmbeddingIndex`), never at the capture sites, so every bridge,
    /// CloudKit-synced thing, and the pre-existing corpus gets embedded alike.
    /// externalStorage (2026-07-15, reversed from the original inline choice):
    /// every `@Query` on `Thing` — including Home/Feed, which never read this
    /// field — was hydrating this ~2KB blob on EVERY row, because SwiftData
    /// eagerly loads inline attributes. That made it the single biggest
    /// amplifier of launch/recompose cost as the corpus grows. Retrieval
    /// (`EmbeddingIndex`, capped at 2000 things) now pays a per-thing file
    /// read instead — worse in isolation, but it only runs on an Ask, not on
    /// every Home/Feed paint. Optional + default nil keeps CloudKit mirroring
    /// happy and marks a thing as not-yet-indexed; an empty `Data` means
    /// "indexed, but unembeddable".
    @Attribute(.externalStorage) var embedding: Data? = nil

    /// Extracted supplementary text for RETRIEVAL ONLY (2026-07-15) — a saved
    /// link's readable article body, or the substance a thin title can't carry.
    /// Never shown as a tag, a title, or a feed row; read only by
    /// `EmbeddingIndex.indexText` (so the vector reflects what a thing is
    /// ABOUT), the retriever's content scan, and `answerSnippet` (so the model
    /// sees the substance, not just the title). `content` still holds the
    /// thing's own bytes — a link's URL, a note's text — so open/route logic is
    /// untouched. Setting this clears `embedding` so the sweep re-indexes on the
    /// richer text. Optional + default nil keeps CloudKit mirroring happy; nil
    /// until an enrichment pass reaches the thing.
    var enrichedText: String? = nil

    /// The SOURCE's own abstract, display-safe (2026-07-22) — an RSS/Atom
    /// item's `<summary>`, a Todoist task's description, a Linear issue's
    /// description, a Raindrop excerpt, a Readwise note. Deliberately NOT
    /// `enrichedText`: that field is text WE extracted by scraping, which is
    /// why it is retrieval-only by ruling (2026-07-15) and why
    /// `GitHubReleaseContent` re-fetches live rather than render it. This is
    /// text the source AUTHORED and handed us in its own payload — the thing a
    /// feed reader shows under the headline — so it is first-class display
    /// copy. `content` still holds the thing's own bytes (a link's URL), so
    /// open/route logic is untouched. Feeds retrieval too, via
    /// `EmbeddingIndex.indexText`. Optional + default nil: purely additive, so
    /// SwiftData infers it and no migration stage is needed.
    var summary: String? = nil

    /// A reminder's own due date, structured (2026-07-14) — the deadline the
    /// "Coming up" lane sorts on. A reminder's `capturedAt` is its CREATION
    /// time, so its deadline can't ride that field; events carry their deadline
    /// as `capturedAt` (the start) and leave this nil. Set after init by
    /// `ScheduleIngest.connectReminders` from `dueDateComponents`; nil for a
    /// reminder with no due date. A 1Claw grant's `expires_at` lands here too
    /// (a real structured deadline); other things leave it nil. Optional +
    /// default nil keeps CloudKit mirroring happy.
    var dueAt: Date? = nil

    /// When a screenshot's text was last read off its pixels (Vision OCR,
    /// prd §67 goal ⑤) — set even when no text was found, so text-less
    /// screenshots aren't re-read on every heal pass. nil = not yet tried.
    /// Optional + default nil keeps CloudKit mirroring happy.
    var ocrAt: Date? = nil

    /// The salient terms/names OCR lifted off a screenshot (2026-07-30) — the
    /// cells the Photos feed's "What you screenshot" treemap counts, replacing
    /// the generic capture-year heatmap. Each is a phrase that LITERALLY
    /// appears in the pixels (the honesty rule — a domain the shot shows, an
    /// organization/place/person NLTagger names), never an invented category;
    /// `ScreenshotTopics.terms` derives them from `content`, deterministically,
    /// off the model. The whole point of a screenshot is its text, so this
    /// answers "what are my screenshots ABOUT" where `ocrAt`'s heatmap only
    /// answered "when did I take them". Empty for every non-screenshot thing,
    /// for a text-less shot, and until `topicsAt` is stamped. An additive
    /// array field like `wikilinks`/`imageURLs` — SwiftData infers it, no
    /// migration stage (see `ThingSchemaVersioning`).
    var ocrTopics: [String] = []

    /// When `ocrTopics` was last extracted — set even when extraction found
    /// nothing (a text-less or term-less shot), so the backfill sweep never
    /// re-reads it, exactly the way `ocrAt` guards the OCR pass. nil = not yet
    /// tried. Optional + default nil keeps CloudKit mirroring happy.
    var topicsAt: Date? = nil

    /// A watched token's USD price the moment it was watched (2026-07-14) —
    /// the anchor for "since you watched": a number no market site can show,
    /// known locally and never back-filled. Set only by TokenWatch.add;
    /// `capturedAt` is the matching WHEN. Optional + default nil keeps
    /// CloudKit mirroring happy; nil for everything else (and for tokens
    /// watched before this field).
    var watchPriceUsd: Double? = nil

    /// A starred repo's stargazer count the moment it was starred (2026-07-14)
    /// — the anchor for "since you starred": a number GitHub itself won't show
    /// you, known locally and never back-filled. Set only by the GitHub Stars
    /// ingest; `capturedAt` is the matching WHEN. Optional + default nil keeps
    /// CloudKit mirroring happy; nil for everything else (and for stars saved
    /// before this field).
    var starCount: Int? = nil

    /// A repo's primary language ("Swift", "Rust") — carried on GitHub star and
    /// watched-repo things so the row can wear the language's canonical color.
    /// Optional + default nil keeps CloudKit mirroring happy; nil for
    /// everything else.
    var repoLanguage: String? = nil

    /// A product's current price as a number (2026-07-14), in `priceCurrency` —
    /// the anchor that lets a re-check say "dropped $40". The row shows the
    /// formatted price in its title; this is the comparable value, set by the
    /// Shopify/Deals ingest and the pasted-product parser. Optional + default
    /// nil keeps CloudKit mirroring happy; nil for every non-product thing.
    var priceValue: Double? = nil
    /// The ISO 4217 code (`USD`, `GBP`) `priceValue` is denominated in — so a
    /// re-formatted price never guesses the currency. nil when unknown.
    var priceCurrency: String? = nil

    // MARK: - Social posts (2026-07-16)

    /// A post's FULL text — the cast/post exactly as written (2026-07-16). The
    /// `title` is still the one-line 80-char clamp every row and search reads,
    /// and `content` still holds the web permalink (so Open/Share/route logic
    /// is untouched) — but a post longer than its title used to be
    /// unrecoverable: the sheet rendered `content`, i.e. a URL string, and the
    /// words were simply gone from the app. This carries them. nil for every
    /// non-social thing, and for posts landed before this field (the refresh
    /// backfills the ones still in the page).
    var postText: String? = nil

    /// WHY a social post is here, when it isn't simply "an account you watch
    /// posted it": `"liked"` (they liked it — the save verb) or `"mention"`
    /// (it names them). nil = authored by a watched account, the plain case.
    /// A raw string, not an enum, so an unknown future value from a synced
    /// device degrades to "no marker" instead of failing the decode.
    var socialContext: String? = nil

    /// The channel/feed a post arrived through — a Farcaster channel name
    /// (`design`) or a Bluesky custom feed's display name. Orthogonal to
    /// `socialContext`: a mention can arrive in a channel. nil when the post
    /// came from an account directly.
    var channelName: String? = nil

    /// A post's engagement at LAST SYNC (2026-07-16) — what the network's own
    /// public API reported, never derived or estimated. These go stale between
    /// syncs, which is why the sheet states them as a quiet line and not a live
    /// number. nil (not 0) when the source didn't report it: a zero means "none",
    /// an absent value means "we don't know", and the honesty rule needs those
    /// to stay different.
    var likeCount: Int? = nil
    var repostCount: Int? = nil
    var replyCount: Int? = nil

    /// The post this one QUOTES — both networks' signature form, dropped at
    /// ingest until now (a quote-post read as a bare, contextless line).
    var quote: SocialCard? = nil

    /// The post this one REPLIES under — so the sheet can say "Replying to
    /// @…" and a landed mention (usually a reply) carries the thing it
    /// answers. nil for a top-level post.
    var parent: SocialCard? = nil

    /// EVERY image the post carries, in order (2026-07-16). `previewImageURL`
    /// stays the row's single 26pt thumb (the band's rhythm holds); this is
    /// what the sheet lays out, so a four-photo post stops losing three of
    /// them. Empty for a text-only post and for everything non-social.
    var imageURLs: [String] = []

    // MARK: - Feed-follow delight (2026-07-28, FeedFollowMoments.swift)

    /// A Reddit post's actual human author (`/u/name`, decoded) — distinct
    /// from `authorHandle`, which every feed-follow bridge (Substack/Reddit/
    /// YouTube/Podcasts) already uses for the FEED's own identity (the
    /// subreddit/channel/publication `FeedLeaderboard` groups by). Lets a
    /// later corpus-wide pass notice the same person posting across two
    /// subreddits you follow. nil for every non-Reddit thing, and for posts
    /// landed before this field.
    var postAuthor: String? = nil

    /// The first non-Reddit link found inside a Reddit post's own body,
    /// captured at landing so a later pass can notice a subreddit discussing
    /// something already saved from elsewhere without re-parsing the post's
    /// HTML. nil when the post carries none, or for every non-Reddit thing.
    var externalLink: String? = nil

    // MARK: - Notes delight (2026-07-28, NoteLinks.swift)

    /// An Obsidian note's own `[[wikilink]]` targets, captured at ingest
    /// against the FULL markdown body — before `ObsidianIngest`'s 300-char
    /// `content` clamp, so a link past that point isn't lost. Plain target
    /// titles, exactly as the vault spells them (an alias after `|` and a
    /// heading after `#` are both stripped — see `NoteLinks.extract`).
    /// Resolved against other landed notes at SHEET-OPEN time, never
    /// persisted as a Thing reference: a target may not have synced yet, or
    /// may never exist, and the vault is the only source of truth for
    /// whether it does. Empty for every non-Obsidian thing.
    var wikilinks: [String] = []

    /// A watched prediction market's settled answer (2026-07-28) — nil while
    /// the market is live, true/false once it resolved. Distinct from
    /// `dueAt` passing: a market can close without resolving (arbitration),
    /// and only an explicit settlement signal from the exchange sets this.
    /// Once set the row is a RECORD, not a watch — `PredictionPulse` stops
    /// refetching it and the watchlist stops counting it as live, so a
    /// year-old list isn't mostly dead markets. nil for everything else.
    var marketResolvedYes: Bool? = nil

    init(
        id: UUID = UUID(),
        kind: ThingKind,
        title: String,
        content: String = "",
        source: String,
        createdAt: Date = .now,
        capturedAt: Date = .now,
        mark: Mark = .none,
        tags: [String] = [],
        provenance: Provenance? = nil,
        sourceRef: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.content = content
        self.source = source
        self.createdAt = createdAt
        self.capturedAt = capturedAt
        self.mark = mark
        // The type tag is always present; caller-supplied tags follow.
        self.tags = ([kind.typeTag] + tags).reduced()
        self.provenance = provenance ?? Provenance(app: source)
        self.sourceRef = sourceRef
    }
}

extension Array where Element == String {
    /// De-dupes case-insensitively while preserving first-seen order.
    func reduced() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
