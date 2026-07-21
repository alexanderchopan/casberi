import SwiftUI

/// The stage (thing sheet B1, 2026-07-16): a wallet transfer's hero. The sheet
/// DEPICTS the transfer instead of describing it — the parties stand on the
/// solid wash (identity tolerates the hue; type doesn't), and the signed
/// amount lands at the seam where the hue has faded to near-ink, so the big
/// number never fights loud color and no film ever covers the wash ("bold,
/// not a film" survives). Direction reads before the words do: money flows
/// left-to-right toward whoever received it, a gain's sign wears confirm
/// green, a send stays white (spending isn't a loss state — red would
/// editorialize).
///
/// Sent/Received only for now — Moved and Swapped keep the standard layout
/// until their two-legged grammar earns a stage of its own.
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

/// The stage rendered: parties → amount → chain. Faces are doors — the
/// counterparty's opens the naming flow when its hex was captured.
struct TransferStageView: View {
    let thing: Thing
    let stage: TransferStage
    /// Present only when the counterparty is nameable (hex captured) — the
    /// face is then a button; without it the face is just a face (no dead
    /// controls).
    var onNameCounterparty: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if hasCounterparty {
                HStack(alignment: .top, spacing: DS.Space.s4) {
                    if stage.direction == .sent {
                        party(face: youFace, label: youLabel)
                        arrow
                        counterpartyParty
                    } else {
                        counterpartyParty
                        arrow
                        party(face: youFace, label: youLabel)
                    }
                }
            }
            amountLine
                .padding(.top, hasCounterparty ? DS.Space.s8 : DS.Space.s3)
            // Where it happened — the chain (off the explorer link, never
            // guessed), and the venue when the title carried one.
            let place = [WalletIngest.chainName(forContent: thing.content),
                         stage.venue].compactMap(\.self)
            if !place.isEmpty {
                Text(verbatim: place.joined(separator: " · "))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A counterparty exists when there's anything true to draw — a captured
    /// hex or a name the title carries. Neither → the stage is just the amount.
    private var hasCounterparty: Bool {
        !(thing.counterpartyAddress ?? "").isEmpty || stage.titledName != nil
    }

    /// The signed amount at the seam. Only a gain's sign carries color —
    /// confirm green for received; sent stays white (color = state, never
    /// decoration, and spending isn't a loss).
    private var amountLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: stage.direction == .sent ? "−" : "+")
                .foregroundStyle(stage.direction == .received ? DS.confirm : DS.textPrimary)
            Text(verbatim: stage.amount)
                .foregroundStyle(DS.textPrimary)
        }
        .dsText(.heading34)
        .monospacedDigit()
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            // Optically centered on the faces, not the whole party column.
            .frame(height: 50)
    }

    private func party(face: some View, label: String) -> some View {
        VStack(spacing: DS.Space.s2) {
            face
            Text(verbatim: label)
                .dsText(.label12)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
        }
        .frame(maxWidth: 120)
    }

    /// The counterparty column — a button when nameable (the pencil says so),
    /// plain otherwise.
    @ViewBuilder private var counterpartyParty: some View {
        let label = counterpartyLabel
        if let onNameCounterparty {
            Button(action: onNameCounterparty) {
                VStack(spacing: DS.Space.s2) {
                    counterpartyFace
                    HStack(spacing: DS.Space.s1) {
                        Text(verbatim: label)
                            .dsText(.label12)
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: 120)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            party(face: counterpartyFace, label: label)
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

    // MARK: - Faces (identity on the solid crown — ringed to hold their edge)

    /// Your face: the profile avatar when set, else the wallet's own identicon
    /// (deterministic — the same face WalletFace gives it everywhere).
    @ViewBuilder private var youFace: some View {
        if let avatar = ProfileStore.shared.avatar {
            Image(uiImage: avatar)
                .resizable().scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(faceShape)
                .overlay(faceRing)
        } else {
            WalletFace(address: thing.walletAddress ?? "you", size: 50)
                .overlay(faceRing)
        }
    }

    /// The counterparty's face — WalletFace's identicon seeded from whatever
    /// identity the record holds (hex when captured, else the titled name), so
    /// the same counterparty always wears the same face. An identicon, not a
    /// claimed avatar — nothing is invented.
    private var counterpartyFace: some View {
        WalletFace(address: thing.counterpartyAddress ?? stage.titledName ?? "?",
                   size: 50)
            .overlay(faceRing)
    }

    private var faceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.appIcon(50), style: .continuous)
    }

    private var faceRing: some View {
        faceShape.strokeBorder(.white.opacity(0.25), lineWidth: 3)
    }

    private var youLabel: String {
        if let a = thing.walletAddress?.lowercased(),
           let watched = WalletStore.shared.addresses.first(where: {
               $0.address.lowercased() == a
           }), !watched.label.isEmpty {
            return watched.label
        }
        return String(localized: "You")
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

    var body: some View {
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
        for prefix in ["Open in ", "Add to "] where verb.label.hasPrefix(prefix) {
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
    }
}
