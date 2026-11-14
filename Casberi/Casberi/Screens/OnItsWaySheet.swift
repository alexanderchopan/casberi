import SwiftUI

/// **ONE THING ON ITS WAY, ITS STEPS (prd §1779).** The page behind a row of
/// the Wallet's On its way: what is travelling, then every step of its trip
/// in order. A step that is done wears the confirm check, the one under way
/// a clock, the ones ahead an empty circle. A trip that waits on you says
/// what it needs on its step, in amber, and the one row under the list is
/// the way on: the address it is waiting at, where the move is made.
struct OnItsWaySheet: View {
    let item: OnItsWay.Item
    /// Opens Receive on the private address. Called once the sheet has gone
    /// (a sheet that raises Move while it closes is re-rendered without the
    /// shell's environment: prd §1767).
    var openAddress: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var opens = false

    var body: some View {
        DSTray(title: item.title, height: CGFloat(200 + item.steps.count * 44 + (item.trip == .address ? 56 : 0))) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(item.steps.indices, id: \.self) { n in
                    row(n)
                }
                if item.trip == .address {
                    DSDoorRow(icon: "arrow.down", label: "Open the address") {
                        opens = true
                        dismiss()
                    }
                    .padding(.top, DS.Space.s2)
                }
            }
        }
        .onDisappear { if opens { openAddress() } }
    }

    private enum Phase { case done, now, ahead }

    private func phase(_ n: Int) -> Phase { n < item.current ? .done : n == item.current ? .now : .ahead }

    @ViewBuilder private func row(_ n: Int) -> some View {
        let phase = phase(n)
        let waits = phase == .now && item.needs != nil
        HStack(spacing: DS.Space.s3) {
            Group {
                switch phase {
                case .done:
                    Image(systemName: "checkmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.confirm)
                case .now:
                    Image(systemName: "clock").dsGlyph(.body, weight: .regular)
                        .foregroundStyle(waits ? DS.attention : DS.textSecondary)
                case .ahead:
                    Image(systemName: "circle").dsGlyph(.body, weight: .regular).foregroundStyle(DS.textTertiary)
                }
            }
            .frame(width: 24)
            .accessibilityHidden(true)
            Text(verbatim: waits ? (item.needs ?? item.steps[n]) : item.steps[n])
                .dsText(phase == .now ? .heading17 : .body17)
                .foregroundStyle(waits ? DS.attentionInk : phase == .now ? DS.textPrimary : phase == .done ? DS.textSecondary : DS.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }
}
