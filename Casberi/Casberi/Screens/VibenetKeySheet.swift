import SwiftUI

/// ONE KEY'S WHOLE STORY, AS A SHEET (2026-08-25, prd §478 — the last
/// inline expander in the room, closed; ANATOMY rebuilt in §480).
///
/// `VibenetAccountDetail.keyRow` used to be its own disclosure: tapping the
/// card rotated a chevron and grew the row in place — terms block, origin,
/// full id — which is exactly the "inline expanding in weird ways" of the
/// §478 report, and it carried a second §478 defect inside it: the terms sat
/// on a `fillFaint` radius-12 box INSIDE the key's own card, a box in a box.
///
/// A key is an object; opening an object is a presentation, not a row
/// growing under the thumb.
///
/// **§480 — IT HAD NO ANATOMY, AND THAT IS WHY IT LOOKED MADE POORLY**
/// (user, with screenshots: *"how can we improve the design of these detail
/// sheets, they look like they were made poorly"*). §478 moved the expanded
/// row's CONTENTS onto a bigger surface and did not give them a shape, so the
/// sheet inherited the row's flat run of lines. Six faults, all of them
/// structural rather than cosmetic:
///
/// 1. **The identity line crammed three identifiers together** — a face, the
///    account's `…4513`, the key's `…ed9b` and the expiry, on one line, with
///    nothing saying which ellipsis was which. Two different objects wearing
///    the same shape, side by side, is the worst thing a detail screen can do.
/// 2. **Everything sat at one rung**, so nothing led: the kind's detail
///    clause, a lone chip, a date row and 66 characters of hex all read as
///    equally important.
/// 3. **Two different fact layouts on one sheet** — "Authorized · date ·
///    block" was a three-column row while the terms used a 74pt label column.
/// 4. **The full id wrapped naked**, unlabeled, in the quietest ink, which
///    reads as debris rather than as the value it is.
/// 5. **Three blue links in a row** is web-footer grammar.
/// 6. **A void below the content**, because the tray was pinned to 540.
///
/// The shape now is the one this app already uses for a subject sheet: WHOSE
/// it is as a real row, WHAT IT MAY DO promoted (it is the question the sheet
/// is opened with), then one facts group under a single label column, then
/// the id as a labeled field, then the verbs. Each block is captioned, so the
/// eye lands somewhere rather than reading a list of sentences.
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
    /// the account row is then a plain read rather than a dead door.
    ///
    /// The PRESENTER dismisses and then scopes, in that order — the room
    /// re-composes behind this sheet, and asking for that while it is still up
    /// lands the change under a covered screen.
    var onScope: ((String) -> Void)? = nil
    /// EDIT THIS KEY'S SCOPE (prd §534) — `AuthorizeActor` called again on
    /// the same actorId, `VibenetSend.authorizeActor`'s own doc has the
    /// upsert citation. nil where this phone cannot sign for the account at
    /// all — `thisPhoneIsAdmin`'s own gate, so the door never opens onto a
    /// sheet that can only fail.
    var onEditScope: ((VibenetActor) -> Void)? = nil

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    private static var knownManagers: VibenetKnownPolicyManagers {
        let c = VibenetConfig.cached()
        return VibenetKnownPolicyManagers(policyManager: c?.policyManager,
                                          sessionPolicy: c?.sessionPolicy)
    }

    var body: some View {
        // SIZED TO ITS CONTENT (§480). A fixed 540 left a third of the sheet
        // empty under a short key and made the whole thing read as unfinished.
        // The height is the blocks that will actually draw — a key with no
        // terms and no origin is a genuinely shorter object than a session key
        // with both.
        DSTray(title: actor.kind.plainTitle, height: trayHeight,
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    subject
                    permissions
                    facts
                    identity
                    doors
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Roughly what the content needs, so the tray is neither padded with void
    /// nor cut off. Deliberately approximate — `.large` is one drag away, and
    /// the failure this replaces was a fixed number too big for every key.
    private var trayHeight: CGFloat {
        var h: CGFloat = 300                       // subject + permissions + id + doors
        h += CGFloat(termRows.count) * 26          // one facts row each
        if origin != nil { h += 52 }               // authorized + block
        return min(660, h)
    }

    // MARK: - 1. Whose key this is

    /// WHOSE IT IS, as a real row rather than three ids on one line (§480).
    ///
    /// The account is a different OBJECT from the key, so it gets a row of its
    /// own with a face and a name — the shape every other account row in this
    /// room already has — and the key's own short id moves down to the
    /// identity block where the full value lives. Nothing on this sheet now
    /// puts two ellipsis strings side by side.
    @ViewBuilder
    private var subject: some View {
        // **THE SHARED SHEET HEAD** (prd §495, user: *"so should account
        // sheets, and permissions sheets"*). Same anatomy as the event sheet
        // and as Wallet's money receipt, which is where it was settled (§363).
        //
        // The disc is the ACCOUNT this key acts for — a key's subject is the
        // account, the way a transaction's is its counterparty — and it is
        // the door, which is why the account row that used to sit under this
        // block is gone: the receipt draws no counterparty row beneath its
        // own disc either.
        DSSheetHead(disc: {
            Button { onScope?(item.address) } label: {
                WalletFace(address: item.address, size: DS.Face.shelf, circular: true)
            }
            .buttonStyle(.plain)
            .disabled(onScope == nil)
            .dsHover()
        },
                    // The state worth stamping on a key is its EXPIRY
                    // standing — a key about to lapse is the one thing about
                    // it somebody may have to act on. Neutral otherwise, by
                    // §490's rule that ink here marks unboundedness and
                    // urgency, never decoration.
                    stamp: actor.expiryStanding(now: .now) == .soon
                        ? String(localized: "Expiring") : nil,
                    stampWeight: .urgent,
                    lead: nil,
                    title: actor.kind.plainTitle,
                    secondary: actor.kind.plainDetail,
                    sentence: nil)
    }

    @ViewBuilder
    private var accountRow: some View {
        let name = VibenetWatch.shared.name(for: item.address)
            ?? VibenetRoom.shortAddress(item.address)
        let body = HStack(spacing: DS.Space.s3) {
            WalletFace(address: item.address, size: DS.Face.rowCircle, circular: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Acts for"))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                Text(name)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            if onScope != nil {
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .dsGlyph(11, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
            }
        }
            // **NO CARD** (user, 2026-08-26: *"Lets do headers no cards"*).
            // This drew on a `fillFaint` slab INSIDE a presented sheet, which
            // is a card on a card — the same shape §478 called out one level
            // down and the same one §495 took out of the event sheet and the
            // account detail. The row is a row.
            .padding(.vertical, DS.Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

        if let onScope {
            Button {
                DSHaptic.selection()
                onScope(item.address)
            } label: { body }
                .buttonStyle(.plain)
                .dsHover()
        } else {
            body
        }
    }

    // MARK: - 2. What it may do

    /// THE ANSWER THE SHEET IS OPENED WITH, promoted and captioned (§480). It
    /// was a lone chip floating under a sentence.
    private var permissions: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            caption(String(localized: "What it can do"))
            chips
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

    // MARK: - 3. The facts, in ONE column

    /// EVERY FACT ON ONE LABEL COLUMN (§480). The expiry was stranded up in
    /// the identity line and the origin used a three-column layout of its own,
    /// so a sheet with four facts had three ways of stating one.
    private var facts: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            caption(String(localized: "Terms"))
            DSSpecTable {
                factRow(String(localized: "Expires"),
                        // The VALUE form, not `expiryLabel` — under a label
                        // already reading "Expires" that one made the row say
                        // "Expires · Expires in 3 days" (prd §495).
                        actor.expiryValue(now: .now),
                        weighted: actor.expiryStanding(now: .now) == .soon,
                        tinted: actor.expiryStanding(now: .now) == .soon)
                ForEach(Array(termRows.enumerated()), id: \.offset) { _, term in
                    factRow(term.label, term.value, weighted: term.weighted, tinted: false)
                }
                if let origin, let began = origin.date {
                    factRow(String(localized: "Authorized"),
                            began.formatted(.dateTime.day().month(.abbreviated).year()),
                            weighted: false, tinted: false)
                    // The BLOCK, not a transaction door — the moment carries
                    // no txHash (`VibenetActorEvent` never needed one), and a
                    // link built from a block number would open the wrong page.
                    factRow(String(localized: "Block"),
                            origin.block.formatted(.number.grouping(.automatic)),
                            weighted: false, tinted: false)
                }
            }
        }
    }

    /// `DSSpecTable`'s row, not a fourth hand-rolled column (2026-08-28) —
    /// this sheet's was 84pt where the thing sheet's was 80 and the fact rows'
    /// 72. `lineLimit: nil` keeps this table's own answer: a term here is a
    /// sentence and wraps freely, where a spec value elsewhere is a field and
    /// stops at two lines.
    ///
    /// Every label already arrives `String(localized:)`, so the `Text` is
    /// verbatim — passing it as a key would look the translated words up in
    /// the catalog a second time.
    private func factRow(_ label: String, _ value: String,
                         weighted: Bool, tinted: Bool) -> some View {
        DSSpecRow(label: Text(verbatim: label),
                  value: Text(verbatim: value),
                  tint: tinted ? Self.mark : DS.textPrimary,
                  weight: weighted ? .semibold : .regular,
                  lineLimit: nil)
    }

    // MARK: - 4. Which key this is

    /// THE ID AS A LABELED FIELD (§480), not 66 characters of unannounced hex
    /// wrapping in the quietest ink. Still selectable, and still the whole
    /// value — §473's ruling, which this only gives a name and a ground.
    private var identity: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            caption(String(localized: "Key id"))
            Text(actor.actorId)
                .dsText(.mono12)
                .foregroundStyle(DS.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                // No card here either (§495). §480 gave the id a "ground" so
                // it would stop being unannounced hex; the CAPTION above is
                // what actually did that work, and the box was the part the
                // no-cards ruling removes.
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 5. The verbs

    /// §470's copy verbs — ONE row of quiet capsules (§480), not three blue
    /// links side by side, which is web-footer grammar and made three
    /// secondary actions look like the sheet's primary content.
    private var doors: some View {
        FlowLayout(spacing: DS.Space.s2) {
            door(String(localized: "Copy key id"), symbol: "doc.on.doc") {
                DSPasteboard.copySensitive(actor.actorId)
            }
            if let signer = VibenetKeyIdentity.signerAddress(actor) {
                door(String(localized: "Copy signer"), symbol: "person.crop.circle") {
                    DSPasteboard.copySensitive(signer)
                }
                // ADD TO ADDRESS BOOK (2026-08-27, the address-book
                // unification) — gated on `signerAddress`, exactly the same
                // guard "Copy signer" uses, and for the same reason: only a
                // secp256k1/delegate key IS an address (`VibenetKeyIdentity`'s
                // own doc — a passkey's actorId is a hash of a public key
                // with no address inside it, so there is nothing here to
                // file). No verb draws for those kinds — not a disabled one
                // (§83) — the copy test simply excludes them.
                door(String(localized: "Add to Address book"),
                     symbol: "person.crop.circle.badge.plus") {
                    let book = AddressBook.shared
                    let accountName = VibenetWatch.shared.name(for: item.address)
                        ?? VibenetRoom.shortAddress(item.address)
                    let isNew = book.entry(for: signer) == nil
                    book.setName(book.name(for: signer) ?? VibenetRoom.shortAddress(signer),
                                for: signer,
                                provenance: String(localized: "Vibenet key · \(accountName)"),
                                // Never DOWNGRADE an existing entry's kind —
                                // only a brand-new row is filed as `.key`.
                                kind: isNew ? .key : nil,
                                networks: [AddressBook.Network.vibenet])
                }
            }
            door(String(localized: "Copy account"), symbol: "wallet.pass") {
                DSPasteboard.copySensitive(item.address)
            }
            // EDIT PERMISSIONS (prd §534) — gated on `thisPhoneIsAdmin`, not
            // always drawn: `AuthorizeActor` is admin-only
            // (`Keystore.applySignedAccountChanges` requires the SIGNER'S
            // scope to be 0), so a door here on an account this phone
            // cannot administer would open a sheet that could only fail.
            if let onEditScope, thisPhoneIsAdmin {
                door(String(localized: "Edit permissions"), symbol: "slider.horizontal.3") {
                    onEditScope(actor)
                }
            }
        }
    }

    /// Whether THIS PHONE'S own key is an unrestricted admin on `item` — the
    /// client-side half of the gate `Keystore.applySignedAccountChanges`
    /// enforces on-chain (scope must be exactly 0). Checked against the
    /// account's own actor list rather than assumed: a phone that watches
    /// many accounts is admin on some and a bystander on others.
    private var thisPhoneIsAdmin: Bool {
        guard let ours = VibenetDeviceKey.actorID()?.lowercased() else { return false }
        return item.actors.contains {
            $0.actorId.lowercased() == ours && $0.scope.isAdmin
        }
    }

    private func door(_ title: String, symbol: String, act: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.tap()
            act()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
                    .dsGlyph(11, weight: .semibold)
                Text(title)
            }
            .dsText(.label12).fontWeight(.semibold)
            .foregroundStyle(DS.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(DS.fillFaint))
            .contentShape(Capsule())
        }
        .buttonStyle(PressSpring())
        .dsHover()
    }

    /// One block caption — the thing this sheet had none of, and the reason
    /// every line read as equally important.
    private func caption(_ text: String) -> some View {
        Text(text)
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
    }

    // MARK: - Model

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
            // WHO RAN IT (prd §507). `PolicyExecuted` carries a `caller` in
            // its non-indexed word and nothing decoded it, so this sheet
            // could say a key had run four times and never by whom — on the
            // one screen whose subject is who can spend.
            //
            // Named only when EVERY run agrees: a key run by two different
            // callers has no single answer, and naming the newest would state
            // a fact about who can spend that is true of one occasion. The
            // same unambiguous-join rule `VibenetEventFacts` keeps for
            // permissions, and for the same reason.
            if let caller = VibenetPolicyRuns.callerLine(
                VibenetPolicyRuns.runs(item.policyRuns, forCommitment: actor.policyCommitment),
                account: item.address) {
                out.append(KeyTerm(label: String(localized: "Invoked by"), value: caller))
            }
        }
        if let shared = sharedKeys
            .filter({ $0.actorId.caseInsensitiveCompare(actor.actorId) == .orderedSame })
            .sharedTarget(name: { VibenetWatch.shared.name(for: $0) ?? VibenetRoom.shortAddress($0) })
        {
            out.append(KeyTerm(label: String(localized: "Also on"), value: shared))
        }
        return out
    }

    /// WHEN THIS KEY BEGAN — nil when its beginning cannot be named (outside
    /// `VibenetKeyHistory.cap`, an older build's row, a failed block-time
    /// read): all three mean the same thing to a reader and none is worth a
    /// sentence, so the two rows simply do not draw.
    private var origin: VibenetKeyMoment? {
        VibenetKeyOrigin.authorized(actor, in: item.history)
    }
}
