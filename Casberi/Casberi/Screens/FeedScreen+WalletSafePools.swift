import SwiftUI

/// **SAFES YOU SIGN FOR, ON YOUR ACCOUNT'S PAGE (prd §1738, was the Safe
/// pick's, §1614; named §1976).** Safe and Privacy Pools are no pick: the
/// Wallet already shows their money. What only the Safe pick said stands on
/// Account — "Safes you sign for" (who signs each) and "Without a signature"
/// (what can move each with nobody signing). How hidden a private balance is, is said
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
    /// **EACH HALF WHERE IT BELONGS (prd §1786, user, of the two under
    /// Account: "i'm confused where they should go").** Who signs a Safe is
    /// Account's, and only once you hold a key to a Safe besides your own:
    /// for your account alone it said the Keys above it again. What can move
    /// a Safe with nobody signing is a permission, and stands on Permissions.
    enum Part { case unsigned, lines }
    var part: Part
    var onOpenSafe: (SafeRoster.Safe) -> Void
    /// Sets this phone up to sign for another Safe; nil where it has no door.
    var onSignForAnother: (() -> Void)? = nil
    /// The queue's rows, so a signature landing re-reads the roster.
    var queueKey: Int = 0
    /// Read from the first frame (stored reads, no network), so the header
    /// never stands without its rows.
    @State private var roster = SafeRoomSource.roster(yours: SafeRosterReading.shared.yours)

    var body: some View {
        switch part {
        case .lines:
            // **SAFES YOU SIGN FOR (user, 2026-11-25: "re 'your safes' should
            // we call it 'external safes' or something i've always felt it is
            // kind of confusing").** Your account is the Safe line above;
            // it is never drawn again here ("Safe · Yours" said it twice).
            // The Safes you hold a key to stand under their own words, each
            // by its name, and the last line sets this phone up to sign for
            // another (`SafeScreen`, whose door was the retired Safe tile,
            // prd §1975).
            VStack(alignment: .leading, spacing: 0) {
                AccountSubhead(text: String(localized: "Safes you sign for"))
                ForEach(roster.safes.filter { !$0.isYourAccount }) { safe in
                    AccountLine(label: safe.name,
                                value: SafeRoster.need(safe).map { String(localized: "\($0) signers") },
                                end: .opens, action: { onOpenSafe(safe) })
                }
                if let onSignForAnother {
                    AccountLine(label: String(localized: "Sign for another Safe"), end: .opens,
                                action: onSignForAnother)
                }
            }
            .task(id: queueKey) { await read() }
        case .unsigned:
            // **ONLY WHAT CAN MOVE ONE (prd §1919, user: "'without a
            // signature' 'none' is weird too. its like a double negative").**
            // An account nothing can move draws no row, and with none the
            // section is not drawn: nothing for a zero (§1463).
            if !movable.isEmpty { section }
            else {
                Color.clear.frame(height: 0).task(id: queueKey) { await read() }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    /// The Safes something can move with nobody signing.
    private var movable: [SafeRoster.Safe] {
        roster.safes.filter { SafeRoster.unsigned($0).tone == .danger }
    }

    private func read() async {
        roster = SafeRoomSource.roster(yours: SafeRosterReading.shared.yours)
        await SafeRosterReading.shared.refresh()
        roster = SafeRoomSource.roster(yours: SafeRosterReading.shared.yours)
    }

    private var section: some View {
        SectionPanelGroup(anchor: nil) {
            SectionPanelName(name: String(localized: "Without a signature"), glyph: "checkmark.shield")
        } rows: {
            Section { rows }
        }
        // Bare, as the Feed's (prd §1382), and as `walletCard` draws it.
        .environment(\.feedSectionPanelFilled, false)
        .task(id: queueKey) { await read() }
    }

    @ViewBuilder
    private var rows: some View {
            ForEach(movable) { safe in
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
