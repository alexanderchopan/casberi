import SwiftUI

/// THE VIBENET ROOM'S HEAD — the `AppStoreConnectRoomCard` shape exactly
/// (2026-08-23), and the reasoning is the same one: several watched
/// accounts are NOT mergeable the way a wallet balance is (one being
/// locked says nothing about another's key count), the same way several
/// App Store Connect apps aren't (one being rejected says nothing about
/// another's build). ASC's answer, reused whole: ONE surfaced card, a
/// LEAD promoted to the headline (`VibenetRoom.lead`, the most urgent
/// account — `ordered` already ranks locked-first), everyone else as a
/// compact row beneath it, a quiet provenance note at the bottom.
///
/// **This is what makes "All" and "one account scoped" the same code
/// path, not two.** When the rail (`VibenetScopeRail`) narrows
/// `room.items` to a single address, `drawn.count` becomes 1, so the
/// "rows beyond the lead" block has nothing left to draw — the card
/// collapses to just that account's own headline, automatically. Wallet's
/// own crown does the same thing (a merged reading when unscoped, that
/// one wallet's own reading when scoped) for the same "click all you see
/// all, click one you see one" reason.
///
/// Superseded, in order: the R3.2 anatomy (a headline sentence + hero face
/// stack + flat row list, all rolled up into one paragraph — the shape
/// that read as a contradiction the moment the hero drew every face while
/// the sentence counted only the locked ones), and R4.6's own first draft
/// (N independently-`.dsWidgetSurface()`-boxed cards, one per account,
/// always all present regardless of scope — which fought the room's own
/// floating settings gear for want of a shared surface for it to sit on,
/// and touched the screen edge because nothing gave it the cards' own
/// margin). Both are gone; this is the third and, per the ASC precedent
/// this was measured against, the last shape this card should need.
///
/// A row's tap OPENS `VibenetAccountSheet` (R3.2) — the card stays a
/// summary; the matrix, the history strip, the sync line and the
/// Explorer door all live on the real surface that has room for them.
///
/// Stores no `Thing` — only value types out of `VibenetRoom`. Corollary 5
/// has nothing to guard here.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount.
///
/// A ROOM-WIDE KEY SUMMARY, added 2026-08-24: no way to see how many keys
/// you're responsible for in TOTAL across the whole room
/// (`VibenetKeyAggregation.compose`) — only per account. Draws ONLY in the
/// roster shape (`room.items.count > 1`), beneath the accounts, with the
/// same "silent when empty" rule as everything else on this card: a room
/// with no keys at all says nothing rather than drawing an empty section
/// (§83). A DELEGATE-MAPPING section briefly lived here too, the same day —
/// see the paragraph below for why it moved off this card entirely.
///
/// **THE ROSTER'S TAP BEHAVIOR WAS WRONG, AND IT WAS WRONG BECAUSE IT
/// MISREAD WHAT WALLET ACTUALLY DOES (fixed 2026-08-24).** Every roster row
/// opened `VibenetAccountSheet` on a tap, modeled on the false premise that
/// Wallet's own unscoped "All" room has an equivalent per-wallet detail
/// view reachable from a tap. It doesn't: Wallet's unscoped room has ZERO
/// tap-to-open-detail rows anywhere. Per-wallet identity shows up in
/// exactly two places, both of which only SCOPE the room in place —
/// `WalletScopeRail` pinned above it, and `WalletFaceChips`
/// (`Screens/WalletFeedTiles.swift`) inside the balance card itself, a
/// horizontal strip of face+reading capsules whose tap sets `selectedWallet`
/// and nothing else. The ONE place a real per-wallet detail view exists is
/// `AddressCard`, reached only from the separate Address Book screen
/// (`WalletScreen.swift`) — a screen dedicated to MANAGING watched wallets,
/// never the feed room.
///
/// So the roster here forks on `onOpen`. Non-nil (`VibenetScreen`'s own
/// roster — the correct analog of Wallet's Address Book) keeps today's full
/// navigable rows unchanged. Nil (the feed room) does NOT navigate.
///
/// **THE FIRST CUT OF THE FEED-ROOM SIDE COPIED `WalletFaceChips` TOO
/// LITERALLY, AND WAS CORRECTED THE SAME DAY.** A face-per-account chip
/// strip is genuinely right for Wallet — but `VibenetScopeRail` is PINNED
/// directly above this very card, already showing every watched account's
/// face, and a second face inside the card read as the same avatar twice.
/// User: *"that is kinda weird to see the avatars because they will
/// literally be in the row above… i think what we want to say on the all
/// page is perhaps N accounts and balance, then the keys, then the
/// events."* So the feed room draws NO face at all: a plain stat block
/// (`balanceAggregateSection` — account/lock count, a native-balance total,
/// per-symbol token totals) stands in for the chip strip, and the mapping
/// section that briefly lived on this card moved OFF it entirely, onto
/// `VibenetAccountDetail`'s own hub diagram — the user settled on "N
/// accounts and balance, then keys, then events" as the COMPLETE list for
/// this room, having floated a room-wide relationship list and talked
/// themselves back out of it ("those show on the individual account
/// page"). Scoping still does the "same cards, just narrowed" job Wallet's
/// own scoped room does (see the doc a few lines up: room.items.count == 1
/// collapses this very card to `VibenetAccountDetail` automatically,
/// mapping and all) — a chip's tap only ever calls `onScope`.
struct VibenetRoomCard: View {
    let room: VibenetRoom
    var onRemove: (String) -> Void
    /// Raised by the context menu's "Name this account…" — the alert itself
    /// lives on the SCREEN (a text-entry alert needs `@State` a card
    /// re-composed from a value type shouldn't own), so this just reports
    /// which address was asked for.
    var onRename: (String) -> Void = { _ in }
    /// nil in the FEED room — a roster row must never navigate there (see
    /// this type's own header doc), so the whole roster draws as a plain
    /// stat block instead (`balanceAggregateSection`, no faces, no
    /// per-account rows). Non-nil in `VibenetScreen`'s OWN roster, the
    /// correct analog of Wallet's Address Book, where a tap opens
    /// `VibenetAccountSheet` exactly as before — the sheet's item is the
    /// address itself (the `L2beatScreen`/`WalletbeatScreen` shape:
    /// `String` is `Identifiable`, so no wrapper type is needed).
    var onOpen: ((String) -> Void)? = nil
    /// The feed room's own scope door — used today only by the Keys
    /// section's soonest-expiry callout (`keysAggregateSection`, since the
    /// stat block itself has nothing left to tap: no rows, no chips, no
    /// face). Scopes the card to one account, never opens anything. The
    /// caller owns the toggle rule (tap the already-scoped account again
    /// to return to "All", `VibenetScopeRail`'s own tap rule).
    var onScope: (String) -> Void = { _ in }

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")
    /// The most rows drawn before the footnote takes over, INCLUDING the
    /// lead — the `StripeRoom`/`ASCRoom` cap shape, so a long watch list
    /// doesn't turn this into an unbounded list on a card meant to be a
    /// summary.
    private static let rowCap = 8

    private var drawn: [VibenetAccountItem] { Array(room.items.prefix(Self.rowCap)) }

    /// R4.7 (2026-08-23), reported: *"the details about the account (eg
    /// the keys) should be on a card. everything a user needs to see
    /// about this account should be present on this screen, not on some
    /// other screen… think like how we do wallet today — we have many
    /// cards and then transaction history."*
    ///
    /// So: the moment the room narrows to EXACTLY ONE account — either
    /// because the rail scoped it there, or because that's simply the
    /// only account watched — the card draws its FULL detail
    /// (`VibenetAccountDetail`: face, name, state, the real key roster,
    /// history, sync, the Explorer/Copy doors) instead of a one-line
    /// teaser you would otherwise have had to tap through to a second
    /// screen to read. That teaser survives only for the roster case
    /// (several accounts on screen at once, where one line each is the
    /// most any of them can have) — the shape "All" already had, just
    /// with the lead promoted instead of stacked into a single sentence.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lead = room.lead, room.items.count == 1 {
                // `room` reaching this branch may be SCOPED to just this
                // one account (the face rail narrowed it) or genuinely be
                // the only account watched — either way, a delegate
                // relationship can name an account that's currently OUT
                // of scope, so links are derived from the FULL watch list
                // rather than this card's own (possibly narrowed) `room`.
                // The same deliberate bypass `VibenetAccountSheet` already
                // makes, for the identical reason — see that file's own
                // doc. Falling back to `room.items` when the full read
                // isn't cached yet can only UNDER-report a link, never
                // invent one that isn't real.
                let fullItems = VibenetRoomSource.card()?.items ?? room.items
                VibenetAccountDetail(item: lead, links: VibenetAccountMapping.links(fullItems))
            } else if let lead = room.lead {
                if let onOpen {
                    // `VibenetScreen`'s OWN roster (see this type's header
                    // doc) — unchanged: every account is a full navigable
                    // row, promoted lead included.
                    row(lead, isLead: true, onOpen: onOpen)
                    // Only the accounts BEYOND the lead get a row — the lead
                    // IS the headline, and repeating it directly underneath
                    // would be the card arguing with itself (ASC's own
                    // ruling, reused).
                    if drawn.count > 1 {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(drawn.dropFirst())) { item in
                                row(item, onOpen: onOpen)
                            }
                        }
                        .padding(.top, DS.Space.s3)
                    }
                } else {
                    // The feed room (2026-08-24, corrected twice the same
                    // day — see this type's own header doc): "N accounts
                    // and balance", no face anywhere in this branch.
                    balanceAggregateSection
                }
                keysAggregateSection
            } else {
                Text(VibenetRoom.headline(room, now: .now))
                    .dsText(.heading17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The bottom-of-card provenance note (2026-08-23, moved off
            // the top of the room's scrollable content — it used to sit
            // directly under the room's own floating settings gear with
            // no surface behind it, reported as "look at it touching the
            // walls"). Gated on having a lead: an empty room's headline
            // already says "Nothing watched on vibenet yet", and a
            // provenance line under that says nothing new.
            if room.lead != nil, let note = VibenetRoom.note(room, drawn: drawn.count) {
                Text(note)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s4)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        // The one-account detail carries its own doors and history — its
        // remaining verbs (rename, stop watching) live on a long-press,
        // matching the roster row's own contextMenu below rather than
        // adding a second visible control competing with `RoomGear` for
        // the same corner.
        .modifier(VibenetDetailContextMenu(
            address: room.items.count == 1 ? room.lead?.address : nil,
            onRename: onRename, onRemove: onRemove))
    }

    // MARK: - Balance stat block (the feed room's own roster, 2026-08-24)

    /// "N accounts and balance" — the user's own words. No face anywhere
    /// (see this type's header doc for why: `VibenetScopeRail` pinned
    /// above already shows every one), and silent piece by piece: no
    /// native reading anywhere draws no native line, no token balance
    /// anywhere draws no chips, a `lockedCount` of zero is a real state
    /// and simply never printed (`VibenetBalanceAggregate.plainLine`'s own
    /// rule) — never an invented "0 locked"/"0 ETH" (§83).
    @ViewBuilder
    private var balanceAggregateSection: some View {
        if let aggregate = VibenetBalanceAggregation.compose(room.items) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(aggregate.plainLine)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // The card's own big-number rung (`stat24` — the MONEY
                // tier, Typography's own naming) — one native total, in
                // native units, never priced. ONE caller of this size on
                // this card, the same "one rung, one job" discipline
                // `heading28` documents for itself.
                if let nativeTotal = aggregate.nativeTotal {
                    Text("\(VibenetBalanceFormat.line(nativeTotal)) ETH")
                        .dsText(.stat24)
                        .foregroundStyle(DS.textPrimary)
                    // The disambiguating caption — reported live, one
                    // account's own big balance and this room's SUMMED
                    // one look identical in size, so a person can read
                    // one account's number as if it were the whole
                    // room's (the same "looks like a parent" confusion
                    // the roster's promoted-lead face already caused
                    // once). Wallet's own crown resolves the identical
                    // ambiguity with a caption, not a size difference —
                    // "Across your wallets" when unscoped, the wallet's
                    // own name when scoped. This is that caption's exact
                    // wording, one venue over.
                    Text(String(localized: "Across your accounts"))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                }
                if !aggregate.tokenTotals.isEmpty {
                    // The Keys section's own capsule grammar, reused
                    // rather than a third pill style invented for one
                    // more room (the same rule `keysAggregateSection`
                    // already states for itself).
                    FlowLayout(spacing: 6) {
                        ForEach(aggregate.tokenTotals, id: \.symbol) { total in
                            Text("\(VibenetBalanceFormat.line(total.amount)) \(total.symbol)")
                                .dsText(.label11)
                                .foregroundStyle(DS.textSecondary)
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

    // MARK: - Keys (the room-wide aggregate)

    /// The count nowhere else on this card states: not "this account has
    /// 2 keys" (each row already says that) but the total across every
    /// watched account, broken down by kind, plus whichever key across
    /// the whole room is closest to lapsing. Silent when
    /// `VibenetKeyAggregation.compose` has nothing to aggregate (§83).
    @ViewBuilder
    private var keysAggregateSection: some View {
        if let aggregate = VibenetKeyAggregation.compose(room.items, now: .now) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(aggregate.plainLine)
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // R3.1's exact capsule grammar, reused rather than
                // reinvented — a THIRD pill style on one card would be
                // the roster row's own alarm badge and the key row's own
                // permission chips joined by a stranger.
                FlowLayout(spacing: 6) {
                    ForEach(aggregate.byKind, id: \.kind) { entry in
                        Text("\(entry.count) \(entry.kind.shortLabel)")
                            .dsText(.label11)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Self.mark.opacity(0.12), in: Capsule())
                    }
                }
                // Tappable — a callout naming the account closest to a
                // key lapsing is only useful if it DOES something, not a
                // dead-end fact (§83's "no dead controls"). Opens when
                // `onOpen` is real (the setup screen's own roster); scopes
                // when it's nil (the feed room, where a roster tap only
                // ever narrows — see this type's header doc) — either way
                // the same account's own expiring key is one tap away.
                if let soonest = aggregate.soonestExpiry {
                    Button {
                        DSHaptic.selection()
                        if let onOpen { onOpen(soonest.address) } else { onScope(soonest.address) }
                    } label: {
                        Text(soonest.line(now: .now))
                            .dsText(.label12)
                            .foregroundStyle(Self.mark)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, DS.Space.s3)
        }
    }

    /// Applies a context menu only when the card is showing ONE account's
    /// full detail — the roster rows already carry their own menu each,
    /// and a menu on the whole card in THAT shape would be ambiguous
    /// about which account it names.
    private struct VibenetDetailContextMenu: ViewModifier {
        let address: String?
        let onRename: (String) -> Void
        let onRemove: (String) -> Void
        func body(content: Content) -> some View {
            if let address {
                content.contextMenu {
                    Button {
                        onRename(address)
                    } label: {
                        Label(String(localized: "Name this account…"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onRemove(address)
                    } label: {
                        Label(String(localized: "Stop watching"), systemImage: "trash")
                    }
                }
            } else {
                content
            }
        }
    }

    // MARK: - Rows

    /// One watched account. The LEAD (`isLead: true`) is this exact same
    /// row, just promoted — a bigger face, bigger name, no vertical
    /// padding of its own (the card's outer `DS.Space.s4` already frames
    /// it) — never a separately-composed sentence, so the two can't drift
    /// apart on what one account's state is called. The subtitle keeps
    /// R2.2's precedence (unlock countdown + runway, else the urgency
    /// line, else the plain key count) because that ranking is the whole
    /// point of surfacing it here — before anyone opens anything.
    private func row(_ item: VibenetAccountItem, isLead: Bool = false,
                      onOpen: @escaping (String) -> Void) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(item.address)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                WalletFace(address: item.address, size: isLead ? 40 : 28, circular: true)
                VStack(alignment: .leading, spacing: 3) {
                    // A nickname takes the title slot (not monospaced —
                    // it's a name, not hex) and the short address drops
                    // to a small line beneath. Unnamed rows are
                    // unchanged: the address alone, exactly as before.
                    if let name = VibenetWatch.shared.name(for: item.address) {
                        Text(name)
                            .dsText(isLead ? .heading22 : .heading17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(VibenetRoom.shortAddress(item.address))
                            .dsText(.label11).monospaced()
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    } else {
                        Text(VibenetRoom.shortAddress(item.address))
                            .dsText(isLead ? .heading22 : .heading17)
                            .foregroundStyle(DS.textPrimary)
                            .monospaced()
                            .lineLimit(1)
                    }
                    // An account mid-unlock leads with its OWN countdown
                    // rather than its key count — "1 key" sits right
                    // beside a badge already saying "Unlocking"; the
                    // number worth a glance here is WHEN.
                    if item.hasInitiatedUnlock, let countdown = item.unlockLabel(now: .now) {
                        Text(countdown)
                            .dsText(.label12)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        // Only when BOTH endpoints are known — a bar with
                        // a guessed start is the fake status §83 forbids,
                        // so this is silent rather than wrong on a build
                        // where the delay never read. No animation on
                        // the fill: a static capsule needs no Reduce
                        // Motion check.
                        if let progress = item.unlockProgress(now: .now) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Self.mark.opacity(0.15))
                                    Capsule().fill(Self.mark)
                                        .frame(width: geo.size.width * progress)
                                }
                            }
                            .frame(height: 4)
                            .frame(maxWidth: 160)
                        }
                    } else if let urgent = item.urgentLine(now: .now) {
                        // R2.2: a key's own clock outranks the plain key
                        // count on the row that's about to be affected
                        // by it. The room's one color carries urgency
                        // here (never bold-white-on-blue — that grammar
                        // stays the lock pill's alone).
                        Text(urgent)
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(Self.mark)
                            .lineLimit(1)
                    } else {
                        Text(VibenetRoom.rowLine(item))
                            .dsText(.label12)
                            .foregroundStyle(item.alarmed ? DS.textPrimary : DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                HStack(spacing: DS.Space.s2) {
                    // The pill states the ALARM; the chevron states
                    // there's more to see.
                    if item.alarmed {
                        Text(item.hasInitiatedUnlock ? String(localized: "Unlocking") : String(localized: "Locked"))
                            .dsText(.label11).fontWeight(.bold)
                            .foregroundStyle(Color.fixed("#ffffff"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Self.mark, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    Image(systemName: "chevron.right")
                        .dsGlyph(12)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, isLead ? 0 : DS.Space.s2)
        .contextMenu {
            Button {
                onRename(item.address)
            } label: {
                Label(String(localized: "Name this account…"), systemImage: "pencil")
            }
            Button {
                DSHaptic.tap()
                UIPasteboard.general.string = item.address
            } label: {
                Label(String(localized: "Copy address"), systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                onRemove(item.address)
            } label: {
                Label(String(localized: "Stop watching"), systemImage: "trash")
            }
        }
    }
}

/// One landed vibenet event, led by WHO it happened to (R4.2).
///
/// Reported 2026-08-23: *"i can't see which accounts they are from."* The
/// room fell to `.plain`, so every row wore one identical brand glyph and
/// the only identifying mark was a truncated `…f21f` at the END of an
/// 80-char title, in the same weight as the rest of the sentence — two
/// accounts' events were indistinguishable at a glance, in a room whose
/// entire subject is which account something happened to. Every other
/// identity room in this app leads with a face; this one now does too.
///
/// Reads `authorHandle` (the account) and `summary` (the event without
/// the address) — both stamped at landing, so nothing here parses a
/// display title back into data. A row that predates those falls back to
/// its whole title, which still says everything, just less prettily.
struct VibenetEventRow: View {
    let thing: Thing

    var body: some View {
        if thing.isLive {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                if let address = thing.authorHandle {
                    WalletFace(address: address, size: 34, circular: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(thing.summary ?? thing.title)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: DS.Space.s2)
                Text(thing.capturedAt.formatted(.relative(presentation: .named)))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1).fixedSize()
            }
            .padding(.vertical, DS.Space.s2)
        }
    }

    /// The account's nickname when it has one, else its short address —
    /// the same identity the room card and the sheet show, so one account
    /// never reads as two different things across three surfaces.
    private var title: String {
        guard let address = thing.authorHandle else { return thing.title }
        return VibenetWatch.shared.name(for: address) ?? VibenetRoom.shortAddress(address)
    }
}
