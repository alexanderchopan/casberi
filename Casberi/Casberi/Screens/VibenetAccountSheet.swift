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
                        VStack(alignment: .leading, spacing: DS.Space.s6) {
                            hero(item)
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

    /// Face, name, address — and the state, but ONLY when the state has
    /// something to say. A sheet whose first line reads "2 keys" directly
    /// above a Keys section listing those same two keys spends its
    /// biggest type restating its own next section; the alarm, the
    /// countdown, the expiring key and "not established yet" are the
    /// facts that earn that slot, and when none of them applies the
    /// section below simply begins.
    private func hero(_ item: VibenetAccountItem) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                WalletFace(address: item.address, size: 64, circular: true)
                VStack(alignment: .leading, spacing: 3) {
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
            }
            state(item)
        }
    }

    /// The one line that outranks everything, or nothing at all. Order
    /// matches the card row's, for the reason that ranking exists: a
    /// countdown beats an expiry beats a plain state.
    @ViewBuilder
    private func state(_ item: VibenetAccountItem) -> some View {
        if item.hasInitiatedUnlock, let countdown = item.unlockLabel(now: .now) {
            VStack(alignment: .leading, spacing: 6) {
                Text(countdown)
                    .dsText(.heading17)
                    .foregroundStyle(Self.mark)
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
            }
        } else if item.locked {
            Text(String(localized: "Locked"))
                .dsText(.heading17)
                .foregroundStyle(Self.mark)
        } else if let urgent = item.urgentLine(now: .now) {
            Text(urgent)
                .dsText(.heading17)
                .foregroundStyle(Self.mark)
        } else if !item.reached || !item.established || item.actors.isEmpty {
            // The real states a person needs told: the chain didn't
            // answer, the account isn't established, or it is and holds
            // no key this build can see. An established account WITH
            // keys says nothing here — the Keys section is the answer.
            Text(VibenetRoom.rowLine(item))
                .dsText(.heading17)
                .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Keys (R3.1 — the matrix's replacement)

    private func keysSection(_ item: VibenetAccountItem) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // The count lives in the HEADING, so the hero above never has
            // to spend its biggest line saying "2 keys" — one statement of
            // the number, at the place the keys actually are.
            // "AUTHORIZED", never "can act" — a key can be authorized on
            // the account and still hold no scope, which is exactly what
            // a fresh account looks like (both of a real devnet
            // account's keys read "Can't act on its own yet"). A heading
            // claiming they CAN act directly above two cards saying they
            // can't is a contradiction the reader has to resolve.
            Text(item.actors.count == 1
                 ? String(localized: "1 key authorized")
                 : String(localized: "\(item.actors.count) keys authorized"))
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(actor.kind.plainTitle)
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            if let detail = actor.kind.plainDetail {
                Text(detail)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let labels = actor.scope.grantedPlainLabels
            if labels.isEmpty {
                // A real state, not an empty chip row — an authorized
                // actor that can originate nothing yet.
                Text(String(localized: "Can't act on its own yet"))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s3)
        // A key is an OBJECT — something that can act for this account —
        // so it gets an object's surface rather than sitting in a run of
        // undifferentiated text. Two keys in a row read as two things,
        // which is the fact the whole sheet is about.
        .dsWidgetSurface(cornerRadius: DS.Radius.widget, fillOpacity: 0.5)
    }

    // MARK: - History (R2.1, moved unchanged)

    /// The account's story, and NOTHING MORE THAN IT HAS. The dot strip
    /// draws only for a real sequence (`isSequence` — more than one block):
    /// two keys authorized in the SAME transaction are one moment, and two
    /// dots side by side would invite the reader to see an order that
    /// never happened. When it isn't a sequence, the sentence and its one
    /// date are the whole truth, so that is all that draws.
    private func historySection(_ item: VibenetAccountItem) -> some View {
        Group {
            if let line = VibenetKeyHistory.summaryLine(item.history) {
                let labels = VibenetKeyHistory.endpointLabels(item.history, now: .now)
                let sequence = VibenetKeyHistory.isSequence(item.history)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(line)
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        // One moment, one date, said right beside it —
                        // no axis, no dots, nothing to decode.
                        if !sequence, let when = labels.oldest {
                            Spacer(minLength: DS.Space.s2)
                            Text(when)
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                                .lineLimit(1).fixedSize()
                        }
                    }
                    if sequence {
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
                        .padding(.top, 2)
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

    /// One sentence, or nothing — see `plainLine`. The chips this
    /// replaced were honest and unreadable ("0 cross-chain changes",
    /// "1 local, epoch 0"): the EIP's own vocabulary, one of them almost
    /// always a zero that means "this never happened".
    private func syncSection(_ item: VibenetAccountItem) -> some View {
        Group {
            if let line = item.changeSequences?.plainLine {
                Text(line)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
