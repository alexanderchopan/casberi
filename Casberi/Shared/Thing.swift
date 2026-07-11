import Foundation
import SwiftData

/// The kind of a thing. Build brief §3 — v1 kinds; the schema leaves room for
/// the Alice kinds (job, run, output, skill) as load on this same model.
enum ThingKind: String, Codable, CaseIterable {
    // v1 (Bob)
    case note, screenshot, chat, event, link, reminder, mail, file, voice
    // Alice load (declared now; unused until bridges prove writes)
    case job, run, output, skill
    // S10 — an agent's ask, waiting on the person. The thing IS the consent
    // surface: Approve/Deny are its verbs.
    case approval
    // Onchain — a wallet's activity lands as a thing (Zerion read bridge). A
    // swap, send, or receive is a discrete event, so it fits the feed; holdings
    // and portfolio value are synthesis, not things.
    case transaction

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
        }
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
    var pinned: Bool = false
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
        pinned: Bool = false,
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
        self.pinned = pinned
        self.provenance = provenance ?? Provenance(app: source)
        self.sourceRef = sourceRef
    }
}

private extension Array where Element == String {
    /// De-dupes case-insensitively while preserving first-seen order.
    func reduced() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
