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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.colorScheme) private var scheme
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
    /// This account's own key-reuse facts (`VibenetKeyReuse.sharing`),
    /// computed by the caller off the FULL room for the identical reason
    /// `links` is — a shared key can name an account currently out of the
    /// rail's scope. Defaults to empty so every existing call site keeps
    /// compiling; drawn inline per key in `keyRow`, not as its own
    /// section, since it's a fact about ONE key, not about the account as
    /// a whole.
    var sharedKeys: [VibenetSharedKey] = []
    /// Whether to draw the hero's own identicon (user, 2026-08-25). FALSE
    /// wherever `VibenetScopeRail` is already on screen above this card,
    /// which is the only place the face is a duplicate; TRUE everywhere else,
    /// which is the default because a screen about one address with nothing
    /// identifying it at a glance is the worse failure of the two. See the
    /// hero's own comment for the full reasoning.
    var showsFace: Bool = true
    /// WHICH SCOPE IS ASKING (prd §491), or nil for the whole detail.
    ///
    /// **This view's sections were always the room's scopes; nothing joined
    /// them up.** Its own doc says so — *"exactly `stackedRoom`'s shape, so
    /// narrowing the room to one account is the same screen with fewer
    /// accounts in it"* — but the card branched instead: `stacksIntoCards`
    /// required MORE THAN ONE account, so one account got this whole page and
    /// none of the chassis. Every figure built for the room was therefore
    /// invisible to a single-account user, which is the ordinary case.
    ///
    /// So the branch is gone and this draws the part the scope asked for:
    /// keys under Permissions, links and sub-accounts under Accounts, the
    /// record under Activity. nil keeps the whole page, for any caller that
    /// still wants it.
    var section: VibenetSection? = nil
    /// Scope the room to another account — how a watched sub-account row
    /// opens (prd §493). nil leaves that row a plain read rather than
    /// pretending at a door, which is the rule every other object row on this
    /// screen already follows.
    var onScope: ((String) -> Void)? = nil
    /// OPEN A KEY (2026-08-25, prd §478) — replaces the `openKey` inline
    /// disclosure this view carried since §473. A key's depth (terms, origin,
    /// full id, the copy doors) lives on `VibenetKeySheet` now; a row that
    /// grew in place under the thumb was the room's last inline expander.
    ///
    /// nil where the caller cannot present a sheet, and the row is then a
    /// plain read with NO chevron — a disclosure pointing at a sheet that
    /// cannot exist is the dead control §83 bans.
    var onOpenKey: ((VibenetActor) -> Void)? = nil
    /// Keys this device is seeing for the FIRST time, as
    /// `VibenetKeySeenDiff.keyID`s (prd §479).
    ///
    /// The room's card has said "1 new" since §471 and nothing on any screen
    /// could tell you WHICH — a count you cannot locate is the shape §471
    /// itself objected to on the census. A marked row is the other half of
    /// that pill.
    ///
    /// Handed in rather than read here, because reading the ledger MARKS it
    /// read (`VibenetKeysSeen.advance`), and a view that spent the answer
    /// while drawing it would erase the marker mid-look. The room card reads
    /// and spends it once, in its own `.task`.
    var newKeyIDs: Set<String> = []

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    /// The contracts a policy manager might be, off the cached config — so a
    /// gated key names what it is gated to rather than printing hex.
    private static var knownManagers: VibenetKnownPolicyManagers {
        let c = VibenetConfig.cached()
        return VibenetKnownPolicyManagers(policyManager: c?.policyManager,
                                          sessionPolicy: c?.sessionPolicy)
    }

    var body: some View {
        // **THE SAME ANATOMY AS THE ROOM (2026-08-25, prd §477).** Reported
        // with screenshots: the aggregate is cards with section headers and
        // this screen was one giant slab holding every component. It was never
        // this view's slab — `VibenetRoomCard.oneSurface` wrapped the whole
        // thing — but the fix belongs here, because the sections have to
        // become cards for the surface to be worth removing.
        //
        // Bare hero, bare balance, then a card per reading under Wallet's own
        // `heading22` headers. Exactly `stackedRoom`'s shape, so narrowing the
        // room to one account is the same screen with fewer accounts in it.
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            // The hero and the balance belong to the CHASSIS when a scope is
            // asking — the crown and its figure are already drawn above the
            // account rail, and drawing them again here is the stacked-crown
            // bug §491 fixed, arriving by a second route.
            if section == nil {
                hero
                balanceSection
            }
            if wants(.permissions), !item.actors.isEmpty {
                // No header under a scope: the chip one row up already says
                // Permissions, and a `heading22` repeating it is §447's two
                // stacked display lines.
                if section == nil { sectionHeader(String(localized: "Keys")) }
                keysSection
            }
            // **THE HEADER SURVIVES UNDER A SCOPE HERE, unlike Permissions'
            // (prd §493).** Reported as *"when you open a subaccount it opens
            // to something wrong"* — and the card was right, the framing was
            // not. These rows are about a RELATIONSHIP, so each leads with the
            // OTHER account's face and name; with no header above them a
            // scoped page opens on somebody else's address and reads as having
            // opened the wrong account.
            //
            // The rule §491 applied — drop the header, the chip already says
            // it — holds only where the chip says the SAME word. The chip says
            // "Accounts"; this says "Linked accounts", which is a different
            // claim, so the header is doing work rather than repeating one.
            // ONE HEADER PER GROUP, not one over both (prd §495). It was a
            // single "Linked accounts" covering two sections that answer
            // OPPOSITE questions — who can act for you, and who you can act
            // for — so the second arrived unlabelled under the first one's
            // name. Turning the cards into headed groups made that visible as
            // a doubled heading on the device; the fix is the header moving
            // INTO each group rather than a second one being removed.
            if wants(.accounts) {
                linkedCard
                subAccountsCard
            }
            if wants(.activity) { recordCard }
        }
        .task(id: item.address) {
            history = VibenetValueStore.samples(for: item.address)
        }
    }

    /// Whether the scope asking wants this section — true for every section
    /// when nothing is scoping (the whole-page caller).
    private func wants(_ candidate: VibenetSection) -> Bool {
        section == nil || section == candidate
    }

    /// Does this account take part in any delegate relationship at all — the
    /// gate on the Linked accounts section, so an account nobody delegates to
    /// and which delegates to nobody grows no empty header.
    private var hasLinks: Bool {
        links.contains {
            $0.from.caseInsensitiveCompare(item.address) == .orderedSame
                || $0.to.caseInsensitiveCompare(item.address) == .orderedSame
        }
    }

    /// `walletGroupHeader`'s recipe, matching the room's own `sectionHeader`.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .dsText(.heading22)
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, DS.Space.s2)
            .padding(.bottom, -DS.Space.s3)
    }

    /// The delegate spine — a HEADER and its rows (prd §495).
    ///
    /// **The cards are gone** (user, 2026-08-26: *"on accounts when you click
    /// an item in the list… we can do better, poor design and also has a
    /// card. needs to look like the others"*, and the standing ruling from the
    /// same session, *"Lets do headers no cards"*).
    ///
    /// This screen was three slabs on a page reached FROM a room that draws
    /// none, so narrowing to one account changed the grammar of the app under
    /// you — which is the opposite of §477's own goal of making the scoped
    /// view feel like the same screen. A header names a group; a slab draws a
    /// box around it and then a second box around the next one.
    @ViewBuilder
    private var linkedCard: some View {
        if hasLinks {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                sectionHeader(String(localized: "Linked accounts"))
                linkedAccountsSection
            }
        }
    }

    /// Sub-accounts — the OTHER direction from the spine above (who named
    /// YOU), which is why it is a second group rather than more rows in the
    /// first.
    @ViewBuilder
    private var subAccountsCard: some View {
        if !item.subAccounts.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                sectionHeader(String(localized: "Sub-accounts"))
                subAccountsSection
            }
        }
    }

    /// THE RECORD — history, sync and the doors, in one card (prd §477).
    ///
    /// Three readings that were three loose blocks at the foot of the slab,
    /// and they are one subject: what this account has DONE and where to go
    /// and see it. No section header, deliberately — a title over the last
    /// card would be a fourth landmark for a footer, and the room's own
    /// provenance note sits bare for the same reason.
    @ViewBuilder
    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            historySection
            syncSection
                .padding(.top, DS.Space.s3)
            doorsSection
                .padding(.top, DS.Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Balance (2026-08-24)

    /// The scoped crown — this account's own native holding, its own curve,
    /// its own holdings block. The aggregate room's anatomy at one account's
    /// scope, which is what the design asks for and what makes narrowing the
    /// room feel like the same screen rather than a different one.
    ///
    /// **The series is THIS ACCOUNT'S** (`VibenetValueStore.samples(for:)`),
    /// never the room's — see that store's own note. Silent piece by piece,
    /// the aggregate's rule reused: no native reading draws no crown, one
    /// reading draws no line (a single point is a flat line, and a flat line
    /// on a balance chart reads as "went to zero"), one asset draws no
    /// holdings block because the crown above already states it.
    /// This account's curve, read ONCE per address rather than per body pass
    /// (2026-08-25, prd §477). It was `VibenetValueStore.samples(for:)` inline
    /// in the body — a `UserDefaults` read and a full `JSONDecoder` pass over
    /// the whole per-account book, on every scroll frame. §476 fixed exactly
    /// this in `VibenetRoomCard` and missed it here, which is why the jitter
    /// survived on the account page.
    @State private var history: [VibenetValueSample] = []

    @ViewBuilder
    private var balanceSection: some View {
        if item.nativeBalance != nil || !item.tokenBalances.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if let native = item.nativeBalance {
                    Text(String(localized: "This account holds"))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                    // `price48` and the amount-first move — the SAME crown as
                    // the aggregate and as Wallet's own (prd §475). Reported:
                    // *"on the individual account sheets in vibenet… they have
                    // a totally different format. We should be using the same
                    // type of format."* This was `price40` with a percent-only
                    // delta while the room above it drew `price48` with the
                    // amount — the same reading, two formats, one tap apart.
                    Text("\(VibenetBalanceFormat.line(native)) ETH")
                        .dsText(.price48)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 2)
                    if let change = VibenetValueHistory.delta(windowed),
                       let move = VibenetValueHistory.move(windowed) {
                        HStack(spacing: 5) {
                            Image(systemName: change >= 0
                                  ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .dsGlyph(9)
                            Text("\(VibenetBalanceFormat.line(abs(move))) ETH (\(VibenetBalanceFormat.percent(change)))")
                                .dsText(.callout15).fontWeight(.semibold)
                                .monospacedDigit()
                            Text(range.sinceLine)
                                .dsText(.callout15)
                                .foregroundStyle(DS.textTertiary)
                        }
                        .foregroundStyle(TokenChartStyle.accent(change: change, scheme: scheme))
                        .padding(.top, 2)
                    }
                    if let series = VibenetValueHistory.series(windowed) {
                        TokenChartPlot(chart: TokenChart(closes: series,
                                                         price: series.last ?? 0,
                                                         change: VibenetValueHistory.delta(windowed) ?? 0),
                                       accent: TokenChartStyle.accent(
                                           change: VibenetValueHistory.delta(windowed) ?? 0, scheme: scheme),
                                       // 120, the aggregate's and Wallet's own
                                       // (prd §475) — it was 90 here, so the
                                       // same curve changed size on the way in.
                                       height: 120, pulses: false,
                                       lineWidth: 2.6, fillOpacity: 0.24, endpointDot: true)
                            .padding(.top, DS.Space.s3)
                        rangeStrip
                    }
                }
                if let scoped = VibenetBalanceAggregation.compose([item]) {
                    VibenetHoldingsBlock(cells: VibenetBalanceTreemap.cells(scoped),
                                         reduceMotion: reduceMotion)
                        .padding(.top, DS.Space.s3)
                }
            }
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
                // THE FACE IS THE RAIL'S WHEN THE RAIL IS THERE (user,
                // 2026-08-25: *"on the individual account page, we don't need
                // the avatar before the address b/c its already in the source
                // strip"*). `VibenetScopeRail` is pinned directly above this
                // card and draws every watched account's face with the scoped
                // one ringed — so a second copy of the same identicon two
                // rows down is the same avatar twice, the identical finding
                // that took the face strip out of the stacked room's own stat
                // block (`VibenetRoomCard`'s header doc).
                //
                // CONDITIONAL, never deleted, and the condition is the rail's
                // OWN (`VibenetScopeRail.shows` wants more than one account
                // watched): a single-account room has no rail, and the
                // account sheet reached from the address book has no rail
                // either. Dropping the face unconditionally would leave both
                // of those faceless — a screen about one address, showing
                // nothing that identifies it at a glance.
                if showsFace {
                    WalletFace(address: item.address, size: DS.Face.shelf, circular: true)
                }
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
        if item.hasInitiatedUnlock {
            // **THE ONE CLOCK IN THIS ROOM THAT REALLY TICKS (prd §472).**
            //
            // A timelock is the only reading here that changes on its own
            // while you look at it — every other number moves when the chain
            // moves and we re-read. Both this bar and its sentence were
            // computed from `Date.now` at DRAW time, so they were correct at
            // the instant the view was built and then FROZE: an account
            // twenty minutes from unlocking sat at "Unlocks in 20 minutes"
            // with a motionless bar for as long as you watched it, and only
            // a scroll or a re-compose moved either. On the one surface whose
            // subject is a countdown, a countdown that does not count is
            // §83's fake status wearing a progress bar.
            //
            // `TimelineView(.periodic)` and NOT a `Timer` — the schedule is
            // owned by SwiftUI, so it stands down when the view is off screen
            // and when the app backgrounds, which a timer of our own would
            // have to be taught. SCOPED to this block alone rather than to
            // the screen: everything else here is chain state that a tick
            // cannot change, and re-evaluating it every second would re-run
            // the key roster's whole body for nothing.
            //
            // A SECOND is the interval and it is not arbitrary: `unlockLabel`
            // speaks in minutes for most of a delay and in SECONDS at the
            // end, which is exactly the stretch somebody stands there
            // watching, and a minute-long tick would freeze the display over
            // the final sixty seconds — the one moment it must not.
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                if let countdown = item.unlockLabel(now: tick.date) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(countdown)
                            .dsText(.heading17)
                            .foregroundStyle(Self.mark)
                            // The label is a whole new string each tick, so
                            // without this it hard-cuts between values; the
                            // bar beside it moves continuously and the two
                            // read as one clock only if both do.
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : DS.Motion.standard, value: countdown)
                        if let progress = item.unlockProgress(now: tick.date) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Self.mark.opacity(0.15))
                                    Capsule().fill(Self.mark)
                                        .frame(width: geo.size.width * progress)
                                }
                            }
                            .frame(height: 6)
                            .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                        }
                    }
                } else {
                    // The delay ELAPSED while you were looking at it — the
                    // moment this whole block exists for. `unlockLabel` going
                    // nil is that event, and the account is now unlocked
                    // pending the next read, so the row says so rather than
                    // holding the last countdown it managed to compute.
                    // THE LANDING (prd §479). Until now this branch simply
                    // swapped in a new sentence — the timelock opening, the
                    // one moment in this room somebody might genuinely sit
                    // and wait for, and it arrived with less ceremony than a
                    // list row gets.
                    //
                    // The bar FILLS to full and stays (the countdown's own
                    // capsule, at 1.0, so the drawing does not disappear at
                    // the instant it completes), the words land with the
                    // press spring, and ONE haptic fires — exactly once,
                    // guarded by `landed`, because a `TimelineView`
                    // re-evaluates every second and an unguarded haptic
                    // would buzz once a second forever.
                    //
                    // `tap`, NOT `success`: `DSHaptic.success` is reserved by
                    // this app's own haptic grammar for a WRITE's outcome and
                    // is fired only by `ShellChrome.flash(tone:)`, so the buzz
                    // and the toast naming it can never drift apart. Nothing
                    // was written here — a delay elapsed on the chain — and
                    // `tap` is that token's own case, "a state toggle
                    // landing".
                    //
                    // `DSHaptic` is a no-op on Mac Catalyst by construction,
                    // so this degrades to the visual alone there rather than
                    // needing a platform branch of its own.
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Ready to unlock"))
                            .dsText(.heading17)
                            .foregroundStyle(Self.mark)
                            .scaleEffect(landed ? 1 : 0.94)
                            .animation(reduceMotion ? nil : DS.Motion.press, value: landed)
                        Capsule().fill(Self.mark)
                            .frame(height: 6)
                            .frame(maxWidth: .infinity)
                    }
                    .task {
                        guard !landed else { return }
                        landed = true
                        DSHaptic.tap()
                    }
                }
            }
            trackOnLockScreen
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
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(VibenetRoom.rowLine(item))
                    .dsText(.heading17)
                    .foregroundStyle(DS.textSecondary)
                // The MECHANISM, on the one state that has one. Without it
                // "Not established yet" reads as something the person is
                // expected to fix and handed no way to — and the balance
                // above it, which an undeployed address really can hold, has
                // no explanation for how it got there.
                if let why = VibenetRoom.undeployedExplainer(item) {
                    Text(why)
                        .dsText(.callout15)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Keys (R3.1)

    /// Keys, SPLIT BY WHAT THEY CAN DO — owners, session keys, limited keys
    /// (`VibenetKeyGrouping`). Base's own account console draws exactly this
    /// division (its Owners and Session keys tabs), and it is not a
    /// presentation choice: the POLICY bit is the difference between a key
    /// that can spend the account and one that may only call a single
    /// contract under terms the account agreed to. Drawn as one flat list,
    /// an admin key and a capped subscription key sat side by side with only
    /// chip colour between them.
    ///
    /// Grouping is NOT the ranking this tray keeps refusing: within a group
    /// the order is still `alphabetical`, and no group claims one of your
    /// keys matters more than another — it names a distinction the scope
    /// bits already draw. A group with no keys is omitted entirely.
    private var keysSection: some View {
        // s6 BETWEEN GROUPS (prd §471), where it was s4 — the same rung that
        // separated a group's caption from its first key, so "Owners" and
        // "Session keys" read as one continuous column of cards rather than
        // as two groups.
        // NO HEADER OF ITS OWN (prd §477) — `body` draws the section header
        // above this now, exactly as the room does above its keys card, so a
        // second `heading22` here would be the same landmark twice. The COUNT
        // stays: it is a reading, not a title.
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                // **NOT UNDER THE PERMISSIONS SCOPE** (prd §495). §477 kept
                // this count on the reasoning that it is a reading rather than
                // a title — true, and the scope's own slot now states exactly
                // the same reading in `stat24` a few points above it, so
                // scoped it was "1 key" over "1 key". A reading is only worth
                // keeping the second time if the two can differ, and they
                // cannot: both count `item.actors`.
                //
                // It survives OFF that scope, where the slot is drawing
                // something else entirely and this is the only place the
                // count appears.
                if section != .permissions {
                    Text(keyCountLine)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // NARROWING, ON THIS PAGE TOO (2026-08-25, prd §480, user:
                // *"what happens if an account has like ten keys, won't they
                // still need to be able to see it the same way?"*).
                //
                // They do, and they could not: §480 gave both surfaces one row
                // grammar and left the TRAY holding the only filter, so the
                // two diverged at exactly the size where narrowing matters —
                // an account with ten keys was a long scroll here and one tap
                // on the All page. It is the tray's own strip, scoped to this
                // account, reading the same `VibenetKeyTray.census` so a chip
                // here and a chip there can never disagree about a count.
                keyFilterStrip
            }
            ForEach(VibenetKeyGrouping.sections(filteredActors)) { section in
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.group.title)
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(DS.textSecondary)
                        // What membership MEANS, so the group name is never
                        // something to infer from the keys inside it.
                        Text(section.group.caption)
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        // WHAT WE CANNOT SAY, ONCE PER GROUP AND NOT ONCE PER
                        // KEY (prd §471). `VibenetPolicyReadability.note` was
                        // drawn inside every gated key row, so an account with
                        // four session keys printed the same three-line
                        // paragraph four times, in the same tertiary ink as
                        // the five other lines around it — by a distance the
                        // largest single source of the "giant slab of gray"
                        // this section was reported as. It is a fact about
                        // session keys AS A CLASS, which is exactly what a
                        // group caption is for. The honesty §463 wanted is
                        // unchanged: it is still said, in full, on the screen.
                        if section.group == .session {
                            Text(VibenetPolicyReadability.note)
                                .dsText(.label11)
                                .foregroundStyle(DS.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(Array(section.actors.enumerated()), id: \.element.id) { index, actor in
                        // THE WHOLE CARD IS THE DOOR (prd §478, superseding
                        // §473's toggle). A key is one object and its card is
                        // one target — §473's reasoning, kept — but the tap
                        // PRESENTS `VibenetKeySheet` now instead of growing
                        // the row in place, which was the room's last inline
                        // expander.
                        if let onOpenKey {
                            Button {
                                DSHaptic.selection()
                                onOpenKey(actor)
                            } label: {
                                keyRow(actor, door: true).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .dsHover()
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                        } else {
                            keyRow(actor, door: false)
                                .chartArrival(index: index, reduceMotion: reduceMotion)
                        }
                    }
                }
            }
        }
    }


    /// TRACK THIS DELAY ON THE LOCK SCREEN (prd §473).
    ///
    /// A CONTROL, never automatic — `VibenetUnlockActivityDriver`'s own doc
    /// carries the argument: an unlock happened on the chain, possibly to an
    /// account somebody merely watches, and putting that on their lock screen
    /// because we noticed would be spending the most personal surface the OS
    /// has on something nobody asked to be interrupted about.
    ///
    /// **ABSENT, not disabled, where it cannot work** (Live Activities off in
    /// Settings, Mac Catalyst, or a delay with no readable end): a control
    /// that is present and inert is the dead control §83 bans, and this one
    /// would be inert for a reason the person cannot see from here.
    @ViewBuilder
    private var trackOnLockScreen: some View {
        // `unlocksAt` is Keystore's own epoch SECONDS (`UInt64`), not a
        // `Date` — converted here at the one place that needs a date, the way
        // `expiryLabel` and `unlockLabel` already do, rather than widening the
        // model to carry a second representation of one instant.
        if VibenetUnlockActivityDriver.available,
           let seconds = item.unlocksAt,
           case let opensAt = Date(timeIntervalSince1970: TimeInterval(seconds)),
           opensAt > .now {
            let tracking = VibenetUnlockActivityDriver.isTracking(item.address)
            Button {
                DSHaptic.selection()
                if tracking {
                    VibenetUnlockActivityDriver.finish(address: item.address)
                } else {
                    VibenetUnlockActivityDriver.start(
                        address: item.address,
                        name: VibenetWatch.shared.name(for: item.address)
                            ?? VibenetRoom.shortAddress(item.address),
                        unlocksAt: opensAt)
                }
                // The driver's dictionary is not observable, so the label is
                // nudged by hand rather than by a publish — one flag, flipped
                // where the act happened, which is cheaper and more honest
                // than making a lock-screen registry into app state.
                lockScreenTick &+= 1
            } label: {
                Label(tracking
                      ? String(localized: "Stop tracking on the lock screen")
                      : String(localized: "Track on the lock screen"),
                      systemImage: tracking ? "bell.slash" : "bell")
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(Self.mark)
            }
            .buttonStyle(.plain)
            .dsHover()
            .padding(.top, DS.Space.s3)
            .id(lockScreenTick)
        }
    }

    /// How far back this account's own curve looks (prd §479) — the room's
    /// own control, on the room's own scoped view, so the two surfaces do not
    /// answer the same question differently.
    @State private var range: VibenetChartRange = .all

    /// The samples the crown's move and the line both read — ONE derivation,
    /// so a figure and its curve can never describe different windows.
    private var windowed: [VibenetValueSample] {
        VibenetValueHistory.windowed(history, range: range, now: .now)
    }

    /// `VibenetRoomCard.rangeStrip`'s own recipe. Drawn only where the book
    /// can answer more than one span, so it is never a row of chips redrawing
    /// one line.
    @ViewBuilder
    private var rangeStrip: some View {
        let options = VibenetValueHistory.options(history, now: .now)
        if options.count > 1 {
            HStack(spacing: DS.Space.s2) {
                ForEach(options, id: \.self) { option in
                    let on = option == range
                    Button {
                        DSHaptic.selection()
                        withAnimation(reduceMotion ? nil : DS.Motion.standard) { range = option }
                    } label: {
                        Text(option.label)
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(on ? DS.textPrimary : DS.textTertiary)
                            .padding(.horizontal, DS.Space.s3)
                            .padding(.vertical, 6)
                            .background(Capsule(style: .continuous)
                                .fill(on ? DS.fillStrong : Color.clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressSpring())
                    .dsHover()
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .padding(.top, DS.Space.s2)
        }
    }

    /// Which permission the list is narrowed to, or nil for every key (prd
    /// §480). `@State`, so it dies with the screen — a look, not a
    /// preference, and a page that reopened pre-filtered would show fewer
    /// keys than its own count line says exist.
    @State private var keyFilter: String?

    /// This account's own census — the same derivation the tray's strip and
    /// the room's card read, so three surfaces can never disagree on a count.
    private var keyCensus: [VibenetPolicyCount] { VibenetKeyTray.census([item]) }

    /// The keys actually listed.
    private var filteredActors: [VibenetActor] {
        guard let keyFilter else { return item.actors }
        return item.actors.filter {
            VibenetKeyTray.holds(VibenetTrayKey(address: item.address, actor: $0),
                                 permission: keyFilter)
        }
    }

    /// "10 keys", or "3 of 10 keys" while narrowed — the count must never
    /// describe a list the screen is not showing, which is the shape §471
    /// objected to when a card said 4 and its list showed 3.
    private var keyCountLine: String {
        let total = item.actors.count
        let shown = filteredActors.count
        if keyFilter != nil && shown != total {
            return String(localized: "\(shown) of \(total) keys")
        }
        return total == 1 ? String(localized: "1 key") : String(localized: "\(total) keys")
    }

    /// The tray's own strip, scoped to this account.
    ///
    /// **Drawn only when there is something to choose between** (`count > 1`)
    /// — on an account whose every key is an Admin the chip would narrow to
    /// the list you are already looking at, which is §83's dead control with
    /// a permission's name on it.
    @ViewBuilder
    private var keyFilterStrip: some View {
        let census = keyCensus
        if census.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    keyChip(label: String(localized: "All"), count: nil, value: nil)
                    ForEach(Array(census.enumerated()), id: \.offset) { _, entry in
                        keyChip(label: entry.label, count: entry.count, value: entry.label)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func keyChip(label: String, count: Int?, value: String?) -> some View {
        let on = keyFilter == value
        return Button {
            DSHaptic.selection()
            withAnimation(reduceMotion ? nil : DS.Motion.standard) { keyFilter = value }
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
            // A NEUTRAL fill for the selection, never the room's mark: blue
            // here means a key is about to expire, and which slice you are
            // looking at is not urgent.
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

    /// One key's permissions — `VibenetKeySheet`'s own chip grammar (§463),
    /// so a key reads the same on the row, the tray and its own sheet.
    private func keyChips(_ actor: VibenetActor) -> some View {
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
                        // Three claims, three treatments. ADMIN inverts: scope
                        // 0 is every capability there is, including reserved
                        // ones this build cannot name, so it must not read as
                        // one more permission among five. The unknown tail is
                        // OUTLINED — a visibly different claim from a named
                        // permission, never an invented name in the same fill.
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

    /// Which new keys have already spent their arrival wash (prd §479) — one
    /// shot each, so a re-compose does not re-light a row somebody is reading.
    @State private var glowedKeys: Set<String> = []

    /// Whether this key is one this device has not seen before.
    private func isNew(_ actor: VibenetActor) -> Bool {
        newKeyIDs.contains(VibenetKeySeenDiff.keyID(address: item.address, actorId: actor.actorId))
    }

    /// Whether the unlock has already landed on this mount (prd §479) — the
    /// haptic is a MOMENT and fires once, where the `TimelineView` around it
    /// re-evaluates every second.
    @State private var landed = false

    /// Bumped whenever the control acts, purely so the label re-reads
    /// `isTracking`. See `trackOnLockScreen`.
    @State private var lockScreenTick: UInt8 = 0

    /// ONE KEY, ONE ROW — THE TRAY'S OWN ROW (2026-08-25, prd §480).
    ///
    /// Reported: *"on the individual account page, why isn't the way we
    /// display keys similar in some way to how we display them on the All
    /// page."* They were two grammars because they came from two passes —
    /// this was §473's CARD PER KEY, and that card existed **so the row could
    /// expand**. §478 deleted the expansion and the card outlived the feature
    /// that justified it, exactly as §471's census box outlived the doors it
    /// held.
    ///
    /// So the tray's row is the one row grammar: kind, id tail, permission
    /// chips, expiry, chevron. **One principled difference, not drift** — the
    /// tray leads with the account's FACE because it is room-wide and a key
    /// title alone is the same words on four accounts; here every row is the
    /// same account, so a face would be the identical picture repeated down
    /// the column and the row starts at its own name instead.
    private func keyRow(_ actor: VibenetActor, door: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Space.s2) {
                    Text(actor.kind.plainTitle)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    // WHICH KEY (prd §470) — two keys of one kind on one
                    // account are otherwise adjacent rows reading identically
                    // end to end. Noun-less and monospaced: a secp256k1
                    // actorId is an address and a passkey's is a hash, so any
                    // label would be a fabrication on half the rows.
                    Text(VibenetKeyIdentity.short(actor.actorId))
                        .dsText(.label11).monospaced()
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                    if isNew(actor) {
                        Text(String(localized: "New"))
                            .dsText(.label11).fontWeight(.semibold)
                            .foregroundStyle(DS.page)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Self.mark))
                            .fixedSize()
                    }
                }
                if let detail = actor.kind.plainDetail {
                    Text(detail)
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                // The scope, as chips — `grantedPlainLabels` is never empty
                // (see its doc), so there is no blank-row branch: an admin
                // arrives as one inverted chip rather than as nothing.
                keyChips(actor)
                    .padding(.top, 4)
            }
            Spacer(minLength: DS.Space.s2)
            let standing = actor.expiryStanding(now: .now)
            Text(actor.expiryLabel(now: .now))
                .dsText(.label11)
                .fontWeight(standing == .soon ? .semibold : .regular)
                .foregroundStyle(standing == .soon ? DS.tint : DS.textTertiary)
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
        // NO CARD, NO SEPARATOR (§480 / §478). The group this sits in is the
        // container; a card per row was the expander's ground and a hairline
        // is banned outright. Air is what separates rows here.
        .padding(.vertical, DS.Space.s3)
        .overlay {
            // …and it arrives lit when it is new (prd §479), one shot.
            if isNew(actor), !reduceMotion {
                RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                    .fill(Self.mark.opacity(glowedKeys.contains(actor.actorId) ? 0 : 0.14))
                    .allowsHitTesting(false)
                    .task {
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        withAnimation(.easeOut(duration: 1.2)) {
                            _ = glowedKeys.insert(actor.actorId)
                        }
                    }
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                DSHaptic.tap()
                DSPasteboard.copySensitive(actor.actorId)
            } label: {
                Label(String(localized: "Copy key id"), systemImage: "doc.on.doc")
            }
            // GATED, never unconditional. Only a secp256k1 actorId decodes to
            // a real signer; a passkey's is a hash that would yield a
            // plausible address belonging to nobody, so this item is absent
            // rather than wrong on those rows (§83, and
            // `VibenetKeyIdentity.signerAddress`'s own doc).
            if let signer = VibenetKeyIdentity.signerAddress(actor) {
                Button {
                    DSHaptic.tap()
                    DSPasteboard.copySensitive(signer)
                } label: {
                    Label(String(localized: "Copy signer address"), systemImage: "person.crop.circle")
                }
            }
            Button {
                DSHaptic.tap()
                DSPasteboard.copySensitive(actor.authenticator)
            } label: {
                Label(String(localized: "Copy authenticator"), systemImage: "checkmark.shield")
            }
        }
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
            // "…them", not a clause that stops dead. The name sits on the line
            // ABOVE the label, so "You can act for" alone renders as a
            // sentence cut off mid-word — its sibling above ("Can act for
            // you") is complete and the pair read as one broken and one fine.
            incoming.map { Spoke(address: $0.from, label: String(localized: "You can act for them")) }
        if !spokes.isEmpty {
            // No title — `body`'s section header says "Linked accounts" and a
            // `heading17` repeating it inside the card is the duplication
            // §475 already removed from the keys headline (prd §477).
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(spokes) { spoke in
                    spokeRow(spoke)
                }
            }
        }
    }

    /// One linked account, one row — FLAT on its card (2026-08-25, prd
    /// §478). It wore its own `dsWidgetSurface` at half opacity INSIDE
    /// `linkedCard`, which is the literal "cards in cards" of the report —
    /// and the half-opacity fill was §471's own named defect ("a 3% lift, a
    /// stain rather than a surface") shipped again the same week it was
    /// written down. The card is the object; these are its rows. Face, its
    /// own identity (name if watched has one, else the short address — the
    /// same identity every other surface in this room shows), and the one
    /// clause saying which direction the relationship runs.
    private func spokeRow(_ spoke: Spoke) -> some View {
        HStack(spacing: DS.Space.s3) {
            WalletFace(address: spoke.address, size: DS.Face.rowCircle, circular: true)
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
        // No surface of its own (§478): rows on a card, separated by the
        // stack's spacing, never boxes in the box.
        .padding(.vertical, DS.Space.s1)
    }

    // MARK: - Sub-accounts (2026-08-24)

    /// Accounts that authorized THIS address as their delegate — Base's own
    /// "Spending Account" shape, which its console gives a tab of its own.
    ///
    /// This is the OTHER direction from Linked accounts above, and the
    /// difference is what makes it worth a section rather than more rows up
    /// there: that one relates two addresses the person already watches,
    /// which needs no discovery. This one asks the chain "who named you",
    /// so it can surface an account you can spend and had never heard of.
    /// An already-watched sub-account still lists — it is a real
    /// relationship — but the unwatched ones sort first and say so, since
    /// they are the only reason to read the section twice.
    ///
    /// NO WATCH BUTTON HERE, deliberately: watching is how this app decides
    /// what to read on every refresh, and adding an account from a row on a
    /// detail screen buries a standing commitment inside a glance. The
    /// address is copyable and the address book takes a paste.
    @ViewBuilder
    private var subAccountsSection: some View {
        if let line = VibenetSubAccounts.line(item.subAccounts) {
            // No title — the group header above says "Sub-accounts" now that
            // the card is gone (§495), and a `heading17` repeating it is the
            // duplication §475 removed from the keys headline and §477
            // removed from the spine one section up.
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(line)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(item.subAccounts) { sub in
                        subAccountRow(sub)
                    }
                }
            }
        }
    }

    /// `spokeRow`'s object treatment, reused rather than inventing a fifth
    /// surface on one screen — a sub-account is an object the same way a key
    /// and a linked account are.
    ///
    /// **IT IS A CONTROL NOW (prd §493).** Reported as *"shows a subaccount you
    /// could tap but doesn't open"*, and it was exactly that: a face, a name, a
    /// date and a pill — the anatomy of every tappable row in this app — with
    /// no gesture on it at all. §83's dead control, wearing a row's clothes.
    ///
    /// The verb depends on what the row IS, which is the honest split: a
    /// WATCHED sub-account is already in the room, so the tap scopes to it; an
    /// UNWATCHED one is an account you can act for and are not following, so
    /// the tap starts watching it — which is the only thing this app can
    /// usefully do about it and the whole reason the read exists.
    @ViewBuilder
    private func subAccountRow(_ sub: VibenetSubAccount) -> some View {
        let inner = subAccountBody(sub)
        if sub.watched, let onScope {
            Button { DSHaptic.selection(); onScope(sub.address) }
                label: { inner.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .dsHover()
        } else if !sub.watched {
            Button {
                DSHaptic.selection()
                VibenetWatch.shared.add(sub.address)
            } label: { inner.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .dsHover()
        } else {
            inner
        }
    }

    private func subAccountBody(_ sub: VibenetSubAccount) -> some View {
        HStack(spacing: DS.Space.s3) {
            WalletFace(address: sub.address, size: DS.Face.rowCircle, circular: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(VibenetWatch.shared.name(for: sub.address) ?? VibenetRoom.shortAddress(sub.address))
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                // The DATE, never a claim about what the account holds — this
                // read knows one thing about it and says only that.
                if let at = sub.authorizedAt {
                    Text(String(localized: "Authorized you \(at.formatted(.relative(presentation: .named)))"))
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // The pill SAYS THE VERB now rather than only the state. It was
            // "Not watched", which names a fact and offers nothing — and the
            // row it sits on is the one place in this app where the answer to
            // that fact is one tap away.
            if !sub.watched {
                Text(String(localized: "Watch"))
                    .dsText(.label11)
                    .foregroundStyle(DS.tint)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background { Capsule().strokeBorder(DS.tint, lineWidth: 1) }
            } else {
                Image(systemName: "chevron.right")
                    .dsGlyph(11)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Flat for `spokeRow`'s reason (§478) — the card is the container.
        .padding(.vertical, DS.Space.s1)
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

    /// Real buttons, not menu items — the verbs worth a tap without a
    /// long-press.
    ///
    /// **`FlowLayout`, not an `HStack` (prd §470).** Every door here is
    /// `.fixedSize()`, so a fifth one ("Copy account state") pushed the run
    /// past a phone's width and the trailing door simply left the screen —
    /// and the row was already four wide on an undeployed account, which is
    /// exactly when the faucet door matters most. Flowing wraps instead of
    /// clipping, and it is the same layout the key rows' own chips use one
    /// section up, so nothing new is introduced to read.
    private var doorsSection: some View {
        FlowLayout(spacing: DS.Space.s3) {
            // Shown ONLY while the account is undeployed, and only when the
            // live config actually named a faucet. `faucetAddress` has been
            // parsed since this seat shipped and read by nothing — the one
            // door the state above can offer, since an account deploys on its
            // first transaction and a devnet address needs funds to make one.
            // A hand-off to the explorer, never a write.
            if VibenetRoom.undeployedExplainer(item) != nil,
               let faucet = VibenetConfig.cached()?.faucetAddress,
               let url = URL(string: VibenetExplorer.address(faucet)) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(String(localized: "Devnet faucet"))
                        Image(systemName: "arrow.up.right")
                    }
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(Self.mark)
                    .lineLimit(1)
                    .fixedSize()
                }
            }
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
            // The one door onto WRITING, and it is deliberately somebody
            // else's. Base's own console creates accounts, mints keys,
            // composes transactions and subscribes a session key; this app
            // reads, and holds no signing key that could do any of it (the
            // Safe co-signer, prd §425/§426, has no counterpart here and
            // building one for a devnet would mean a second, more powerful
            // key on an app whose whole posture is that it has none). A
            // hand-off costs nothing and never goes stale.
            Link(destination: URL(string: VibenetExplorer.console)!) {
                HStack(spacing: 4) {
                    Text(String(localized: "Manage on Base"))
                    Image(systemName: "arrow.up.right")
                }
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .fixedSize()
            }
            Button {
                DSHaptic.tap()
                // `DSPasteboard`, not a bare `UIPasteboard.general.string`
                // (corrected 2026-08-25, prd §470): the raw write has no
                // expiry and rides Universal Clipboard to every other device
                // on the account, which is the default §277 introduced this
                // type to stop. An address is that doc's own named
                // `copySensitive` case, and every other address copy in the
                // app already goes through it — this one call site was the
                // straggler.
                DSPasteboard.copySensitive(item.address)
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
            // THE RAW READ, FOR SOMEBODY DEBUGGING (prd §470). Everything
            // this app knows about the account — actorIds, scope as the hex
            // word the contract stores, expiry as the unix integer — in the
            // one place §463 allows spec internals to go: a paste that is
            // asked for explicitly and competes with nothing on screen. See
            // `VibenetAccountDebug`.
            //
            // `copy`, not `copySensitive`: this is a DOCUMENT whose whole
            // purpose is to travel to wherever the debugging is happening,
            // which `DSPasteboard`'s own doc names as the case for the
            // cross-device verb ("copying a note on the phone and pasting it
            // on the Mac is a real thing people do, and this app runs on
            // both"). The single-value copies on each key row stay
            // `copySensitive` — those are the "an address, a sign-in code"
            // case, this is the note.
            Button {
                DSHaptic.tap()
                DSPasteboard.copy(VibenetAccountDebug.text(
                    for: item,
                    name: VibenetWatch.shared.name(for: item.address),
                    now: .now))
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "Copy account state"))
                    Image(systemName: "curlybraces")
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
