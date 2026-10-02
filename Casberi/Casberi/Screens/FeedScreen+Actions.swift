import SwiftUI
import SwiftData

// The visit and the verbs: last-seen stamps, landing and leaving, the swipe's
// verbs, pull and refresh, the wallet's live read and the block stream, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// Per-source last-visit stamps. All keeps its original "feed.lastSeen"
    /// key — an update never resets anyone's divider.
    private func lastSeenKey(for source: String) -> String {
        source == "All" ? "feed.lastSeen" : "feed.lastSeen.\(source)"
    }

    private func lastSeen(for source: String) -> Date? {
        let stamp = UserDefaults.standard.double(forKey: lastSeenKey(for: source))
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    private func stampSeen(_ source: String) {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970,
                                  forKey: lastSeenKey(for: source))
    }

    /// This page came to the front: freeze its boundary for the visit, replay
    /// the shape's entrance, stream its synthesis block. Every one of these is
    /// an ARRIVAL — spending them on a mounted-but-unseen neighbour would hand
    /// the person a page whose moment already happened.
    /// Who posted here since you last opened this room — the social rail's
    /// attention ring, handed UP to the shell (prd §362).
    ///
    /// It is computed here and not in `MainSurface` because both of its inputs
    /// are the feed's: `newSince` is this room's own frozen last-visit stamp,
    /// and `visible` is the room's boundary-filtered rows. The shell's own
    /// corpus query deliberately does not fetch `authorHandle`, so asking it
    /// there would fault the heavy columns back in on every body pass — the exact
    /// cost that query's `propertiesToFetch` exists to avoid.
    ///
    /// Written on LANDING only, alongside the crown pour and for the same
    /// reason: it is a fact about arriving in a room, and recomputing it as rows
    /// stream in would dissolve the rings one by one while you watched.
    private func publishFreshHandles() {
        guard SocialRoom.hasRoster(source) else {
            chrome.freshHandles = []
            chrome.recentHandles = []
            return
        }
        // Newest post per author, for the rail's cap (prd §824).
        var newest: [String: Date] = [:]
        for thing in visible {
            guard let handle = thing.authorHandle else { continue }
            if newest[handle].map({ thing.capturedAt > $0 }) ?? true {
                newest[handle] = thing.capturedAt
            }
        }
        chrome.recentHandles = newest.sorted { $0.value > $1.value }.map(\.key)
        guard let since = newSince else {
            chrome.freshHandles = []
            return
        }
        chrome.freshHandles = Set(visible.compactMap {
            $0.capturedAt > since ? $0.authorHandle : nil
        })
    }

    func land() {
        freezeBoundary()
        // Replay the shape's entrance ONLY the first time this page is landed
        // (2026-07-30, user: swiping between screens had a tiny lag; "just
        // appear on revisit"). Re-animating every row on every swipe-in was
        // both the extra motion and a per-frame main-actor cost on each visit —
        // now the rows animate in the first time the page is seen and simply
        // ARE there on return. Pull-to-refresh still replays deliberately
        // (`refreshFeed` bumps `shapeWave` itself), and a page never yet built
        // still gets its first-appearance entrance from `RowEntrance.onAppear`.
        if !hasLanded {
            hasLanded = true
            shapeWave += 1
            shapeWaveAt = Date.timeIntervalSinceReferenceDate
        }
        streamBlock()
        loadWalletLive()
        publishFreshHandles()
        // Every landing writes the crown pour's hue (prd §159): the scoped
        // wallet's face tint when you're standing inside one, else nil —
        // Casberi's own blue. Written unconditionally, not just by the Wallet
        // page, so arriving on ANY page resets a scoped tint the wallet page
        // left behind; no leave() bookkeeping to race the pager's ordering.
        chrome.pourHue = roomTakesWalletScope ? selectedWallet.map(WalletFace.tint) : nil
        // And how much of it this room gets (prd §297, 2026-08-03) — the rule
        // and its reasoning live together on `ShellChrome`. Written
        // unconditionally beside the hue for the same reason: arriving on any
        // page settles the crown, with no leave() bookkeeping to race the
        // pager.
        chrome.pourDose = ShellChrome.pourDose(for: source)
    }

    /// The person left this page — stamp what they saw, so the next visit's
    /// "New since" line is honest, and let the boundary freeze afresh then.
    func leave() {
        stampSeen(source)
        visitFrozen = false
    }

    /// The boundary freezes on arrival and holds for the whole visit — a
    /// bounce out to another page and back can't move the line (ruling
    /// 2026-07-09). All tracks `AppVisit.away` instead of a per-page stamp
    /// (2026-07-20) — the same "since you left the app" window the agent's
    /// own "While I was away?" chip already names; there's no single page
    /// for the whole corpus to have left.
    private func freezeBoundary() {
        guard !visitFrozen else { return }
        visitFrozen = true
        newSince = source == "All" ? AppVisit.away?.lowerBound : lastSeen(for: source)
    }

    // MARK: - Verbs from the swipe (reads pass, writes confirm)

    func run(_ verb: Verb, on thing: Thing) {
        if verb.isWrite {
            confirming = (verb, thing)
        } else {
            perform(verb, on: thing)
        }
    }

    func perform(_ verb: Verb, on thing: Thing) {
        switch verb.action {
        case .openURL(let url):
            openExternal(url)
        case .addToCalendar:
            Task {
                do {
                    try await HandOff.addToCalendar(thing)
                    chrome.flash(String(localized: "Copied — paste it in Calendar"), tone: .success)
                } catch { chrome.flash(error.localizedDescription, tone: .failure) }
            }
        case .addToReminders:
            Task {
                do {
                    try await HandOff.addToReminders(thing)
                    chrome.flash(String(localized: "Copied — paste it in Reminders"), tone: .success)
                } catch { chrome.flash(error.localizedDescription, tone: .failure) }
            }
        case .copyText:
            DSPasteboard.copy(thing.content.isEmpty ? thing.title : thing.content)
            // The row's copy and the sheet's copy are the same act and now
            // feel the same (prd §867). `flash` defaults to `.neutral`, which
            // fires nothing, so this was the app's other silent pasteboard
            // write — and a bare String is not localized by `Text`, while the
            // `.addToReminders` arm four lines up already passes through the
            // catalog. Both keys exist there; neither needed adding.
            chrome.flash(String(localized: "Copied"), tone: .success)
        case .markDone:
            // Rung-1 local mark only — app-owned things (a note turned to-do,
            // demo seeds). A real reminder's done-state is READ-ONLY, mirrored
            // from the Reminders app (ruling 2026-07-25), so it never offers
            // this verb; nothing here writes back to any external record.
            thing.mark = .done
            modelContext.saveHonestly()
        case .translate:
            translateText = thing.postText ?? thing.content
            showTranslate = true
        case .showInFiles:
            Task {
                do { try await HandOff.showInFiles(thing) }
                catch { chrome.flash(error.localizedDescription, tone: .failure) }
            }
        case .openAddress:
            // An in-app destination the feed cannot present itself opens the
            // sheet that can. The address card is a `FaceTarget` on
            // `ThingSheetView`, which is where this row's tap already goes.
            openThing(thing)
        case .edit:
            // A note of yours, reopened in the note sheet (prd §981).
            chrome.editNote(thing.id)
        case .approve:
            // The MCP door's save requests (PRD §34) went with the door
            // (2026-10-01) and their rows with it (`SourceRename.sweepRetiredAsk`), so an
            // approval here only records the answer.
            withAnimation(DS.Motion.standard) {
                thing.mark = .done
                modelContext.saveHonestly()
            }
            // Honesty: the answer is recorded on the thing. Nothing is
            // sent anywhere — no agent transport exists yet (2026-07-10;
            // the old copy claimed a gateway was told).
            chrome.flash("Approved", tone: .success)
        case .deny:
            withAnimation(DS.Motion.standard) {
                thing.mark = .done
                modelContext.saveHonestly()
            }
            chrome.flash("Denied")
        }
    }

    /// Loads the real per-wallet holdings for the Wallet chip's own shape —
    /// the ONLY place holdings show in Feed (amendment 2026-07-10: the
    /// module already lives on Home; leading All with it doubled that).
    /// Everything watched shows here regardless of pin — this is the
    /// wallet's native view. Composing is synchronous elsewhere in this
    /// screen; the wallet fetch isn't, so it lands in the background and
    /// repaints.
    /// Pull-to-refresh (2026-07-12): re-polls every connected bridge for fresh
    /// things, then RECOMPOSES the feed the way a source switch does — the
    /// shaped rows re-cascade (shapeWave replays their entrance) and the
    /// synthesis block re-streams. The Feed's take on Home's pull re-compose:
    /// records paint, so the delight is the cascade, not a typewriter — which
    /// is why this returns as soon as the work is handed off (2026-07-28): the
    /// cascade IS the beat, and holding the refresh control's spinner open for
    /// an extra 450ms afterwards only made the gesture feel slow.
    /// The one pull, however it's triggered — a real gesture (`.refreshable`)
    /// or Mac's ⌘R (`chrome.refreshRequest`, see the `.onChange` above). Kept
    /// as one function so the two triggers can never drift into dealing the
    /// roster/pulse/sync sequence differently.
    func performPull() async {
        // WHAT FALLS (prd §619): the sources this pull asks. All → the whole
        // connected sweep; a folded category → its connected members; a
        // source's own room → that source.
        //
        // **A WALLET-SCOPED PULL FALLS AS ITS SEAT'S TILES TOO (prd §655).**
        // It used to empty the roster so the shower could say "which wallet"
        // in a hue (§171) rather than "Wallet", which the room already does —
        // and that was the app's last berry. The hue this set (`refreshHue`)
        // is deleted with the berries; the wallet's stop still travels on
        // `chrome.pourHue` (set by `land()`), which is what retints the
        // crown (§159) and was always the stronger telling of the same fact.
        let roster: [String] = source == "All"
            ? BridgeRefresh.roster(store: bridges)
            : CategoryFold.isCategory(source) ? BridgeRefresh.roster(store: bridges, category: source)
            : [source]
        chrome.rain(sources: roster)   // spins the avatar door, deals the shower
        await refreshFeed()
    }

    private func refreshFeed() async {
        // ONE pull, ONE shower (2026-07-28). The `.refreshable` closure above
        // already bumped `refreshPulse`; bumping it again here dealt a SECOND
        // shower a few milliseconds behind the first, over the same drop
        // identities — so the first shower's drops were re-dealt mid-fall and
        // the pour read as a stutter every time. The pulse belongs to the
        // gesture, and the gesture happens once.
        shapeWave += 1
        shapeWaveAt = Date.timeIntervalSinceReferenceDate
        // The haptic lands with the gesture, not after it (user, 2026-07-28:
        // "need pull to refresh snappy"). It sat behind a deliberate 450ms
        // beat — "a short beat lets the pull read before it lands with a soft
        // thud" (2026-07-12) — which also held the refresh control's spinner
        // open for that long after the work was already handed off. The
        // cascade below IS the beat; the thud shouldn't wait for it.
        DSHaptic.success()
        // A deliberate pull re-fetches live — clear the holdings cache so the
        // Wallet feed's treemap isn't served a TTL-cached read (same contract as
        // Home's pull; the cache is for the automatic fan-out, not the gesture).
        await WalletIngest.invalidateHoldingsCache()
        // The prediction rooms' own book cache is cleared by `performPull`
        // BEFORE it bumps the pulse (see the note there) — it cannot live
        // here, because by the time this runs the pulse has already started
        // the reload this was meant to freshen.
        BridgeRefresh.refreshAllConnected(context: modelContext, store: bridges, force: true)
        streamBlock()
    }

    /// Reads the Wallet feed's live state for the current scope. Off the Wallet
    /// feed it clears rather than holding a stale read — the tiles are gone
    /// from the screen anyway, and stale state would flash on return.
    func loadWalletLive() {
        guard source == "Wallet" else {
            if walletLive != WalletLiveState() { walletLive = WalletLiveState() }
            return
        }
        let scope = selectedWallet
        Task { @MainActor in
            let state = await WalletWatch.liveState(scopeTo: scope, context: modelContext)
            // The scope may have moved while the reads were in flight — a late
            // answer for a wallet we've since left must not paint.
            guard scope == selectedWallet else { return }
            // Animated on purpose (2026-07-20, wallet streaming fix): this
            // lands SECONDS after the balance tile (live chain reads vs a
            // local sample file), and an unanimated set hard-popped the
            // warnings/DeFi tiles into place — "looks unintentional". The
            // animation carries the LAYOUT (rows sliding to make room);
            // each tile's own RowEntrance carries its reveal.
            withAnimation(DS.Motion.standard) { walletLive = state }
        }
        // Whether this wallet has anything to PICK (prd §387).
        //
        // Read HERE rather than inside the shelf card, and that placement is
        // the whole fix: the card draws nothing until it knows, so a card that
        // asked for itself produced an empty row, `List` pruned the row, and
        // the `.task` that would have answered never ran — the invitation could
        // never appear on any wallet. Gating a section on state the section
        // itself has to be alive to fetch is a chicken-and-egg; the owner of
        // the section owns the question.
        //
        // Costs no request: served from the same cached read the wallet refresh
        // already made for the NFT spam allowlist.
        if let entry = nftShelfWallet {
            Task { @MainActor in
                let any = !(await WalletNFTShelf.collections(for: entry.address)).isEmpty
                guard scope == selectedWallet else { return }
                if nftHasCollections != any { nftHasCollections = any }
            }
        } else if nftHasCollections {
            nftHasCollections = false
        }
    }

    func streamBlock() {
        guard source == "Wallet" else {
            if !blockStream.els.isEmpty { blockStream.paint([]) }
            if portfolio != nil { portfolio = nil }
            return
        }
        // The treemap paints as soon as holdings land, and the portfolio behind
        // it lands on the same beat — one read, both answers (prd §155), so the
        // balance number, the map, and the concentration line can never be
        // three different moments. Scoped to the selected wallet when the feed
        // is (prd §128) — the doc generator filters its groups to that address;
        // nil paints the combined map.
        let scope = selectedWallet
        Task { @MainActor in
            let read = await WalletIngest.portfolioRead(scopeTo: scope)
            // The scope may have moved while the read was in flight — a late
            // answer for a wallet we've since left must not paint (the same
            // guard `loadWalletLive` keeps).
            guard scope == selectedWallet else { return }
            if let read {
                // Same animated landing as `loadWalletLive` — the treemap is
                // the tallest late-arriving block, so ITS unanimated insert
                // was the most jarring of the pops.
                withAnimation(DS.Motion.standard) {
                    blockStream.paint(read.doc)
                    portfolio = read.portfolio
                }
            } else if !blockStream.els.isEmpty || portfolio != nil {
                withAnimation(DS.Motion.standard) {
                    blockStream.paint([])
                    portfolio = nil
                }
            }
            // Read AFTER the holdings pass, so it reports what that pass
            // actually found rather than the pass before it.
            let unreadable = await WalletIngest.unreadableNetworks()
            let unpriced = await WalletIngest.unpricedNetworks()
                .filter { !unreadable.contains($0) }
            guard scope == selectedWallet else { return }
            if unreadable != unreadableChains { unreadableChains = unreadable }
            if unpriced != unpricedChains { unpricedChains = unpriced }
        }
    }
}
