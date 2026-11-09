import SwiftUI

/// What a private move costs, in dollars and its parts (prd §1700y, Railgun's
/// `RailgunMove.Cost` of §1728 item 6, one shape for both private balances).
struct PrivateCost: Equatable {
    struct Part: Equatable, Hashable { let words: String; let figure: String }
    let usd: Double
    let parts: [Part]

    /// "Costs about $0.39", or "Costs under $0.01".
    var figure: String {
        usd < 0.01 ? String(localized: "Costs under $0.01")
            : String(localized: "Costs about \(usd.formatted(.currency(code: "USD").precision(.fractionLength(2))))")
    }
}

/// **THE FOOT'S ONE THING (prd §1700y, agreed with the Railgun session).**
/// A private move's foot holds one thing at a time over its act: this cost
/// line while the move is ready, the steps while it works and after
/// (`PrivateStepRows`), or the warming row while the balance is read
/// (`PrivateWarmingRow`). "Costs about $0.39 · your account isn't on it";
/// a tap shows the parts. Where no price makes a dollar figure, `fallback`
/// (the old words: Shield's percentage, how long) stands in its place.
struct PrivateCostLine: View {
    let cost: PrivateCost?
    /// What the move buys you, after the figure ("private in about an hour").
    let tail: String?
    let fallback: String
    @State private var showParts = false

    var body: some View {
        if let cost {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(DS.Motion.standard) { showParts.toggle() }
                    DSHaptic.selection()
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        Text(verbatim: [cost.figure, tail].compactMap { $0 }.joined(separator: " · "))
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: showParts ? "chevron.up" : "chevron.down")
                            .dsGlyph(.body, weight: .regular).foregroundStyle(DS.textTertiary)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityHint(Text(showParts ? "Hides what it costs" : "Shows what it costs"))
                if showParts {
                    ForEach(cost.parts, id: \.self) { part in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                            Text(verbatim: part.words).dsText(.body17).foregroundStyle(DS.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DS.Space.s2)
                            Text(verbatim: part.figure).dsText(.body17).foregroundStyle(DS.textPrimary).monospacedDigit()
                        }
                        .frame(minHeight: 32)
                        .accessibilityElement(children: .combine)
                    }
                    .transition(.opacity)
                }
            }
        } else {
            Text(verbatim: fallback).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "Getting your private balance ready · 12 s": the foot while a private
/// balance is read, real seconds with a spinner, never a bar (prd §1700y;
/// Railgun's §1728 words).
struct PrivateWarmingRow: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: DS.Space.s2) {
                DSSpinner(size: .small)
                Text(verbatim: String(localized: "Getting your private balance ready · \(max(0, Int(context.date.timeIntervalSince(since).rounded()))) s"))
                    .dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Hit.min)
        }
    }
}
