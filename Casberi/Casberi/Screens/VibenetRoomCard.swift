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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                VibenetAccountDetail(
                    item: lead,
                    links: VibenetAccountMapping.links(fullItems),
                    sharedKeys: VibenetKeyReuse.sharing(lead, in: fullItems))
            } else if let lead = room.lead {
                if let onOpen {
                    // `VibenetScreen`'s OWN roster (see this type's header
                    // doc) — every account is a full navigable row,
                    // promoted lead included, and UNCAPPED (2026-08-24,
                    // found reading the code rather than reported): this
                    // is the dedicated screen for MANAGING every watched
                    // account, the Wallet-Address-Book analog, not the
                    // "keep it short" summary `rowCap`/`drawn` exist for.
                    // Sharing that cap with the feed card meant anything
                    // past the 8th watched address had no row, no context
                    // menu and no way to rename or stop watching it —
                    // reachable only by unwatching blind from the note's
                    // own "N more watched" count, or not at all.
                    let roster = Array(room.items.dropFirst())
                    row(lead, isLead: true, onOpen: onOpen)
                    // Only the accounts BEYOND the lead get a row — the lead
                    // IS the headline, and repeating it directly underneath
                    // would be the card arguing with itself (ASC's own
                    // ruling, reused).
                    if !roster.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            // The roster is what this card draws from data —
                            // one row per watched account beyond the lead —
                            // so it wears the same staged arrival every other
                            // room's ranked rows do, Reduce Motion included.
                            ForEach(Array(roster.enumerated()), id: \.element.id) { index, item in
                                row(item, onOpen: onOpen)
                                    .chartArrival(index: index, reduceMotion: reduceMotion)
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
                linkedAccountsSection
                    .padding(.top, DS.Space.s4)
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
            //
            // `onOpen != nil` (the management screen) draws every account
            // now, so nothing is hidden there — `room.items.count` tells
            // `note` so, rather than the `rowCap`-limited `drawn.count`
            // that's still correct for the feed card's own summary.
            if room.lead != nil, let note = VibenetRoom.note(room, drawn: onOpen != nil ? room.items.count : drawn.count) {
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
    /// The crown, in Wallet's own order (prd §463): caption, then the big
    /// number, then the standing beneath it. It shipped inverted — a
    /// `heading17` account count ABOVE a `stat24` figure whose caption came
    /// after it — so the room led with an inventory line and the reader met
    /// the money as an afterthought. Wallet's crown has answered this exact
    /// question for a year: the caption says WHOSE, the number is the biggest
    /// thing on the card, the standing is quiet underneath.
    ///
    /// NO SPARKLINE AND NO DELTA, deliberately. The design calls for both and
    /// this bridge records no per-account value history — `WalletStore`'s
    /// `ValueSample` has no vibenet counterpart — so a line here would be
    /// drawn from a single reading, which is a flat line, which reads as
    /// "went to zero". Absent until the history exists.
    @ViewBuilder
    private var balanceAggregateSection: some View {
        if let aggregate = VibenetBalanceAggregation.compose(room.items) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Across your accounts"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                if let nativeTotal = aggregate.nativeTotal {
                    // `price40`, the crown rung — this is the room's one
                    // biggest thing, and `stat24` left it the same size as
                    // an ordinary card statistic.
                    Text("\(VibenetBalanceFormat.line(nativeTotal)) ETH")
                        .dsText(.price40)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 2)
                }
                Text(aggregate.plainLine)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if !aggregate.tokenTotals.isEmpty {
                    tokenTreemap(aggregate)
                        .padding(.top, DS.Space.s3)
                }
            }
        }
    }

    /// What the accounts hold, as areas rather than a capsule row — the
    /// design's treemap, and the app's own `DS.ink(magnitude:)` ramp, so this
    /// reads as the same family of object as every other treemap here. NO
    /// HUE: magnitude is the only thing area or tone may carry (the TokenHue
    /// deletion ruling), and these are three different assets with no shared
    /// unit to rank across, so the native holding simply leads at the size
    /// its own share earns.
    ///
    /// Native ETH is the lead cell and the tokens stack beside it. They are
    /// NEVER summed — no price feed here, so the areas state each asset's
    /// own share of its own total rather than implying one converted figure.
    @ViewBuilder
    private func tokenTreemap(_ aggregate: VibenetBalanceAggregate) -> some View {
        let cells = VibenetBalanceTreemap.cells(aggregate)
        if !cells.isEmpty {
            HStack(spacing: DS.Space.s2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cell.symbol)
                            .dsText(index == 0 ? .body17 : .callout15)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(cell.amount)
                            .dsText(.subhead13)
                            .foregroundStyle(index == 0 ? DS.textPrimary : DS.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(DS.Space.s2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: index == 0 ? 92 : 92)
                    .background(DS.ink(magnitude: cell.share),
                                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .layoutPriority(index == 0 ? 2 : 1)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
        }
    }

    /// KEYS, BY WHAT THEY CAN DO (prd §463). This shipped as taxonomy — "4
    /// secp256k1, 1 P-256, 1 Passkey" — which answers what KIND of key each
    /// one is and says nothing about who can spend. The room is opened with
    /// the other question, so the count leads and the permissions are the
    /// rows: Admin first, then the contract's own bits in its own order.
    ///
    /// The kind capsules are GONE rather than kept alongside. Two lists of
    /// counts over the same ten keys, differing only in what they group by,
    /// is a card arguing with itself — and the kinds are still one tap away
    /// on every key row in the detail.
    @ViewBuilder
    private var keysAggregateSection: some View {
        if let aggregate = VibenetKeyAggregation.compose(room.items, now: .now) {
            VStack(alignment: .leading, spacing: 0) {
                Text(aggregate.plainLine)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                let policies = VibenetPolicyAggregation.compose(room.items)
                if !policies.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(policies.enumerated()), id: \.offset) { index, entry in
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                                Text(entry.label)
                                    .dsText(.body17)
                                    .foregroundStyle(DS.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: DS.Space.s2)
                                Text("\(entry.count)")
                                    .dsText(.subhead13)
                                    .foregroundStyle(DS.textSecondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 5)
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                        }
                    }
                    .padding(.top, DS.Space.s2)
                }
                // The one clock, and only the soonest — the card ends on a
                // single blue sentence rather than a stack of competing
                // attention lines.
                if let soonest = aggregate.soonestExpiry {
                    Text(soonest.line(now: .now))
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(Self.mark)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s2)
                }
            }
        }
    }

    /// WHO CAN ACT FOR WHOM — the room's delegate links, as the app's own
    /// connections shape: one face-led row per link, direction stated in
    /// words. Same-weight throughout (§295's ruling, reused): this card makes
    /// no claim that one relationship matters more than another, so nothing
    /// here is sized or coloured to suggest it.
    ///
    /// Silent when there are none. Note these are WATCHED-to-WATCHED only,
    /// which is `VibenetAccountMapping.links`' own deliberate bound.
    /// A watched account's own name, or its short address — the same
    /// fallback every row on this card already makes, so the spine can never
    /// name an account differently from the roster above it.
    private static func displayName(_ address: String) -> String {
        VibenetWatch.shared.name(for: address) ?? VibenetRoom.shortAddress(address)
    }

    @ViewBuilder
    private var linkedAccountsSection: some View {
        let links = VibenetAccountMapping.links(room.items)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Linked accounts"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    HStack(spacing: DS.Space.s3) {
                        WalletFace(address: link.to, size: DS.Face.row, circular: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.displayName(link.to))
                                .dsText(.heading17)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Text(String(localized: "Can act for \(Self.displayName(link.from))"))
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, DS.Space.s2)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
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
                // Hoisted out of the call: `face-ramp-audit` reads the first
                // token after `size:`, so a ternary of two legal tiers reads to
                // it as a bare identifier. Naming it keeps both the tier check
                // and the promoted-lead sizing.
                let faceSize = isLead ? DS.Face.list : DS.Face.rowCircle
                WalletFace(address: item.address, size: faceSize, circular: true)
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
                    WalletFace(address: address, size: DS.Face.list, circular: true)
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
