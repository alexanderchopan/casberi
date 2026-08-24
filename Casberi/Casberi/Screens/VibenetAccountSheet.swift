import SwiftUI

/// R3.2 (2026-08-23) — the account detail SHEET, replacing the card's old
/// expand-in-place block. `.sheet(item:)` on `VibenetScreen`, keyed by the
/// address itself (`String` is `Identifiable` — the same shape
/// `L2beatScreen`/`WalletbeatScreen` use for a chain/wallet id, no wrapper
/// type needed).
///
/// VALUE TYPES ONLY. `room` is a `VibenetRoom` struct, not a `Thing` —
/// nothing here is SwiftData, so none of the six liveness corollaries in
/// CLAUDE.md apply. What DOES apply is the shape of the problem they solve:
/// `room` can go stale while the sheet is open (a foreground refresh
/// re-composes it, or the address gets unwatched from the row's own
/// context menu). `item` is recomputed from the LATEST `room` every body
/// pass, and if the address is no longer in it, the sheet shows nothing
/// and dismisses itself rather than rendering a frozen, wrong account.
struct VibenetAccountSheet: View {
    let address: String
    let room: VibenetRoom
    var onRemove: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    /// The rename alert lives HERE, not delegated to the presenting
    /// screen — an `.alert` attached to a view BEHIND an active sheet
    /// never shows (the sheet covers it), so the screen's own alert (for
    /// the card's context menu) can't double as this one. No separate
    /// target to track: this sheet is always about `address`.
    @State private var renaming = false
    @State private var renameText = ""

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    private var item: VibenetAccountItem? { room.items.first { $0.address == address } }

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.Space.s4) {
                            hero(item)
                            stateSentence(item)
                            if !item.actors.isEmpty {
                                keysSection(item)
                            }
                            historySection(item)
                            syncSection(item)
                            doorsSection(item)
                        }
                        .padding(DS.Space.s4)
                    }
                    .dsPageBackground()
                    .dsSoftScrollEdges()
                } else {
                    // The address vanished from `room` (unwatched, or a
                    // re-compose that dropped it) — dismiss rather than
                    // show a frozen or empty account. `Color.clear` gives
                    // `onAppear` something to fire from with no flash of
                    // empty content.
                    Color.clear.onAppear { dismiss() }
                }
            }
            .navigationTitle(item.map { VibenetWatch.shared.name(for: $0.address) ?? VibenetRoom.shortAddress($0.address) } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                if item != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                renameText = VibenetWatch.shared.name(for: address) ?? ""
                                renaming = true
                            } label: {
                                Label(String(localized: "Name this account…"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onRemove(address)
                                dismiss()
                            } label: {
                                Label(String(localized: "Stop watching"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert(String(localized: "Name this account"), isPresented: $renaming) {
                TextField(String(localized: "Name"), text: $renameText)
                Button(String(localized: "Save")) {
                    VibenetWatch.shared.setName(renameText, for: address)
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
        }
        .dsPageSheet()
    }

    // MARK: - Hero

    private func hero(_ item: VibenetAccountItem) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            WalletFace(address: item.address, size: 56, circular: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(VibenetWatch.shared.name(for: item.address) ?? VibenetRoom.shortAddress(item.address))
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                // The FULL address, always — this is the one place it
                // appears whole. Middle truncation (never tail) so both
                // the identifying head and the distinguishing tail
                // survive if it doesn't fit; Copy in the doors below
                // hands over the exact string regardless.
                Text(item.address)
                    .dsText(.label11).monospaced()
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: DS.Space.s2)
            if item.alarmed {
                Text(item.hasInitiatedUnlock ? String(localized: "Unlocking") : String(localized: "Locked"))
                    .dsText(.label11).fontWeight(.bold)
                    .foregroundStyle(Color.fixed("#ffffff"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Self.mark, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }

    // MARK: - State sentence

    /// The row's own precedence, verbatim — unlock countdown + runway,
    /// else the urgency line, else the plain key-count sentence. Full
    /// width here (no `maxWidth: 160` cap): the row compressed the
    /// runway for a summary tile, the sheet has the whole page.
    private func stateSentence(_ item: VibenetAccountItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.hasInitiatedUnlock, let countdown = item.unlockLabel(now: .now) {
                Text(countdown)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                if let progress = item.unlockProgress(now: .now) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Self.mark.opacity(0.15))
                            Capsule().fill(Self.mark)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                }
            } else if let urgent = item.urgentLine(now: .now) {
                Text(urgent)
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(Self.mark)
            } else {
                Text(VibenetRoom.rowLine(item))
                    .dsText(.callout15)
                    .foregroundStyle(item.alarmed ? DS.textPrimary : DS.textSecondary)
            }
        }
    }

    // MARK: - Keys (R3.1 — the matrix's replacement)

    private func keysSection(_ item: VibenetAccountItem) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(String(localized: "Keys"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
            ForEach(VibenetAccountItem.byReach(item.actors)) { actor in
                keyRow(actor)
            }
        }
    }

    /// One key, one row — plain title, one honest detail clause, then its
    /// granted permissions as chips (R2.3's exact capsule grammar) laid
    /// out with `FlowLayout` so a whole capsule wraps to the next line
    /// but the text INSIDE one never does. Replaces the matrix's column
    /// lookup with "read the row" — the whole point of R3.1.
    private func keyRow(_ actor: VibenetActor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(actor.kind.plainTitle)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
            if let detail = actor.kind.plainDetail {
                Text(detail)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
            }
            let labels = actor.scope.grantedPlainLabels
            if labels.isEmpty {
                // A real state, not an empty chip row — an authorized
                // actor that can originate nothing yet.
                Text(String(localized: "Can't originate anything yet"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        let isUnknownTail = index == labels.count - 1 && actor.scope.unknownCount > 0
                        Text(label)
                            .dsText(.label11)
                            .foregroundStyle(isUnknownTail ? DS.textTertiary : DS.textPrimary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                // The unknown-count tail draws OUTLINED —
                                // a visibly different claim from a named
                                // permission, never an invented name
                                // wearing the same fill (§83).
                                if isUnknownTail {
                                    Capsule().strokeBorder(DS.textTertiary, lineWidth: 1)
                                } else {
                                    Capsule().fill(Self.mark.opacity(0.12))
                                }
                            }
                    }
                }
            }
            if actor.expiry > 0 {
                Text(actor.expiryLabel(now: .now))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    // MARK: - History (R2.1, moved unchanged)

    private func historySection(_ item: VibenetAccountItem) -> some View {
        Group {
            if let line = VibenetKeyHistory.summaryLine(item.history) {
                let labels = VibenetKeyHistory.endpointLabels(item.history, now: .now)
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text(String(localized: "History"))
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                    Text(line)
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                    if item.history.count > 1 {
                        HStack(spacing: 8) {
                            if item.history.count > VibenetKeyHistory.cap {
                                Text(String(localized: "+\(item.history.count - VibenetKeyHistory.cap) earlier"))
                                    .dsText(.label11)
                                    .foregroundStyle(DS.textTertiary)
                                    .lineLimit(1)
                            }
                            ForEach(item.history) { moment in
                                Circle()
                                    .strokeBorder(Self.mark, lineWidth: moment.authorized ? 0 : 2.5)
                                    .background(Circle().fill(moment.authorized ? Self.mark : .clear))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        HStack {
                            if let oldest = labels.oldest {
                                Text(oldest).dsText(.label11).foregroundStyle(DS.textTertiary)
                                    .lineLimit(1).fixedSize()
                            }
                            Spacer(minLength: DS.Space.s2)
                            if let newest = labels.newest {
                                Text(newest).dsText(.label11).foregroundStyle(DS.textTertiary)
                                    .lineLimit(1).fixedSize()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sync chips (R2.3)

    private func syncSection(_ item: VibenetAccountItem) -> some View {
        Group {
            if let cs = item.changeSequences {
                // Kept as a horizontal scroll even at full sheet width —
                // large Dynamic Type can still outgrow two chips.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(cs.chips.enumerated()), id: \.offset) { _, chip in
                            HStack(spacing: 3) {
                                Text(chip.value)
                                    .dsText(.label12).fontWeight(.semibold)
                                    .foregroundStyle(DS.textPrimary)
                                Text(chip.label)
                                    .dsText(.label11)
                                    .foregroundStyle(DS.textTertiary)
                            }
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Self.mark.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Doors

    /// A sheet earns visible verbs where a row only had a context menu —
    /// Explorer and Copy are real buttons here, not menu items.
    private func doorsSection(_ item: VibenetAccountItem) -> some View {
        HStack(spacing: DS.Space.s3) {
            Link(destination: URL(string: VibenetExplorer.address(item.address))!) {
                HStack(spacing: 4) {
                    Text(String(localized: "Explorer"))
                    Image(systemName: "arrow.up.right")
                }
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)
                .lineLimit(1)
                .fixedSize()
            }
            Button {
                DSHaptic.tap()
                UIPasteboard.general.string = item.address
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "Copy address"))
                    Image(systemName: "doc.on.doc")
                }
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(.top, DS.Space.s2)
    }
}
