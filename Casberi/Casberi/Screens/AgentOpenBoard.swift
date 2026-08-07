import SwiftUI

/// The agent's room on a plain open (prd §334) — the lead, then the panel.
///
/// §332 built this as a lead plus answer tiles plus a threaded ledger, and the
/// ledger is what made it read as a list. The user's ruling: "the rest is all /
/// only visualizations from source feeds… show something they don't see on All
/// and give the most info at a glance." So the body is `AgentPanelGrid` and
/// nothing else — every room's own figure, and no rows.
///
/// Reads only value types (`AgentPanel.*`), never a `Thing`. That makes the
/// whole liveness-corollary family structurally unreachable here: rows carry an
/// id string and hand it back on tap, so there is no model to read off.
struct AgentOpenBoard: View {
    let composition: AgentPanel.Composition
    /// Open a thing by id — the composer's `path.append`.
    let onOpen: (String) -> Void
    /// Open a room — the composer switches the feed and lowers the agent.
    let onOpenRoom: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice = composition.notice { noticeCard(notice) }
            if !composition.cards.isEmpty {
                AgentPanelGrid(cards: composition.cards, onOpen: onOpenRoom)
            }
        }
    }

    /// The claim, with the things it is about pinned underneath.
    ///
    /// The kicker's wording tracks WHO looked. "Noticed overnight" claims the
    /// model read the corpus, and on a device with no Apple Intelligence — where
    /// a deterministic join stands in — that sentence would be false. §83
    /// forbids exactly that borrowed status.
    @ViewBuilder
    private func noticeCard(_ notice: AgentPanel.Notice) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s1 + 2) {
                    Image(systemName: notice.deterministic ? "link" : "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(notice.deterministic
                         ? String(localized: "a connection in your things")
                         : String(localized: "noticed overnight"))
                        .dsText(.subhead13)
                }
                .foregroundStyle(DS.tint)

                Text(notice.claim)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s4)

            if !notice.evidence.isEmpty {
                HStack(alignment: .top, spacing: DS.Space.s2) {
                    ForEach(notice.evidence, id: \.id) { item in
                        evidenceChip(item)
                    }
                }
                .padding(.horizontal, DS.Space.s3)
                .padding(.bottom, DS.Space.s3)
            }
        }
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
        .settleIn(delay: 0.04)
    }

    private func evidenceChip(_ item: AgentPanel.Item) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(item.id)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1 + 1) {
                HStack(spacing: DS.Space.s1 + 2) {
                    BridgeIcon(name: item.source, size: 15, circular: false)
                    Text(item.source)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Text(item.title)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s3)
            .background(DS.surfaceWell,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .dsHover()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
