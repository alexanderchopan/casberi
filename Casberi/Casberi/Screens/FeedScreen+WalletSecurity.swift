import SwiftUI

/// **THE WALLET'S SECURITY TILE (prd §1107)** — who can act for you, and what
/// is trying to fool you, in one place.
///
/// It took two tiles' work: Permissions' (Safe signatures, delegations,
/// approvals, §947) and the three kinds Risk listed as "Worth a look" — address
/// poisoning, fake tokens, fake transfers (user: "those are three rows"). The
/// loan risk Risk also held went to Holdings, beside the positions it is about.
///
/// **The box is a CHECKUP** (user: "checkup is the best"): one statement — what
/// needs you, else what is worth reviewing, else "All clear" — over six counts,
/// one per kind, in the list's own order. A count with something behind it is
/// a door to its section; a zero is a fact and takes no tap (§83). It replaced
/// the ringed faces over "in reach" (user: "i HATE the image we have there");
/// the dollars in reach survive as a phrase on the line.
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
    var inReach: Double? = nil

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
            fakeTransfers: warnings.filter { $0.kind == .fakeTransfer }.count,
            inReach: WalletPermissions.totalUSD(holders))
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }
}

/// The checkup: a statement, one line, and six counts in two rows of three —
/// what can act for you over what is trying to fool you.
struct WalletSecurityFigure: View {
    let counts: WalletSecurityCounts
    let onJump: (FeedScreen.SecurityAnchor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(statement)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let line {
                Text(line)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Grid(horizontalSpacing: DS.Space.s2, verticalSpacing: DS.Space.s3) {
                GridRow {
                    cell(.signatures, glyph: WalletWarning.Kind.safe.glyph, count: counts.signatures,
                         word: String(localized: "Signatures"), needsYou: counts.signatures > 0)
                    cell(.delegations, glyph: WalletWarning.Kind.delegation.glyph,
                         count: counts.delegations,
                         word: String(localized: "Delegations"), needsYou: false)
                    // How many are unlimited is the line's to say; the count
                    // turns amber for them.
                    cell(.approvals, glyph: WalletWarning.Kind.approval.glyph, count: counts.approvals,
                         word: String(localized: "Approvals"), needsYou: counts.unlimited > 0)
                }
                GridRow {
                    cell(.poisoning, glyph: WalletWarning.Kind.poisoning.glyph, count: counts.poisoning,
                         word: String(localized: "Address poisoning"), needsYou: counts.poisoning > 0)
                    cell(.fakeTokens, glyph: WalletWarning.Kind.spoofedSymbol.glyph,
                         count: counts.fakeTokens,
                         word: String(localized: "Fake tokens"), needsYou: counts.fakeTokens > 0)
                    // Spam is noise to recognise, not an act (§1004's ink is
                    // for what wants you): it never turns amber.
                    cell(.fakeTransfers, glyph: WalletWarning.Kind.fakeTransfer.glyph,
                         count: counts.fakeTransfers,
                         word: String(localized: "Fake transfers"), needsYou: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// What needs you, else what is worth a look, else "All clear".
    private var statement: String {
        if counts.signatures > 0 {
            return counts.signatures == 1 ? String(localized: "1 needs you")
                                          : String(localized: "\(counts.signatures) need you")
        }
        let review = counts.unlimited + counts.poisoning + counts.fakeTokens
        if review > 0 { return String(localized: "\(review) to review") }
        return String(localized: "All clear")
    }

    /// The figures the cells cannot say: unlimited grants, flagged transfers,
    /// and the dollars in reach — masked under Hide balances.
    private var line: String? {
        var parts: [String] = []
        if counts.unlimited > 0 {
            parts.append(counts.unlimited == 1 ? String(localized: "1 unlimited approval")
                                               : String(localized: "\(counts.unlimited) unlimited approvals"))
        }
        if counts.flagged > 0 {
            parts.append(counts.flagged == 1 ? String(localized: "1 flagged transfer")
                                             : String(localized: "\(counts.flagged) flagged transfers"))
        }
        if let reach = counts.inReach {
            let money = BalancePrivacy.shared.withheld ? BalancePrivacy.mask
                                                       : WalletApprovalExposure.money(reach)
            parts.append(String(localized: "\(money) in reach"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func cell(_ anchor: FeedScreen.SecurityAnchor, glyph: String, count: Int,
                      word: String, needsYou: Bool) -> some View {
        // **THE GLYPH AND THE COUNT SHARE A LINE (user: "clipping").** Stacked,
        // a cell ran ~96pt and two rows of them overran the box; side by
        // side, each cell is one line and its word, and both rows fit.
        let face = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.Space.s2) {
                ZStack {
                    Circle().fill(DS.fillFaint)
                    Image(systemName: glyph)
                        .dsGlyph(.caption, weight: .semibold)
                        .foregroundStyle(needsYou ? DS.attention : DS.textSecondary)
                }
                .frame(width: Self.disc, height: Self.disc)
                .accessibilityHidden(true)
                Text("\(count)")
                    .dsText(.stat24)
                    .foregroundStyle(needsYou ? DS.attentionInk
                                     : (count == 0 ? DS.textTertiary : DS.textPrimary))
                    .monospacedDigit()
            }
            Text(word)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)

        // A count with something behind it is a door; a zero is a fact (§83).
        if count > 0 {
            Button {
                DSHaptic.selection()
                onJump(anchor)
            } label: {
                face.contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
        } else {
            face
        }
    }

    static let disc: CGFloat = 28
}
