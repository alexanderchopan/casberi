import SwiftUI

/// One account's full detail — face, name, state, its key roster, its
/// history, its sync standing, its doors (Explorer/Copy) — as ONE reusable
/// view. Shared by `VibenetAccountSheet` (still reached from a tap on "All",
/// where several accounts are on screen and only one summary line each
/// fits) and `VibenetRoomCard` (drawn INLINE the moment the room narrows to
/// exactly one account — 2026-08-23, reported: *"everything a user needs to
/// see about this account should be present on this screen, not on some
/// other screen… think like how we do wallet today — we have many cards and
/// then transaction history."* Scoping to the one account you asked about
/// and still handing back a one-line teaser you have to tap through again
/// was the bug; this is the fix — ONE definition, so the room and the sheet
/// can never drift apart on what one account's detail actually says.
struct VibenetAccountDetail: View {
    let item: VibenetAccountItem
    /// This account's OUTGOING and INCOMING delegate relationships — both
    /// directions, unfiltered, computed by the caller off the FULL room
    /// (`VibenetAccountMapping.links(room.items)`), since this view has
    /// only ever seen `item`, one account, and deriving a room-wide
    /// mapping needs every other watched account too. Defaults to empty
    /// so every existing call site keeps compiling unchanged; the two
    /// real call sites (`VibenetRoomCard`'s inline single-account branch,
    /// `VibenetAccountSheet`) both HAVE the full room in scope and pass
    /// it through — see `linkedAccountsSection` for why the filtering by
    /// direction happens here rather than at either call site (both
    /// directions read differently and only this view knows which is
    /// which for `item`).
    var links: [VibenetDelegateLink] = []

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            hero
            if !item.actors.isEmpty {
                keysSection
            }
            linkedAccountsSection
            historySection
            syncSection
            doorsSection
        }
    }

    // MARK: - Hero

    /// Face, name, address — and the state, but ONLY when the state has
    /// something to say. A block whose first line reads "2 keys" directly
    /// above a Keys section listing those same two keys spends its
    /// biggest type restating its own next section; the alarm, the
    /// countdown, the expiring key and "not established yet" are the
    /// facts that earn that slot, and when none of them applies the
    /// section below simply begins.
    private var hero: some View {
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
                    // survive if it doesn't fit; the doors below hand over
                    // the exact string regardless.
                    Text(item.address)
                        .dsText(.label11).monospaced()
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: DS.Space.s2)
            }
            state
        }
    }

    /// The one line that outranks everything, or nothing at all — a
    /// countdown beats an expiry beats a plain state.
    @ViewBuilder
    private var state: some View {
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

    // MARK: - Keys (R3.1)

    private var keysSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // The count lives in the HEADING, so the hero above never has
            // to spend its biggest line saying "2 keys" — one statement of
            // the number, at the place the keys actually are.
            // "AUTHORIZED", never "can act" — a key can be authorized on
            // the account and still hold no scope, which is exactly what
            // a fresh account looks like (both of a real devnet account's
            // keys read "Can't act on its own yet"). A heading claiming
            // they CAN act directly above cards saying they can't is a
            // contradiction the reader has to resolve.
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
    /// out with `FlowLayout` so a whole capsule wraps to the next line but
    /// the text INSIDE one never does.
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
                                // The unknown-count tail draws OUTLINED — a
                                // visibly different claim from a named
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
        // undifferentiated text. Several keys in a row read as several
        // things, which is the fact this section is about.
        .dsWidgetSurface(cornerRadius: DS.Radius.widget, fillOpacity: 0.5)
    }

    // MARK: - Linked accounts (2026-08-24)

    /// A small struct rather than a bare tuple so `ForEach`/`spokeRow`
    /// read cleanly — `address` is the linked account, `label` is the
    /// ALREADY direction-correct plain-English clause (see
    /// `linkedAccountsSection`'s own comment for the ground-truth
    /// derivation of which direction gets which words — KEPT verbatim
    /// across two failed presentation attempts, because it was never
    /// the part that was wrong).
    ///
    /// `Identifiable` on `address + label` rather than `address` alone:
    /// a MUTUAL relationship (this account and another each authorized
    /// the other as their own delegate) produces two real rows sharing
    /// one address, and `address` alone would collide in `ForEach`.
    private struct Spoke: Identifiable {
        var id: String { "\(address):\(label)" }
        let address: String
        let label: String
    }

    /// This account's own share of `VibenetAccountMapping.links`, as a
    /// plain row list — the THIRD presentation this section has worn.
    /// Two spatial layouts (a two-chip flow, then a centered hub with
    /// spokes) both read as implying a hierarchy that isn't there; user,
    /// on the hub: *"for the linked accounts on the one account screen
    /// that doesn't work either, perhaps we need a different way."*
    /// Settled: no diagram at all — a row per linked account, the exact
    /// same visual weight as every other section on this screen (the
    /// Keys rows immediately above already do this, so there's nothing
    /// new to invent). Silent when there are none (§83) — most accounts
    /// have no delegate relationship at all, and a section that draws
    /// itself empty on every ordinary account is worse than one that
    /// simply isn't there.
    @ViewBuilder
    private var linkedAccountsSection: some View {
        let outgoing = links.filter { $0.from.caseInsensitiveCompare(item.address) == .orderedSame }
        let incoming = links.filter { $0.to.caseInsensitiveCompare(item.address) == .orderedSame }
        // GROUND TRUTH, re-derived here rather than trusted from memory,
        // because getting a delegate direction backward misstates a real
        // permission: `VibenetAccountMapping.links` builds
        // `VibenetDelegateLink(from: A, to: B)` when A's OWN actor list
        // names B as a `.delegate` — i.e. A authorized B, so B is the one
        // who ACTS, on A's behalf. Concretely: Alice authorizes Bob as her
        // delegate → link(from: Alice, to: Bob) → Bob can act for Alice.
        //
        // OUTGOING here (`link.from == item`) means `item` is Alice: the
        // other account (`link.to`) is Bob, who can act for `item`.
        // Label: "Can act for you". INCOMING (`link.to == item`) means
        // `item` IS the delegate — the other account (`link.from`)
        // authorized `item`, so `item` acts for it. Label: "You can act
        // for".
        let spokes: [Spoke] =
            outgoing.map { Spoke(address: $0.to, label: String(localized: "Can act for you")) } +
            incoming.map { Spoke(address: $0.from, label: String(localized: "You can act for")) }
        if !spokes.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(String(localized: "Linked accounts"))
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(spokes) { spoke in
                        spokeRow(spoke)
                    }
                }
            }
        }
    }

    /// One linked account, one row — `keyRow`'s own object treatment
    /// (padding, `.dsWidgetSurface(cornerRadius: DS.Radius.widget,
    /// fillOpacity: 0.5)`), reused rather than inventing a fourth
    /// surface style on one screen: a linked account is an OBJECT the
    /// same way a key is, and the section right above this one already
    /// makes that argument. Face, its own identity (name if watched has
    /// one, else the short address — the same identity every other
    /// surface in this room shows, so a row never introduces an account
    /// under a different name than its own roster row does), and the
    /// one clause saying which direction the relationship runs.
    private func spokeRow(_ spoke: Spoke) -> some View {
        HStack(spacing: DS.Space.s3) {
            WalletFace(address: spoke.address, size: 30, circular: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(VibenetWatch.shared.name(for: spoke.address) ?? VibenetRoom.shortAddress(spoke.address))
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(spoke.label)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s3)
        .dsWidgetSurface(cornerRadius: DS.Radius.widget, fillOpacity: 0.5)
    }

    // MARK: - History (R2.1)

    /// The account's story, and NOTHING MORE THAN IT HAS. The dot strip
    /// draws only for a real sequence (`isSequence` — more than one
    /// block): two keys authorized in the SAME transaction are one
    /// moment, and two dots side by side would invite the reader to see
    /// an order that never happened. When it isn't a sequence, the
    /// sentence and its one date are the whole truth, so that is all that
    /// draws.
    private var historySection: some View {
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
                        // One moment, one date, said right beside it — no
                        // axis, no dots, nothing to decode.
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

    // MARK: - Sync (R2.3)

    /// One sentence, or nothing — see `plainLine`. The chips this
    /// replaced were honest and unreadable ("0 cross-chain changes", "1
    /// local, epoch 0"): the EIP's own vocabulary, one of them almost
    /// always a zero that means "this never happened".
    private var syncSection: some View {
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

    /// Real buttons, not menu items — the two verbs worth a tap without a
    /// long-press.
    private var doorsSection: some View {
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
