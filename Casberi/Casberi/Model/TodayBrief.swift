import Foundation
import SwiftData

/// The Today brief (prd §166, user: "lets build b2 with b3 synthesis card") —
/// the screen the whisper capsule opens, and a keepable ask in its own right
/// (`kind == "today"`).
///
/// **The module doctrine, ruled 2026-07-22.** A count is almost never the
/// fact: people receive dozens of things a day and care WHAT landed. So every
/// module here is exactly one of four shapes, and none of them is a tally:
///   1. a **visualization** (the money hero's treemap + line, the hour strip),
///   2. the **most recent thing itself**, rendered in full (the mention that
///      names you, the read worth opening),
///   3. **what's next** (the nearest real deadline),
///   4. a **synthesis card** — the agent's own read of the day.
/// Counts survive in exactly one place, where the count IS the event: money
/// moving ("1 transaction"). Everything else names its subject.
///
/// Layout is direction B2 (the mosaic): form encodes type — the fused money
/// hero leads, paired tiles carry the two glanceable reads, wide cards carry
/// things with words in them, and the hour strip closes. The synthesis card
/// from direction B3 sits at the very top, and is the one module that may
/// vanish entirely: it draws only observations that actually fired.
///
/// Deterministic throughout (docs/agent-brief.md ruling 1) — every line is
/// template-composed from facts already held. No model, ever, on this path.
@MainActor
enum TodayBrief {

    /// The words that name this ask. ONE definition, read by the typed answer
    /// path (`RootShell.answerDocument`), the keepable-kind recognizer
    /// (`Composer`), and the whisper's own tap — so a question that answers
    /// can always also be kept, and none of the three can drift.
    static func matches(_ query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "? "))
        return q == "today" || q == "my day" || q == "how's my day" || q == "hows my day"
            || q == "what's my day" || q == "whats my day"
            || q.contains("brief me") || q.contains("my day so far")
            || q.contains("catch me up on today")
    }

    /// The canonical question — what the whisper sends, and the title a kept
    /// "today" pill wears.
    static let title = String(localized: "How's my day?")

    // MARK: - Compose

    static func compose(things: [Thing], context: ModelContext) async -> KeptAskComposers.Result? {
        let now = Date.now
        let landed = DayBrief.landed(things, now: now)
        let move = DayBrief.walletMove(now: now)
        let holdings = WalletStore.shared.addresses.isEmpty
            ? []
            : await WalletIngest.topHoldingsByWallet()
        let moves = TokensAsk.watched(context).isEmpty
            ? []
            : await TokensAsk.moves(context: context)

        var ids: [String] = []
        var lines: [String] = []

        // 1. The synthesis card (B3) — only the observations that fired.
        let notes = observations(landed: landed, move: move, moves: moves, now: now)
        if !notes.isEmpty {
            ids.append("notes")
            lines.append("notes = DayNotes([\(notes.indices.map { "n\($0)" }.joined(separator: ", "))])")
            for (i, n) in notes.enumerated() {
                lines.append("n\(i) = DayNote(\"\(n.glyph)\", \"\(genSafe(n.text))\", \"\(n.thingID)\")")
            }
        }

        // 2. The money hero — the day's one fused visualization.
        if let hero = moneyHero(move: move, holdings: holdings, landed: landed) {
            ids.append("hero")
            lines.append(hero)
        }

        // 3. The pair: what's moving, what's next.
        var tiles: [String] = []
        if let movers = moversTile(moves) {
            tiles.append("tmov")
            lines.append(movers)
        }
        if let next = nextTile(things) {
            tiles.append("tnext")
            lines.append(next)
        }
        if !tiles.isEmpty {
            ids.append("pair")
            lines.append("pair = TilePair([\(tiles.joined(separator: ", "))])")
        }

        // 4. The leads — a thing in full, per shape that landed.
        if let mention = mentionCard(landed) {
            ids.append("men")
            lines += mention
        }
        if let reading = readingCard(landed) {
            ids.append("read")
            lines += reading
        }

        // 5. When it all landed — the day's own shape.
        if let strip = hourStrip(landed, now: now) {
            ids.append("hours")
            lines.append(strip)
        }

        // Nothing to draw at all — an honest empty day, not an empty screen.
        guard !ids.isEmpty else {
            return KeptAskComposers.Result(
                delta: "", digest: String(localized: "quiet"),
                doc: ["root = Stack([ins])",
                      "ins = Insight(\"\(genSafe(String(localized: "Nothing has landed yet today.")))\")"])
        }
        // The digest IS the whisper's own detail line — so the kept pill's
        // trailing signal and the capsule that teases this screen say the
        // same thing, and the changed-dot fires on exactly the days the
        // whisper would have changed. (The whisper's TITLE is deliberately
        // not part of it: a pill that already reads "How's my day?" doesn't
        // need "Your Wednesday brief" repeated after it.)
        let digest = DayBrief.detail(things: things, now: now) ?? String(localized: "quiet")
        return KeptAskComposers.Result(delta: digest, digest: digest,
                                       doc: ["root = Stack([\(ids.joined(separator: ", "))])"] + lines)
    }

    // MARK: - 1. Synthesis (direction B3)

    struct Note {
        let glyph: String
        let text: String
        var thingID: String = ""
    }

    /// The agent's read of the day — at most three observations, each a
    /// deterministic pattern that actually fired. The discipline this module
    /// lives or dies by: **a pattern that didn't fire produces no line**.
    /// Three strong lines read as intelligence; three padded ones read as a
    /// horoscope, so nothing here has a filler branch — a patternless day
    /// simply drops the card and the brief starts at the money hero.
    static func observations(landed: [Thing], move: DayBrief.WalletMove?,
                             moves: [TokensAsk.Move], now: Date) -> [Note] {
        var out: [Note] = []

        // A mention that's gathering a conversation — the reply count is the
        // pattern, not the mention itself (any mention already leads its own
        // card below; this fires only when people are talking under it).
        if let hot = landed
            .filter({ $0.socialContext == "mention" && ($0.replyCount ?? 0) >= 3 })
            .max(by: { ($0.replyCount ?? 0) < ($1.replyCount ?? 0) }),
           let replies = hot.replyCount {
            let who = hot.authorHandle ?? String(localized: "someone")
            out.append(Note(glyph: "bubble.left.and.bubble.right",
                            text: String(localized: "\(who)'s mention is gathering replies — \(replies) so far."),
                            thingID: hot.id.uuidString))
        }

        // A dominant topic across the day's reading — the same word carried by
        // three or more titles. Named by that word, with the ONE read that
        // isn't about it promoted as the outlier: the useful half of the
        // observation is what your reading ISN'T.
        if let topic = dominantTopic(landed) {
            var text = String(localized: "Your reading keeps circling \(topic.word).")
            if let outlier = topic.outlier {
                // A clamped title already ends in an ellipsis — a sentence
                // period after it renders "…." (caught on-device 2026-07-22).
                // 60, not 48: at 48 an ordinary headline cut mid-phrase right
                // above the Reading card showing the SAME headline in full,
                // which read as a rendering fault rather than a summary.
                let name = clamp(outlier.title, max: 60)
                let stop = name.hasSuffix("…") ? "" : "."
                text += " " + String(localized: "The one that doesn't: \(name)\(stop)")
            }
            out.append(Note(glyph: "newspaper",
                            text: text,
                            thingID: topic.outlier?.id.uuidString ?? ""))
        }

        // What actually moved the wallet — the day-scoped holdings
        // attribution (§166: `holdingsDeltas(forAddress:since:)`), never the
        // all-time one, so the sentence spans exactly what the percentage
        // claims. Silent when no snapshot pair covers the window.
        if let move {
            let deltas = WalletStore.shared.holdingsDeltas(forAddress: nil, since: move.since)
            if let top = deltas.first, abs(top.delta) >= 1 {
                let direction = top.delta > 0
                    ? String(localized: "did the lifting")
                    : String(localized: "took it back")
                out.append(Note(glyph: "chart.line.uptrend.xyaxis",
                                text: String(format: "%@ %@ — the wallet is %+.1f%% on the day.",
                                             top.symbol, direction, move.pct)))
            }
        }

        // A watchlist leader worth naming — only a real move, and only when
        // it clearly leads the rest (a 0.2% "leader" is noise wearing a
        // ranking). Skipped once three observations already fired.
        if out.count < 3, let leader = moves.max(by: { abs($0.change) < abs($1.change) }),
           abs(leader.change) >= 0.03 {
            out.append(Note(glyph: "chart.xyaxis.line",
                            text: String(format: "%@ leads your watchlist at %+.1f%%.",
                                         leader.symbol, leader.change * 100),
                            thingID: leader.thing.id.uuidString))
        }

        return Array(out.prefix(3))
    }

    /// The word three or more of the day's reads share, and the newest read
    /// that doesn't carry it. Deterministic and cheap: significant words only
    /// (4+ characters, not a stopword), counted across link titles.
    private static func dominantTopic(_ landed: [Thing])
        -> (word: String, outlier: Thing?)? {
        let reads = reads(landed)
        guard reads.count >= 4 else { return nil }
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for read in reads {
            // Count each word ONCE per title — a headline repeating a word
            // must not out-vote three separate articles sharing it.
            var seen = Set<String>()
            for raw in read.title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let word = String(raw)
                let key = word.lowercased()
                guard key.count >= 4, !stopwords.contains(key), seen.insert(key).inserted
                else { continue }
                counts[key, default: 0] += 1
                display[key] = word
            }
        }
        guard let (key, n) = counts.max(by: { $0.value < $1.value }), n >= 3
        else { return nil }
        let outlier = reads.first { !$0.title.lowercased().contains(key) }
        return (display[key] ?? key, outlier)
    }

    /// Words that carry no topic — common English plus the vocabulary every
    /// headline shares. Small on purpose: the 3-title floor does most of the
    /// filtering, this only stops the obvious false leaders.
    private static let stopwords: Set<String> = [
        "this", "that", "with", "from", "your", "have", "here", "what", "when",
        "will", "just", "into", "over", "more", "than", "then", "they", "them",
        "about", "after", "before", "could", "would", "should", "their", "there",
        "these", "those", "which", "while", "where", "https", "http", "www",
        "new", "news", "says", "said", "make", "makes", "made", "like", "still",
        "first", "best", "everything", "announced", "announcement",
    ]

    // MARK: - 2. The money hero (the fused visualization)

    /// `MoneyHero(total, delta, csv, subline, [cells])` — the day's one big
    /// read: the combined total, its day move, the balance line and the
    /// holdings treemap side by side, and beneath them the transactions that
    /// actually settled. The single place a count is allowed (money moving IS
    /// the event), and it names the transaction whenever there's just one.
    private static func moneyHero(move: DayBrief.WalletMove?,
                                  holdings: [WalletIngest.HoldingsGroup],
                                  landed: [Thing]) -> String? {
        guard !holdings.isEmpty else { return nil }
        let total = holdings.reduce(0) { $0 + $1.totalUSD }
        guard total > 0 else { return nil }
        // Every watched wallet's cells merged — this is the PORTFOLIO's day,
        // not the first wallet's (§155's combined read, same principle).
        let cells = holdings.flatMap(\.cells)
        guard !cells.isEmpty else { return nil }
        let samples = WalletStore.shared.combinedValueSamples()
        let csv = samples.count >= 2
            ? samples.suffix(60).map { String(format: "%.2f", $0.usd) }.joined(separator: ",")
            : ""
        let delta = move.map { String(format: "%+.1f%%", $0.pct) } ?? ""
        // The settled money of the window — the honest count, plus the name
        // when there's exactly one.
        let settled = landed.filter { $0.kind == .transaction || $0.source == "Peer" }
        // A single named transaction draws as a real ROW (title/meta/id, args
        // 6–8); the plural and empty cases have no one thing to name, so they
        // keep the plain subline.
        var subline = ""
        var txTitle = "", txMeta = "", txID = ""
        if settled.count == 1 {
            let tx = settled[0]
            txTitle = clamp(tx.title, max: 52)
            txMeta = String(localized: "your only transaction · settled \(tx.capturedAt.formatted(.dateTime.hour().minute()))")
            txID = tx.id.uuidString
        } else if settled.count > 1 {
            subline = String(localized: "\(settled.count) transactions settled")
        } else {
            subline = String(localized: "Nothing moved today")
        }
        // The line's anchor — what span the curve covers, named the way
        // `ValueSpark`'s own subline names it.
        let anchor = samples.count >= 2
            ? (move.map { String(localized: "since \($0.since.formatted(.dateTime.month(.abbreviated).day()))") } ?? "")
            : ""
        return "hero = MoneyHero(\"\(genSafe(compactUSD(total)))\", \"\(delta)\", \"\(csv)\", \"\(genSafe(subline))\", [\(cells.prefix(6).joined(separator: ", "))], \"\(genSafe(anchor))\", \"\(genSafe(txTitle))\", \"\(genSafe(txMeta))\", \"\(txID)\")"
    }

    // MARK: - 3. The pair

    /// `MoversTile(label, "SYM|+4.2%,…")` — the watchlist at a glance. Real
    /// direction gets real color here (unlike `StatRow`'s neutral counts): a
    /// price move HAS a sign. A move that rounds to flat says "flat" and takes
    /// no color, per §83.
    private static func moversTile(_ moves: [TokensAsk.Move]) -> String? {
        guard !moves.isEmpty else { return nil }
        let rows = moves
            .sorted { abs($0.change) > abs($1.change) }
            .prefix(3)
            .map { m -> String in
                let pct = m.change * 100
                let value = abs(pct) < 0.05
                    ? String(localized: "flat")
                    : String(format: "%+.1f%%", pct)
                return "\(tileSafe(m.symbol))|\(value)"
            }
        return "tmov = MoversTile(\"\(String(localized: "Watchlist"))\", \"\(rows.joined(separator: ","))\")"
    }

    /// `NextTile(label, title, when, alert, thingID)` — the nearest real
    /// DEADLINE, plus the overdue tail as its alert line.
    ///
    /// Deadlines only, never calendar events: an event's start rides
    /// `capturedAt`, and folding those in here would rebuild exactly the
    /// day-planner lane §101 cut ("a person who sees their whole day in
    /// Casberi stops opening their calendar"). Same scoping the `upcoming`
    /// composer already holds to.
    private static func nextTile(_ things: [Thing]) -> String? {
        let open = things.filter { $0.mark != .done && $0.dueAt != nil }
        let ahead = open.filter { ($0.dueAt ?? .distantPast) >= .now }
            .sorted { ($0.dueAt ?? .now) < ($1.dueAt ?? .now) }
        let overdue = open.filter { ($0.dueAt ?? .distantFuture) < .now }
        guard let next = ahead.first ?? overdue.first else { return nil }
        let when = (next.dueAt ?? .now).formatted(.dateTime.weekday(.abbreviated).hour().minute())
        var alert = ""
        if !overdue.isEmpty {
            if overdue.count == 1, overdue[0].id == next.id {
                alert = String(localized: "overdue")
            } else {
                let late = overdue.filter { $0.id != next.id }
                if late.count == 1 {
                    alert = String(localized: "\(clamp(late[0].title, max: 28)) is late")
                } else if late.count > 1 {
                    alert = String(localized: "\(late.count) more overdue")
                }
            }
        }
        return "tnext = NextTile(\"\(String(localized: "Up next"))\", \"\(genSafe(clamp(next.title, max: 40)))\", \"\(genSafe(when))\", \"\(genSafe(alert))\", \"\(next.id.uuidString)\")"
    }

    // MARK: - 4. The leads (the thing itself, in full)

    /// The mention that names you, rendered as the real post — author, their
    /// words, their avatar. The card's title says WHY it's here.
    private static func mentionCard(_ landed: [Thing]) -> [String]? {
        let mentions = landed.filter { $0.socialContext == "mention" }
        guard let mention = mentions.first else { return nil }
        let words = mention.postText ?? mention.title
        let author = mention.authorHandle ?? mention.source
        // The meta line carries the conversation's size and what's behind it —
        // the one place the module admits there's more, and it NAMES the rest
        // rather than only counting the first.
        var meta: [String] = []
        if let replies = mention.replyCount, replies > 0 {
            meta.append(replies == 1 ? String(localized: "1 reply")
                                     : String(localized: "\(replies) replies"))
        }
        if mentions.count > 1 {
            meta.append(String(localized: "\(mentions.count - 1) more behind it"))
        }
        return ["men = Widget(\"\(genSafe(String(localized: "\(mention.source) · mentions you")))\", \"\", [m0])",
                "m0 = LeadPost(\"\(genSafe(author))\", \"\(genSafe(clamp(words, max: 200)))\", \"\(genSafe(mention.authorAvatarURL ?? ""))\", \"\(genSafe(meta.joined(separator: " · ")))\", \"\(mention.id.uuidString)\")"]
    }

    /// The one read worth opening — the topic outlier when the day has a
    /// dominant topic (the interesting one is the one that ISN'T like the
    /// others), else simply the newest. The residue is named, never counted:
    /// "the rest keeps circling Samsung".
    private static func readingCard(_ landed: [Thing]) -> [String]? {
        let reads = reads(landed)
        guard !reads.isEmpty else { return nil }
        let topic = dominantTopic(landed)
        let lead = topic?.outlier ?? reads[0]
        let meta = "\(genSafe(lead.source)) · \(shortTime(lead.capturedAt))"
        var refs = ["r0"]
        var doc = ["", "r0 = LeadRow(\"\(genSafe(lead.title))\", \"\(meta)\", \"\(genSafe(lead.previewImageURL ?? ""))\", \"\(lead.id.uuidString)\")"]
        // The residue gets somewhere to GO (2026-07-22) — it was a plain
        // subline naming a topic the person then had no way to see. Asking
        // the topic re-runs the deterministic retriever and pushes the result
        // onto the agent's own Stack.
        if let topic, reads.count >= 2 {
            // The label deliberately does NOT re-name the topic: the synthesis
            // note above already said "your reading keeps circling Samsung",
            // and repeating it here made the word appear three times on one
            // screen. The QUERY is still the topic — the link just doesn't
            // narrate what the card above it already established.
            refs.append("rmore")
            doc.append("rmore = AskMore(\"\(genSafe(String(localized: "See the rest")))\", \"\(genSafe(topic.word))\")")
        }
        doc[0] = "read = Widget(\"\(String(localized: "Reading"))\", \"\", [\(refs.joined(separator: ", "))])"
        return doc
    }

    // MARK: - 5. The hour strip

    /// `Bars` over the window's hours — the day's own shape, and the one
    /// module that answers "when did all this arrive" rather than "what is
    /// it". Buckets to keep the bar count readable; drops entirely when the
    /// day is too thin to have a shape.
    private static func hourStrip(_ landed: [Thing], now: Date) -> String? {
        guard landed.count >= 6 else { return nil }
        let start = DayBrief.windowStart(now: now)
        let span = now.timeIntervalSince(start)
        guard span >= 3600 else { return nil }
        let buckets = 8
        let width = span / Double(buckets)
        var counts = [Int](repeating: 0, count: buckets)
        for thing in landed {
            let offset = thing.capturedAt.timeIntervalSince(start)
            let i = min(buckets - 1, max(0, Int(offset / width)))
            counts[i] += 1
        }
        // Three anchors — the ends, plus the MIDPOINT (2026-07-22). With ends
        // alone an overnight window's long quiet stretch is unreadable: two
        // stamps eight buckets apart say nothing about where 2am sits. One
        // middle label makes the shape legible without turning the strip into
        // an axis (nothing draws a grid; the hairline law holds on charts).
        // The blanks are a SPACE, not an empty string: `GenBars` splits its
        // label CSV with `split(separator:)`, which omits empty subsequences,
        // so empty labels collapsed the array and every stamp bunched under
        // the first bars (caught on-device 2026-07-22).
        let labels = (0..<buckets).map { i -> String in
            guard i == 0 || i == buckets / 2 || i == buckets - 1 else { return " " }
            let at = start.addingTimeInterval(width * Double(i))
            return at.formatted(.dateTime.hour())
        }
        return "hours = Bars(\"\(String(localized: "When it landed"))\", \"\", \"\(counts.map(String.init).joined(separator: ","))\", \"\(labels.joined(separator: ","))\")"
    }

    // MARK: - Shared

    /// What "reading" actually means here: link things MINUS the money
    /// sources. A watched token and a trending pool both land as `.link`
    /// (their content is a Dexscreener URL, which is what makes their sheet
    /// draw a chart) — so an unfiltered `kind == .link` filed "dogwifhat ·
    /// $WIF" under Reading and let it win the topic outlier, caught on-device
    /// 2026-07-22. Scoped by the catalog's OWN category vocabulary rather than
    /// a hardcoded source list, so a market source added later is excluded for
    /// free.
    private static func reads(_ landed: [Thing]) -> [Thing] {
        landed.filter { $0.kind == .link && !moneySources.contains($0.source) }
    }

    private static let moneySources: Set<String> = Set(
        BridgeCatalog.offers
            .filter { ["Markets", "Wallet"].contains(BridgeCatalog.category(of: $0)) }
            .map(\.name)
    )

    /// $20,480 → "$20,480"; big numbers compact, matching the wallet room's
    /// own money grammar.
    private static func compactUSD(_ usd: Double) -> String {
        if usd >= 100_000 {
            return "$" + (usd / 1000).formatted(.number.precision(.fractionLength(0))) + "K"
        }
        return "$" + usd.formatted(.number.precision(.fractionLength(0)))
    }

    private static func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    private static func clamp(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        let cut = t.prefix(max)
        if let space = cut.lastIndex(of: " ") {
            return String(cut[cut.startIndex..<space]) + "…"
        }
        return String(cut) + "…"
    }

    /// A symbol safe for the `MoversTile` grammar, whose `,` and `|` are its
    /// field separators (the same treatment `KeptAskComposers.allocSafe`
    /// gives `AllocBar`'s segments).
    private static func tileSafe(_ s: String) -> String {
        genSafe(s).replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: ",", with: " ")
    }

    /// Strips what would break the one-line gen-UI grammar — the same
    /// file-private treatment `HomeComposition`/`RootShell`/`KeptAskComposers`
    /// each already keep their own copy of (the standing convention here).
    private static func genSafe(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
