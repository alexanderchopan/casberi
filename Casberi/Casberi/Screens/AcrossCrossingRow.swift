import SwiftUI

/// **A SWAP TO ANOTHER NETWORK, ONE ROW (prd §1555, the user's design).**
/// Waiting: an amber clock, "USDC arriving on Base", its line "Swapped 0.01
/// ETH on Ethereum · now" in the attention ink and what arrives grey on the
/// right. Filled: the swap glyph, "0.02 ETH for USDC" (the verb is the
/// glyph's, VoiceOver keeps it), "Ethereum to Base · 9:41 AM", what arrived.
/// Refunded: a grey return, "Refunded 0.01 WETH on Ethereum", "The swap to
/// Base wasn't filled". The words are `YourAccountAcross`'s, the thing
/// `WalletAcross`'s.
struct AcrossCrossingRow: View {
    let thing: Thing

    // A leaf body re-evaluates on the model's own observation: a deleted
    // Thing must not be read (ThingRowKeying.swift, swiftdata-liveness-audit).
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        let crossing = WalletAcross.crossing(of: thing)
        let state = crossing?.state ?? .filled
        let waiting = state == .waiting
        DSFeedRow(name: Self.name(thing.title, state: state),
                  line: Text(verbatim: [thing.summary, Self.when(crossing?.settledAt ?? thing.capturedAt)]
                      .compactMap { $0 }.joined(separator: " · "))
                      .foregroundStyle(waiting ? DS.attentionInk : DS.textTertiary)) {
            DSGlyphLead(glyph: Self.glyph(state), tint: waiting ? DS.attention : DS.textSecondary)
        } trailing: {
            // A refund's title carries its amount; a figure beside it would
            // cut the title (prd §1550's rule: a row never runs off).
            if let crossing, state != .refunded {
                Text(verbatim: YourAccountAcross.figure(crossing))
                    .dsText(.price17)
                    .monospacedDigit()
                    .foregroundStyle(state == .filled ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [thing.title, thing.summary].compactMap { $0 }.joined(separator: ", ")))
    }

    /// The drawn name: a filled crossing drops "Swapped", the glyph says it
    /// (user, 2026-10-26); waiting and refunded keep their verbs.
    static func name(_ title: String, state: YourAccountAcross.Crossing.State) -> String {
        let verb = String(localized: "Swapped") + " "
        guard state == .filled, title.hasPrefix(verb) else { return title }
        return String(title.dropFirst(verb.count))
    }

    static func glyph(_ state: YourAccountAcross.Crossing.State) -> String {
        switch state {
        case .waiting: "clock"
        case .filled: "arrow.left.arrow.right"
        case .refunded: "arrow.uturn.backward"
        }
    }

    /// "now" inside a minute, else the time of day.
    static func when(_ date: Date) -> String {
        abs(date.timeIntervalSinceNow) < 60 ? String(localized: "now")
            : date.formatted(date: .omitted, time: .shortened)
    }
}
