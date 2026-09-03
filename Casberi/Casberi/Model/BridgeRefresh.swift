import Foundation
import SwiftData

/// One foreground refresh for every connected polling bridge (RSS, Bluesky,
/// Farcaster, and each connected token bridge). RootShell fires it on
/// scenePhase → .active; screens can reuse it (e.g. pull-to-refresh) instead of
/// repeating the guard-then-Task shape per bridge. Each bridge refreshes
/// independently, fire-and-forget, on the main actor.
@MainActor
enum BridgeRefresh {
    /// Spreads a foreground refresh's ~45 independent bridge Tasks instead of
    /// firing every one in the same instant (2026-07-15 — no cap or stagger
    /// existed before this). Each bridge still refreshes fully independently —
    /// this only delays ITS OWN first `await`, never queues one bridge behind
    /// another — so a slow bridge still can't block a fast one.
    ///
    /// Two paces since 2026-08-06 (the post-271 "laggy at open" report, see
    /// `SweepClock`): the AUTOMATIC scenePhase sweep holds the whole pass for
    /// a lead-in — past the first-scroll moment it used to land on — and then
    /// spaces slots 120ms apart, since every slot's decode+insert half runs on
    /// the main actor and 40ms packed all ~45 of them into the opening two
    /// seconds. A pull-to-refresh keeps the original 0ms lead-in and 40ms
    /// spacing: the gesture's contract is immediacy, and the person is
    /// watching the spinner, not scrolling.
    ///
    /// The delay arrives ALREADY COMPUTED (`slot()` returns milliseconds, not
    /// an index) so a pass's pace is fixed at the instant it dispatches. Read
    /// from shared state in here instead, a pull-to-refresh landing while an
    /// automatic sweep is still staggering would re-pace that sweep's
    /// not-yet-woken slots to the pull's own 0/40 — collapsing the thirty
    /// still to come into one burst, which is precisely the stall the lead-in
    /// exists to prevent, arriving at the one moment nobody would look for it.
    private static func stagger(_ delayMs: Int) async {
        guard delayMs > 0 else { return }
        try? await Task.sleep(for: .milliseconds(delayMs))
    }

    /// When the whole sweep last ran — a rapid background→active bounce
    /// (a notification glance, Face ID, control center) used to re-fire all
    /// ~25 bridges every time (2026-07-21: no cooldown existed at all). The
    /// per-bridge `running` guards only stop a bridge overlapping ITSELF;
    /// they never stopped back-to-back sweeps. Mirrors the min-interval gate
    /// `GitHubGraphStore.refreshIfStale`/`KalshiWatch` already use per-store.
    private static var lastSweep: Date?
    private static let minSweepInterval: TimeInterval = 45

    /// Per-heal throttle (2026-07-24 perf): the pure DELETE-SYNC passes —
    /// removing rows whose upstream item is gone (Photos/Calendar) — are
    /// cleanup, not fresh content, so they needn't run on every foreground the
    /// way the "land new items" refreshes do. Each runs at most once per
    /// `healInterval`, keyed in UserDefaults so the throttle survives relaunch.
    /// A deleted item lingering a few extra minutes is invisible; a full
    /// source-wide fetch+diff on every foreground is not free. (Bluesky/
    /// Farcaster/Mail heals already carry their own 1h network throttle.)
    private static let healInterval: TimeInterval = 600
    static func dueForHeal(_ key: String) -> Bool {
        let k = "heal.due.\(key)"
        let now = Date.now.timeIntervalSince1970
        guard now - UserDefaults.standard.double(forKey: k) > healInterval else { return false }
        UserDefaults.standard.set(now, forKey: k)
        return true
    }

    /// `force: true` (pull-to-refresh) always runs live, matching the
    /// gesture's own contract of bypassing every other TTL/cache in the
    /// refresh path — only the automatic scenePhase-driven sweep is gated.
    static func refreshAllConnected(context: ModelContext, store: BridgeStore, force: Bool = false) {
        // THE DEMO REACHES NOTHING (2026-08-07). Not a nicety and not merely
        // privacy — the demo marks 60-odd seats connected and watches a wallet
        // address that does not exist, and the keyless wallet paths ride the
        // watched list rather than any credential. So an ungated sweep would
        // fire real RPC reads for a made-up address on somebody's first run,
        // and then write what came back: `WalletIngest` would record a fresh
        // value sample of ZERO over the seeded curve, which renders as a
        // balance that fell off a cliff — the "flat curve reads as went to
        // zero" failure `agent-panel-selftest` exists to prevent, arriving by
        // a route that self-test cannot see.
        //
        // `force` does NOT override this, unlike every other gate here: a
        // pull-to-refresh is a request for fresher data, and in the demo there
        // is no fresher data to get — only real requests and a chance to
        // corrupt the seed. Nothing about the demo is time-sensitive, so the
        // gesture costs nothing by doing nothing.
        //
        // ONE exception, and it's a re-seed not a read (2026-08-11):
        // `TokenPulse.pulses` is in-memory only, so a fresh launch/relaunch
        // starts it empty — this is the exact spot a REAL launch's sweep
        // would have refreshed it, so it's the right spot for the demo's
        // synthetic equivalent too. No network, never reads `DemoMode`'s own
        // wallet address, and it's a no-op once already seeded this process.
        if DemoMode.isActive {
            TokenPulse.shared.reseedDemoIfNeeded()
            PredictionPulse.shared.reseedDemoIfNeeded()
            return
        }
        if !force, let last = lastSweep, Date.now.timeIntervalSince(last) < minSweepInterval { return }
        lastSweep = .now
        // This pass's pace, fixed here rather than read per slot — see
        // `stagger`.
        let leadInMs = force ? 0 : 1800
        let slotSpacingMs = force ? 40 : 120
        // Where this pass's time goes, when `-sweepTimer YES` asked (2026-08-06).
        // Off, this is one `Bool` read; on, it is the only view of the main-actor
        // stalls a foreground sweep causes — the thing `perf.sh` cannot see,
        // since none of its three numbers touch this path. See `SweepClock`.
        SweepClock.beginPass(force: force)
        // What the LAST pass learned about who is still letting us in — see
        // `BridgeHealth.reconcile` for why it reads the previous pass rather
        // than this one. Pure local bookkeeping over ~60 seats, no request.
        BridgeHealth.reconcile(store: store)
        // Returns this slot's DELAY IN MILLISECONDS, not its index — so every
        // `stagger(s)` below carries its pass's pace with it.
        var nextSlot = 0
        func slot() -> Int {
            defer { nextSlot += 1 }
            return leadInMs + nextSlot * slotSpacingMs
        }
        // The native-framework bridges (Photos/Calendar/Reminders/Health/
        // Music) only ever ingested at the moment of connect — nothing
        // re-scanned them, so a screenshot taken an hour later never
        // landed (report 2026-07-09). Their ingest calls already dedupe on
        // sourceRef exactly like every polling bridge ("reconnects and
        // refreshes are cheap" — HealthIngest's own doc comment); they were
        // just never wired into the foreground refresh. Calendar/Reminders
        // re-present the system dialog on every foreground if you call the
        // request API again unconditionally (field report 2026-07-13) — the
        // refresh path below must go through a bare re-scan that checks
        // authorizationStatus first, same fix already applied to
        // AppleMusicIngest/ContactsIngest — gated on BridgeStore so a
        // never-connected bridge is never silently asked.
        func connected(_ id: String) -> Bool {
            store.bridges.contains { $0.id == id && $0.status == .connected }
        }
        // Photos gates on the REAL authorization, not the stored bridge status
        // (2026-07-24 fix): the `pho` status could drift off exactly
        // `.connected` while full Photos access was granted the whole time, and
        // the old `connected("pho")` gate then silently stopped every
        // foreground/pull from ingesting new screenshots — connect landed the
        // first batch and nothing refreshed after (user report). Run whenever
        // access is live and the user hasn't explicitly PAUSED the bridge.
        if let photoBridge = store.bridges.first(where: { $0.id == "pho" }),
           photoBridge.status != .paused {
            if ScreenshotIngest.hasAccess {
                // LIMITED access is the silent version of this bridge's own
                // bug report (2026-07-25): every fetch still succeeds, so
                // nothing downstream can tell "your library has 4 screenshots"
                // from "iOS only lets us see the 4 you picked" — new
                // screenshots never land and older ones are missing wholesale,
                // which reads exactly like a broken sync. Say it instead
                // (honesty rule); Photos' detail screen carries the remedy.
                let limitedLine = String(localized: "Limited access — only the photos you picked can land")
                if ScreenshotIngest.accessIsLimited {
                    if photoBridge.status != .attention || photoBridge.statusLine != limitedLine {
                        store.markAttention("pho", statusLine: limitedLine)
                    }
                } else if photoBridge.status != .connected || photoBridge.statusLine == limitedLine {
                    // Self-heal a drifted status so the Apps catalog reads true.
                    store.reconnect("pho", proof: "Synced just now")
                }
                // Staggered off the synchronous call path (2026-07-24 perf):
                // this runs TWO PHAsset library scans and must stay on the main
                // actor for its SwiftData inserts, so calling it inline stalled
                // the main thread mid-animation — the chip-flip and refresh
                // confetti stuttered. A Task defers it a beat past the frame the
                // animation starts on; new screenshots still land this sweep.
                let ps = slot(); Task { @MainActor in
                    await BridgeRefresh.stagger(ps)
                    await sweepTimed("photos.ingest") { _ = ScreenshotIngest.ingest(context: context) }
                    // …and one batch of the walk BACKWARDS through the library,
                    // so screenshots older than the head fetch's window finally
                    // arrive. Costs nothing once the walk has reached the end.
                    ScreenshotIngest.backfill(context: context)
                }
                // Thumbnails for new rows, removal of confirmed-gone hollow
                // ones. Throttled — new screenshots still land via `ingest` —
                // but a deliberate pull runs it live, same contract as Mail's
                // heal below: `force` bypasses every other TTL in this path.
                if force || BridgeRefresh.dueForHeal("photos") {
                    let s = slot(); Task { @MainActor in
                        await BridgeRefresh.stagger(s)
                        _ = await sweepTimed("photos.heal") { await ScreenshotIngest.heal(context: context) }
                        // Mirror Photos deletions (prd §231): a screenshot
                        // deleted from the library leaves Casberi too. One
                        // batched existence check, no per-asset await — so it
                        // catches the fully-healed rows heal's perf filter
                        // skips, which is exactly why deletion never synced
                        // before (2026-07-30).
                        await sweepTimed("photos.prune") { _ = ScreenshotIngest.pruneDeleted(context: context) }
                        // Then lift the treemap terms off whatever OCR text the
                        // heal (and prior passes) have written — no PHAsset walk,
                        // just `content`, so it's cheap and self-terminating once
                        // the library is fully topic'd (2026-07-30).
                        _ = await sweepTimed("photos.topics") { await ScreenshotTopics.healTopics(context: context) }
                    }
                }
            } else if photoBridge.status != .attention {
                // Access revoked since connect — say so instead of silently
                // ingesting nothing forever (honesty rule).
                store.markAttention("pho", statusLine: "Photos access is off — reconnect to resume")
            }
        }
        if connected("cal") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ScheduleIngest.refreshCalendar(context: context)
            }
            // Delete-sync: an event deleted outright (not just aged out of
            // the ingest window) — local EventKit check. Throttled: refresh
            // above still lands new/changed events every foreground.
            if BridgeRefresh.dueForHeal("calendar") {
                let s2 = slot(); Task { @MainActor in
                    await BridgeRefresh.stagger(s2)
                    _ = ScheduleIngest.healCalendar(context: context)
                }
            }
        }
        if connected("rem") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ScheduleIngest.refreshReminders(context: context)
            }
        }
        let healthOn = connected("hlt"), stravaOn = connected("strava")
        if healthOn || stravaOn {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await HealthIngest.connectAndIngest(context: context,
                                                        healthOn: healthOn, stravaOn: stravaOn)
            }
        }
        if connected("music") {
            // The bare re-scan — refresh must never re-present the
            // permission dialog (2026-07-10).
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await AppleMusicIngest.ingest(context: context)
            }
        }
        if !RSSStore.shared.feeds.isEmpty {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await RSSIngest.refresh(context: context)
            }
        }
        // What the articles actually SAY (2026-08-06) — a bounded, ledgered
        // read of the pages RSS and Substack rows already link to, into
        // retrieval-only `enrichedText`. Its own slot: it is several fetches
        // against several publishers and has no business delaying the landing
        // pass above. Self-retiring — returns at once when every recent row
        // has been read or has run out of attempts.
        if !RSSStore.shared.feeds.isEmpty || !FeedFollowStore.substack.isEmpty {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await sweepTimed("feeds.articleText") { await FeedArticleText.sweep(context: context) }
            }
        }
        if BlueskyStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await BlueskyIngest.refresh(context: context)
                // Drop what no current follow explains — a topic or account
                // unfollowed before the tap-time prune existed (prd §286),
                // which a reinstall can't clear either since the corpus
                // returns from CloudKit as it was.
                SocialTopics.reconcile(source: "Bluesky",
                    watchedHandles: BlueskyStore.shared.handles,
                    topics: BlueskyStore.shared.feeds.map(\.name), context: context)
            }
            // Delete-sync: a post removed by its author or moderation.
            // Own network round trip and its own hourly throttle.
            let s2 = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s2)
                _ = await BlueskyIngest.heal(context: context)
            }
        }
        if FarcasterStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await FarcasterIngest.refresh(context: context)
                SocialTopics.reconcile(source: "Farcaster",
                    watchedHandles: FarcasterStore.shared.usernames,
                    topics: FarcasterStore.shared.channels.map(\.name), context: context)
            }
            let s2 = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s2)
                _ = await FarcasterIngest.heal(context: context)
            }
        }
        if NostrStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await NostrIngest.refresh(context: context)
                SocialTopics.reconcile(source: "Nostr",
                    watchedHandles: NostrStore.shared.accounts.map(\.pubkeyHex),
                    topics: NostrStore.shared.hashtags.map(\.tag), context: context)
            }
            // Delete-sync: own network round trip and its own hourly
            // throttle, same shape as Farcaster/Bluesky's heals above.
            let s2 = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s2)
                _ = await NostrIngest.heal(context: context)
            }
        }
        if !PinterestStore.shared.username.isEmpty {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await PinterestIngest.refresh(context: context)
            }
        }
        // The feed-follow bridges (Substack/Reddit/YouTube/Podcasts) — each
        // polls only when it's watching something.
        for kind in FeedFollowKind.allCases where !kind.store.isEmpty {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await FeedFollowIngest.refresh(kind, context: context)
                // Read-only passes over what just landed, touching nothing in
                // the ingest above — same shape as the social bridges' own
                // return-check (delight pass 2026-07-28). YouTube's view
                // doubling and retitle checks already ran inside the ingest
                // itself (they need the per-item feed data, not just the
                // landed corpus), so only the corpus-wide checks live here.
                // Podcasts joined YouTube/Reddit here 2026-07-28 (a show off
                // hiatus is the exact same shape).
                // A Short and a twenty-minute review land as the same kind of
                // row — the feed says nothing about which is which, so this
                // asks (2026-08-06, `YouTubeShorts`). Bounded, ledgered and
                // self-retiring: it returns immediately once every landed
                // video has been classified once.
                if kind == .youtube {
                    _ = await sweepTimed("youtube.shorts") { await YouTubeShorts.sweep(context: context) }
                    // The room's topic map reads a video's own description,
                    // which only started landing on 2026-08-06 (`media:description`
                    // is namespaced, so the parser had never matched it). The
                    // sweep call sites are hand-wired per source, so a
                    // `topicSource` case with no call HERE is inert — the
                    // silent no-op X and TikTok both shipped with (§313), where
                    // a registry answering nil is indistinguishable from a room
                    // with nothing to say.
                    _ = await sweepTimed("youtube.topics") {
                        await ScreenshotTopics.healTopics(source: "YouTube", context: context)
                    }
                }
            }
        }
        if connected("contacts") {
            // The bare re-scan — refresh must never re-present the permission
            // dialog; it runs only when access is already granted.
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ContactsIngest.refresh(context: context)
            }
        }
        if connected("homekit") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await HomeKitIngest.refresh(context: context)
            }
        }
        // Apple Wallet (prd §313). Gated on the bridge's OWN flag rather than
        // the catalog seat: the seat is registered by a successful read, so
        // gating on it would mean a device that connected but has nothing yet
        // never reads again. `refresh` re-checks authorization itself and
        // never re-presents the system prompt (the Contacts rule).
        if AppleWalletBridge.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await AppleWalletBridge.refresh(context: context, store: store)
            }
        }
        for bridge in TokenBridge.allCases where bridge.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await TokenIngest.refresh(bridge, context: context)
            }
        }
        // OpenRouter's credit reading (2026-08-09) — not a `TokenBridge` case
        // (it's an agent key, not a bridge token), so it needs its own line
        // rather than riding the loop above. `AgentAnswer.check` is the free
        // "who am I" read every provider gets at connect time; re-running it
        // here is what turns a one-time key-check into a periodic monitor,
        // behind `dueForHeal`'s 10-minute throttle so a busy foreground sweep
        // doesn't hit OpenRouter every single activation.
        if connected("openrouter"), BridgeRefresh.dueForHeal("openrouter.credits"),
           let key = TokenVault.get(AgentProvider.openrouter.vaultKey) {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await AgentAnswer.check(key, provider: .openrouter)
                let existing = IngestSupport.existingSourceRefs(context)
                OpenRouterCredits.drainPending(context: context, existing: existing)
            }
        }
        // Peer & Privacy Pools ride the watched wallets automatically (prd
        // §207) — reflect that in the catalog every foreground: connected
        // while a wallet is watched, dropped when the last one goes.
        store.reconcileWalletSeats()
        if !WalletStore.shared.addresses.isEmpty {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await WalletIngest.refresh(context: context)
            }
            // The wallet's value-sample + faces pass (2026-07-15): fetch the
            // full holdings so a sample is recorded from a plain foreground on
            // Home, not only from the Wallet screen. Holdings sample-throttle
            // at 4h. Faces resolve here too, so a wallet wears its ENS avatar
            // before you ever open its screen.
            let s2 = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s2)
                _ = await WalletIngest.topHoldingsByWallet()
                await WalletStore.shared.loadAvatars()
            }
        }
        // Not an ingest — the watchlist's 24h pulse for the feed-row
        // sparkline. Exits instantly when no tokens are watched.
        let s = slot(); Task { @MainActor in
            await BridgeRefresh.stagger(s)
            await TokenPulse.shared.refresh(context: context)
        }
        // Same shape for watched prediction markets (Kalshi/Polymarket) —
        // without this a watched market goes dead the moment its own screen
        // closes, since nothing else ever refetches its odds. It is also
        // what stamps a settled market and fires its resolution moment.
        let sp = slot(); Task { @MainActor in
            await BridgeRefresh.stagger(sp)
            await PredictionPulse.shared.refresh(context: context)
        }
        for provider in MailProvider.allCases where provider.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await MailIngest.refresh(provider, context: context)
            }
            // Delete-sync: reconciles against what the server still has.
            // Own network round trip and its own hourly throttle, so it
            // runs as an independent staggered task rather than tacked onto
            // refresh above. `force` must ride along here too (2026-07-24
            // fix) — this call used to always default to `force: false`, so
            // heal's own hourly throttle silently ate a person's deliberate
            // pull-to-refresh: a mail deleted in Mail.app kept reappearing
            // in Casberi for up to an hour after a pull that looked, from
            // the gesture, like it should have caught it immediately —
            // exactly the contract `force` exists to guarantee (see the
            // comment on `refreshAllConnected` above).
            let s2 = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s2)
                _ = await MailIngest.heal(provider, context: context, force: force)
            }
        }
        if SteamBridge.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await SteamIngest.refresh(context: context)
            }
        }
        if ObsidianStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                // nil means the vault couldn't be walked at all — moved,
                // renamed, or its permission lost. Say so, the way Files and
                // Mail do (prd §284): this used to be discarded, so a vault
                // that had gone unreadable went on showing its old notes while
                // every pull did nothing and no screen said why.
                guard await ObsidianIngest.refresh(context: context) != nil else {
                    store.markAttention("obsidian",
                        statusLine: "Couldn't read that vault — reconnect it to resume")
                    return
                }
                // Then the treemap terms off the words the sync just stored —
                // the Files ordering. Store-only and self-terminating, so it
                // can only ever trail the reader it reads.
                _ = await sweepTimed("obsidian.topics") {
                    await ScreenshotTopics.healTopics(source: "Obsidian", context: context)
                }
            }
        }
        if FilesStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                // nil means the folder couldn't be walked at all — moved,
                // renamed, or its permission lost. That used to be discarded
                // (`_ =`), so the room went on showing rows for files that
                // were no longer there while every pull silently did nothing
                // and nothing on any screen said why. Say it instead — the
                // honesty rule, and the same gap that made Mail read as
                // broken (prd §284).
                if await FilesIngest.refresh(context: context) == nil {
                    store.markAttention("files",
                        statusLine: "Couldn't read that folder — reconnect it to resume")
                }
            }
            // Thumbnails + OCR for the image files a sync already landed —
            // same throttle contract as Photos' heal above.
            if force || BridgeRefresh.dueForHeal("files") {
                let s2 = slot(); Task { @MainActor in
                    await BridgeRefresh.stagger(s2)
                    _ = await FilesIngest.heal(context: context)
                    // Then the treemap terms off whatever OCR text the heal
                    // (and prior passes) have written — the Photos ordering
                    // (2026-08-02). Store-only and self-terminating, so
                    // riding the heal's throttle costs nothing: topics can
                    // only ever trail the OCR they read.
                    _ = await sweepTimed("files.topics") { await ScreenshotTopics.healTopics(source: "Files", context: context) }
                }
            }
        }
        if DropboxStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await DropboxIngest.refresh(context: context)
            }
        }
        if SlackAuth.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await SlackIngest.refresh(context: context)
            }
        }
        if TwitchAuth.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await TwitchIngest.refresh(context: context)
            }
        }
        // Spotify was never in this sweep at all — its only caller was its own
        // setup screen's `onAppear`, so liked songs arrived when you went to
        // look at the connect screen and at no other moment. The connected row
        // says "liked songs land in your feed", and for a person who connected
        // once and never returned to that screen, they did not.
        if SpotifyAuth.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await SpotifyIngest.refresh(context: context)
            }
        }
        if VibenetWatch.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                // THE ROOM IS COMPOSED ON THE SWEEP (prd §507), which it never
                // was: `VibenetRoomSource.compose()` had exactly ONE caller in
                // the whole app — the address book screen's own load — so the
                // feed's head, the crown, the sparkline and every reading on
                // the card were as fresh as the last time somebody happened to
                // open that screen. §468 gave the card a "when this was read"
                // line precisely because the snapshot could be days old; this
                // is the other half of that fix.
                //
                // The landing then reads the composed room instead of asking
                // the chain again for the transfers, policy runs and creation
                // it has just fetched.
                let room = await VibenetRoomSource.compose()
                _ = await VibenetEvents.land(context: context, room: room)
            }
        }
        // Hegotá lands NO `Thing` — every reading is live state on the room,
        // the `WalletDeFi` shape. A devnet test address has no news: no row a
        // screenshot would reference, nothing to search for later, and a
        // balance that is test ETH. So the sweep refreshes the room's state
        // and inserts nothing into the corpus.
        if HegotaWatch.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                await HegotaLiveState.shared.refresh()
            }
        }
        if OpenSeaStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await OpenSeaIngest.refresh(context: context)
            }
        }
        if TrendingStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await TrendingIngest.refresh(context: context)
            }
        }
        if X402Store.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await X402Ingest.refresh(context: context)
                // The second act: a seller's own page for its picture. A
                // network pass, so it goes behind `dueForHeal` exactly like
                // Instagram's captions and TikTok's faces — a bounded slice per
                // interval, self-terminating once every seller has been asked
                // once. Under no deadline, unlike Snapchat's expiring memories.
                if BridgeRefresh.dueForHeal("x402.faces") {
                    _ = await X402Faces.heal(context: context)
                }
            }
        }
        if HuggingFaceStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await HuggingFaceIngest.refresh(context: context)
            }
        }
        // Radicle (prd §400). A quiet pass is one `GET /repos/:rid` per
        // watched repo — the snapshot diff decides whether walking patches or
        // issues is worth a request at all — so this is cheap to run every
        // foreground even against a volunteer-run seed.
        if RadicleStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await RadicleIngest.refresh(context: context)
            }
        }
        // What became of the pull request a Cursor agent opened (2026-08-08,
        // prd §340). Its own line rather than a rider on the Cursor bridge,
        // because it spends the GITHUB token: it is gated on both seats being
        // connected, and `reconcile` re-checks the token itself so a
        // disconnect between the two reads can't fire a keyless request.
        //
        // Behind `dueForHeal` like x402's faces and Instagram's captions — a
        // PR merges on human time, not on foreground time, so asking on every
        // activation would spend a request per open PR to learn nothing.
        if TokenVault.get(TokenBridge.cursor.tokenKey)?.isEmpty == false,
           TokenVault.get(TokenBridge.github.tokenKey)?.isEmpty == false,
           BridgeRefresh.dueForHeal("cursor.pullRequests") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await CursorPullRequests.reconcile(context: context)
            }
        }
        // npm and PyPI are keyless watch lists, so — like Hugging Face and
        // GeckoTerminal above — they need their own line here rather than
        // riding `TokenBridge.allCases`. One slot each: they are separate
        // seats a person connects independently, and the steady-state cost of
        // each is one small request per watched package.
        for registry in PackageRegistry.allCases where PackageStore.shared.connected(registry) {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await PackageIngest.refresh(registry, context: context)
            }
        }
        // Stocktwits — the watch lives in the corpus (the thing IS the
        // watch); the seat gates the foreground poll so a person who never
        // connected it doesn't pay the watched-tickers fetch every
        // foreground, and a disconnected seat stays disconnected.
        // Instagram imports nothing on a foreground — it has no live read at
        // all (prd §245). What it does have is unfinished local work: the
        // topic terms behind the room's "What you write about" map, lifted off
        // captions and comments already in the store. Bounded per pass, so a
        // years-deep import finishes over a few opens rather than blocking the
        // one it landed on, and self-terminating once every note is stamped.
        // Its OTHER unfinished local work is captions (prd §245 amendment):
        // saves and likes land as a handle and a permalink, and one keyless
        // request each turns them into the post's own words. That one IS a
        // network pass, so unlike the topic map it goes behind `dueForHeal` —
        // at most once per `healInterval`, `perPass` rows at a time, paced,
        // and self-terminating once every row carries its caption.
        // The chat imports' topic map (2026-08-08, prd §340). `ScreenshotTopics
        // .topicSource` and `FeedInsight.topicMap` both gained cases for these
        // three rooms the same day their transcripts started landing — and
        // both would have been reachable-but-never-reached without this, the
        // exact §313 X finding: a registry entry nothing calls into is a
        // no-op indistinguishable from having nothing to say. No network
        // component, unlike Instagram's captions — the transcript these terms
        // are read from already lands at import, so this is purely a
        // `content`-in-store operation like Files' and Obsidian's.
        for (seatID, source) in [("gpt", "ChatGPT"), ("claude", "Claude"), ("gemini", "Gemini"),
                                 (ClaudeCodeImport.seatID, ClaudeCodeImport.source)]
        where connected(seatID) {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await sweepTimed("\(seatID).topics") {
                    await ScreenshotTopics.healTopics(source: source, context: context)
                }
            }
        }
        // The two journal importers, 2026-08-17 (prd §398) — the chat block's
        // shape one room over, and reachable for the same reason: neither has a
        // live read, so the only work a foreground can do for them is on words
        // already in the store. Free (no network, no request), self-terminating
        // once `topicsAt` is stamped on every entry.
        //
        // It runs HERE and not only at import because a re-import cannot do it:
        // both importers dedupe on `sourceRef`, so every entry already in the
        // corpus is skipped before its text is ever looked at — the §320
        // Obsidian lesson, and the reason years of already-imported entries
        // would otherwise never appear in the map this pass gave these rooms.
        for (seatID, source) in [("dayone", "Day One"), ("journal", "Apple Journal")]
        where connected(seatID) {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await sweepTimed("\(seatID).topics") {
                    await ScreenshotTopics.healTopics(source: source, context: context)
                }
            }
        }
        if connected("instagram") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await sweepTimed("instagram.topics") { await ScreenshotTopics.healTopics(source: "Instagram", context: context) }
                if BridgeRefresh.dueForHeal("instagram.captions") {
                    _ = await InstagramCaptions.heal(context: context)
                }
            }
        }
        // TikTok imports nothing on a foreground either — it has no live read
        // at all (prd §279). Its unfinished local work is FACES: saves and
        // likes land as a bare link, and one keyless oEmbed request each turns
        // one into the video's caption, creator and cover. That is a network
        // pass, so it goes behind `dueForHeal` exactly like Instagram's
        // captions — at most once per `healInterval`, a bounded slice at a
        // time, self-terminating once every row has been named.
        //
        // No topic-map heal beside it, unlike Instagram: TikTok's own writing
        // is split across two kinds (captions ride the `.link` rows of your
        // posts, comments are `.note`s), and `FeedInsight.topicMap` reads one
        // kind. A map labelled "what you write about" that silently covered
        // half the writing would be exactly the fake status §245 forbids.
        if connected("tiktok"), BridgeRefresh.dueForHeal("tiktok.faces") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await sweepTimed("tiktok.faces") { await TikTokImport.fetchFaces(limit: 60, context: context) }
            }
        }
        // X has no live read either (prd §280) and carries BOTH kinds of
        // unfinished local work, so it takes Instagram's shape and TikTok's in
        // one block (2026-08-05).
        //
        // TOPICS are free — they read `content` that is already stored — so
        // they run every foreground, unthrottled, and drain a large archive
        // over a few opens. Before this the only caller was the import screen
        // itself, one bounded pass at the moment of import, which for a
        // multi-thousand-post archive meant the map saw the first slice and
        // never the rest.
        //
        // FACES are a request each, so they go behind `dueForHeal` like the
        // other two. They name the AUTHOR of a liked post, which the archive
        // itself never carries — see `XArchiveImport.fetchFaces`.
        if connected("x") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await sweepTimed("x.topics") { await ScreenshotTopics.healTopics(source: "X", context: context) }
                // The words the room draws, for rows landed before it had a
                // shape to draw them in (2026-08-06). Free like topics — a
                // copy between fields already in the store — and one-shot, so
                // it costs a `bool(forKey:)` once it has drained. It runs
                // here rather than at import because a re-import can't do it:
                // `landTweets` skips a ref it has already seen.
                _ = await sweepTimed("x.healRoom") { await XArchiveImport.healRoom(context: context) }
                // The door back to X, for rows landed before they had one
                // (2026-08-18, prd §396). Free, one-shot and its own key —
                // `healRoom` has already drained wherever this is needed.
                _ = await sweepTimed("x.healLinks") { await XArchiveImport.healLinks(context: context) }
                if BridgeRefresh.dueForHeal("x.faces") {
                    _ = await sweepTimed("x.faces") { await XArchiveImport.fetchFaces(limit: 60, context: context) }
                }
            }
        }
        if connected("stocktwits") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await StocktwitsIngest.refresh(context: context)
            }
        }
        if connected("walletbeat") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await WalletbeatIngest.refresh(context: context)
            }
        }
        // ENS (prd §534) — the watch lives in the corpus (the thing IS the
        // follow), the seat gates the foreground poll the Stocktwits way: a
        // person who never connected it pays nothing, and a disconnected seat
        // stays disconnected.
        if connected("ens") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ENSIngest.refresh(context: context)
            }
        }
        if connected("l2beat") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await L2beatIngest.refresh(context: context)
            }
        }
        // CardPointers (prd §420). Gated on the SUBSCRIPTION as well as the
        // seat: every tool there refuses an account without CardPointers+, so
        // a sweep for one is a guaranteed round trip to be told no, on every
        // foreground, forever. `CardPointersIngest.refresh` re-checks the same
        // thing — this is the cheap gate, not the only one.
        if connected("cardpointers"), CardPointersAuth.isPro {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await CardPointersIngest.refresh(context: context)
            }
        }
        if ShopifyStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ShopifyIngest.refresh(context: context)
            }
        }
        if DealsStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await DealsIngest.refresh(context: context)
            }
        }
        // Every slot is now dispatched, so the pass's own dispatch window is
        // known exactly — tell the clock, or it closes the pass in the quiet
        // between two widely-staggered slots and reports half a sweep. Only
        // measurable here: `nextSlot` is this pass's real slot count, which
        // depends on what this person has connected.
        SweepClock.holdPass(for: .milliseconds(leadInMs + nextSlot * slotSpacingMs))
        // (`nextSlot` is the count, so this is the delay the NEXT slot would
        // have had — one spacing past the last real one, which is the margin
        // we want anyway.)
    }
}
