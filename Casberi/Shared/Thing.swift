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

    /// Sources that keep their STAMP but earn no chip and no room (user
    /// ruling 2026-08-02: "i say get rid of the you chip and room").
    ///
    /// "You" is the first, and for now the only one. It is `source`'s own
    /// default — the honest provenance of anything you captured yourself: the
    /// share sheet, a drop, a note — but it is not an app, and the strip is a
    /// row of apps. Three things made its room wrong rather than merely thin:
    ///
    ///   • **The rail already carries a person.** `AvatarDoor` renders
    ///     `person.crop.circle` for Settings at the head of the strip, and the
    ///     chip drew `person` (`KindGlyph`) a few slots along — one
    ///     silhouette, two meanings, on one rail. It read as "profile".
    ///   • **The room had no face and could not get one.** `FeedScreen`'s
    ///     `.you` shape is assigned and matched by nothing, so it fell through
    ///     to a plain list. §247 gave every room a hero; this room's contents
    ///     are a link, a note, a PDF and a dropped file — heterogeneous by
    ///     definition, which is the one thing a map can't be made of.
    ///   • **Nothing was reachable only there.** Unlike `searchOnlySources`
    ///     (hidden from the feed) or `bulkImportSources` (kept out of All),
    ///     every "You" thing already shows in All — so the room added scoping
    ///     and no reach, and scoping is already done better three ways: the
    ///     `.saved` mark, projects, and Find (§215).
    ///
    /// Deliberately NOT `searchOnlySources`: that hides a source from the feed
    /// altogether, and your own captures belong in All more than anything a
    /// bridge pours in. The stamp stays on the record too, where the sheet's
    /// spec table already reads "From — written by you" in plain words. This
    /// removes a ROOM, not a fact.
    static let chiplessSources: Set<String> = ["You"]

    /// Does this source get a chip in the strip, a room behind it, and a
    /// `casberi://feed/source/…` door pointing at it? Read by every surface
    /// that offers a source as a destination, so the answer is declared once.
    static func earnsRoom(_ source: String) -> Bool {
        !chiplessSources.contains(source) && !searchOnlySources.contains(source)
    }

    /// Sources that arrive in BULK from a file you exported yourself —
    /// thousands of things in one pass, dated across years (2026-07-31).
    ///
    /// They keep their own room and their source chip, unlike
    /// `searchOnlySources` above; what they must never do is enter the ALL
    /// feed, where a single import would bury every real capture the day it
    /// ran — the same failure the address-book rule exists to prevent, one
    /// step short of hiding the source entirely. All gets ONE receipt
    /// instead (`isImportReceipt`), and the room holds everything.
    static let bulkImportSources: Set<String> = ["Instagram", "Snapchat", "TikTok", "X", "Telegram"]

    /// Ref namespaces whose rows arrived LIVE, one at a time, even though
    /// their source is a bulk-import source (2026-08-23, prd §456).
    ///
    /// Telegram is the first seat with BOTH shapes under one source: you
    /// follow public channels (a drip of a few posts a day, exactly like
    /// Substack or YouTube) and you can also import a Desktop export
    /// (thousands of rows dated across years). The two want opposite things
    /// from the All feed, and `bulkImportSources` is per-SOURCE, so without
    /// this the seat has to pick one and be wrong about the other: either a
    /// followed channel is a strictly worse Substack whose posts only appear
    /// if you go looking for them, or one import buries every real capture the
    /// day it ran.
    ///
    /// The distinction is already written on every row — a followed post is
    /// `telegram:post:…`, an imported one is `telegram:chat:…` /
    /// `telegram:saved:…` — so it needs no new stored property and no CloudKit
    /// deploy, and it cannot drift from the truth the way a flag set at
    /// landing time could.
    ///
    /// **The other four bulk sources declare nothing here and are unaffected**
    /// — Instagram, Snapchat, TikTok and X have no live half to let through.
    static let liveRefPrefixes: Set<String> = ["telegram:post:"]

    /// Did this row arrive live rather than out of an imported file?
    static func arrivedLive(_ thing: Thing) -> Bool {
        guard let ref = thing.sourceRef else { return false }
        return liveRefPrefixes.contains { ref.hasPrefix($0) }
    }

    /// Seats whose `.transaction` rows are a CARD PURCHASE — money you spent,
    /// stamped with a real `priceValue`/`priceCurrency` rather than a formatted
    /// substring inside a title (2026-08-06, prd §317).
    ///
    /// Declared once because two readers must agree about it: the "what did I
    /// spend?" ask and the money-flow composer's card leg. A wallet transfer is
    /// deliberately absent — it moves money without buying anything, and
    /// folding it in here would total a swap as shopping.
    ///
    /// **Membership is a data test, not a judgement about the seat**: a member
    /// lands `.transaction` rows carrying `priceValue` AND `priceCurrency`.
    /// Adding a seat that doesn't is worse than leaving it out — its rows would
    /// pass the source filter, then be dropped for want of a number, and the
    /// answer would state a total that silently excluded them.
    ///
    /// Two deliberate absences, each for its own reason:
    ///   · **Privacy.com** — a real card, and since 2026-08-06 its rows ARE
    ///     `.transaction` carrying a real `priceValue`/`priceCurrency` in USD,
    ///     so the old reason (an amount readable only by re-parsing the title)
    ///     is gone. What keeps it out now is that the arithmetic would be
    ///     WRONG rather than absent, which is worse: a RETURN is unmeasured —
    ///     the read filters `result=APPROVED` and the amount falls back from
    ///     `settled_amount` to `amount`, so a refund lands wearing its positive
    ///     authorization amount and reads as a purchase, while the card leg
    ///     subtracts only on a `Refund` tag Privacy doesn't carry — the trap
    ///     `KeptAskComposers.moneyFlow` names for Apple Wallet, which lands
    ///     refunds stamped positive and tagged. Measure a return with
    ///     `-privacyProbe` against a live key, then join.
    ///   · **Stripe** — `StripeRoomSource` documents why its amounts can't do
    ///     arithmetic either, and it wouldn't belong regardless: it reads
    ///     strangers paying you, not you paying anyone.
    ///
    /// **The REVENUE seats are out by definition, not by measurement**
    /// (2026-09-01, prd §558). Dodo Payments and Polar both land `.transaction`
    /// rows carrying a real `priceValue` AND `priceCurrency`, so both pass the
    /// data test above and the question of joining reads as open until it is
    /// answered here. It isn't open: Stripe's second reason governs all three —
    /// money ARRIVING is not money SPENT, and folding a Merchant of Record's
    /// takings into "what did I spend?" would answer that question with the
    /// opposite sign. A revenue seat's own figure belongs on its own room head
    /// (`DodoPaymentsRoom`), never in this set.
    static let cardSpendSources: Set<String> = ["Apple Wallet", "Gnosis Pay", "ether.fi"]

    /// The stable ref of a source's import receipt. Stable ON PURPOSE: a
    /// second import must UPDATE the one receipt rather than stack another,
    /// so All never accumulates a pile of "you imported" rows.
    static func importReceiptRef(source: String) -> String {
        "import:receipt:" + source.lowercased()
    }

    /// Does this thing belong in the unfiltered All feed? Everything does,
    /// except a bulk-import source's own things — and its receipt is the one
    /// exception to that exception.
    static func showsInAll(_ thing: Thing) -> Bool {
        guard bulkImportSources.contains(thing.source) else { return true }
        // A row this source received live is not part of the dump the rule
        // above exists to keep out (prd §456).
        if arrivedLive(thing) { return true }
        return isImportReceipt(thing)
    }

    /// Is this the app's own "you imported N things" row? It sits in the
    /// source's room as well as in All (see `ImportReceipt`), which makes it
    /// the one thing there that isn't something the person did — so every
    /// aggregate over a room excludes it: it would add a phantom day to a
    /// calendar year, and its `.note` body ("312 saved · 1,204 comments")
    /// would otherwise be read for topics alongside real writing.
    static func isImportReceipt(_ thing: Thing) -> Bool {
        guard bulkImportSources.contains(thing.source) else { return false }
        return thing.sourceRef == importReceiptRef(source: thing.source)
    }

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

    /// How many things exist, without materialising one — a SQL `COUNT`.
    ///
    /// One home for an expression that had grown five copies (2026-08-12).
    /// Two of them are load-bearing beyond tidiness: `FeedScreen` and
    /// `MainSurface` use this as the CHANGE SIGNAL their `.task(id:)` and
    /// `onChange(of:)` key on, because the obvious alternative — a bounded
    /// `@Query`'s `.count` — both materialises the fetch in its getter and,
    /// past the bound, stops changing at all. See `FeedScreen.corpusRevision`.
    static func count(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<Thing>())) ?? 0
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

/// One part a bridge read, kept as a part (2026-08-12, prd §365).
///
/// It exists because of a pattern the Life sheets made impossible to ignore:
/// **every Life bridge joined its facts into a display string at ingest and
/// threw the parts away.** `ContactsIngest.line(for:)` produced
/// `"Designer · Studio · ana@studio.com"`; `HomeKitIngest.line(for:home:)`
/// produced `"Lock · Front door · Reachable"`; `ScheduleIngest.eventLine`
/// produced `"14:00 · Studio"`. A sheet handed one of those can only reprint
/// it — which is exactly why the thing sheets read like a database row printed
/// as a sentence, with not one character of it tappable.
///
/// Deliberately ONE field rather than a column per source. A `place`, a
/// `jobTitle`, a `roomName`, a `distanceMeters` and a `reachable` would be five
/// additive fields today and five more the next time a bridge lands something
/// structured — and every one of them is a CloudKit Production deploy before it
/// syncs (see `docs/cloudkit-deploy.md`). The parts share one shape: a short
/// label, a value, and what tapping it should do.
///
/// `action` is what keeps this from being the spec table it replaces. A row
/// that can only be read is `.none`; a phone number is `.call`; an address is
/// `.map`. The VIEW decides how to draw a kind, so the bridge never has to know
/// about `tel:` — and a fact whose action can't be honoured simply renders as a
/// fact, never as a control that does nothing (the §83 rule).
///
/// Encoded as one string per fact so it can ride a `[String]` — the same
/// additive array shape `tags`/`ocrTopics`/`wikilinks` already use, which
/// SwiftData infers with no migration stage. The separator is US (U+001F),
/// which no label, value or action can contain: it is not typeable, does not
/// survive a copy-paste, and is the standard answer to exactly this. A fact
/// that fails to decode is DROPPED rather than rendered half-read — a row
/// saying "Lock" with no label is worse than no row.
struct ThingFact: Hashable, Identifiable, Sendable {
    /// What tapping the fact does. `none` is the common case and the default:
    /// most facts are facts.
    enum Action: String, Sendable {
        case none, call, mail, map, web
        /// A number with a unit — drawn as a metric, never as a label/value
        /// row. A run's distance, not its location.
        case metric
        /// Live state (HomeKit's reachability) — drawn as a pill whose tone is
        /// the state, never as grey prose. `value` is the state's own word and
        /// `label` is what was checked.
        case state
        /// This moment has no clock: an all-day event.
        ///
        /// It is an ACTION rather than a `Thing` column because it is a
        /// display instruction and nothing else — EventKit reports an all-day
        /// event's start as midnight, so a reader with only the dates draws
        /// "00:00" and states a time nobody meant. `endAt` cannot carry the
        /// signal either: it is deliberately nil for these, since EventKit's
        /// end is the last instant of the final day and a range of
        /// "00:00 – 23:59" is the same wrong answer wearing two clocks.
        ///
        /// The forward-compat behaviour is the reason this shape is safe: a
        /// build that predates this case decodes it to `.none` (see
        /// `init(encoded:)`) and draws it as an ordinary fact row reading
        /// "When · All day", which is still true.
        case allDay
    }

    var id: String { "\(label)\u{1F}\(value)" }

    /// Sentence case, one or two words ("Mobile", "Room", "Pace"). Never
    /// ALL-CAPS — the design law bans caps eyebrows and this is drawn as one.
    var label: String
    var value: String
    var action: Action = .none

    private static let sep = "\u{1F}"

    var encoded: String { [label, value, action.rawValue].joined(separator: Self.sep) }

    /// nil for anything that isn't exactly three non-empty-labelled parts.
    /// An unknown action decodes to `.none` rather than dropping the fact —
    /// a build that predates a new action should still show the words.
    init?(encoded: String) {
        let parts = encoded.components(separatedBy: Self.sep)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        self.label = parts[0]
        self.value = parts[1]
        self.action = Action(rawValue: parts[2]) ?? .none
    }

    init(_ label: String, _ value: String, _ action: Action = .none) {
        self.label = label
        self.value = value
        self.action = action
    }
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
    /// Local B-tree indexes on the columns the hot fetches sort and filter by
    /// (2026-09-01, perf spec P5.1). `#Index` is `@available(iOS 18, …)` and
    /// this target deploys to 18.0, so it needs no availability gate — checked
    /// against the SDK's own `SwiftData.swiftinterface`, not remembered.
    ///
    /// **This is not a schema migration and not a CloudKit ship.** An index
    /// declares no stored property, so it mints no `CD_*` field, needs no row
    /// in `docs/cloudkit-schema.ckdb`, and needs no `ThingSchemaVN` stage:
    /// `ThingSchemaVersioning`'s own rule names a rename, a type change, or a
    /// removed property whose data must move, and an index is none of the
    /// three. It is also NOT `#Unique`, which sits beside it in the API and IS
    /// banned under CloudKit mirroring (see the class doc above) — an index
    /// constrains nothing, it only tells SQLite where to look.
    ///
    /// Each one names the read it exists for:
    ///
    ///   · **`capturedAt`** — every room sorts on it, descending, as do both
    ///     `EmbeddingIndex` sweeps. Its absence is already on record as a
    ///     decision rather than an oversight: `AgentOpenCache` refused to page
    ///     its corpus walk because "`Thing.capturedAt` carries no index, so
    ///     every page would re-sort the whole table." This retroactively
    ///     legalises that paging.
    ///   · **`source, capturedAt`** — the compound is what a SOURCE room
    ///     actually asks (`WHERE source = ? ORDER BY capturedAt DESC`), which
    ///     one index answers in a single ordered walk instead of a filter and
    ///     then a sort. **There is deliberately NO standalone `source` index**:
    ///     a B-tree already serves an equality test on its LEADING column, so
    ///     the bare `source ==` reads — `MainSurface.newestPerSource`, once per
    ///     source seat, and `existingSourceRefs(_:source:)` — are covered by
    ///     this one. A second index on the same leading column would buy
    ///     nothing and still be paid for on every insert.
    ///   · **`sourceRef`** — the dedupe key, and the most-repeated lookup in
    ///     the app. `IngestSupport.existingSourceRefs` is called from 76 sites
    ///     and runs on every ingest pass of every bridge, and 32 more files
    ///     point-look-up a single `sourceRef == ref`. Every one of those was a
    ///     table scan.
    ///   · **`pinnedAt`** — the pinned room is `WHERE pinnedAt != nil ORDER BY
    ///     pinnedAt DESC` and is deliberately UNBOUNDED (a ceiling there could
    ///     hide a row you pinned on purpose), and `Pinboard.hasAny` asks the
    ///     same predicate on mount, foreground and arrival. Nearly every row is
    ///     nil, which is the shape an index answers best and a scan worst.
    ///
    /// **THE KNOWN COST, stated because it is real: an index is paid on every
    /// WRITE, and this app's writes arrive in bursts.** A bulk import lands
    /// thousands of rows in one afternoon through `ImportCommit` — a chunk is a
    /// commit — and every insert now maintains four B-trees instead of none.
    /// There is also a one-time build when an existing store first opens
    /// against this schema, which lands on a launch nobody chose.
    ///
    /// **Both costs are UNMEASURED on this host**, and so is the read win: no
    /// number here has been taken on real hardware in Release (perf spec P0).
    /// If an import or a launch gets slower, this is the first thing to A/B —
    /// interleaved, on a drained corpus, per the spec's method rule 2.
    #Index<Thing>([\.capturedAt], [\.source, \.capturedAt], [\.sourceRef], [\.pinnedAt])

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
    /// What the moved amount was WORTH, in USD, at the moment it moved
    /// (2026-08-01) — the unit the flow band needs to put a 0.5 ETH receipt
    /// and a 300 USDC payment on one scale.
    ///
    /// Read, never computed: Zerion already prices every transfer leg it hands
    /// over (the request has always carried `currency=usd`) and the parser
    /// simply threw the number away. So this costs no extra request, and it is
    /// the price AT THE TIME rather than today's — repricing an old transfer
    /// at the current rate would quietly restate history every time the market
    /// moved.
    ///
    /// nil for: the Alchemy fallback arm (which carries no price at all), any
    /// token Zerion couldn't price, and every transfer landed before this
    /// field. `WalletFlow` counts those as unpriced and says so rather than
    /// treating them as zero. Optional + default nil keeps CloudKit mirroring
    /// happy and needs no migration (additive, per the schema-versioning rule).
    var transferUSD: Double? = nil
    /// The wallet safety signals on a landed transfer — a comma-joined SET,
    /// read through `securityFlags`/`hasSecurityFlag`, never compared as a
    /// whole string.
    ///
    /// `"poisoning"` (2026-07-20): an incoming transfer whose counterparty
    /// address fuzzily mimics one this wallet has actually sent to (same
    /// leading/trailing hex, different address), the address-poisoning scam's
    /// whole mechanism. `"symbol"` (2026-07-21, prd §160): the transferred
    /// token's SYMBOL is a confusable copy of a well-known one ("ÚЅDС" for
    /// USDC) — see `SymbolConfusables`. `"spam"` (2026-08-02): an OUTBOUND
    /// transfer of a token this wallet has never held and that nobody will
    /// price — a spam contract emitting `Transfer(you → attacker)` to buy
    /// itself a seat in your history; see `WalletSafety.flagFakeTransfer`.
    /// Any of the three, the thing still lands honestly as a transfer; a flag
    /// only adds the warning.
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

    /// When a moment ENDS (2026-08-12, prd §365) — an event's end, a booking's,
    /// a workout's. The one fact the Life sheets genuinely did not have.
    ///
    /// An event has carried its START as `capturedAt` since `ScheduleIngest`
    /// shipped, and `dueAt` is documented as a reminder's field, so a duration
    /// was never computable: the sheet could say "14:00" and nothing else. Not
    /// a cosmetic gap — "14:00 – 15:00 · 1 hr" is most of what a calendar entry
    /// IS, and the old `eventLine` string could not carry it because EventKit's
    /// `endDate` was never read.
    ///
    /// Set only from a real end. An all-day event leaves it nil (its end is a
    /// calendar convention, not a moment, and rendering "00:00" would be a
    /// confident wrong answer); so does anything whose duration we would have to
    /// invent. A reader shows a range only when this is present — never a start
    /// plus a guess. Optional + default nil keeps CloudKit mirroring happy.
    var endAt: Date? = nil

    /// The parts a bridge read, kept as parts rather than joined into one
    /// display string (2026-08-12, prd §365) — see `ThingFact` above for the
    /// whole reasoning, which is the reason this field exists at all.
    ///
    /// ORDER IS THE BRIDGE'S and readers must preserve it: a contact's mobile
    /// before its email is that bridge saying which one you reach for first,
    /// and re-sorting alphabetically in a view would throw away the only
    /// ranking anybody has. Empty for every thing whose source has nothing
    /// structured to say, which is most of the corpus.
    ///
    /// An additive array field like `tags`/`ocrTopics` — SwiftData infers it,
    /// no migration stage (see `ThingSchemaVersioning`).
    var facts: [String] = []

    /// `facts`, decoded, in the bridge's own order. Undecodable entries are
    /// dropped (see `ThingFact.init(encoded:)`). Every reader goes through
    /// this rather than parsing the strings itself, so the encoding has exactly
    /// one implementation to get wrong.
    var factList: [ThingFact] { facts.compactMap(ThingFact.init(encoded:)) }

    /// When a token approval was actually GRANTED on chain (2026-07-31) — the
    /// fact the Worth-a-look tray states as "Granted Mar 2024", which is what
    /// turns a live approval from a notice into a decision: a two-year-old
    /// forgotten unlimited grant is exactly what Revoke.cash exists for, while
    /// one made this morning is probably you.
    ///
    /// It exists as its own field rather than reading `capturedAt` because
    /// `capturedAt` cannot carry this honestly. `WalletApprovals` stamps the
    /// block's real time when it can read it and falls back to `.now` when it
    /// can't — fine when the date only drives sort order, but a fallback
    /// rendered as a sentence would say "Granted today" about a grant from
    /// years ago, understating the age of exactly the approvals that most
    /// deserve attention. So this is set ONLY from a real block timestamp and
    /// left nil otherwise; the tray states an age only when one is known, and
    /// approvals landed before this field existed stay silent rather than
    /// guessing. Optional + default nil keeps CloudKit mirroring happy.
    var grantedAt: Date? = nil

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

    /// A number of money, in `priceCurrency` (2026-07-14). The row shows a
    /// formatted price in its title; this is the comparable value.
    ///
    /// **It carries three different tenses, and summing across them is wrong.**
    /// The doc used to say "nil for every non-product thing", which stopped
    /// being true the day the card seats landed:
    ///   · a PRODUCT price is CURRENT and re-checkable — the anchor that lets a
    ///     later pass say "dropped $40" (Shopify/Deals, the pasted-product
    ///     parser);
    ///   · a TRANSACTION amount is FINAL — what you were charged, and the only
    ///     tense `Corpus.cardSpendSources` may do arithmetic over;
    ///   · a SNAPSHOT is true only at `capturedAt` — a trending token's price
    ///     (GeckoTerminal, 2026-08-06), which must never paint as live. It is
    ///     safe there only because nothing draws `priceValue` on a `.link`
    ///     kind, and the sheet's own chart answers "what's it worth now".
    /// Optional + default nil keeps CloudKit mirroring happy; nil when the
    /// source quotes no number.
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

    /// How many messages a landed CONVERSATION really holds (2026-07-31). Its
    /// whole reason to exist is that `content` is a clamped transcript — the
    /// Snapchat importer keeps the newest `lineCap` lines inside a byte
    /// ceiling — so counting the lines a row stores would rank a decade-long
    /// friendship level with a week-old one. This is stamped at import from
    /// the FULL parse, before the clamp, which is the only place the true
    /// number is ever in hand. nil (not 0) when the source didn't say, the
    /// same distinction the engagement counts above keep. Additive optional —
    /// SwiftData infers it, no migration stage.
    var messageCount: Int? = nil

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
    /// subreddits you follow. Since 2026-08-06 an RSS/Substack item fills it
    /// too, from `<dc:creator>` or an Atom `<author><name>` — so a multi-author
    /// publication no longer collapses onto the publication's own name. An
    /// author that merely repeats the feed's name is dropped rather than
    /// stored. nil when the feed names nobody, and for posts landed before
    /// this field.
    var postAuthor: String? = nil

    /// A second URL a row carries beside its own permalink. Two fillers, and
    /// the doc used to name only the first:
    ///   · a Reddit post's first non-Reddit body link, captured at landing so
    ///     a later pass can notice a subreddit discussing something already
    ///     saved from elsewhere without re-parsing the post's HTML;
    ///   · a podcast episode's `<enclosure>` audio URL (2026-08-06) — the
    ///     episode itself, which the feed states and nothing else stores.
    /// nil when the row carries neither.
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

    /// What a row can REACH, detected once from this thing's own text and
    /// stored (PERF 2026-08-01, prd §260) — a `tel:` URL and a maps
    /// destination, or nil when the text holds neither.
    ///
    /// These exist because detection is a property of the CONTENT, not of the
    /// render, and it was being paid as if it were the latter. Every feed row
    /// attaches a `.contextMenu`, whose builder is non-escaping and therefore
    /// runs at body-build time for EVERY row on EVERY render; it called
    /// `VerbDerivation.verbs(for:)`, which faulted the heavy `content` column
    /// and ran two `NSDataDetector` passes (address + phone) over the full
    /// text. A profile of a swipe put that at ~21% of all busy main-thread
    /// time — the single largest cost, and per-row rather than per-corpus,
    /// which is why the lag was even across rooms rather than concentrated in
    /// a big one.
    ///
    /// Stored as `String`, not `URL`: these are CheckingType results rebuilt
    /// into schemes we construct ourselves, and a String keeps the column
    /// trivially lightweight for `propertiesToFetch`.
    var detectedTel: String? = nil
    var detectedPlace: String? = nil
    /// The mailto: compose URL, detected from the same text (added 2026-08-01,
    /// prd §262). It was left computing per row by §260 because it is a regex
    /// rather than an `NSDataDetector` and looked cheap next to the other two;
    /// a Time Profiler trace of the real device measured it at **7% of all
    /// main-thread samples** — the same mistake as its two siblings, in the one
    /// function that was judged rather than measured.
    var detectedMailto: String? = nil
    /// Which detection PASS stamped this row (prd §262). `detectedAt` answers
    /// "has it been scanned", which is not enough the moment the scan learns a
    /// new field — every already-stamped row would keep the old answer forever,
    /// which is exactly what happened when `detectedMailto` joined. Bumping
    /// `VerbDetection.version` re-enrols the whole corpus in the bounded sweep
    /// without a migration or a mass write.
    var detectionVersion: Int? = nil
    /// When detection last ran. Distinct from both fields being nil, which is
    /// the common and legitimate answer ("this text holds no phone or
    /// address") — without this marker every such thing would be re-scanned
    /// forever, which is the cost this exists to remove. See
    /// `VerbDetection.backfill`.
    var detectedAt: Date? = nil

    // MARK: - Pinned (2026-08-10)

    /// When YOU pinned this thing — the app's one editorial verb over its own
    /// corpus, and the only field here a person writes directly.
    ///
    /// **Why not `Mark.saved`,** which already exists and looks free: `mark` is
    /// owned by the task bridges. Linear, GitHub, Trello and Jira all write it
    /// from their own state (`thing.mark = now.mark` on every reconcile), so
    /// pinning an issue would overwrite its state and the next sync would
    /// silently unpin it. A pin has to be a field nothing else touches.
    ///
    /// **Why a date and not a `Bool`:** the pinned room is a LIST, and a list
    /// needs an order. Pin order is when you acted, which is the whole
    /// difference between this room and every other one in the app — every
    /// other room sorts on `capturedAt`, i.e. when the thing happened. A Bool
    /// would leave the list sorted by the corpus's clock rather than yours.
    ///
    /// nil = not pinned, which is almost every row. Additive optional, so
    /// SwiftData infers it with no migration stage — but it IS a new CloudKit
    /// field, so it ships only once `CD_pinnedAt` is deployed to Production
    /// (see docs/cloudkit-deploy.md). Unpinning writes nil; nothing about a
    /// pin is permanent to the person, only the column is permanent to iCloud.
    var pinnedAt: Date? = nil

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
