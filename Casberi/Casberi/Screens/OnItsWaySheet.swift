import SwiftUI

/// **ONE THING ON ITS WAY, ITS STEPS (prd §1779).** The page behind a row of
/// the Wallet's On its way: what is travelling, then every step of its trip
/// in order. A step that is done wears the confirm check, the one under way
/// a clock, the ones ahead an empty circle. A trip that waits on you says
/// what it needs on its step, in amber, and the one row under the list is
/// the way on: the address it is waiting at, where the move is made. A
/// deposit Privacy Pools is checking offers Take it back there instead
/// (prd §1576, moved here from Needs you by §1827).
struct OnItsWaySheet: View {
    let item: OnItsWay.Item
    /// Opens Receive on the private address. Called once the sheet has gone
    /// (a sheet that raises Move while it closes is re-rendered without the
    /// shell's environment: prd §1767).
    var openAddress: () -> Void = {}
    /// Takes back the notes named, once the sheet has gone (as above).
    var takeBack: ([String]) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var opens = false
    @State private var confirming = false
    @State private var takes = false

    /// The notes Take it back would return, still kept and still checked.
    private var takeable: [PrivateMoney.Note] {
        let wanted = Set(item.commitments.map { $0.lowercased() })
        return PrivateMoneyStore.shared.notes.filter { wanted.contains($0.commitment.lowercased()) && $0.status == .waiting }
    }

    var body: some View {
        let notes = item.trip == .approval ? takeable : []
        DSTray(title: item.title, height: CGFloat(200 + item.steps.count * 44 + (item.trip == .address || !notes.isEmpty ? 56 : 0))) {
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
                if !notes.isEmpty {
                    DSDoorRow(icon: "arrow.uturn.backward", label: "Take it back") {
                        confirming = true
                    }
                    .padding(.top, DS.Space.s2)
                }
            }
        }
        .confirmationDialog(Text("Take back \(item.title)?"), isPresented: $confirming, titleVisibility: .visible) {
            Button(String(localized: "Take it back")) {
                takes = true
                dismiss()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            // Where it goes, on the network it is on, and what it gives up.
            Text(notes.first?.chainId == PrivacyNetwork.ethereum.chainId
                 ? String(localized: "It goes back to your account on Ethereum, in public. This deposit won't be private.")
                 : String(localized: "It goes back to \(WalletPrivateAsks.owner) on Sepolia, in public."))
        }
        .onDisappear {
            if opens { openAddress() }
            if takes { takeBack(notes.map(\.commitment)) }
        }
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
