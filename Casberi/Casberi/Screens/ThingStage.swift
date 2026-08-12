import SwiftUI

/// What survived the stage (prd §363, 2026-08-12).
///
/// This file used to hold the thing sheet's three wallet HEROES — a party/arrow
/// tableau for Sent/Received (2026-07-16), relaid out as a ledger (2026-08-04),
/// plus separate centred tableaus for Moved and Swapped. All three were gated on
/// `kind == .transaction && source == "Wallet"`, which is why eleven other money
/// families had no hero at all, and the two that stayed centred never got the
/// ledger's treatment — one sheet, two visual grammars.
///
/// `MoneyReceipt` replaces all three. What remains here is what still had a job:
///
///   · **`MovedStage`** — the parser only. A self-move's counterparty is your
///     OWN watched wallet, which already has a name, so the sheet's Name disc
///     must stand down; this is how it knows.
///   · **`SwapStage`** — the parser only. A swap's two legs are what
///     `MoneyCommentary.rate` divides, and its " → " is a delimiter the bridge
///     itself writes, not prose.
///   · **`VerbDial`** — never wallet-specific; every sheet in the app uses it.
///
/// `TransferStage` went with its view: the receipt reads
/// `transferDirection`/`transferAmount`/`transferCounterparty` straight off the
/// record, so the title-parsing fallback that type existed for is gone.

/// A self-transfer between the person's own watched wallets — the "Moved 0.5
/// ETH · Main → Cold" title `WalletIngest` builds when both legs are watched
/// (2026-07-15). Parsed from the title because a self-move stores no
/// direction/amount fields: there is no single direction to store, so the title
/// IS the structured record here.
struct MovedStage {
    /// "0.5 ETH", or the bare asset when the leg carried no value.
    let amount: String
    let fromLabel: String
    let toLabel: String
    /// The real hex addresses behind the labels — two different wallets that
    /// happen to share a label prefix must not draw the same face. Resolved
    /// from `thing.walletAddress`/`counterpartyAddress`, both real since
    /// `WalletIngest`'s Moved arm stamps the counterparty like every other
    /// transfer (2026-07-21 fix; the first cut passed the label strings into
    /// `WalletFace`, fabricating an identicon from text no address ever made).
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
        // mine→other, a deterministic guess rather than a crash; worst case the
        // two sides are swapped, never a wrong address.
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

/// A trade folded from a matched send+receive on one hash — "Swapped 0.5 ETH →
/// 1,200 USDC on Uniswap" (`WalletIngest.swapThing`). Two assets change hands,
/// not one signed amount, so a swap stores no direction/amount pair; the title's
/// own " → " is the delimiter the bridge writes, and the only thing read out of
/// it is two numbers to divide.
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

/// The verb dial (B1, 2026-07-16) — the iOS contact-card pattern: discs with
/// short labels, recognizable at a glance, still capped. Reads pass, writes
/// confirm (the caller routes through the same confirm dialog), Share is the
/// same ThingShareLink.
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
                        .dsGlyph(19, weight: .regular)
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
