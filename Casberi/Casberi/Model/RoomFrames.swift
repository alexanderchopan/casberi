import Foundation

/// WHAT A TRANSACTION RAN — the Frames scope's reading, in every room that has
/// one (prd §698).
///
/// **Three rooms, one question, and three answers before this.** Hegotá UTXO
/// counted frames over its framed transactions and drew them as mode-coloured
/// strips; Hegotá Privacy counted `frameCount` and drew a GAS BUDGET BAR, which
/// answers what the steps were allowed to COST rather than what they did;
/// Hegotá Frames counted every row it had — single-step transactions included —
/// and then listed only the multi-step ones, so its headline could say "14
/// steps" over four rows. This is the one definition all three take.
///
/// **A STEP IS A FRAME.** The population is every transaction that ran at least
/// one, and the headline counts frames over exactly the population the list
/// shows. That equality is the whole point: the three defects above are three
/// spellings of a scope disagreeing with itself.
///
/// **MODE IS THE FILL; OUTCOME OVERRIDES IT.** A segment's width is what the
/// step cost and its colour is what the step DID — each chain's own mode
/// vocabulary, which is the one thing these rooms may legitimately differ on.
/// Three overrides, in this order, because each is something a reader must not
/// miss and a mode name is not: a FAILED step takes the alarm colour, a ROLLED
/// BACK one is drawn as an outline (it ran and was undone — a different fact
/// from failing), and an UNREAD one is hollow (a step whose receipt we could
/// not pair is not a step that went wrong — §515a's rule, that zero and unknown
/// are different readings).
///
/// Foundation-only so every room's harness can drive it. The colours live in
/// the view, which takes a per-room hue for a mode NAME.
enum RoomFrames {

    /// What became of one step.
    enum Outcome: String, Equatable, Sendable, CaseIterable {
        case ran, failed, rolledBack, unread
    }

    /// One frame of one transaction.
    struct Step: Identifiable, Equatable, Sendable {
        /// This chain's own word for what the step was — "Verify", "Sender",
        /// "UTXO", or "Mode 7" where the chain publishes a number nobody has
        /// named. **Never a borrowed neighbour's noun**: the numbering is
        /// EIP-8141's and the names are not, so a room that has not measured
        /// its modes says the number rather than guessing a name (§83).
        let modeName: String
        /// What this step cost, for the segment's width. Zero means unread, and
        /// the shares fall back to an even split rather than drawing a strip of
        /// nothing.
        let weight: Double
        let outcome: Outcome
        /// Position in its own run — the id a `ForEach` keys on, and the index
        /// a tap hands back to open that step's sheet.
        let id: Int
    }

    /// One transaction's steps, in the order they ran.
    struct Run: Identifiable, Equatable, Sendable {
        let id: String
        let steps: [Step]
    }

    /// The census over every run in the scope — what the headline, the caption
    /// and the legend are all made of, so none of them can count differently
    /// from the others.
    struct Mix: Equatable, Sendable {
        struct Slice: Identifiable, Equatable, Sendable {
            let modeName: String
            let count: Int
            var id: String { modeName }
        }

        let slices: [Slice]
        /// Transactions counted — never the step count, which is `total`.
        let transactions: Int
        let total: Int
        let failed: Int
        /// Ran and was undone. Kept apart from `failed` because they are
        /// different facts and only one of them means something went wrong.
        let rolledBack: Int
        /// Steps whose receipt could not be paired, so the outcome is unknown.
        let unread: Int

        /// The modes that SHARE the top count — one normally, several on a tie.
        ///
        /// **`slices` is the drawing's ORDER; this is the CAPTION's question,
        /// and they are not the same question** (`HegotaFrameMix.leaders`'
        /// hard-won note, inherited): `mix(_:)` breaks a tie on the mode's own
        /// name so the figure is stable between opens, which is right for an
        /// order and wrong for a superlative. On a 7–7 split the caption said
        /// "mostly Send steps" because Send sorts first.
        var leaders: [Slice] {
            guard let top = slices.first?.count else { return [] }
            return slices.filter { $0.count == top }
        }

        /// True only where one mode really does lead a field of several.
        var hasCommonest: Bool { leaders.count == 1 && slices.count > 1 }
    }

    /// **ONE VOCABULARY FOR ONE NUMBERING (prd §698).** The mode is EIP-8141's
    /// number and the three rooms had three names for it: Hegotá UTXO said
    /// Call / Verify / Send / Check / UTXO, Hegotá Frames said Default /
    /// Verify / Sender / "Mode N", and Hegotá Privacy read the number and named
    /// nothing at all. Same field, same spec, three glossaries — which is
    /// §500's own complaint ("one room using two words for one thing") across
    /// rooms instead of within one.
    ///
    /// Hegotá UTXO's words win because they were the deliberated ones:
    /// **Call** for the general frame (a call is what it is; "Default" names
    /// its position in a table, not its job), **Send** for the value-moving
    /// frame, **Check** for an assertion, and the literal **UTXO** and
    /// **Verify** for the two the specs name themselves.
    ///
    /// **An unnamed number says its number.** Mode 7 is "Mode 7" — a name
    /// guessed from a neighbour's table is exactly the overclaim §83 bans, and
    /// this chain family is young enough that a new mode is an ordinary event.
    /// A step whose mode was not read at all is "Step".
    static func modeName(_ raw: UInt64?) -> String {
        guard let raw else { return String(localized: "Step") }
        switch raw {
        case 0: return String(localized: "Call")
        case 1: return String(localized: "Verify")
        case 2: return String(localized: "Send")
        case 3: return String(localized: "Check")
        case 5: return String(localized: "UTXO")
        default: return String(localized: "Mode \(String(raw))")
        }
    }

    /// Every transaction that ran at least one step. **The list and the
    /// headline both read this**, which is what stops them disagreeing.
    static func runs(_ all: [Run]) -> [Run] { all.filter { !$0.steps.isEmpty } }

    static func mix(_ all: [Run]) -> Mix? {
        let framed = runs(all)
        guard !framed.isEmpty else { return nil }

        var tally: [String: Int] = [:]
        var failed = 0, rolledBack = 0, unread = 0, total = 0
        for run in framed {
            for step in run.steps {
                tally[step.modeName, default: 0] += 1
                total += 1
                switch step.outcome {
                case .failed:      failed += 1
                case .rolledBack:  rolledBack += 1
                case .unread:      unread += 1
                case .ran:         break
                }
            }
        }
        let slices = tally.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }.map { Mix.Slice(modeName: $0.key, count: $0.value) }
        return Mix(slices: slices, transactions: framed.count, total: total,
                   failed: failed, rolledBack: rolledBack, unread: unread)
    }

    /// **"N steps", not "N transactions"** — the transaction count is the
    /// Activity scope's headline one chip away, so repeating it here would make
    /// two scopes look like one reading twice. What this scope adds is that
    /// those transactions are made of parts.
    static func headline(_ mix: Mix?) -> String? {
        guard let mix, mix.total > 0 else { return nil }
        return mix.total == 1 ? String(localized: "1 step")
                              : String(localized: "\(String(mix.total)) steps")
    }

    /// The caption over the strips — Hegotá UTXO's sentence, now everyone's.
    ///
    /// **It is not the headline said twice**: the headline counts STEPS and
    /// this counts TRANSACTIONS (§510's exact confusion), and it is the only
    /// place a failed or rolled-back step is named.
    ///
    /// A failure is rare by construction, so it is worth the whole caption when
    /// it happens rather than a share of one. A rollback comes second for the
    /// same reason and because it is the lesser fact.
    ///
    /// **Mode names are NOT lowercased.** A mode label is a NAME and one of
    /// them is an initialism — lowercasing rendered a chain's own word as
    /// "mostly utxo steps", which is §500's naming ruling broken by a string
    /// transform rather than by a decision.
    static func caption(_ mix: Mix) -> String {
        let leaders = mix.leaders
        guard !leaders.isEmpty else { return String(localized: "What your transactions ran") }
        let what = mix.transactions == 1
            ? String(localized: "1 transaction")
            : String(localized: "\(String(mix.transactions)) transactions")
        if mix.failed > 0 {
            return mix.failed == 1
                ? String(localized: "\(what) · 1 step failed")
                : String(localized: "\(what) · \(String(mix.failed)) steps failed")
        }
        if mix.rolledBack > 0 {
            return mix.rolledBack == 1
                ? String(localized: "\(what) · 1 step rolled back")
                : String(localized: "\(what) · \(String(mix.rolledBack)) steps rolled back")
        }
        if mix.hasCommonest {
            return String(localized: "\(what) · mostly \(leaders[0].modeName) steps")
        }
        // ONE mode present is not "mostly" anything — it is all of them.
        if mix.slices.count == 1 {
            return String(localized: "\(what) · all \(leaders[0].modeName) steps")
        }
        if leaders.count == 2 {
            return String(localized: "\(what) · \(leaders[0].modeName) and \(leaders[1].modeName), evenly")
        }
        return String(localized: "\(what) · no commonest step")
    }

    /// **THE LEGEND AND THE BARS COUNT DIFFERENT POPULATIONS, and this is what
    /// says so** (prd §510). The legend is a census over every framed
    /// transaction — it is what the "N steps" headline is made of — while the
    /// drawing is capped. Naming the remainder without naming the census leaves
    /// the contradiction intact, so both halves are stated or neither is.
    static func censusNote(drawn: Int, of runs: Int) -> String? {
        guard runs > drawn else { return nil }
        return String(localized: "\(String(drawn)) of \(String(runs)) shown · step counts cover all")
    }

    /// **A STEP THE STRIP CANNOT SHOW IS A STEP THE READER CANNOT COUNT.** A
    /// frame that burned a thousandth of the gas still ran, and at its true
    /// width it is a sub-pixel sliver — which reads as four steps where there
    /// were five. The clamp costs proportionality at the bottom of the range
    /// and buys the count being right, which is the fact the strip is for.
    static let minShare: Double = 0.12

    /// Each step's share of its run's width, by what it cost.
    ///
    /// **Weighted ONLY when every step carries a weight.** A strip where three
    /// steps are measured and one is not would draw the unmeasured one at
    /// whatever the arithmetic happened to leave over and present that as its
    /// cost — a number invented by the drawing. All-or-nothing, so a partial
    /// read falls back to equal widths, which claims nothing.
    ///
    /// **RESERVE, then share out the remainder — do NOT clamp and
    /// renormalise.** Renormalising after a clamp pushes the clamped step back
    /// BELOW its floor (measured on Hegotá Privacy: weights 900 and 1 give
    /// 0.107 against a 0.12 floor), so the guarantee the floor exists for is
    /// silently broken by the step meant to preserve the total. A floored step
    /// keeps exactly `minShare` and everything above the floor divides what is
    /// left. Iterated, because giving one step the floor can push the next
    /// below it.
    ///
    /// Lifted from `PrivacyDevnetFigure.shares`, which had reasoned every line
    /// of this out and then lost its only caller when §606 replaced that room's
    /// per-frame strip with a budget bar — so the family's best implementation
    /// of this had been dead code with live tests over it.
    static func shares(_ steps: [Step]) -> [Double] {
        guard !steps.isEmpty else { return [] }
        let equal = Array(repeating: 1.0 / Double(steps.count), count: steps.count)
        // A zero weight is "unread" here: none of the three chains publishes a
        // step that genuinely cost nothing, and a mixed read must not be drawn
        // as a measurement.
        guard !steps.contains(where: { $0.weight <= 0 }) else { return equal }
        let values = steps.map(\.weight)
        let total = values.reduce(0, +)
        guard total > 0 else { return equal }
        // Past this many steps the floor cannot be honoured at all, so the
        // strip stops pretending and draws equal widths — the honest reading of
        // "these are too many to compare".
        guard Double(steps.count) * minShare <= 1 else { return equal }

        var share = values.map { $0 / total }
        var floored = Array(repeating: false, count: steps.count)
        while true {
            let below = share.indices.filter { !floored[$0] && share[$0] < minShare }
            if below.isEmpty { break }
            for i in below { floored[i] = true; share[i] = minShare }
            let reserved = Double(floored.filter { $0 }.count) * minShare
            let free = share.indices.filter { !floored[$0] }
            let freeTotal = free.reduce(0.0) { $0 + values[$1] }
            guard freeTotal > 0, !free.isEmpty else { return equal }
            for i in free { share[i] = (values[i] / freeTotal) * (1 - reserved) }
        }
        return share
    }
}
