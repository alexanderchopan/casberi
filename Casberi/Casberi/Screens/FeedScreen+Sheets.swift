import SwiftUI
import SwiftData

// The feed's one sheet: its route, its content, and every door that opens it, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// The one sheet this screen can have open at a time (2026-07-24, fixing
    /// prd §196's "opens and dismisses itself on first try"). Five separate
    /// `.sheet` modifiers stacked on one view — thing/token/combined
    /// wallets/allocation/Worth-a-look — fought each other for the
    /// presentation controller: SwiftUI only reliably drives one
    /// `.sheet(item:)` + one `.sheet(isPresented:)` per view, and past that
    /// the first tap's controller got torn down mid-present by a sibling's
    /// state settling, so it flashed open and closed; the second tap then
    /// worked because the machinery had quieted. One enum route behind one
    /// `.sheet(item:)` removes the contention entirely.
    enum FeedSheetRoute: Identifiable {
        /// A row, and the LIST it was opened from (prd §645 pass 3). The scope
        /// is a VALUE — never a `[Thing]`, which is corollary 4 and build 177
        /// exactly — so the neighbour doors rebuild the predicate rather than
        /// hold the array. `.none` wherever the list cannot be rebuilt, which
        /// is every hero and shelf door below.
        case thing(Thing, walk: WalkScope)
        case token(TokenQuickRoute)
        case allocation
        case worthALook
        /// The two composition doors (prd §240, 2026-07-31). Both carry the
        /// composition VALUE rather than reading `walletLive` at present time:
        /// the books can land again under an open tray, and a tray that
        /// re-reads mid-presentation would renumber itself while being looked
        /// at. Value-typed all the way down, so no `Thing` and no liveness
        /// question here.
        /// A web page in the in-app Safari sheet (prd §653) — a faucet page
        /// raised from a room's Top up, which sits inside this List's rows and
        /// cannot present its own sheet.
        case web(URL)
        /// The NFT picker (prd §387). Routed here rather than presented by the
        /// shelf card, which lives inside this List's rows — a `.sheet` on a row
        /// resolves to the same presenting controller as this one and the picker
        /// would rise part way and close again (ruling 2026-07-28). Carries only
        /// value types, so no `Thing` and no liveness question.
        case nftPicks(address: String, label: String)
        /// Your years with one person, opened from the room's own board
        /// (2026-08-18, prd §396). Routed here for the standing reason every
        /// case above it is: the board lives inside this List's rows, and a
        /// `.sheet` on a row resolves to the same presenting controller as
        /// this one — the half-open-then-close bug (ruling 2026-07-28).
        /// Carries a handle and a source, so no `Thing` and no liveness
        /// question.
        case person(source: String, handle: String)
        /// **THE SEND FORM, ON A SHEET (prd §553, §548).** Home holds the verbs
        /// and the form holds the screen — routed here rather than presented by
        /// the card: a `.sheet` on a view inside this List resolves to the same
        /// presenting controller as this one and half-opens before closing again.
        case framesSend
        /// The Logos send form (prd §1084) — the same sheet, routed here for
        /// `framesSend`'s reason.
        case logosSend
        /// One Logos conversation (prd §1155), read live from the Observer.
        /// Carries the conversation's id and title, never a message: nothing
        /// of the chat is kept.
        case logosChat(id: String, title: String)
        /// ONE FRAMES TRANSACTION, and the three routes below it — all four
        /// here for two reasons at once: the seat lands no
        /// `Thing` so nothing can ride `.thing`, and every card that opens one
        /// lives inside this List's rows, where a `.sheet` resolves to the same
        /// presenting controller as this one and half-opens before closing.
        ///
        /// Carries the OWNING address beside the move: in an unscoped room
        /// nothing else can say which of the shown addresses it belonged to.
        case framesMove(FramesMove, String)
        /// One FRAME — the object this chain is NAMED for, and until now the
        /// one thing in the room that could not be opened anywhere. Carries the
        /// whole move and an index rather than the frame alone, so the sheet
        /// can draw the step in its sequence; a step out of its order is a step
        /// without its meaning.
        case framesFrame(FramesMove, Int)
        /// Everyone a social room's face row leaves behind its `+N` (prd §824),
        /// routed here since the row moved into the room (§959): a `.sheet`
        /// inside a List row tears this screen's own sheet down mid-rise.
        case socialFaces
        /// Markets' Add (prd §1081): find a token or a stock and watch it.
        case watchAdd
        /// Reading's Search (prd §1085).
        case readingFind(ReadingScope)
        /// One thing followed, by its id and room (prd §1118).
        case following(String, Following.Room)
        /// A room's verb for what you follow: Reading's Follow tray, Media's
        /// track tray, Work's watch tray (prd §1118).
        case followingAdd(Following.Room)
        /// Subscribe to a calendar, from an empty Coming up (prd §1137).
        case calendarSubscribe
        /// Social's Follow (prd §1086).
        case socialFollow
        /// The Wallet's Follow (prd §1090), the Watch tile since prd §1105.
        case walletFollow
        case walletTokens
        /// One subscription, by its key (prd §1105).
        case subscription(String)
        /// Track a subscription by hand (prd §1105, the verb since §1117).
        case subscriptionAdd
        /// Track a subscription, opened on one app: raised once on the
        /// arrival a first connect made (prd §1164).
        case subscriptionTrack(String)
        /// One mailing list, by its key (prd §1111).
        case mailSubscription(String)
        /// Track a sender's mail as a subscription (prd §1117).
        case mailSubscriptionAdd
        /// A company from Markets' index you don't watch yet (prd §1082).
        case company(CompanyPacks.Company)
        /// GitHub's watch tray (prd §1030): raised once on the arrival a
        /// connect made, and from the room's Watch tile (§1031).
        case githubWatch
        /// One address that paid somebody else's gas, with the moves the room
        /// is currently showing — passed rather than re-read, because the room
        /// may be scoped and a sheet that quietly widened to every account
        /// would answer a question nobody asked.
        case framesPayer(FramesPayer, [FramesMove])
        /// One watched Frames address, or this phone's own.
        case framesAccount(FramesAccount)
        /// Somebody asking this phone to pay their fee (prd §728c), opened by a
        /// `casberi://frames/sponsor` link through `chrome.framesSponsorRequest`.
        case framesSponsor(FramesSponsorRequest)

        var id: String {
            switch self {
            // The scope is folded in, or the same thing opened from two
            // different rooms is ONE identity to SwiftUI and the second open
            // reuses the first's doors.
            case .thing(let t, let walk): "thing:\(t.id.uuidString)@\(walk.key)"
            case .token(let r): "token:\(r.id)"
            case .allocation: "allocation"
            case .worthALook: "worthALook"
            case .socialFaces: "socialFaces"
            case .watchAdd: "watchAdd"
            case .readingFind(let scope): "readingFind:\(scope.rawValue)"
            case .following(let id, let room): "following:\(room.rawValue):\(id)"
            case .followingAdd(let room): "followingAdd:\(room.rawValue)"
            case .calendarSubscribe: "calendarSubscribe"
            case .socialFollow: "socialFollow"
            case .walletFollow: "walletFollow"
            case .walletTokens: "walletTokens"
            case .subscription(let id): "subscription:\(id)"
            case .subscriptionAdd: "subscriptionAdd"
            case .subscriptionTrack(let app): "subscriptionTrack:\(app)"
            case .mailSubscription(let id): "mailSubscription:\(id)"
            case .mailSubscriptionAdd: "mailSubscriptionAdd"
            case .company(let c): "company:\(c.name)"
            case .web(let url): "web:\(url.absoluteString)"
            case .nftPicks(let address, _): "nftPicks:\(address)"
            case .person(let source, let handle): "person:\(source):\(handle)"
            case .framesSend: "framesSend"
            case .logosSend: "logosSend"
            case .logosChat(let id, _): "logosChat:\(id)"
            case .framesMove(let m, _): "framesMove:\(m.id)"
            case .framesFrame(let m, let i): "framesFrame:\(m.id)#\(i)"
            case .framesPayer(let p, _): "framesPayer:\(p.id)"
            case .framesAccount(let a): "framesAccount:\(a.address)"
            case .framesSponsor(let r): "framesSponsor:\(r.id)"
            case .githubWatch: "githubWatch"
            }
        }
    }

    /// Opening a URL is an ACTION here — a button tap, a swipe verb — and never
    /// something the body renders. It used to arrive as
    /// `@Environment(\.openURL)`, which is a stored property, and
    /// `OpenURLAction` wraps a closure, so it can never compare equal: every
    /// recomputation of the environment counted as a change to this view and
    /// re-ran the whole feed body.
    ///
    /// MEASURED 2026-08-06 on a 6,000-row corpus, via `Self._printChanges()`:
    /// 18 of 53 FeedScreen invalidations in one launch named `_openURL`, and
    /// each one is a ~260ms `feedList` rebuild on the main actor — a third of
    /// the rebuild storm, bought by a value the view never draws. Nothing above
    /// this view overrides `openURL` (the one override in the tree wraps
    /// `ThingSheetView` inside the composer), so this is the same call the
    /// environment action would have made.
    ///
    /// It is NOT the whole rebuild story and should not be read as the fix:
    /// the dominant trigger is `@self` — MainSurface re-creating this view —
    /// which this does nothing about. A/B measured rebuilds ~49 → ~43.
    func openExternal(_ url: URL) {
        UIApplication.shared.open(url)
    }

    /// What ↑/↓ walk: the rows this feed ACTUALLY RENDERED, in the order it
    /// rendered them. Mac only — nothing else compiles this.
    ///
    /// The first cut published `visible`, the room's chronology, on the theory
    /// that day-grouping a newest-first array leaves the sequence untouched.
    /// True of the grouping, false of the All room — which is the room this
    /// feature is most for. `bundledSections` collapses any day's three-or-more
    /// same-source things into ONE bundle row and drops the members from the
    /// tree entirely, so walking `visible` there steps onto dozens of ids with
    /// no view: `scrollTo` finds nothing, no highlight paints, and ↓ looks dead
    /// for a run of presses on exactly the days with the most in them.
    ///
    /// So it reads `memo.groups` — the bundled row list the `ForEach` itself
    /// walks, which `boundaryID(in:)` already treats as the feed's canonical
    /// order for the same reason. Reading a memo written during body evaluation
    /// is safe here precisely because nothing reads this DURING body:
    /// `KeyboardWalk` publishes from `.onChange`, which runs after the update
    /// that filled it. Rooms that don't bundle leave the memo empty and fall
    /// back to `visible`, which for them genuinely is the render order.
    ///
    /// A BUNDLE row is skipped: it summarizes things rather than being one, so
    /// it has nothing to open in the pane. The walk steps over it.
    ///
    /// Two shapes regroup rather than bundle — Reminders splits by mark (Doing
    /// / To do / Done), Gmail lifts two "Waiting on you" rows to the top while
    /// leaving them in their day. Every row there does render, so nothing is
    /// unreachable; the walk visits them in corpus order and the list scrolls
    /// to each. Stated rather than hidden: the alternative is a second copy of
    /// every shape branch, drifting from the first the day either changes.
    ///
    /// Row ids (`String`) — the same value `FeedRow.id` and every `ForEach` key
    /// in this feed use, so the scroll target and the list's own identity are
    /// one thing rather than two kept in step by hand. Ids and never models: a
    /// `[Thing]` handed to the shell's long-lived `chrome` is the 2026-07-24
    /// crash class by construction.
    ///
    /// `isActive` guards for PERF as much as correctness — `body` evaluates for
    /// all three mounted pager pages, including the one the 2026-07-30 pass
    /// deliberately leaves unbuilt, and `visible` is the derivation that pass
    /// exists to avoid paying for off-screen.
    var walkRowIDs: [String] {
        guard isActive else { return [] }
        guard memo.groups.isEmpty else {
            return memo.groups.flatMap(\.1).compactMap { row in
                if case .single = row.kind { return row.id }
                return nil
            }
        }
        // The Notes room's folder list draws the cover and no rows (prd
        // §980), so only the cover is walkable there.
        if Pinboard.isPinnedRoom(source), chrome.notesScope == .folders, chrome.notesFolder == nil {
            return ledeThingID(in: [(Pinboard.room, visible)]).map { [$0.uuidString] } ?? []
        }
        return visible.map { $0.id.uuidString }
    }

    /// A walked row id back to its model, against the live corpus at the moment
    /// of the keypress rather than holding one — see `walkRowIDs`. The one
    /// resolution behind all four walk verbs (open, copy, peek, and the
    /// peekable read that gates Space), so none of them can disagree about
    /// which row the ring is on.
    func resolveRowID(_ rowID: String) -> Thing? {
        visible.live.first(where: { $0.id.uuidString == rowID })
    }

    /// Open a walked row.
    func openRowID(_ rowID: String) {
        guard let thing = resolveRowID(rowID) else { return }
        openThing(thing)
    }

    // THE YEAR GRAPH LEFT THIS ROOM (user ruling, 2026-09-11) — see the room
    // head's own note below. It draws on the GitHub ACCOUNT PAGE now
    // (`TokenSetupScreen`), where facts about the account live.

    /// What each `FeedSheetRoute` presents.
    ///
    /// Extracted from the `.sheet(item:)` closure for `roomHead`'s reason
    /// (below): the switch is one expression over a dozen cases, and adding a
    /// single argument to one of its calls put it over the type-checker's
    /// budget. Behaviour is unchanged — this is still the ONE presentation
    /// this screen makes (see `FeedSheetRoute`'s doc for why five separate
    /// `.sheet` modifiers made the first tap self-dismiss).
    @ViewBuilder
    func sheetContent(_ route: FeedSheetRoute) -> some View {
        switch route {
        case .thing(let thing, let walk):
            // Zoom transition DROPPED for thing opens (2026-07-30, prd
            // ruling 232): a beta tester on build 225 hit a deterministic crash
            // opening any photo ("every photo, instantly, every time")
            // that never reproduced for the dev or on the simulator —
            // headless open, the real tile-tap zoom, and the sheet content
            // path were all verified clean. That profile — universal for
            // one device, invisible everywhere else — is an OS/device-
            // specific `.navigationTransition(.zoom)` fault, the one
            // fragile system API in an otherwise clean path. The zoom is
            // decorative; the standard sheet present is the safe fallback.
            // The matching `matchedTransitionSource` sources were removed
            // with it. Restore only once a symbolicated stack proves a
            // different cause.
            ThingSheetView(thing: thing)
        case .token(let route):
            TokenQuickSheet(route: route)
        case .socialFaces:
            socialFacesTray
        case .watchAdd:
            WatchAddSheet()
        case .socialFollow:
            SocialFollowSheet()
        case .walletFollow:
            WalletFollowSheet()
        case .walletTokens:
            // Every token Holdings folded (prd §1107). A pick closes the tray
            // first, then opens the token: one sheet at a time (§872).
            if let portfolio = portfolioShown {
                WalletTokensSheet(positions: portfolio.positions, total: portfolio.totalUSD,
                                  moves: walletHoldingMoves) { position in
                    feedSheet = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        walletOpenToken(position)
                    }
                }
            }
        case .subscription(let id):
            SubscriptionSheet(id: id)
        case .subscriptionAdd:
            // A Catalyst sheet does not inherit the presenter's environment
            // (prd §872); the tray reads the connected apps (§1164).
            SubscriptionAddTray()
                .environment(chrome)
                .environment(bridges)
        case .subscriptionTrack(let app):
            SubscriptionAddTray(prefill: .init(name: app, site: SubscriptionAddTray.siteByOffer[app]))
                .environment(chrome)
                .environment(bridges)
        case .mailSubscriptionAdd:
            MailSubscriptionAddTray()
        case .mailSubscription(let id):
            MailSubscriptionSheet(id: id) { mailID in
                // One sheet at a time (§872): the list closes, then the mail.
                feedSheet = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    let d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.id == mailID })
                    if let thing = (try? modelContext.fetch(d))?.first, thing.isLive { openThing(thing) }
                }
            }
        case .following(let id, let room):
            FollowingSheet(id: id, room: room)
        case .followingAdd(let room):
            followingAddTray(room)
        case .readingFind:
            ReadingFindSheet(mode: .search) { thing in
                // The find tray closes before the thing's sheet rises: one
                // sheet at a time, never one raised from inside another (§872).
                feedSheet = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    openThing(thing)
                }
            }
        case .calendarSubscribe:
            CalendarSubscribeSheet()
        case .company(let company):
            CompanySheet(company: company)
        case .githubWatch:
            GitHubWatchTray()
        case .allocation:
            if let portfolio {
                WalletAllocationTray(portfolio: portfolio)
            }
        case .worthALook:
            // The two walk doors (prd §449). Each is handed over ONLY
            // when its card is really on screen — the sheet falls back to
            // enumerating that group itself otherwise, so a pill can
            // never point at a card this room isn't drawing (§83's dead
            // control, and the same nil-able shape
            // `WalletCompositionStrip` keeps for Deposited and Locked).
            //
            // Dismiss and scroll are set TOGETHER on purpose: `scrollTo`
            // animates over ~0.3s and the sheet's dismissal over ~0.35s,
            // so the card is already centred as the sheet clears — the
            // room moving to meet you rather than a jump you arrive to.
            WalletWorthALookTray(
                warnings: walletLive.warnings,
                flagged: walletLive.flagged,
                activeApprovals: walletLive.activeApprovals,
                exposure: walletLive.exposure,
                // No walk doors (prd §947): the tray opens from Risk, and the
                // approvals and lending cards it walked to are Permissions'
                // and Positions' now, so it enumerates those groups itself.
                onWalkToApprovals: nil,
                onWalkToLending: nil)
        case .framesMove(let move, let owner):
            FramesMoveSheet(move: move, owner: owner) { index in
                // Frame-to-frame through the ONE sheet: replacing the route
                // swaps the tray's content in place, so the step rises where
                // the transaction was rather than as a second sheet over it.
                feedSheet = .framesFrame(move, index)
            }
        case .framesFrame(let move, let index):
            FramesFrameSheet(move: move, index: index) { next in
                // Step-to-step, the same route swap that opened this one.
                feedSheet = .framesFrame(move, next)
            }
        case .framesPayer(let payer, let moves):
            FramesPayerSheet(payer: payer, moves: moves) { move in
                // The owner is this room's own scope: a sponsored transaction
                // was read off one of the shown accounts, and the payer is by
                // definition NOT it.
                feedSheet = .framesMove(move, framesOwner(of: move))
            }
        case .framesSponsor(let request):
            FramesSponsorSheet(request: request)
        case .framesAccount(let account):
            FramesAccountSheet(account: account) { section in
                // The sheet's facts are doors: scope the room to this account
                // and open the list the fact names.
                chrome.framesScope = account.address
                chrome.framesSection = section
                feedSheet = nil
            }
        case .web(let url):
            DSWebSheet(url: url) { feedSheet = nil }
        case .nftPicks(let address, let label):
            WalletNFTPickerSheet(wallet: address, label: label)
        case .person(let source, let handle):
            // `dsNavSheet` (prd §560) — this route had no sizing, so a person
            // room opened into a ~540×620 box on iPad and Mac.
            NavigationStack {
                PersonRoomScreen(profile: SocialProfile(
                    source: source, handle: handle,
                    displayName: nil, bio: nil, avatarURL: nil))
                    // The dismiss is declared HERE and not on the screen,
                    // because `PersonRoomScreen` is also PUSHED (the roster's
                    // own door, `navigationDestination(item: $openPerson)`) —
                    // a Done button on the screen itself would appear over a
                    // pushed room, where it exits nothing.
                    .dsSheetDismiss { feedSheet = nil }
            }
            .dsNavSheet()
            // A sheet covers `RootShell`'s haptic listener, and this room is
            // not a `DSTray` (which carries its own) — so its `DSHaptic` calls
            // bump a counter nothing is listening to unless one is mounted
            // here. `RootShell.rootPresented`'s note states the rule: a root
            // sheet that is not a tray and fires its own haptics needs one.
            // Only on THIS door — pushed, the room is under the shell's copy
            // and a second listener would buzz twice.
            .background(DSHapticSink())
        // **THE SEND FORM (prd §553).** The room hands the sheet what it
        // knows: who the book knows, what the account holds, whether a Max is
        // honest, and the one closure that actually sends. Everything visual
        // lives in `DevnetSendSheet`.
        case .logosChat(let id, let title):
            LogosChatTray(convo: id, title: title)
        case .logosSend:
            // **A NATIVE TRANSFER, ONE SIGNER, NO MAX (prd §1084).** The
            // sender pays the fee and must hold its reserve besides, so the
            // whole balance cannot send itself — Frames' reason for no Max.
            DevnetSendSheet(
                venue: String(localized: "Logos"),
                seat: LogosRoom.source,
                tint: DS.tint,
                unit: String(localized: "test coins"),
                candidates: logosSendCandidates,
                heldLine: logosHeldLine,
                maxAmount: nil,
                isValidAddress: { LogosWire.watchableID($0) != nil },
                isValidAmount: { LogosWire.typedAmount($0) != nil },
                perform: { to, amount in await sendLogos(to: to, amount: amount) })
        case .framesSend:
            DevnetSendSheet(
                venue: String(localized: "Frames"),
                seat: FramesIdentity.source,
                tint: DS.tint,
                unit: String(localized: "test ETH"),
                candidates: framesSendCandidates,
                heldLine: framesHeldLine,
                // **NO MAX**: the sender pays its own gas, so an amount equal
                // to the whole balance cannot pay for itself and is a
                // guaranteed failure — the dead control §83 bans wearing a
                // convenience's clothing.
                maxAmount: nil,
                isValidAddress: DevnetSendParse.isValidAddress,
                isValidAmount: { DevnetSendParse.weiData(from: $0) != nil },
                perform: { to, amount in await sendFrames(to: to, amount: amount) },
                // The one thing neither neighbour can say — see
                // `FramesSendPlanSteps`.
                // **THE VENUE STITCHES** (prd §548 sixth follow-up): this
                // chain's whole capability is putting several frames under one
                // signature, and until then the send built exactly two.
                stitch: DevnetStitch(
                    headName: String(localized: "Verify"),
                    headDetail: String(localized: "An expiry check, then your signature · always first"),
                    atomicity: .chosen(
                        title: String(localized: "All or nothing"),
                    // **BOTH STATES ARE SPELLED, and OFF is the one that
                    // matters.** Measured on this chain (see
                    // `FramesTransaction.atomicFlag`): with the flag clear, a
                    // frame that fails leaves the frames before it SENT — the
                    // recipient of a failed transaction's first frame still
                    // holds the money. No other send in this app behaves that
                    // way, so leaving OFF undescribed would be the §83 fake
                    // status in the place it costs money.
                        on: String(localized: "If any frame fails, none of them send."),
                        off: String(localized: "A frame that fails leaves the ones before it sent.")),
                    // The chain bounds the verify prefix at 500,000 gas and its
                    // refusal names no remedy, so the sheet stops first. Eight
                    // is well inside it and is also more legs than a list this
                    // size can show without scrolling past the control.
                    maxLegs: 8,
                    atCapacity: String(localized: "That's as many frames as one transaction can carry here."),
                    send: { legs, atomic in await sendFramesStitched(legs, atomic: atomic) },
                    // **THE SAME STRIP THE ROOM DRAWS.** Not a preview invented
                    // for this screen: `FramesSequenceStrip` is what the Frames
                    // scope uses to show what a transaction DID, so composing in
                    // it means composing in the shape the result will be read
                    // in — and the join between cells is the only place the
                    // all-or-nothing toggle is visible as a picture rather than
                    // as a sentence.
                    // Drawn on the commit tile's own tint fill since §571, so
                    // it takes the palette for that ground — the same drawing,
                    // not a second one written for the tile.
                    preview: { legs, atomic in
                        AnyView(FramesSequenceStrip(runs: [framesPreviewRun(legs)],
                                                    joinProgress: atomic ? 1 : 0,
                                                    palette: .onTint))
                    },
                    // **ASKED OF THE ENCODER, NEVER RE-SPELLED** (prd §571).
                    // The list draws a tie between joined legs, and the rule
                    // for which legs those are is `FramesTransaction.stitched`'s
                    // — the last payload frame never carries the flag, which
                    // the node enforces by refusing the transaction outright.
                    // Reading it back off the run this file already builds for
                    // the strip means the tie in the list and the tie in the
                    // drawing are one fact with one door, rather than two
                    // spellings that agree until somebody edits one.
                    joins: { legs, atomic in
                        guard atomic else { return Array(repeating: false, count: legs.count) }
                        return framesPreviewRun(legs)
                            .filter { $0.frame.mode != 1 }
                            .map(\.joinedToNext)
                    }),
                // **TOKENS, THROUGH THE SAME SHEET (prd §728b).** The coin still
                // goes through `perform`; a token rides the stitched path as a
                // one-leg batch, so it is signed, noted and refreshed exactly as
                // every other send here.
                assets: framesSendAssets,
                sendAsset: { to, amount, asset in
                    await sendFramesStitched([DevnetSendLeg(address: to, amount: amount,
                                                            asset: asset.id, unit: asset.unit)],
                                             atomic: false)
                },
                planAsset: { destination, amount, asset in
                    FramesSendPlanSteps.steps(destination: destination, amount: amount, asset: asset)
                },
                // **SOMEBODY ELSE CAN PAY (prd §728c)** — a row on the batch,
                // drawn only when there is somebody you follow to ask.
                payerChoice: DevnetPayerChoice(
                    // A request is signed by this phone's secp256k1 key, so the
                    // passkey account cannot ask — its sponsor would be asked to
                    // pay for an account the request's signature does not speak for.
                    candidates: framesSendsFromPasskey ? [] : framesPayerCandidates,
                    ask: { legs, atomic, payer in
                        await askFramesSponsor(legs, atomic: atomic, payer: payer)
                    },
                    paysHere: { FramesKey.holds($0) }),
                senderChoice: framesSenderChoice)
        }
    }

    /// Open the row a head card named, by its `sourceRef`. The cards hold no
    /// `Thing` (corollary 5), so every one of them hands back a value and the
    /// lookup lands here, against the live corpus.
    func openBySourceRef(_ ref: String, in visible: [Thing]) {
        guard let match = visible.first(where: { $0.isLive && $0.sourceRef == ref })
        else { return }
        openThing(match)
    }

    /// Open a thing by its `id.uuidString`, resolved against the live feed — the
    /// head-card contract for a head whose members carry ids rather than
    /// `sourceRef`s (the cross-source thread; not every thing has a unique ref).
    /// Liveness inside the filter, before any stored read (corollary 3).
    private func openByID(_ id: String, in visible: [Thing]) {
        guard let match = visible.first(where: { $0.isLive && $0.id.uuidString == id })
        else { return }
        openThing(match)
    }

    /// Open the newest row of a source that a predicate accepts — for a head
    /// that ranks something owning MANY rows and so
    /// cannot name a single `sourceRef`. Liveness is checked inside the filter,
    /// before any stored property is read (corollary 3).
    func openNewest(source: String, in visible: [Thing],
                            where matches: (Thing) -> Bool) {
        let match = visible
            .filter { $0.isLive && $0.source == source && matches($0) }
            .max { $0.capturedAt < $1.capturedAt }
        if let match { openThing(match) }
    }

    /// Every row opens its own thing sheet — including a wallet transaction
    /// (2026-07-24, user: "when i tap 'received' on a transaction it brings me
    /// to the wallet management screen... no reason to go there"). The old
    /// ruling (2026-07-09) sent Wallet rows to the management screen because
    /// "the generic sheet had nothing more than an explorer link to show" —
    /// long obsolete: the sheet now leads with the full transfer STAGE (the
    /// parties, the signed amount, the chain, the flag banner) and its Open
    /// disc IS that explorer link. Tapping a transaction should show the
    /// transaction, not the page for managing which wallets you watch.
    ///
    /// On iPad wide enough for two columns (2026-07-25) this fills the
    /// trailing DETAIL PANE instead of throwing a sheet over the whole
    /// screen — the row and the thing it opens stay on screen together, which
    /// is the point of the shape. `present` returns false wherever no pane
    /// exists (iPhone, an iPad mini in portrait, Slide Over), and the sheet
    /// path below is then exactly the one this app has always taken.
    func openThing(_ thing: Thing) {
        // A NOTE OF YOURS IS ITS PAGE (prd §1099): it opens where it is
        // written, read until a tap on the words, never on a reading sheet
        // whose Edit then opened the page. A locked note keeps the sheet's
        // Face ID door (§982), and a highlight its "from <the page> ›" (§1020).
        if Self.opensAsPage(thing) {
            chrome.editNote(thing.id, typing: false)
            return
        }
        let walk = rowWalk
        guard !detail.present(thing, walk: walk) else { return }
        feedSheet = .thing(thing, walk: walk)
    }

    /// Whether a tap opens this thing on the note page (prd §1099).
    static func opensAsPage(_ thing: Thing) -> Bool {
        thing.isLive && Pinboard.isNote(thing)
            && !NoteLock.isLocked(thing) && !Highlight.isHighlight(thing)
    }

    /// The scope a row tap carries (prd §645 pass 3) — the room and the kind
    /// filter this list is actually showing.
    ///
    /// **`narrowed` is the whole safety of it.** `liveVisible` applies four
    /// more filters that no `source ==` predicate can rebuild: the pinned
    /// room's membership is `pinnedAt != nil` rather than a source, and the
    /// wallet and person scopes narrow to a subset the room's own
    /// chip chose. In any of those the doors are ABSENT, which A.3 rule 4
    /// says plainly: an absent door is honest, a door onto a row the list does
    /// not hold is not.
    private var rowWalk: WalkScope {
        WalkScope.feed(source: source, tag: filter.tag,
                       narrowed: Pinboard.isPinnedRoom(source)
                           || (roomTakesWalletScope && selectedWallet != nil)
                           || personScoped)
    }
}
