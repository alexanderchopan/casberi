import SwiftUI

/// **PRIVACY, ON THREATS (prd §1701).** One row per EVM account the
/// Wallet's Yours · Following · All switch has in scope: what Nymis read
/// gives the address away, or Scan. No score anywhere (user, 2026-11-04).
/// The whole row is the control: Scan scans, a reading opens its sheet.
extension FeedScreen {

    /// The accounts in scope that Nymis can read: your account and the
    /// wallets you follow, narrowed as the switch and the menu narrow every
    /// other list; an app picked has none.
    var walletPrivacySlots: [DSAccountSlot] {
        let evm = walletAccountSlots.filter { slot in
            !RoomAccounts.isSeat(slot.id) && NymisScan.isEVMAddress(slot.id)
        }
        if RoomAccounts.isSeat(chrome.walletScope) { return [] }
        if walletOnFollowing { return evm.filter { !Self.isYourAccount($0.id) } }
        if let one = selectedWallet {
            return evm.filter { NymisScan.key($0.id) == NymisScan.key(one) }
        }
        return evm.filter { Self.isYourAccount($0.id) } + evm.filter { !Self.isYourAccount($0.id) }
    }

    @ViewBuilder
    func walletPrivacySection(_ slots: [DSAccountSlot]) -> some View {
        if !slots.isEmpty {
            walletCard(String(localized: "Privacy"), glyph: "", mark: "Nymis") {
                ForEach(slots) { slot in walletPrivacyRow(slot) }
                DSFootnote("Scanning sends the address to Nymis.")
                    .padding(.leading, DSRoomChassis.headGlyph + DSRoomChassis.headGap)
                    .walletListRow()
            }
            .task { NymisScans.shared.resume() }
        }
    }

    @ViewBuilder
    func walletPrivacyRow(_ slot: DSAccountSlot) -> some View {
        let state = NymisScans.shared.state(slot.id)
        Button {
            switch state {
            case .done, .failed(.some):
                DSHaptic.selection()
                feedSheet = .nymisReading(address: slot.id, name: slot.name)
            case .none, .failed(nil):
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { NymisScans.shared.scan(slot.id) }
            case .scanning:
                break
            }
        } label: {
            DSFeedRow(name: slot.name, line: Self.privacyLine(state, slot: slot),
                      trailingBesideLine: true) {
                WalletFace(address: slot.id, size: DS.Face.row, circular: true)
            } trailing: {
                switch state {
                case .done(let reading), .failed(.some(let reading)):
                    Text(verbatim: FeedScreen.dayWord(reading.scannedAt))
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                case .scanning:
                    DSSpinner()
                case .none, .failed(nil):
                    Text("Scan").dsText(.body17).foregroundStyle(DS.pickInk)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .disabled(state.isScanning)
        .contextMenu {
            if !state.isScanning, NymisScans.shared.reading(slot.id) != nil {
                Button { NymisScans.shared.scan(slot.id) } label: {
                    Label("Scan again", systemImage: "arrow.clockwise")
                }
            }
        }
        .walletListRow()
    }

    /// Under the name: what gives the address away, what Nymis is doing,
    /// or the address itself before a scan.
    static func privacyLine(_ state: NymisScans.State, slot: DSAccountSlot) -> Text? {
        switch state {
        case .done(let reading):
            return Text(verbatim: NymisScan.rowLine(reading) ?? String(localized: "Nothing gives it away"))
        case .scanning(let stage):
            return Text(verbatim: stage ?? String(localized: "Starting"))
        // The reading before it still opens; the line says the new one failed.
        case .failed(let reading):
            return Text(reading == nil ? "Couldn't scan" : "Couldn't scan again").foregroundStyle(DS.attentionInk)
        case .none:
            return slot.sub.map { Text(verbatim: $0) }
        }
    }
}

extension NymisScans.State {
    var isScanning: Bool { if case .scanning = self { true } else { false } }
}
