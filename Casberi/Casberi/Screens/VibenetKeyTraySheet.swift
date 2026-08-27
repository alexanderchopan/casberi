import SwiftUI

/// THE KEY TRAY — every key the room can see, one row each (user, 2026-08-25:
/// *"on the All page the key card should open to a list of keys and
/// permissions that show which keys are in which category"*, prd §468; the
/// LAYOUT below supersedes that pass's per-permission sections, prd §478).
///
/// **The chevron this makes honest.** `VibenetRoomCard.keysAggregateSection`
/// (deleted 2026-08-25, prd §469 — its content is `keysCard`/`keysBody`, the
/// only surface left that draws the room's key summary) carried a comment
/// since 2026-08-24 saying it withholds the chevron the design draws because
/// "it points at a key tray that does not exist in this build, and a chevron
/// that opens nothing is the dead control §83 bans. The surface is the part
/// that carries the meaning; the affordance can arrive with the screen it
/// would open." This is that screen, and the chevron arrives with it.
///
/// **Why a card of counts needed one.** "Send anywhere 4" is the one shape of
/// fact you cannot act on: it does not say WHICH four, on which account, or
/// when any of them lapses — and this is the room a person opens to find out
/// who can spend their account. The counts stay on the card, because a card is
/// a summary; the members live here.
///
/// **ONE ROW PER KEY, AND THE PERMISSIONS ARE ITS CHIPS (prd §478).** §468
/// shipped this as sections — a heading per permission, a key repeated under
/// each one it holds — and that shape had a cost the reworking of it makes
/// plain: **a card reading "8 keys" opened a list of fourteen rows**, which
/// needed a footnote to explain away, and a single key appeared three times
/// with a different "Also:" line each time, so the question somebody actually
/// arrives with — *what can THIS key do, and when does it lapse?* — was the
/// one you had to assemble by scrolling. Reported as "cards in cards, inline
/// expanding in weird ways… I want the vibenet experience to feel like a tool
/// you can move through quickly to see information like the keys."
///
/// So the roster is the key's own list, alphabetical (§463's ruling: *"the
/// keys could just be listed in alphabetical order then we aren't making some
/// judgement call"*), each row carrying its permissions as chips — which is
/// **the same grammar `VibenetAccountDetail` has drawn since §463**, so a key
/// reads identically on both surfaces instead of being two different objects.
/// The permission census survives as a FILTER STRIP at the top, so "which keys
/// are in which category" is still one tap, and it is the same
/// `VibenetPolicyAggregation.compose` the card above states — check the card
/// against the strip and they agree, which is most of what a tray is for.
///
/// **And the box inside the box is gone with it.** §471 grouped the rows on a
/// `fillFaint` radius-14 fill inside the sheet; the sheet IS the container,
/// and the rows now sit on it directly at the same left edge as the filters
/// above them.
///
/// Value types throughout (`[VibenetAccountItem]`, handed in by
/// `FeedSheetRoute` rather than re-read at present time), so there is no
/// `Thing`, no liveness question, and no renumbering under an open tray.
struct VibenetKeyTraySheet: View {
    let items: [VibenetAccountItem]
    /// Tapping a key SCOPES THE ROOM to the account it belongs to (prd §470).
    ///
    /// The tray answers "which keys can send anywhere" and, before this,
    /// dead-ended on the answer: you found the key, read that it sits on
    /// `…0b1c`, and then had to dismiss the tray, find that face in the rail
    /// and tap it — three gestures to follow up the one you came for.
    ///
    /// The CALLER dismisses and scopes, in that order, because the tray does
    /// not own its own presentation (`FeedSheetRoute` does) and a sheet that
    /// dismissed itself while the room re-composed behind it is the
    /// half-open-then-close class this room has already paid for. nil where
    /// there is nothing to scope, so the rows stay plain rather than
    /// pretending at a door.
    var onPick: ((String) -> Void)? = nil
    /// Keys this device has not seen before (prd §479) — the same set the
    /// account detail marks, so a new key is findable from either surface.
    /// Read and spent by `VibenetRoomCard`, handed in here.
    var newKeyIDs: Set<String> = []

    /// The key whose own sheet is up (prd §479).
    ///
    /// **A tray row used to SCOPE THE ROOM to the key's account** (§470),
    /// which was the right follow-up when a key had nowhere of its own to
    /// open — §478 gave it `VibenetKeySheet`, and the same object then had two
    /// different tap outcomes depending on which surface you found it on. It
    /// opens the key here too; the account is still one tap away, from inside
    /// that sheet.
    ///
    /// A nested `.sheet` is correct here: this tray is itself a presented
    /// sheet and therefore its own presentation host, which is a different
    /// thing from the banned shape (a `.sheet` on a List ROW, resolving to the
    /// screen's own controller).
    private struct PresentedKey: Identifiable {
        let key: VibenetTrayKey
        var id: String { key.id }
    }
    @State private var openedKey: PresentedKey?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which permission the strip is narrowed to, or nil for every key.
    ///
    /// `@State`, so it dies with the sheet: it is a look, not a preference,
    /// and a tray that reopened pre-filtered would be a tray showing fewer
    /// keys than the card that opened it says exist.
    @State private var filter: String?

    private var roster: [VibenetTrayKey] { VibenetKeyTray.roster(items) }
    private var census: [VibenetPolicyCount] { VibenetKeyTray.census(items) }

    /// The rows actually drawn. A filter naming a permission nobody holds
    /// cannot occur — the strip is built from the census, which drops an
    /// empty permission — so this needs no empty-state of its own beyond the
    /// one below, which answers a genuinely keyless room.
    private var drawn: [VibenetTrayKey] {
        guard let filter else { return roster }
        return roster.filter { VibenetKeyTray.holds($0, permission: filter) }
    }

    var body: some View {
        DSTray(title: String(localized: "Keys and permissions"),
               height: 660,
               // Draggable past its natural size: the row count is a function
               // of how many accounts somebody watches, which has no ceiling
               // worth guessing at — the `detents` escape hatch this type
               // documents for exactly this.
               detents: [.height(660), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if roster.isEmpty {
                        // Never an empty tray: the card that opens this is
                        // itself silent with no keys, so this is only
                        // reachable if a read emptied underneath it.
                        Text(String(localized: "No key on a watched account was read."))
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // WHAT THIS IS, said once. Under §468 this sentence had to
                    // explain why the row count exceeded the key count; one
                    // row per key needs no such apology, so it states the
                    // roster's own size and keeps only the §83 admission
                    // about keys this build cannot describe.
                    if let note = VibenetKeyTray.footnote(items) {
                        Text(note)
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !census.isEmpty { filterStrip }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(drawn.enumerated()), id: \.element.id) { index, key in
                            row(key)
                                .chartArrival(index: index, reduceMotion: reduceMotion)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $openedKey) { presented in
            VibenetKeySheet(actor: presented.key.actor,
                            item: item(for: presented.key.address) ?? items[0],
                            sharedKeys: VibenetKeyReuse.sharing(
                                item(for: presented.key.address) ?? items[0], in: items),
                            // THE ACCOUNT IS STILL ONE TAP AWAY (prd §479) —
                            // §470's scope, moved inside the key rather than
                            // deleted: the tray answers "which keys can send
                            // anywhere", and following one of them to its
                            // account is the same follow-up it always was.
                            // The tray dismisses ITSELF first and then asks
                            // the caller to scope, `FeedSheetRoute`'s own
                            // dismiss-then-scope order one level down.
                            onScope: onPick.map { pick in
                                { address in
                                    openedKey = nil
                                    pick(address)
                                }
                            })
        }
    }

    /// The account a key belongs to. Present by construction — the roster is
    /// built from these very items — but written as a lookup rather than a
    /// force-unwrap, because "by construction" is what every crash in this
    /// codebase's own ledger was before it happened.
    private func item(for address: String) -> VibenetAccountItem? {
        items.first { $0.address.caseInsensitiveCompare(address) == .orderedSame }
    }

    /// THE CENSUS, AS CONTROLS. The same counts the card states, in the same
    /// order (`VibenetPolicyAggregation.compose`, forwarded — never a second
    /// derivation, or a card would say 4 and the list it opens show 3).
    ///
    /// A capsule strip rather than headings, because a heading you scroll past
    /// costs a screenful and a chip you tap costs nothing when you don't. "All"
    /// leads and is the rest state, so the tray always opens showing every key
    /// the card counted.
    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                filterChip(label: String(localized: "All"), count: nil, value: nil)
                ForEach(Array(census.enumerated()), id: \.offset) { _, entry in
                    filterChip(label: entry.label, count: entry.count, value: entry.label)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(label: String, count: Int?, value: String?) -> some View {
        let on = filter == value
        return Button {
            DSHaptic.selection()
            withAnimation(reduceMotion ? nil : DS.Motion.standard) { filter = value }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .dsText(.label12).fontWeight(.semibold)
                if let count {
                    Text("\(count)")
                        .dsText(.label12)
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            // The SELECTED chip is a neutral fill, never the room's mark:
            // blue in this room means urgency (a key about to lapse) and a
            // filter is not urgent. `fillStrong`/`fillFaint` is the source
            // strip's own selected grammar.
            .foregroundStyle(on ? DS.textPrimary : DS.textSecondary)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(on ? DS.fillStrong : DS.fillFaint))
            .contentShape(Capsule())
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// One key. The ACCOUNT leads with its face because this list is
    /// room-wide: a key title alone ("Passkey") is the same words on four
    /// different accounts, and which account a key can act for is the fact
    /// that makes the row worth reading.
    @ViewBuilder
    private func row(_ key: VibenetTrayKey) -> some View {
        Button {
            DSHaptic.selection()
            openedKey = PresentedKey(key: key)
        } label: {
            rowBody(key, door: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .contextMenu { copyItems(key) }
    }

    /// The same copy actions the account detail's own key rows carry
    /// (prd §470), so a key hands over its id from wherever you found it —
    /// and one definition, since two would drift into two different sets of
    /// verbs for one object.
    @ViewBuilder
    private func copyItems(_ key: VibenetTrayKey) -> some View {
        Button {
            DSHaptic.tap()
            DSPasteboard.copySensitive(key.actor.actorId)
        } label: {
            Label(String(localized: "Copy key id"), systemImage: "doc.on.doc")
        }
        // Gated for `VibenetKeyIdentity.signerAddress`'s own reason: only an
        // address-shaped actorId has a signer to name.
        if let signer = VibenetKeyIdentity.signerAddress(key.actor) {
            Button {
                DSHaptic.tap()
                DSPasteboard.copySensitive(signer)
            } label: {
                Label(String(localized: "Copy signer address"), systemImage: "person.crop.circle")
            }
        }
        Button {
            DSHaptic.tap()
            DSPasteboard.copySensitive(key.address)
        } label: {
            Label(String(localized: "Copy account address"), systemImage: "wallet.pass")
        }
    }

    private func rowBody(_ key: VibenetTrayKey, door: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            WalletFace(address: key.address, size: DS.Face.rowCircle, circular: true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Space.s2) {
                    // **`shortLabel`, not `plainTitle` (prd §491).** This row
                    // carries the kind, an actor id, a New badge and an expiry
                    // on one line, and `plainTitle`'s longest forms do not fit:
                    // "Custom authenticator" has been clipping to "Custom
                    // authenti…" since the tray shipped, and renaming the
                    // secp256k1 curve off "Wallet key" made it clip too
                    // ("secp25…"), which is worse than the name it replaced —
                    // a curve truncated mid-digit is unreadable.
                    //
                    // `shortLabel` exists for exactly this and loses nothing
                    // here: the tray is titled keys, so "secp256k1" needs no
                    // "key" after it, and "Passkey" is unchanged.
                    Text(key.actor.kind.shortLabel)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    // WHICH KEY (prd §470) — the noun-less monospaced tail the
                    // detail's rows carry. Two keys of one kind on one account
                    // otherwise land as adjacent rows reading identically end
                    // to end.
                    Text(VibenetKeyIdentity.short(key.actor.actorId))
                        .dsText(.label11).monospaced()
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                    // WHICH key is new (prd §479) — the account detail's own
                    // chip, so one key reads the same on both surfaces.
                    if newKeyIDs.contains(key.id) {
                        Text(String(localized: "New"))
                            .dsText(.label11).fontWeight(.semibold)
                            .foregroundStyle(DS.page)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Self.mark))
                            .fixedSize()
                    }
                }
                Text(Self.accountName(key.address))
                    .dsText(.label11)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                // WHAT IT MAY DO — `VibenetAccountDetail.keyRow`'s own chip
                // grammar (§463), so one key is one object across both
                // surfaces: an admin INVERTS (scope 0 is unrestricted and
                // includes reserved bits, so five chips would understate it),
                // an unknown tail is outlined rather than filled (it names a
                // count, not a permission), everything else is a soft fill in
                // the room's mark.
                permissionChips(key)
                    .padding(.top, 4)
            }
            Spacer(minLength: DS.Space.s2)
            // The clock, in the row's own words rather than a shared one:
            // "Never expires" is a real answer here and drawing nothing in its
            // place would leave a reader unable to tell it from unknown.
            let urgent = key.actor.expiryStanding(now: .now) == .soon
            Text(key.actor.expiryLabel(now: .now))
                .dsText(.label11)
                .fontWeight(urgent ? .semibold : .regular)
                .foregroundStyle(urgent ? Self.mark : DS.textTertiary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            if door {
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .dsGlyph(11, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, 2)
            }
        }
        // NO SEPARATOR (user, 2026-08-25: *"do NOT USE HAIRLINES"*). §8's
        // no-line rule has zero exceptions, and a `Rectangle().fill(fillFaint)
        // .frame(height: 1)` is a hairline whatever the comment above it calls
        // it — this file's own said "a FILL at the faintest rung… nothing
        // strokes a line", which is a rationalisation: the rule is that nothing
        // DRAWS one. Rows are separated by air and by the chip block's own
        // rhythm, which is what this design system separates things with.
        .padding(.vertical, DS.Space.s3)
    }

    /// One key's permissions, as chips. `grantedPlainLabels` is never empty
    /// (an admin yields `["Admin"]`, any non-zero scope sets a bit that is
    /// either named or counted), so this needs no empty branch.
    private func permissionChips(_ key: VibenetTrayKey) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(key.actor.scope.grantedPlainLabels, id: \.self) { label in
                chip(label, key: key)
            }
        }
    }

    @ViewBuilder
    private func chip(_ label: String, key: VibenetTrayKey) -> some View {
        let isAdmin = key.actor.scope.isAdmin
        let isUnknown = label.hasPrefix("+")
        Text(label)
            .dsText(.label11)
            .fontWeight(isAdmin ? .semibold : .regular)
            .foregroundStyle(isAdmin ? DS.page : DS.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                if isAdmin {
                    Capsule().fill(DS.textPrimary)
                } else if isUnknown {
                    Capsule().strokeBorder(DS.textTertiary, lineWidth: 1)
                } else {
                    Capsule().fill(Self.mark.opacity(0.12))
                }
            }
    }

    /// The room's own mark, for the one fact in this tray that earns a colour.
    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    /// The account's own name if it has one, else its short address — the
    /// same fallback `VibenetRoomCard.displayName` makes, so this tray can
    /// never name an account differently from the room that opened it.
    private static func accountName(_ address: String) -> String {
        VibenetWatch.shared.name(for: address) ?? VibenetRoom.shortAddress(address)
    }
}
