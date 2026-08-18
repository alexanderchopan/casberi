import Foundation

/// THE RADICLE ROOM'S HEAD (prd §401, 2026-08-18) — what is stuck.
///
/// §400 shipped this seat deliberately headless. Its own first draft proposed a
/// span strip fed by `/activity`, and the measurement killed it: that endpoint
/// returns a trailing ~365-day window (oldest entry 363/339/343/362/152/359
/// days ago across six measured repos), so a strip drawn from it would claim a
/// span it structurally cannot see — the exact bug §398 had just fixed for the
/// journals. The entry said the honest head was "a separate pass over the dates
/// the bridge DOES recover exactly". This is that pass.
///
/// ## The reading
///
/// A room of patch and issue rows newest-first tells you what happened last. It
/// cannot tell you that a patch has been sitting unreviewed since March, which
/// is the only fact here that changes what you do next. So this card is
/// **oldest-open-first**: what has been waiting longest, across every repo you
/// watch.
///
/// ## Why the ages are honest
///
/// `OpenItem.opened` is `revisions[0].timestamp` for a patch and
/// `discussion[0].timestamp` for an issue — recovered from Radicle's own
/// record, exact, and NOT a mark of when this device first looked. So "open
/// since March" is a fact about the patch.
///
/// That is the sharp contrast with the same room's issue CLOSES, which carry no
/// timestamp anywhere on the wire and are therefore stamped with when we
/// watched the count move (`ASCStanding.observed`'s situation). One room, two
/// date grades, and the difference is stated rather than smoothed: this card
/// only ever draws the exact kind.
///
/// ## It spends nothing
///
/// `RadicleStore.openItems` is written by the sweep from the patch and issue
/// pages it ALREADY fetches when the snapshot diff says a count moved — pages
/// that until now were read for what to land and then thrown away. No request,
/// no new `Thing` property, no CloudKit deploy.
///
/// It reads STATE and not rows, like `ASCRoom` and unlike `CursorRoom`, and for
/// the same reason: a landed row says a patch was PROPOSED, and no arrangement
/// of landed rows can say it is still unresolved. "Has no merge row yet" is not
/// the same claim — an ARCHIVED patch never gets one either, and would sit on
/// this card forever.
///
/// ## What it may NOT draw
///
/// **No count of open work as the headline** — that is a tally, and §223 is
/// unambiguous. The count appears only as the subline under a named item.
///
/// **No velocity, no "usually merged in N days", no burn-down.** The store
/// holds what is open NOW and nothing about what closed; every rate that could
/// be drawn from it would be computed over the window we happened to observe.
///
/// **No claim about a repo we could not name.** A watched repo whose name has
/// not been learned yet is drawn by its own id rather than a stand-in, and a
/// repo with nothing open contributes nothing rather than a zero row.
///
/// **A DRAFT is never called stuck.** It is your own unfinished work, waiting
/// on nobody — it is counted apart and never leads the card, or the first thing
/// this room would say is that your scratch branch needs attention.
///
/// Foundation-only by design so `scripts/radicle-selftest.sh` can compile it
/// WHOLE and unmodified.
struct RadicleRoom: Equatable {

    struct Item: Equatable {
        let kind: RadicleWire.OpenItem.Kind
        let title: String
        let opened: Date
        /// The repo this belongs to, as a person reads it — its learned name,
        /// or its id when the sweep has not named it yet. Never a stand-in.
        let repo: String
        /// The repo's id, for the permalink.
        let rid: String
        let id: String

        /// Whole days open, floored, as of `now`. Floored rather than rounded
        /// because a patch opened this morning must read as 0 and not 1.
        func daysOpen(asOf now: Date) -> Int {
            max(0, Int(now.timeIntervalSince(opened) / 86_400))
        }
    }

    /// What is stuck, longest-waiting first. Drafts excluded.
    let items: [Item]
    /// Your own unfinished patches — counted, never ranked with the rest.
    let drafts: Int
    /// How many repos contributed something open.
    let repos: Int

    /// The oldest thing waiting, which is what the card leads with.
    var oldest: Item? { items.first }

    /// The count line. A number, and never the headline — the headline is an
    /// ITEM (§223: a tally is not a thing; here it is context for one).
    func subline(asOf now: Date) -> String? {
        guard items.count > 1 else { return nil }
        if repos > 1 {
            return String(localized: "\(items.count) open across \(repos) repos")
        }
        return String(localized: "\(items.count) open")
    }

    /// Said only when there are drafts, and always apart from the count above,
    /// so unfinished work of your own is never added into "waiting".
    var draftLine: String? {
        guard drafts > 0 else { return nil }
        return drafts == 1
            ? String(localized: "1 draft of your own")
            : String(localized: "\(drafts) drafts of your own")
    }

    // MARK: - Compose

    /// The most items the card draws.
    static let cap = 5
    /// Below this there is nothing worth a card: one open patch in one repo is
    /// already the first row of the room, and a head that repeats the row under
    /// it is furniture. Two is the smallest set that can carry the reading this
    /// card exists for — which of them has waited longer.
    static let floor = 2

    /// Builds the card, or nil when there is nothing stuck.
    ///
    /// Takes plain values rather than the store, so this file stays
    /// Foundation-only and the harness compiles it whole.
    static func compose(
        repos: [(rid: String, name: String?, items: [RadicleWire.OpenItem])]
    ) -> RadicleRoom? {
        var items: [Item] = []
        var drafts = 0
        var contributing: Set<String> = []
        for repo in repos {
            let label = repo.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            for item in repo.items {
                if item.isDraft { drafts += 1; continue }
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                contributing.insert(repo.rid)
                items.append(Item(kind: item.kind, title: title, opened: item.opened,
                                  // The learned name, else the id itself. An
                                  // id is not pretty and is the truth; a
                                  // stand-in like "a repo" would be neither.
                                  repo: (label?.isEmpty == false) ? label! : repo.rid,
                                  rid: repo.rid, id: item.id))
            }
        }
        guard items.count >= floor else { return nil }
        // TOTAL, so the card cannot reshuffle between two opens over identical
        // data (the `ASCRoom` rule). Oldest first, then the id, which is unique.
        items.sort {
            if $0.opened != $1.opened { return $0.opened < $1.opened }
            return $0.id < $1.id
        }
        return RadicleRoom(items: Array(items.prefix(cap)),
                           drafts: drafts, repos: contributing.count)
    }
}
