import SwiftUI

/// The agent's room on a plain open (prd §332, 2026-08-07) — the rendering half
/// of `AgentOpen`.
///
/// Reads only VALUE types (`AgentOpen.Item`), never a `Thing`. That is worth
/// stating because it makes a whole crash family structurally unreachable here:
/// the liveness corollaries 1–6 all describe a view reading a stored property
/// off a model that was deleted underneath it, and nothing in this file holds a
/// model to begin with. Rows carry an id string and hand it back on tap, so the
/// audit's six checks find nothing because there is nothing to find.
///
/// Both callbacks route through the composer's existing doors: `onOpen` is the
/// same `path.append(id)` the gen-UI thing-open environment hook uses, and
/// `onAsk` is `commit()`, so a tap here starts an ordinary turn on the agent's
/// own Stack — no new navigation, no new answer surface.
struct AgentOpenBoard: View {
    let composition: AgentOpen.Composition
    /// Send a question — the composer's `commit()`.
    let onAsk: (String) -> Void
    /// Open a thing by id — the composer's `path.append`.
    let onOpen: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice = composition.notice { noticeCard(notice) }
            if !composition.tiles.isEmpty { tileRow }
            if !composition.threads.isEmpty { threadStack }
            if let fold = composition.fold { foldRow(fold) }
            if let quiet = composition.quiet { quietLine(quiet) }
        }
    }

    // MARK: - The noticing

    /// The claim, with the things it is about pinned underneath.
    ///
    /// The kicker's wording tracks WHO looked. "Noticed overnight" is a claim
    /// that the model read the corpus, and on a device with no Apple
    /// Intelligence — where the line is a deterministic join standing in — that
    /// sentence would be false. §83 forbids exactly this kind of borrowed
    /// status, so the deterministic path says what it actually is.
    @ViewBuilder
    private func noticeCard(_ notice: AgentOpen.Notice) -> some View {
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

    private func evidenceChip(_ item: AgentOpen.Item) -> some View {
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

    // MARK: - The answers

    /// Kept asks, answering on their faces.
    ///
    /// A tile IS the pill it replaced — same tap, same `commit()`, same kind —
    /// so nothing about keeping or un-keeping an ask changed. What changed is
    /// that the row no longer spends its height saying "something moved" when
    /// the computation behind it already knows what.
    private var tileRow: some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            ForEach(Array(composition.tiles.enumerated()), id: \.element.kind) { i, tile in
                Button {
                    DSHaptic.selection()
                    onAsk(tile.title)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tile.title)
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                        Text(tile.headline)
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let sub = tile.sub {
                            Text(sub)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.s3)
                    .background(tile.changed ? AnyShapeStyle(DS.tintDim)
                                             : AnyShapeStyle(DS.surfaceSheet),
                                in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                     style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .dsHover()
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .modifier(BoardEntrance(index: i, reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
    }

    // MARK: - What moved

    private var threadStack: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("what moved")
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s4)

            ForEach(Array(composition.threads.enumerated()), id: \.element.name) { i, thread in
                VStack(alignment: .leading, spacing: DS.Space.s1 + 1) {
                    HStack(spacing: DS.Space.s2) {
                        Text(thread.name)
                            .dsText(.heading17)
                            .foregroundStyle(thread.loose ? DS.textTertiary : DS.textPrimary)
                            .lineLimit(1)
                        if let streak = thread.streak {
                            Text(streak)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.tint)
                                .padding(.horizontal, DS.Space.s2)
                                .padding(.vertical, 3)
                                .background(DS.tintDim,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Space.s4)

                    ForEach(thread.rows, id: \.item.id) { row in
                        rowView(row)
                    }
                }
                .modifier(BoardEntrance(index: i + 1, reduceMotion: reduceMotion))
            }
        }
    }

    private func rowView(_ row: AgentOpen.Row) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(row.item.id)
        } label: {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                BridgeIcon(name: row.item.source, size: 30, circular: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.item.title)
                        .dsText(.callout15)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let margin = row.margin {
                        Text(margin)
                            .dsText(.subhead13)
                            .foregroundStyle(row.marginIsSignal ? DS.tint : DS.textTertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .dsHover()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.s4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The fold

    /// What didn't earn a row, as one line wearing its sources' marks.
    ///
    /// A tap ASKS rather than expanding in place: "while I was away" is a real
    /// question this app already answers with the full list, so the fold hands
    /// off to the answer path instead of growing a second, lesser list here.
    private func foldRow(_ fold: AgentOpen.Fold) -> some View {
        Button {
            DSHaptic.selection()
            onAsk(String(localized: "While I was away?"))
        } label: {
            HStack(spacing: DS.Space.s2) {
                HStack(spacing: -6) {
                    ForEach(fold.sources, id: \.self) { source in
                        BridgeIcon(name: source, size: 20, circular: true)
                    }
                }
                Text("\(fold.count) more")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .dsHover()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
        .accessibilityElement(children: .combine)
    }

    private func quietLine(_ text: String) -> some View {
        Text(text)
            .dsText(.subhead13)
            .foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)
    }
}

/// One band's staggered rise on open — the same grammar `ChipEntrance` already
/// gives the chip rows, so the board settles as one surface rather than two.
///
/// Honours Reduce Motion (`design-motion-audit.py`'s first check): an
/// appear-triggered animation must, and this one is appear-triggered by
/// construction — it plays off `shown` flipping in `onAppear`.
private struct BoardEntrance: ViewModifier {
    let index: Int
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .animation(reduceMotion ? nil
                       : DS.Motion.standard.delay(Double(min(index, 6)) * 0.05),
                       value: shown)
            .onAppear { shown = true }
    }
}
