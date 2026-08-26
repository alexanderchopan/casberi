import SwiftUI

/// ONE KEY'S WHOLE STORY, AS A SHEET (2026-08-25, prd §478 — the last
/// inline expander in the room, closed).
///
/// `VibenetAccountDetail.keyRow` used to be its own disclosure: tapping the
/// card rotated a chevron and grew the row in place — terms block, origin,
/// full id — which is exactly the "inline expanding in weird ways" of the
/// §478 report, and it carried a second §478 defect inside it: the terms sat
/// on a `fillFaint` radius-12 box INSIDE the key's own card, a box in a box.
///
/// A key is an object; opening an object is a presentation, not a row
/// growing under the thumb. Everything the expanded row showed is here, on
/// the sheet's own plane with no inner containers, plus the room the row
/// never had: §470's copy verbs as visible doors rather than a context menu
/// somebody has to know to long-press for.
///
/// VALUE TYPES ONLY — `VibenetActor` and `VibenetAccountItem` are structs
/// handed in by the presenter, never re-read at present time, so nothing
/// here renumbers under an open sheet and no liveness corollary applies.
struct VibenetKeySheet: View {
    let actor: VibenetActor
    /// The account the key acts for — the terms need its `policyUses` (has
    /// this session key ever run) and its `history` (when the key began).
    let item: VibenetAccountItem
    /// Where else this exact authorized address can also act — computed by
    /// the presenter over the FULL watch list, for
    /// `VibenetRoomCard.detailBranch`'s own reason: a shared key can name an
    /// account the rail has scoped out.
    var sharedKeys: [VibenetSharedKey] = []
    /// Follow this key to its account (prd §479) — §470's scope, moved inside
    /// the key. The tray's rows used to scope directly; §478 gave a key its
    /// own sheet, so the follow-up lives one level in, where the account it
    /// names is on screen beside it. nil where there is nothing to scope, and
    /// the account line is then a plain read rather than a dead door.
    ///
    /// The PRESENTER dismisses and then scopes, in that order — the room
    /// re-composes behind this sheet, and asking for that while it is still up
    /// lands the change under a covered screen.
    var onScope: ((String) -> Void)? = nil

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    private static var knownManagers: VibenetKnownPolicyManagers {
        let c = VibenetConfig.cached()
        return VibenetKnownPolicyManagers(policyManager: c?.policyManager,
                                          sessionPolicy: c?.sessionPolicy)
    }

    var body: some View {
        DSTray(title: actor.kind.plainTitle, height: 540,
               detents: [.height(540), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // WHOSE it is, and which one it is — the collapsed row's
                    // two quiet facts, restated because a sheet must stand
                    // alone: it can be on screen after the list behind it
                    // scrolled or re-scoped.
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        accountDoor
                        Text(VibenetKeyIdentity.short(actor.actorId))
                            .dsText(.label11).monospaced()
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                        Spacer(minLength: DS.Space.s2)
                        let standing = actor.expiryStanding(now: .now)
                        Text(actor.expiryLabel(now: .now))
                            .dsText(.label12)
                            .fontWeight(standing == .soon ? .semibold : .regular)
                            .foregroundStyle(standing == .soon ? Self.mark : DS.textTertiary)
                            .lineLimit(1)
                    }
                    if let detail = actor.kind.plainDetail {
                        Text(detail)
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    // WHAT IT MAY DO — the same chip grammar as everywhere
                    // (user, §478: "they should be chips instead of like a
                    // sentence"): admin inverts, the unknown tail outlines,
                    // named permissions wear the room's mark at 12%.
                    chips
                        .padding(.top, DS.Space.s3)
                    // THE TERMS — label/value rows ON THE SHEET, not on a
                    // faint box: the sheet is the container (§478's own
                    // rule), and the labels' fixed column is what makes them
                    // scannable, not a fill behind them.
                    let terms = termRows
                    if !terms.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(terms.enumerated()), id: \.offset) { _, term in
                                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                                    Text(term.label)
                                        .dsText(.label11)
                                        .foregroundStyle(DS.textTertiary)
                                        .frame(width: 74, alignment: .leading)
                                    Text(term.value)
                                        .dsText(.label11)
                                        .fontWeight(term.weighted ? .semibold : .regular)
                                        .foregroundStyle(DS.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                        .padding(.top, DS.Space.s3)
                    }
                    origin
                    // THE FULL ID (prd §473's ruling, kept): a developer
                    // comparing against a console log needs the whole word on
                    // a screen, not only on the clipboard.
                    Text(actor.actorId)
                        .dsText(.label11).monospaced()
                        .foregroundStyle(DS.textTertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s4)
                    doors
                        .padding(.top, DS.Space.s4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// WHOSE KEY THIS IS, and the way to it. A door only where the presenter
    /// can scope — otherwise a plain name, never a control that does nothing.
    @ViewBuilder
    private var accountDoor: some View {
        let name = VibenetWatch.shared.name(for: item.address)
            ?? VibenetRoom.shortAddress(item.address)
        if let onScope {
            Button {
                DSHaptic.selection()
                onScope(item.address)
            } label: {
                HStack(spacing: 5) {
                    WalletFace(address: item.address, size: DS.Face.badge, circular: true)
                    Text(name)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                        .dsGlyph(10, weight: .semibold)
                        .foregroundStyle(DS.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
        } else {
            HStack(spacing: 5) {
                WalletFace(address: item.address, size: DS.Face.badge, circular: true)
                Text(name)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var chips: some View {
        let labels = actor.scope.grantedPlainLabels
        let isAdmin = actor.scope.isAdmin
        return FlowLayout(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let isUnknownTail = index == labels.count - 1 && actor.scope.unknownCount > 0
                Text(label)
                    .dsText(.label11)
                    .fontWeight(isAdmin ? .semibold : .regular)
                    .foregroundStyle(isAdmin ? DS.page
                                     : (isUnknownTail ? DS.textTertiary : DS.textPrimary))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        if isAdmin {
                            Capsule().fill(DS.textPrimary)
                        } else if isUnknownTail {
                            Capsule().strokeBorder(DS.textTertiary, lineWidth: 1)
                        } else {
                            Capsule().fill(Self.mark.opacity(0.12))
                        }
                    }
            }
        }
    }

    /// One label/value pair in the terms — `VibenetAccountDetail`'s own
    /// composition, moved here whole when the expansion did (§478). Every
    /// value is the model's own string, never a substring cut back out of a
    /// localized sentence (the `MoneyReceipt` guard).
    private struct KeyTerm {
        let label: String
        let value: String
        var weighted = false
    }

    private var termRows: [KeyTerm] {
        var out: [KeyTerm] = []
        if let target = actor.policyTarget(known: Self.knownManagers) {
            out.append(KeyTerm(label: String(localized: "Limited to"), value: target))
            let use = item.policyUses.use(for: actor)
            out.append(KeyTerm(label: String(localized: "Activity"),
                               value: use?.line(now: .now) ?? String(localized: "Never used"),
                               weighted: true))
        }
        if let shared = sharedKeys
            .filter({ $0.actorId.caseInsensitiveCompare(actor.actorId) == .orderedSame })
            .sharedTarget(name: { VibenetWatch.shared.name(for: $0) ?? VibenetRoom.shortAddress($0) })
        {
            out.append(KeyTerm(label: String(localized: "Also on"), value: shared))
        }
        return out
    }

    /// WHEN THIS KEY BEGAN — silent when its beginning cannot be named
    /// (outside `VibenetKeyHistory.cap`, an older build's row, a failed
    /// block-time read): all three mean the same thing to a reader and none
    /// is worth a sentence.
    @ViewBuilder
    private var origin: some View {
        if let origin = VibenetKeyOrigin.authorized(actor, in: item.history), let began = origin.date {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(String(localized: "Authorized"))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .frame(width: 74, alignment: .leading)
                Text(began.formatted(.dateTime.day().month(.abbreviated).year()))
                    .dsText(.label11)
                    .foregroundStyle(DS.textSecondary)
                Spacer(minLength: DS.Space.s2)
                // The BLOCK, not a transaction door — the moment carries no
                // txHash (`VibenetActorEvent` never needed one), and a link
                // built from a block number would open the wrong page.
                Text(String(localized: "block \(origin.block.formatted(.number.grouping(.automatic)))"))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
            }
            .padding(.top, DS.Space.s3)
        }
    }

    /// §470's copy verbs, VISIBLE at last — on the row they were a context
    /// menu because a row already carrying a title, chips and a clock had no
    /// room for three more controls; a sheet does. `copySensitive` for every
    /// item, each being exactly the "an address, a key" class that modifier
    /// exists for.
    private var doors: some View {
        FlowLayout(spacing: DS.Space.s3) {
            door(String(localized: "Copy key id"), symbol: "doc.on.doc") {
                DSPasteboard.copySensitive(actor.actorId)
            }
            if let signer = VibenetKeyIdentity.signerAddress(actor) {
                door(String(localized: "Copy signer address"), symbol: "person.crop.circle") {
                    DSPasteboard.copySensitive(signer)
                }
            }
            door(String(localized: "Copy account address"), symbol: "wallet.pass") {
                DSPasteboard.copySensitive(item.address)
            }
        }
    }

    private func door(_ title: String, symbol: String, act: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.tap()
            act()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            .dsText(.label12).fontWeight(.semibold)
            .foregroundStyle(Self.mark)
            .lineLimit(1)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .dsHover()
    }
}
