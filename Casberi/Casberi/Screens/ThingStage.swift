import SwiftUI

/// What survived the stage (prd §369, 2026-08-12).
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

/// The verb dial (B1, 2026-07-16): a thing sheet's acts. Reads pass, writes
/// confirm (the caller routes through the same confirm dialog), Share raises
/// the share tray.
///
/// **THE ROOMS' TILES SINCE prd §1178** (user: "for the buttons on the thing
/// sheets i'd like them to be same size they are on the rooms … so we are
/// never hand rolling"): the round discs became `DSScopeTiles`, the very
/// template You's row and every room's tiles draw, every tile a verb — the
/// thing's acts in order, Name, then Share last. Four columns, as a room's.
struct VerbDial: View {
    let thing: Thing
    let verbs: [Verb]
    var onVerb: (Verb) -> Void
    /// The Name disc — present only when there's an address to name.
    var onName: (() -> Void)?
    /// THE FOURTH TILE KEEPS UP WITH IT FOR YOU (prd §1181, user: "for since
    /// we have only three tiles and a fourth is empty what can we put there …
    /// what are we trying to get people to track"): Save a person, Watch a
    /// wallet, Track a charge that repeats. Drawn only where it fits in four.
    var keep: Keep? = nil
    struct Keep {
        let label: String
        let glyph: String
        let act: () -> Void
    }

    /// The copy disc's own beat. A copy is the one verb on this dial whose
    /// whole effect is INVISIBLE — nothing opens, nothing moves, and the
    /// pasteboard is somewhere else entirely — so until now the only answer
    /// to the press was a line of text under the strip, six discs away from
    /// the finger. The glyph becomes a checkmark for a beat, where the tap
    /// landed. It is a statement of fact rather than an optimistic guess at
    /// an outcome the parent is still computing (§83): `DSPasteboard.copy`
    /// cannot fail, which is why this is the one verb that gets it.
    @State private var copied: Verb.ID?
    /// The share tray, raised by the Share disc.
    @State private var sharing = false


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
        let tiles = self.tiles
        DSScopeTiles(sections: tiles, active: SheetTile.none, verbs: Set(tiles)) { pick($0) }
            // In the rows' column, as a room's tiles stand: the discs were
            // centred and needed no inset; a grid does.
            .padding(.horizontal, DSRoomChassis.inset)
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $sharing) { ShareTray(thing: thing) }
            // Bound to `copied`, so SwiftUI cancels it when the sheet goes and
            // restarts it when a second copy lands before the first has cleared.
            .task(id: copied) {
                guard copied != nil else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                copied = nil
            }
    }

    /// The thing's acts, then Name, then Share: the order is the meaning
    /// (`SheetTile.keepsOrder`). A copy wears a checkmark for a beat.
    private var tiles: [SheetTile] {
        var out = verbs.map { verb in
            SheetTile(id: "verb:" + verb.id, label: Self.dialLabel(for: verb),
                      glyph: copied == verb.id ? "checkmark" : verb.icon)
        }
        if onName != nil { out.append(SheetTile(id: "name", label: "Name", glyph: "square.and.pencil")) }
        if let keep, out.count < 3 { out.append(SheetTile(id: "keep", label: keep.label, glyph: keep.glyph)) }
        out.append(SheetTile(id: "share", label: "Share", glyph: "square.and.arrow.up"))
        return out
    }

    private func pick(_ tile: SheetTile) {
        switch tile.id {
        case "name": onName?()
        case "keep": keep?.act()
        case "share": sharing = true
        default:
            guard let verb = verbs.first(where: { "verb:" + $0.id == tile.id }) else { return }
            press(verb)
        }
    }

    private func press(_ verb: Verb) {
        onVerb(verb)
        if case .copyText = verb.action { copied = verb.id }
    }

    /// The word under a disc. `shortLabel` alone collapses every hand-off to
    /// "Open", so a sheet with Directions + Photos + Call would read "Open
    /// Open Open" — the destination is the differentiator, so it's what the
    /// disc says.
    ///
    /// `"Show in "` joined the strip list on 2026-09-15 (prd §736), when the
    /// Files verb started naming the folder rather than the app. Without it
    /// "Show in Receipts" is 16 characters, falls past the 12-char gate to
    /// `shortLabel`, and reads "Files" — i.e. the disc would silently drop the
    /// one fact the deleted "From — in Receipts" row existed to carry, which
    /// is the whole of that ruling undone by a length check.
    static func dialLabel(for verb: Verb) -> String {
        for prefix in ["Open in ", "Send to ", "Add to ", "Show in "] where verb.label.hasPrefix(prefix) {
            return String(verb.label.dropFirst(prefix.count))
        }
        if verb.label.hasPrefix("Open") { return "Open" }
        if verb.label.hasPrefix("Copy") { return "Copy" }
        return verb.label.count <= 12 ? verb.label : verb.shortLabel
    }
}

/// One of a thing sheet's tiles (prd §1178): one of its acts, Name or Share,
/// drawn by `DSScopeTiles` like a room's. Its glyph is the act's own symbol —
/// a sheet's acts are not scopes, so they read no `ScopeTileGlyph` table —
/// and its order is the caller's.
struct SheetTile: DSTileScope {
    let id: String
    let label: String
    let glyph: String
    var summary: String { label }
    static var keepsOrder: Bool { true }

    /// The pick nothing is: every sheet tile is a verb, so none ever lights.
    static let none = SheetTile(id: "", label: "", glyph: "")
}
