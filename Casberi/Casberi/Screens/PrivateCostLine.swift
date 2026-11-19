import SwiftUI

/// What a private move costs, in dollars and its parts (prd §1700y, Railgun's
/// `RailgunMove.Cost` of §1728 item 6, one shape for both private balances).
struct PrivateCost: Equatable {
    struct Part: Equatable, Hashable { let words: String; let figure: String }
    let usd: Double
    let parts: [Part]

    /// The Cost row's figure: "about $0.39", or "under $0.01".
    var amount: String {
        usd < 0.01 ? String(localized: "under $0.01")
            : String(localized: "about \(usd.formatted(.currency(code: "USD").precision(.fractionLength(2))))")
    }
}

/// **COST IS A ROW (prd §1876, retiring §1700y's line that unfolded and
/// §1754's door on the fee; user: "these detail menus on all our move
/// actions are sloppy. they are hard to access and janky").** Under a
/// sentence's choices, in their shape: the name grey, the figure at their
/// size, and a door's chevron, because it opens a list in the page and
/// never a menu. Nothing unfolds: the foot is the same height before and
/// after.
struct MoveCostRow: View {
    var name: String = String(localized: "Cost")
    let value: String
    let act: () -> Void

    var body: some View {
        Button {
            act()
            DSHaptic.selection()
        } label: {
            HStack(alignment: .center, spacing: DS.Space.s2) {
                Text(verbatim: name).dsText(.body17).foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: DS.Space.s3)
                Text(verbatim: value)
                    .dsText(.heading20)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // In the menu chevron's own column, so every figure on the
                // page ends on one edge.
                Image(systemName: "chevron.up.chevron.down").dsGlyph(.caption, weight: .semibold)
                    .hidden()
                    .overlay {
                        Image(systemName: "chevron.right").dsGlyph(.caption, weight: .semibold)
                            .foregroundStyle(DS.textSecondary)
                    }
                    .accessibilityHidden(true)
            }
            .frame(minHeight: MoveChoiceRowLabel.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(RowPress())
        .accessibilityHint(Text("Shows what it costs"))
    }
}

/// **THE COST'S OWN LIST (prd §1876).** It takes the rows' place in the
/// page: its name at its head closes it, as every list's does, with the
/// figure beside it, then what the figure is made of.
struct MoveCostList<Rows: View>: View {
    var name: String = String(localized: "Cost")
    var value: String?
    var ink: Color = DS.pickInk
    let close: () -> Void
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: DS.Space.s2) {
                MoveListBack(name: name, ink: ink) {
                    close()
                    DSHaptic.selection()
                }
                Spacer(minLength: DS.Space.s2)
                if let value {
                    Text(verbatim: value).dsText(.heading20).foregroundStyle(DS.textPrimary)
                        .monospacedDigit().lineLimit(1)
                }
            }
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One part of a cost: its words grey, its figure white, at a row's pitch.
struct MoveCostPartRow: View {
    let part: PrivateCost.Part

    var body: some View {
        // One gap, not two: "A Railgun broadcaster sends it" and its figure
        // fit the phone's line with 8pt between them, and wrapped with 20.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: part.words).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: part.figure).dsText(.body17).foregroundStyle(DS.textPrimary).monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
        }
        // The public swap's Details pitch (`MoveDetails.row`), so a cost
        // reads alike on both (user, 2026-11-18: "is it same spacing we use
        // on the swap screen?").
        .walletRowPitch()
        .accessibilityElement(children: .combine)
    }
}

/// **A PRIVATE SENTENCE'S ROWS, WITH ITS COST (prd §1876).** The page's own
/// rows, the Cost row under them while there is a cost, and the cost's list
/// in their place once it is opened. The page holds `open`, so its foot's
/// back card can close the list too.
struct MoveCostRows<Rows: View>: View {
    /// Nil while there is nothing to cost: no row.
    let cost: PrivateCost?
    @Binding var open: Bool
    var ink: Color = DS.pickInk
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        ZStack(alignment: .topLeading) {
            if open, let cost {
                MoveCostList(value: cost.amount, ink: ink, close: { withAnimation(DS.Motion.standard) { open = false } }) {
                    ForEach(cost.parts, id: \.self) { MoveCostPartRow(part: $0) }
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    rows()
                    if let cost {
                        MoveCostRow(value: cost.amount) { withAnimation(DS.Motion.standard) { open = true } }
                            .transition(.opacity)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(DS.Motion.standard, value: cost == nil)
        // The list never outlives its cost (the move began, the amount went).
        .onChange(of: cost == nil) { _, gone in if gone { open = false } }
    }
}

/// **THE FOOT'S ONE THING (prd §1700y, amended by §1876).** A private
/// move's foot holds one thing at a time over its act: what the move buys
/// you while it is ready ("Private in about an hour"), the steps while it
/// works and after (`PrivateStepRows`), or the warming row while the
/// balance is read (`PrivateWarmingRow`). The cost is a row above
/// (`MoveCostRow`); where no price makes a dollar figure, `fallback` (the
/// old words: Shield's percentage, how long) stands here. Never a control.
struct PrivateCostNote: View {
    let cost: PrivateCost?
    let tail: String?
    let fallback: String

    private var words: String? {
        guard cost != nil else { return fallback.isEmpty ? nil : fallback }
        return tail.map { $0.prefix(1).localizedUppercase + $0.dropFirst() }
    }

    var body: some View {
        if let words {
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.s2)
        }
    }
}

/// "Getting your private balance ready · 12 s": the foot while a private
/// balance is read, real seconds with a spinner, never a bar (prd §1700y;
/// Railgun's §1728 words).
struct PrivateWarmingRow: View {
    let since: Date
    /// The first sync on this phone (prd §1885): it builds what later syncs
    /// keep, so it says so, how far it is, and that only leaving the app
    /// stops it (iOS pauses the engine in the background, never a sheet).
    var firstTime = false
    var percent: Int? = nil
    /// Railgun's catch-up after the first: it updates what is kept (user,
    /// 2026-11-18: "it should say something like that re re-sync").
    var railgun = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since).rounded()))
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(spacing: DS.Space.s2) {
                    DSSpinner(size: .small)
                    Text(verbatim: firstTime
                         ? (percent.map { String(localized: "Setting up your private balance · \($0)%") }
                            ?? String(localized: "Setting up your private balance · \(seconds) s"))
                         : railgun ? String(localized: "Updating your private balance · \(seconds) s")
                         : String(localized: "Getting your private balance ready · \(seconds) s"))
                        .dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
                    Spacer(minLength: 0)
                }
                if firstTime {
                    Text("Only once. Close this, not Casberi.")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                }
            }
            .frame(minHeight: DS.Hit.min)
        }
    }
}
