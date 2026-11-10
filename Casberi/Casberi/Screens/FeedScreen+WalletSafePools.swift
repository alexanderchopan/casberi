import SwiftUI

/// **YOUR SAFES, ON YOUR ACCOUNT'S PAGE (prd §1738, was the Safe pick's,
/// §1614).** Safe and Privacy Pools are no pick: the Wallet already shows
/// their money. What only the Safe pick said stands under Your account's
/// keys — "Your Safes" (who signs each) and "Without a signature" (what can
/// move each with nobody signing). How hidden a private balance is, is said
/// where you send from it (`MovePrivate`).
extension FeedScreen {

    /// The Safe rows' ids and tags: a landed, signed or gone transaction
    /// changes it, so the Safe box reads its queue again.
    static func safeQueueKey(_ visible: [Thing]) -> Int {
        var hasher = Hasher()
        for thing in visible where thing.isLive && thing.source == SafeBridge.sourceName {
            hasher.combine(thing.sourceRef)
            hasher.combine(thing.tags)
        }
        return hasher.finalize()
    }

    /// A Safe's door: your account's keys, or the Safe's own app.
    func walletOpenSafe(_ safe: SafeRoster.Safe) {
        if safe.isYourAccount {
            chrome.walletSection = .yourAccount
        } else if let seg = safe.seg, let url = SafeBridge.webURL(seg: seg, safeAddress: safe.address) {
            openExternal(url)
        }
    }

    /// Opens Move's private sentence (prd §1554).
    func walletMovePrivately(_ mode: PrivateMove.Mode) {
        DSHaptic.selection()
        chrome.movePrivately = mode
        chrome.moveTray = true
    }

}

/// **YOUR SAFES, AND WITHOUT A SIGNATURE (prd §1614, on Your account's page
/// since §1738):** each Safe you hold a key to, who signs it, and what can
/// move it with nobody signing. Your account says None (prd §1631); a Safe
/// with no module says None; a module on another Safe is red. A row opens
/// the Safe.
struct WalletUnsignedSection: View {
    var onOpenSafe: (SafeRoster.Safe) -> Void
    /// The queue's rows, so a signature landing re-reads the roster.
    var queueKey: Int = 0
    /// Read from the first frame (stored reads, no network), so the header
    /// never stands without its rows.
    @State private var roster = SafeRoomSource.roster(yours: SafeRosterReading.shared.yours)

    var body: some View {
        if !roster.isEmpty {
            yourSafes
            section
        }
    }

    private var yourSafes: some View {
        SectionPanelGroup(anchor: nil) {
            SectionPanelName(name: String(localized: "Your Safes"), glyph: "person.badge.key")
        } rows: {
            Section {
                ForEach(roster.safes) { safe in
                    Button {
                        DSHaptic.selection()
                        onOpenSafe(safe)
                    } label: {
                        HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                            Image(systemName: safe.isYourAccount ? "person.crop.circle" : "person.2")
                                .dsGlyph(.body)
                                .foregroundStyle(DS.textSecondary)
                                .frame(width: DSRoomChassis.headGlyph)
                                .accessibilityHidden(true)
                            Text(verbatim: safe.name)
                                .dsText(.body17)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: DS.Space.s2)
                            SafeFaces(faces: safe.faces)
                            if let need = SafeRoster.need(safe) {
                                Text(verbatim: need)
                                    .dsText(.price17)
                                    .monospacedDigit()
                                    .foregroundStyle(DS.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .walletRowPitch()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                    .accessibilityLabel(Text(verbatim: [safe.name, SafeRoster.line(safe), SafeRoster.need(safe)]
                        .compactMap { $0 }.joined(separator: ", ")))
                    .walletListRow()
                }
            }
        }
        .environment(\.feedSectionPanelFilled, false)
    }

    private var section: some View {
        SectionPanelGroup(anchor: nil) {
            SectionPanelName(name: String(localized: "Without a signature"), glyph: "checkmark.shield")
        } rows: {
            Section { rows }
        }
        // Bare, as the Feed's (prd §1382), and as `walletCard` draws it.
        .environment(\.feedSectionPanelFilled, false)
        .task(id: queueKey) {
            roster = SafeRoomSource.roster(yours: SafeRosterReading.shared.yours)
            await SafeRosterReading.shared.refresh()
            roster = SafeRoomSource.roster(yours: SafeRosterReading.shared.yours)
        }
    }

    @ViewBuilder
    private var rows: some View {
            ForEach(roster.safes) { safe in
                let unsigned = SafeRoster.unsigned(safe)
                Button {
                    DSHaptic.selection()
                    onOpenSafe(safe)
                } label: {
                    HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                        Image(systemName: glyph(unsigned.tone))
                            .dsGlyph(.body)
                            .foregroundStyle(ink(unsigned.tone, glyph: true))
                            .frame(width: DSRoomChassis.headGlyph)
                            .accessibilityHidden(true)
                        Text(verbatim: safe.name)
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: unsigned.word)
                            .dsText(.price17)
                            .foregroundStyle(ink(unsigned.tone, glyph: false))
                            .lineLimit(1)
                    }
                    .walletRowPitch()
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
                .accessibilityLabel(Text(verbatim: "\(safe.name). \(unsigned.word)"))
                .walletListRow()
            }
    }

    private func glyph(_ tone: SafeRoster.Tone) -> String {
        switch tone {
        case .confirm: "checkmark.shield"
        case .danger: "exclamationmark.shield"
        }
    }

    /// A status word takes the ink, a glyph keeps the hue (§1004).
    private func ink(_ tone: SafeRoster.Tone, glyph: Bool) -> Color {
        switch tone {
        case .confirm: glyph ? DS.confirm : DS.confirmInk
        case .danger: glyph ? DS.destructive : DS.destructiveInk
        }
    }
}
