import SwiftUI

/// **THE WALLET'S SECURITY TILE (prd §1107)** — who can act for you, and what
/// is trying to fool you, in one place.
///
/// It took two tiles' work: Permissions' (Safe signatures, delegations,
/// approvals, §947) and the three kinds Risk listed as "Worth a look" — address
/// poisoning, fake tokens, fake transfers (user: "those are three rows"). The
/// loan risk Risk also held went to Holdings, beside the positions it is about.
///
/// **The box is a CHECKUP** (user: "checkup is the best"): six counts, one per
/// kind, in the list's own order, and no statement over them (§1107a). A count
/// with something behind it is a door to its section; a zero is a fact and
/// takes no tap (§83). It replaced the ringed faces over "in reach" (user: "i
/// HATE the image we have there"); what each grant reaches is on its row.
///
/// The cells stand bare on the box's well, as every figure does: no plate
/// under a cell (§758, §782).
struct WalletSecurityCounts: Equatable {
    var signatures = 0
    var delegations = 0
    /// A delegate read whose modules could not be read: the section says so,
    /// so the scope is not empty, though nothing is counted.
    var delegationsUnreadable = false
    var approvals = 0
    var unlimited = 0
    var poisoning = 0
    var fakeTokens = 0
    var fakeTransfers = 0

    var flagged: Int { poisoning + fakeTokens + fakeTransfers }
    var isEmpty: Bool {
        signatures + delegations + approvals + flagged == 0 && !delegationsUnreadable
    }
}

extension FeedScreen {

    /// The six counts, from the same reads the sections below draw on, so a
    /// cell and its section can never disagree.
    var walletSecurityCounts: WalletSecurityCounts {
        let holders = WalletPermissionsSource.holders(exposure: walletLive.exposure,
                                                      acting: walletLive.acting)
        let warnings = walletLive.warnings
        let grants = walletLive.exposure.all
        return WalletSecurityCounts(
            signatures: walletSignatureWarnings.count,
            delegations: WalletPermissions.actingHolders(holders).count,
            delegationsUnreadable: walletLive.acting.contains(where: { $0.modulesUnreadable }),
            approvals: grants.count,
            unlimited: grants.filter(\.unlimited).count,
            poisoning: warnings.filter { $0.kind == .poisoning }.count,
            fakeTokens: warnings.filter { $0.kind == .spoofedSymbol }.count,
            fakeTransfers: warnings.filter { $0.kind == .fakeTransfer }.count)
    }

    /// Where a cell's door lands: its section's header.
    enum SecurityAnchor: String {
        case signatures, delegations, approvals, poisoning, fakeTokens, fakeTransfers
        var id: String { "wallet.security.\(rawValue)" }
    }

    var walletSecurityFigure: some View {
        WalletSecurityFigure(counts: walletSecurityCounts) { anchor in
            cardScrollTarget = anchor.id
        }
    }

    /// The list, in the box's order: what waits on you, what acts as you,
    /// what can spend for you, then the three kinds of transfer made to fool
    /// you. Each section draws only when it has rows.
    @ViewBuilder
    var walletSecuritySections: some View {
        walletSignaturesSection
        walletActingSection
        walletApprovalsSection
        walletFlaggedSection(.poisoning, anchor: .poisoning,
                             word: String(localized: "Address poisoning"))
        walletFlaggedSection(.spoofedSymbol, anchor: .fakeTokens,
                             word: String(localized: "Fake tokens"))
        walletFlaggedSection(.fakeTransfer, anchor: .fakeTransfers,
                             word: String(localized: "Fake transfers"))
    }

    /// One kind of flagged transfer under its own name (it was one "Worth a
    /// look" group, §947). A row opens the tray at its group, as it did.
    @ViewBuilder
    func walletFlaggedSection(_ kind: WalletWarning.Kind, anchor: SecurityAnchor,
                              word: String) -> some View {
        let flagged = walletLive.warnings.filter { $0.kind == kind }
        if !flagged.isEmpty {
            Section {
                DSGroupHeader(word: word)
                    .id(anchor.id)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(flagged) { warning in
                        needsYouRow(glyph: warning.kind.glyph,
                                    critical: warning.severity == .critical,
                                    title: warning.rowName ?? warning.title,
                                    line: warning.rowLine ?? warning.subtitle) {
                            feedSheet = .worthALook
                        }
                    }
                }
                .listRowInsets(WalletCardStyle.rowInsets)
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
        }
    }
}

/// The checkup: six counts in two rows of three — what can act for you over
/// what is trying to fool you — and nothing else (prd §1107a, user: "i'm not
/// even sure if we need to say n Needs you"). The amber counts and the tile's
/// amber word already say what needs you, so the box gives the counts its
/// whole height.
struct WalletSecurityFigure: View {
    let counts: WalletSecurityCounts
    let onJump: (FeedScreen.SecurityAnchor) -> Void

    /// **SETTINGS' COUNT GRID (prd §1221, user: "make the security card look
    /// like the settings and sources one -- 2 columns").** Six counts two
    /// across in `DSCountTile`s; a count that wants you says so in its word
    /// (§1004), and a zero is a fact, not a door (§83).
    var body: some View {
        let cells: [(FeedScreen.SecurityAnchor, Int, String, Bool)] = [
            (.signatures, counts.signatures, String(localized: "Signatures"), counts.signatures > 0),
            (.delegations, counts.delegations, String(localized: "Delegations"), false),
            // A grant with no limit wants you.
            (.approvals, counts.approvals, String(localized: "Approvals"), counts.unlimited > 0),
            // The tile's short word; the list under it keeps the full name.
            (.poisoning, counts.poisoning, String(localized: "Poisoning"), counts.poisoning > 0),
            (.fakeTokens, counts.fakeTokens, String(localized: "Fake tokens"), counts.fakeTokens > 0),
            // Spam is noise to recognise, not an act: it never wants you.
            (.fakeTransfers, counts.fakeTransfers, String(localized: "Fake transfers"), false),
        ]
        let widest = cells.map(\.1).max()
        DSCountGrid(items: cells.count, bare: true) {
            ForEach(cells, id: \.0) { anchor, count, word, wants in
                DSCountTile(count: count, label: word, isOn: false, wants: wants,
                            inline: true, widest: widest) {
                    DSHaptic.selection()
                    onJump(anchor)
                }
                .disabled(count == 0)
            }
        }
    }
}
