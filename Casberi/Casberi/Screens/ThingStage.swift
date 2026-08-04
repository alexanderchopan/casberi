import SwiftUI

/// The stage (thing sheet B1, 2026-07-16; ledger relayout 2026-08-04): a
/// wallet transfer's hero. The party/arrow tableau retired for the LEDGER
/// layout the user picked from mockups — left-aligned and typographic, like a
/// bank statement done well: the verb line says what happened in a sentence
/// ("Received from maria.eth"), the signed amount is the headline underneath,
/// the fiat-at-landing line prices it when Zerion did (`transferUSD`), the
/// counterparty is one tappable row that discloses your shared history
/// in place, and the facts sit in one spec slab (Into/From · Network ·
/// Landed). A gain wears confirm green — the whole amount now, per the
/// approved mockup, not just its sign — while a send stays white (spending
/// isn't a loss state; red would editorialize).
///
struct TransferStage {
    enum Direction { case sent, received }
    let direction: Direction
    /// "0.9962 ETH" — the words between the verb and the clauses.
    let amount: String
    /// The counterparty's display name ("Mom", "Uniswap") — from
    /// `transferCounterparty` (kept in step with renames by the rename flow),
    /// or parsed from the title for pre-field transfers. The display fallback
    /// when no hex was captured to resolve live.
    let titledName: String?
    /// The venue a Solana move rode ("Jupiter") — the title's " on …" tail.
    /// A where, not a who: it joins the chain subline, never the party row.
    let venue: String?

    init?(_ thing: Thing) {
        guard thing.kind == .transaction, thing.source == "Wallet" else { return nil }
        let title = thing.title

        // Structured fields first (2026-07-16): a transfer landed since the
        // fields existed carries direction/amount/counterparty/venue as data
        // (stamped at ingest by WalletIngest/SolanaActivity, and
        // `transferCounterparty` rewritten by the rename flow beside the
        // title), so the stage never re-derives a fact from a sentence. An
        // unrecognized direction (a newer device's sync) falls through to
        // the title parse.
        let fieldDirection: Direction? = switch thing.transferDirection {
        case "sent": .sent
        case "received": .received
        default: nil
        }
        if let fieldDirection, let amount = thing.transferAmount, !amount.isEmpty {
            direction = fieldDirection
            self.amount = amount
            venue = thing.transferVenue
            titledName = thing.transferCounterparty
            return
        }

        // The title parse — the fallback for transfers landed before the
        // fields existed.
        let direction: Direction, prefix: String, delim: String
        if title.hasPrefix("Sent ") {
            (direction, prefix, delim) = (.sent, "Sent ", " to ")
        } else if title.hasPrefix("Received ") {
            (direction, prefix, delim) = (.received, "Received ", " from ")
        } else {
            return nil
        }
        self.direction = direction
        var rest = String(title.dropFirst(prefix.count))
        // FORWARD search: the amount is numbers and a space-less symbol, so
        // the FIRST delimiter is always the clause boundary — a counterparty
        // named "Gift to Mom" splits correctly, where a backwards search
        // would land inside the name.
        if let r = rest.range(of: delim) {
            titledName = String(rest[r.upperBound...])
            rest = String(rest[..<r.lowerBound])
        } else {
            titledName = nil
        }
        // Solana's titles carry the venue instead of a counterparty ("Sent
        // 0.5 SOL on Jupiter" — SolanaActivity.title); without this split the
        // venue rides inside the giant amount.
        if titledName == nil, let r = rest.range(of: " on ") {
            venue = String(rest[r.upperBound...])
            rest = String(rest[..<r.lowerBound])
        } else {
            venue = nil
        }
        guard !rest.isEmpty else { return nil }
        amount = rest
    }
}

/// The stage rendered as a LEDGER (2026-08-04, user-picked mockup): verb line
/// → amount → fiat → counterparty row → spec slab. Naming still lives on the
/// dial's Name disc and the "Name this address?" nudge card (2026-07-23, user:
/// three doors to one action) — the counterparty row here is the door to your
/// SHARED HISTORY only, disclosed in place rather than presented (the sheet
/// already carries three sibling `.sheet`s and deliberately refuses a fourth).
struct TransferStageView: View {
    let thing: Thing
    let stage: TransferStage
    @Environment(\.modelContext) private var modelContext

    /// The other Wallet transfers with this counterparty (this one excluded —
    /// you're looking at it), newest first. Read through `AddressActivity`,
    /// the ONE definition of address activity, then narrowed to Wallet rows
    /// because the row's claim is "transfers with you" — a Peer fill this
    /// address made is activity, but it isn't *with* you. Held as `KeyedThing`
    /// so the disclosure's `ForEach` and row bodies follow the liveness rules.
    @State private var sharedHistory: [KeyedThing] = []
    /// Total Wallet transfers with this counterparty, this one included —
    /// "3 transfers with you" counts the one on screen.
    @State private var transferCount = 0
    @State private var historyShown = false

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            verbLine
            amountLine
                .padding(.top, DS.Space.s1)
            if let usd = thing.transferUSD {
                // Priced AT LANDING (`transferUSD`, read off Zerion's own
                // leg pricing) — never today's rate, which would restate
                // history every time the market moved. nil (the Alchemy
                // fallback arm, unpriced tokens, pre-field transfers) shows
                // nothing rather than a guess.
                Text("≈ \(Self.fiat(usd)) when it landed")
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
            }
            if hasCounterparty {
                counterpartyCard
                    .padding(.top, DS.Space.s4)
            }
            specSlab
                .padding(.top, hasCounterparty ? DS.Space.s3 : DS.Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard thing.isLive else { return }
            loadHistory()
        }
    }

    /// A counterparty exists when there's anything true to draw — a captured
    /// hex or a name the title carries. Neither → the stage is just the amount.
    private var hasCounterparty: Bool {
        !(thing.counterpartyAddress ?? "").isEmpty || stage.titledName != nil
    }

    // MARK: - Verb line + amount

    /// What happened, as a sentence — "Received from maria.eth" / "Sent to
    /// maria.eth", the name a step heavier than the verb. No counterparty →
    /// the bare verb.
    private var verbLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1 + 1) {
            if hasCounterparty {
                Text(stage.direction == .sent ? "Sent to" : "Received from")
                    .foregroundStyle(DS.textSecondary)
                Text(verbatim: counterpartyLabel)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(stage.direction == .sent ? "Sent" : "Received")
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .dsText(.callout15)
    }

    /// The signed amount as the headline, on the sheet's hero-money rung. A
    /// gain wears confirm green — the whole figure now, not just its sign
    /// (2026-08-04, the approved mockup; green on a gain is still color as
    /// STATE) — while a send stays white (spending isn't a loss state; red
    /// would editorialize).
    private var amountLine: some View {
        Text(verbatim: (stage.direction == .sent ? "−" : "+") + stage.amount)
            .foregroundStyle(stage.direction == .received ? DS.confirm : DS.textPrimary)
            // Clamp to one line (2026-07-23): a spoofed token's "name" is
            // attacker-controlled text ("4,672 USDT Staked • gitos.org" —
            // a phishing domain), and rendering it huge across two wrapped
            // lines amplified exactly the lie the warning below is calling
            // out. The real amount reads at the front; the full (untrusted)
            // spelling still lives in Copy and the warning line, so nothing
            // is hidden — it just never gets the hero seat.
            // minimumScaleFactor keeps a long-but-honest amount
            // ("1,240.5000 USDC") legible before it truncates.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .truncationMode(.tail)
            .dsText(.price40)
            .monospacedDigit()
    }

    /// "$3,480" / "$12.99" — cents only where they carry information.
    private static func fiat(_ usd: Double) -> String {
        usd.formatted(.currency(code: "USD")
            .precision(.fractionLength(usd < 100 ? 2 : 0)))
    }

    // MARK: - Counterparty row (the door to your shared history)

    /// One card: the counterparty's face and name, and — when the corpus
    /// holds more transfers with them — a disclosure that unfolds that
    /// history in place. Naming is NOT here (the dial's Name disc is the one
    /// door); with no further history the row is plain identity, no chevron,
    /// per the no-dead-controls law.
    private var counterpartyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sharedHistory.isEmpty {
                counterpartyRowContent
            } else {
                Button {
                    withAnimation(DS.Motion.standard) { historyShown.toggle() }
                } label: {
                    counterpartyRowContent
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsHover()
                .accessibilityLabel(Text("\(counterpartyLabel), \(transferCount) transfers with you"))
                .accessibilityHint(Text("Shows your history together"))
            }
            if historyShown {
                historyRows
                    .padding(.top, DS.Space.s3)
            }
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private var counterpartyRowContent: some View {
        HStack(spacing: DS.Space.s3) {
            counterpartyFace
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: counterpartyLabel)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subline = counterpartySubline {
                    Text(verbatim: subline)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !sharedHistory.isEmpty {
                Image(systemName: "chevron.down")
                    .accessibilityHidden(true)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
                    .rotationEffect(.degrees(historyShown ? 180 : 0))
            }
        }
    }

    /// The short hex (when captured) and how much history you share — the
    /// count only once there's a second transfer, since "1 transfer with you"
    /// is the row you're already reading.
    private var counterpartySubline: String? {
        var parts: [String] = []
        if let cp = thing.counterpartyAddress, !cp.isEmpty {
            parts.append(WalletStore.shortAddress(cp))
        }
        if transferCount >= 2 {
            parts.append(String(localized: "\(transferCount) transfers with you"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The unfolded history — up to six prior transfers, each its signed
    /// amount (or the title, for pre-field rows) and its day. Content, not
    /// controls: the walk into any one of them stays a feed job, and rows
    /// here are a read.
    private var historyRows: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(sharedHistory.prefix(6)) { row in
                if let past = row.live {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(verbatim: Self.historyLine(past))
                            .dsText(.callout15)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(verbatim: past.capturedAt.formatted(
                            .dateTime.month(.abbreviated).day()))
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
            }
            if sharedHistory.count > 6 {
                Text("and \(sharedHistory.count - 6) more")
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    private static func historyLine(_ past: Thing) -> String {
        if let amount = past.transferAmount, !amount.isEmpty {
            return (past.transferDirection == "sent" ? "−" : "+") + amount
        }
        return past.title
    }

    /// The corpus's record of this counterparty, read once per open through
    /// `AddressActivity` (the one definition of activity) and narrowed to
    /// Wallet transfers — the only rows the "with you" claim is true of.
    /// Keyed on the hex; a name-only counterparty (pre-field, or a native
    /// send) has no address to match, so its row stays plain identity.
    private func loadHistory() {
        guard let cp = thing.counterpartyAddress, !cp.isEmpty else { return }
        let myID = thing.id
        let transfers = AddressActivity.history(for: cp, in: modelContext)
            .filter { $0.source == "Wallet" }
        transferCount = transfers.count
        sharedHistory = transfers.filter { $0.id != myID }.keyed
    }

    // MARK: - Spec slab (the facts, in the sheet's own spec grammar)

    /// Into/From · Network · Venue · Landed — the same quiet card the spec
    /// table below the stage draws, so the sheet keeps one fact language.
    /// "Network", not "Chain" (user, 2026-08-04).
    private var specSlab: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            specRow(stage.direction == .sent ? String(localized: "From")
                                             : String(localized: "Into"),
                    youLabel)
            if let network = WalletIngest.chainName(forContent: thing.content) {
                specRow(String(localized: "Network"), network)
            }
            if let venue = stage.venue {
                specRow(String(localized: "Venue"), venue)
            }
            specRow(String(localized: "Landed"),
                    thing.capturedAt.formatted(
                        .dateTime.month(.abbreviated).day().hour().minute()))
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func specRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: label)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .frame(width: 80, alignment: .leading)
            Text(verbatim: value)
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    /// Your name for the address wins, then the title's clause, then short hex.
    private var counterpartyLabel: String {
        if let cp = thing.counterpartyAddress, !cp.isEmpty {
            return WalletIngest.knownLabel(for: cp) ?? stage.titledName
                ?? WalletStore.shortAddress(cp)
        }
        return stage.titledName ?? ""
    }

    /// The counterparty's face — WalletFace's identicon seeded from whatever
    /// identity the record holds (hex when captured, else the titled name), so
    /// the same counterparty always wears the same face. An identicon, not a
    /// claimed avatar — nothing is invented. Round unless the address book
    /// already identified this specific address as a contract or Safe (a
    /// "what", not a "who") — an address never checked yet defaults to round,
    /// same as `AddressBook.Kind.glyph`'s own `.wallet, .unknown` grouping.
    private var counterpartyFace: some View {
        let address = thing.counterpartyAddress ?? stage.titledName ?? "?"
        let kind = AddressBook.shared.entry(for: address)?.kind ?? .unknown
        let circular = kind != .contract && kind != .safe
        return WalletFace(address: address, size: 40, circular: circular)
            .overlay {
                // The ring matches the face's own shape — a round ring on a
                // contract's squircle would draw a second, disagreeing edge.
                if circular {
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 2)
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.appIcon(40), style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 2)
                }
            }
    }

    /// Never "You" (2026-07-23, user: "we don't know it is 'you', we only
    /// know it is the address used or followed") — every watched wallet here
    /// is read-only, so nothing distinguishes the person's own wallet from a
    /// public address they're just tracking (this exact screen, in testing,
    /// was showing "You" over vitalik.eth). Falls back to whatever the
    /// person actually named it, then the watched spelling itself (an ENS
    /// name reads fine as a label; a raw hex shortens the same way the
    /// counterparty side already does) — an honest identity, never an
    /// assumed one. Feeds the slab's Into/From row now that the tableau's
    /// party column is gone.
    ///
    /// Matches through `scopeMatches` (2026-07-23), the SAME hex↔name
    /// equality the scoped feed uses — a thing stamps the RESOLVED hex, but
    /// a wallet is watched by whatever spelling it was added under, so a
    /// plain `address == a` compare missed every ENS-watched wallet and fell
    /// straight to short-hex (why vitalik.eth read as "0xd8dA…6045").
    private var youLabel: String {
        let stored = thing.walletAddress ?? ""
        let watched = WalletStore.shared.addresses.first {
            WalletStore.shared.scopeMatches(stored, scope: $0.address)
        }
        guard let watched else { return WalletStore.shortAddress(stored) }
        if !watched.label.isEmpty { return watched.label }
        return ENS.isHexAddress(watched.address)
            ? WalletStore.shortAddress(watched.address) : watched.address
    }
}

/// A self-transfer between two of the person's own watched wallets — the
/// "Moved 0.5 ETH · Main → Cold" title `WalletIngest` builds when both legs
/// are watched (2026-07-15). Parsed from the title, the same fallback grammar
/// `TransferStage` uses for pre-field transfers — a self-move stores no
/// direction/amount fields (there's no single direction to store), so the
/// title IS the structured record here.
struct MovedStage {
    /// "0.5 ETH", or the bare asset when the leg carried no value.
    let amount: String
    let fromLabel: String
    let toLabel: String
    /// The real hex addresses behind `fromLabel`/`toLabel` — `WalletFace`
    /// needs the actual address for its identicon (and any resolved ENS
    /// avatar), not the display label, or two different wallets that happen
    /// to share a label prefix would draw the same face. Resolved from
    /// `thing.walletAddress`/`counterpartyAddress` — both real, since
    /// `WalletIngest`'s Moved arm stamps the counterparty like every other
    /// transfer (2026-07-21 fix; the first cut passed the label strings
    /// straight into `WalletFace`, fabricating an identicon from text no
    /// address ever produced).
    let fromAddress: String
    let toAddress: String

    init?(_ thing: Thing) {
        guard thing.kind == .transaction, thing.source == "Wallet",
              thing.title.hasPrefix("Moved "),
              let mine = thing.walletAddress, !mine.isEmpty,
              let other = thing.counterpartyAddress, !other.isEmpty
        else { return nil }
        let rest = String(thing.title.dropFirst("Moved ".count))
        guard let sep = rest.range(of: " · "),
              let arrow = rest.range(of: " → ", range: sep.upperBound..<rest.endIndex)
        else { return nil }
        amount = String(rest[..<sep.lowerBound])
        fromLabel = String(rest[sep.upperBound..<arrow.lowerBound])
        toLabel = String(rest[arrow.upperBound...])
        // The title's word order, matched back to whichever wallet's CURRENT
        // label produced it. A rename since this thing landed can break the
        // match (the title is frozen, the label isn't) — falls back to
        // mine→other, a deterministic guess rather than a crash; worst case
        // the two faces land on the wrong side, never a wrong address.
        let mineLabel = WalletStore.shared.label(forAddress: mine) ?? WalletStore.shortAddress(mine)
        if fromLabel == mineLabel {
            fromAddress = mine; toAddress = other
        } else if toLabel == mineLabel {
            fromAddress = other; toAddress = mine
        } else {
            fromAddress = mine; toAddress = other
        }
    }
}

/// A trade folded from a matched send+receive on one hash — "Swapped 0.5 ETH
/// → 1,200 USDC on Uniswap" (`WalletIngest.swapThing`). Two assets change
/// hands, not a single signed amount, so the stage draws the trade itself
/// rather than borrowing `TransferStage`'s party/arrow grammar. Parsed from
/// the title for the same reason `MovedStage` is: a swap stores its venue as
/// `transferCounterparty`, but never split the two leg amounts into fields.
struct SwapStage {
    let outAmount: String
    let inAmount: String
    let venue: String?

    init?(_ thing: Thing) {
        guard thing.kind == .transaction, thing.source == "Wallet",
              thing.title.hasPrefix("Swapped ") else { return nil }
        var rest = String(thing.title.dropFirst("Swapped ".count))
        if let onRange = rest.range(of: " on ") {
            venue = String(rest[onRange.upperBound...])
            rest = String(rest[..<onRange.lowerBound])
        } else {
            venue = nil
        }
        guard let arrow = rest.range(of: " → ") else { return nil }
        outAmount = String(rest[..<arrow.lowerBound])
        inAmount = String(rest[arrow.upperBound...])
    }
}

/// The self-move stage: two of your own wallets, an arrow, a plain amount.
/// No sign — moving your own money between your own wallets is neither a
/// gain nor a loss (the same "spending isn't a loss state" reasoning
/// `TransferStageView.amountLine` states for a send, taken one step further).
struct MovedStageView: View {
    let thing: Thing
    let stage: MovedStage

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s4) {
                party(address: stage.fromAddress, label: stage.fromLabel)
                arrow
                party(address: stage.toAddress, label: stage.toLabel)
            }
            Text(verbatim: stage.amount)
                .foregroundStyle(DS.textPrimary)
                .dsText(.heading34)
                .monospacedDigit()
                .padding(.top, DS.Space.s8)
            if let chain = WalletIngest.chainName(forContent: thing.content) {
                Text(verbatim: chain)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .accessibilityHidden(true)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(height: 50)
    }

    private func party(address: String, label: String) -> some View {
        VStack(spacing: DS.Space.s2) {
            WalletFace(address: address, size: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.appIcon(50), style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 3)
                )
            Text(verbatim: label)
                .dsText(.label12)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
        }
        .frame(maxWidth: 120)
    }
}

/// The swap stage: what left, an arrow, what arrived — the trade as a fact,
/// no party faces (a router isn't a "who" the way a counterparty is; naming
/// it still rides the Name disc off `counterpartyAddress`, same as any
/// transfer).
struct SwapStageView: View {
    let thing: Thing
    let stage: SwapStage

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: stage.outAmount)
                Image(systemName: "arrow.right")
                    .accessibilityHidden(true)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(verbatim: stage.inAmount)
            }
            .foregroundStyle(DS.textPrimary)
            .dsText(.stat24)
            .monospacedDigit()
            .multilineTextAlignment(.center)

            let place = [WalletIngest.chainName(forContent: thing.content), stage.venue]
                .compactMap(\.self)
            if !place.isEmpty {
                Text(verbatim: place.joined(separator: " · "))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s3)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The verb dial (B1, 2026-07-16) — the iOS contact-card pattern: discs with
/// short labels, recognizable at a glance, still capped. Same wiring as the
/// text action rows it replaces on stage sheets: reads pass, writes confirm
/// (the caller routes through the same confirm dialog), Share is the same
/// ThingShareLink.
struct VerbDial: View {
    let thing: Thing
    let verbs: [Verb]
    var onVerb: (Verb) -> Void
    /// The Name disc — present only when there's an address to name.
    var onName: (() -> Void)?

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        HStack(alignment: .top, spacing: DS.Space.s4 + 2) {
            ForEach(verbs) { verb in
                Button { onVerb(verb) } label: {
                    disc(icon: verb.icon, label: Self.dialLabel(for: verb))
                }
                .buttonStyle(.plain)
            }
            if let onName {
                Button(action: onName) {
                    disc(icon: "square.and.pencil", label: "Name")
                }
                .buttonStyle(.plain)
            }
            ThingShareLink(thing: thing) {
                disc(icon: "square.and.arrow.up", label: "Share")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    /// The word under a disc. `shortLabel` alone collapses every hand-off to
    /// "Open", so a sheet with Directions + Photos + Call would read "Open
    /// Open Open" — the destination is the differentiator, so it's what the
    /// disc says.
    static func dialLabel(for verb: Verb) -> String {
        for prefix in ["Open in ", "Send to ", "Add to "] where verb.label.hasPrefix(prefix) {
            return String(verb.label.dropFirst(prefix.count))
        }
        if verb.label.hasPrefix("Open") { return "Open" }
        if verb.label.hasPrefix("Copy") { return "Copy" }
        return verb.label.count <= 12 ? verb.label : verb.shortLabel
    }

    private func disc(icon: String, label: String) -> some View {
        VStack(spacing: DS.Space.s2 - 2) {
            Circle()
                .fill(DS.fillLine)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 19))
                        .foregroundStyle(DS.textPrimary)
                }
            Text(LocalizedStringKey(label))
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        // One hover for all three callers above — the verb discs, Name, and
        // Share — since they share this anatomy. No tooltip: every disc wears
        // its own word underneath, so a cursor already has the name.
        .dsHover()
    }
}
