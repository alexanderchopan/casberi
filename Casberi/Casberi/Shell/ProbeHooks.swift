#if DEBUG
import Foundation
import SwiftData
import Photos
import UIKit

/// The launch-arg connect-and-sync probes: `-chatgptImport <path>`,
/// `-claudeImport <path>`,
/// `-tokenBridge "<Name>:<token>"`, `-fcName <username>`, `-bskyHandle
/// <handle>`, `-rssFeed <url>`. Each reads one UserDefaults key a `simctl
/// launch` arg set, performs the connect, and NSLogs its result — one shape,
/// one loop, so a new headless bridge test is one row. RootShell calls
/// `runAll` once on launch.
@MainActor
enum ProbeHooks {
    static func runAll(context: ModelContext) {
        NSLog("[Casberi] probeArgs: %@",
              ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))
        for hook in hooks {
            guard let value = UserDefaults.standard.string(forKey: hook.key) else { continue }
            hook.run(value, context)
        }
    }

    private struct Hook {
        let key: String
        let run: @MainActor (String, ModelContext) -> Void
    }

    private static let hooks: [Hook] = [
        // `-chatgptImport <path>` imports a conversations.json from disk.
        Hook(key: "chatgptImport") { path, context in
            guard let data = FileManager.default.contents(atPath: path) else { return }
            let summary = ChatGPTImport.run(data: data, context: context)
            NSLog("ChatGPT probe: %d imported, %d skipped, failed=%d",
                  summary.imported, summary.skipped, summary.failed ? 1 : 0)
        },
        // `-claudeImport <path>` imports a Claude conversations.json from disk.
        Hook(key: "claudeImport") { path, context in
            guard let data = FileManager.default.contents(atPath: path) else { return }
            let summary = ClaudeImport.run(data: data, context: context)
            NSLog("Claude probe: %d imported, %d skipped, failed=%d",
                  summary.imported, summary.skipped, summary.failed ? 1 : 0)
        },
        // `-geminiImport <path>` imports a Google Takeout MyActivity.json
        // (Gemini Apps) from disk.
        Hook(key: "geminiImport") { path, context in
            guard let data = FileManager.default.contents(atPath: path) else { return }
            let summary = GeminiImport.run(data: data, context: context)
            NSLog("Gemini probe: %d imported, %d skipped, failed=%d",
                  summary.imported, summary.skipped, summary.failed ? 1 : 0)
        },
        // `-dayoneImport <path>` imports a Day One export .json from disk.
        Hook(key: "dayoneImport") { path, context in
            guard let data = FileManager.default.contents(atPath: path) else { return }
            let summary = DayOneImport.run(data: data, context: context)
            NSLog("Day One probe: %d imported, %d skipped, failed=%d",
                  summary.imported, summary.skipped, summary.failed ? 1 : 0)
        },
        // `-journalImport <path>` imports an unzipped Apple Journal export folder.
        Hook(key: "journalImport") { path, context in
            let summary = JournalImport.run(folder: URL(fileURLWithPath: path), context: context)
            NSLog("Journal probe: %d imported, %d skipped, failed=%d",
                  summary.imported, summary.skipped, summary.failed ? 1 : 0)
        },
        // `-tokenBridge "<Name>:<token>"` connects a token bridge headlessly.
        Hook(key: "tokenBridge") { spec, context in
            guard let colon = spec.firstIndex(of: ":"),
                  let bridge = TokenBridge(rawValue: String(spec[..<colon])) else { return }
            TokenVault.set(String(spec[spec.index(after: colon)...]), for: bridge.tokenKey)
            Task { @MainActor in
                let n = await TokenIngest.refresh(bridge, context: context)
                NSLog("Token probe (%@): %@ new things", bridge.rawValue,
                      n.map(String.init) ?? "FAILED")
            }
        },
        // `-fcName <username>` connects Farcaster headlessly (appends, so a
        // comma-separated list watches several — dedupes, safe to re-fire).
        Hook(key: "fcName") { name, context in
            for n in name.split(separator: ",") { FarcasterStore.shared.add(String(n)) }
            Task { @MainActor in
                let n = await FarcasterIngest.refresh(context: context)
                NSLog("Farcaster probe: %@ new things", n.map(String.init) ?? "FAILED")
            }
        },
        // `-fcChannel <name[,name]>` follows Farcaster channels headlessly
        // (each name resolves via the channel directory, the way a username
        // resolves its fid) and syncs. Fire Farcaster probes one at a time —
        // the refresh's running guard makes a concurrent one report 0.
        Hook(key: "fcChannel") { names, context in
            Task { @MainActor in
                var followed = 0
                for n in names.split(separator: ",") {
                    if await FarcasterIngest.followChannel(String(n)) != nil { followed += 1 }
                }
                let n = await FarcasterIngest.refresh(context: context)
                NSLog("Farcaster channel probe: %d followed, %@ new things",
                      followed, n.map(String.init) ?? "FAILED")
            }
        },
        // `-fcLikes <username>` watches an account's LIKES (adding the
        // account if new) and syncs — liked casts land as things.
        Hook(key: "fcLikes") { name, context in
            let n = FarcasterStore.normalize(name)
            FarcasterStore.shared.add(n)
            FarcasterStore.shared.setLikes(true, for: n)
            Task { @MainActor in
                let added = await FarcasterIngest.refresh(context: context)
                NSLog("Farcaster likes probe: %@ new things",
                      added.map(String.init) ?? "FAILED")
            }
        },
        // `-fcMentions <username>` watches MENTIONS of an account and syncs.
        Hook(key: "fcMentions") { name, context in
            let n = FarcasterStore.normalize(name)
            FarcasterStore.shared.add(n)
            FarcasterStore.shared.setMentions(true, for: n)
            Task { @MainActor in
                let added = await FarcasterIngest.refresh(context: context)
                NSLog("Farcaster mentions probe: %@ new things",
                      added.map(String.init) ?? "FAILED")
            }
        },
        // `-fcReplies "<username>:<0xhash>"` fetches a cast's thread and
        // NSLogs the count + first line (the sheet's replies section,
        // headless — just the author's name and the full hash, no thing).
        Hook(key: "fcReplies") { spec, _ in
            guard let colon = spec.firstIndex(of: ":") else { return }
            let handle = FarcasterStore.normalize(String(spec[..<colon]))
            let hash = String(spec[spec.index(after: colon)...])
            Task { @MainActor in
                let replies = await FarcasterIngest.replies(handle: handle, hash: hash)
                NSLog("Farcaster replies probe: %d replies%@", replies.count,
                      replies.first.map { " — @\($0.handle): \(String($0.text.prefix(60)))" } ?? "")
            }
        },
        // `-pinterestUser <username>` connects Pinterest headlessly.
        Hook(key: "pinterestUser") { name, context in
            PinterestStore.shared.username = PinterestStore.normalize(name)
            Task { @MainActor in
                let n = await PinterestIngest.refresh(context: context)
                NSLog("Pinterest probe: %@ new things", n.map(String.init) ?? "FAILED")
            }
        },
        // `-bskyHandle <handle>` connects Bluesky headlessly (appends, so a
        // comma-separated list watches several — dedupes, safe to re-fire).
        Hook(key: "bskyHandle") { handle, context in
            for h in handle.split(separator: ",") { BlueskyStore.shared.add(String(h)) }
            Task { @MainActor in
                let n = await BlueskyIngest.refresh(context: context)
                NSLog("Bluesky probe: %@ new things", n.map(String.init) ?? "FAILED")
            }
        },
        // `-bskyMentions <handle>` watches MENTIONS of a Bluesky account
        // (adding it if new) and syncs — posts naming them land as things.
        Hook(key: "bskyMentions") { name, context in
            let h = BlueskyStore.normalize(name)
            BlueskyStore.shared.add(h)
            BlueskyStore.shared.setMentions(true, for: h)
            Task { @MainActor in
                let added = await BlueskyIngest.refresh(context: context)
                NSLog("Bluesky mentions probe: %@ new things",
                      added.map(String.init) ?? "FAILED")
            }
        },
        // `-bskyReplies "at://…"` fetches a post's thread by its at-uri (a
        // Bluesky thing's sourceRef is "bsky:<at-uri>") and NSLogs the count
        // + first line (the sheet's replies section, headless).
        Hook(key: "bskyReplies") { uri, _ in
            Task { @MainActor in
                let replies = await BlueskyIngest.replies(uri: uri)
                NSLog("Bluesky replies probe: %d replies%@", replies.count,
                      replies.first.map { " — @\($0.handle): \(String($0.text.prefix(60)))" } ?? "")
            }
        },
        // `-openSeaKey <key>` seeds a known-good OpenSea API key, so a headless
        // run can verify the feed without waiting on the mint endpoint's
        // 1-key-per-hour limit (the IP the sim shares is easily exhausted).
        // Runs before `-openSeaFeed` (list order) so the key is in place.
        Hook(key: "openSeaKey") { key, _ in
            OpenSeaStore.shared.setKey(key.trimmingCharacters(in: .whitespaces), expiry: nil)
            NSLog("OpenSea probe: key seeded (%d chars)", key.count)
        },
        // `-openSeaFeed <chains|YES>` connects OpenSea (a comma-separated chain
        // list, or YES for the defaults) and syncs — headless bridge test.
        Hook(key: "openSeaFeed") { spec, context in
            let list = spec.split(separator: ",")
                .compactMap { OpenSeaChain.from(String($0).trimmingCharacters(in: .whitespaces)) }
            if list.isEmpty { OpenSeaStore.shared.connectDefaults() }
            else { for c in list { OpenSeaStore.shared.add(c) } }
            Task { @MainActor in
                let n = await OpenSeaIngest.refresh(context: context)
                NSLog("OpenSea probe: %@ new drops", n.map(String.init) ?? "FAILED")
            }
        },
        // `-geckoTrending <chains|YES>` connects GeckoTerminal (a comma-separated
        // chain list like `ethereum,base,solana`, or YES for the defaults) and
        // syncs the current trending tokens — headless bridge test.
        Hook(key: "geckoTrending") { spec, context in
            let list = spec.split(separator: ",")
                .compactMap { TrendingChain.from(String($0).trimmingCharacters(in: .whitespaces)) }
            if list.isEmpty { TrendingStore.shared.connectDefaults() }
            else { for c in list { TrendingStore.shared.add(c) } }
            Task { @MainActor in
                let n = await TrendingIngest.refresh(context: context)
                NSLog("GeckoTerminal probe: %@ trending in", n.map(String.init) ?? "FAILED")
            }
        },
        // `-shopifyStore <url[,url]>` follows one or more Shopify stores and
        // syncs — headless bridge test. A blocked store logs FAILED honestly.
        Hook(key: "shopifyStore") { spec, context in
            for raw in spec.split(separator: ",") {
                ShopifyStore.shared.add(String(raw).trimmingCharacters(in: .whitespaces))
            }
            Task { @MainActor in
                let n = await ShopifyIngest.refresh(context: context)
                NSLog("Shopify probe: %@ new products", n.map(String.init) ?? "FAILED")
            }
        },
        // `-dealsFeed <sources|YES>` connects the Deals bridge (a comma list of
        // source ids, or YES for the defaults) and syncs — headless test.
        Hook(key: "dealsFeed") { spec, context in
            let list = spec.split(separator: ",")
                .compactMap { DealSource.from(String($0).trimmingCharacters(in: .whitespaces)) }
            if list.isEmpty { DealsStore.shared.connectDefaults() }
            else { for s in list { DealsStore.shared.add(s) } }
            Task { @MainActor in
                let n = await DealsIngest.refresh(context: context)
                NSLog("Deals probe: %@ new deals", n.map(String.init) ?? "FAILED")
            }
        },
        // `-barcodeProbe <code>` looks up a grocery barcode in Open Food Facts
        // and lands it — headless test of the keyless lookup.
        Hook(key: "barcodeProbe") { code, context in
            Task { @MainActor in
                guard let food = await OpenFoodFacts.lookup(code) else {
                    NSLog("Barcode probe: FAILED (not found)"); return
                }
                let landed = OpenFoodFacts.land(food, context: context) != nil
                NSLog("Barcode probe: %@ — %@ (%@)", food.name,
                      landed ? "landed" : "already saved", food.nutriscore ?? "no score")
            }
        },
        // `-priceProbe <url>` parses a product page's price/identity and NSLogs
        // it — the price-watch parser, headless (no thing landed).
        Hook(key: "priceProbe") { raw, _ in
            guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)) else { return }
            Task { @MainActor in
                if let meta = await ProductMeta.fetch(url) {
                    NSLog("Price probe: title=%@ price=%@ %@ image=%@",
                          meta.title ?? "-",
                          meta.priceValue.map { String($0) } ?? "nil",
                          meta.priceCurrency ?? "-",
                          (meta.image?.isEmpty == false) ? "yes" : "no")
                } else {
                    NSLog("Price probe: FAILED (no price or identity found)")
                }
            }
        },
        // `-watchToken <address|symbol|link>` watches a token headlessly.
        Hook(key: "watchToken") { query, context in
            Task { @MainActor in
                guard let token = await TokenWatch.resolve(query) else {
                    NSLog("Dexscreener probe: FAILED to resolve"); return
                }
                let added = TokenWatch.add(token, context: context)
                NSLog("Dexscreener probe: %@ (%@)", token.name,
                      added != nil ? "watched" : "already")
            }
        },
        // `-watchMarket <team|event query>` watches a Kalshi market headlessly.
        Hook(key: "watchMarket") { query, context in
            Task { @MainActor in
                guard let market = await KalshiWatch.resolve(query) else {
                    NSLog("Kalshi probe: FAILED to resolve"); return
                }
                let added = KalshiWatch.add(market, context: context)
                NSLog("Kalshi probe: %@ (%d%% · %@)", market.title,
                      Int((market.probability * 100).rounded()),
                      added != nil ? "watched" : "already")
            }
        },
        // `-userSearch "<bluesky|farcaster>:<query>"` runs the find-a-person
        // search and logs the hits — headless test of the search endpoints.
        Hook(key: "userSearch") { spec, _ in
            guard let colon = spec.firstIndex(of: ":") else { return }
            let which = String(spec[..<colon]).lowercased()
            let query = String(spec[spec.index(after: colon)...])
            Task { @MainActor in
                let hits = which.hasPrefix("f")
                    ? await UserSearch.farcaster(query)
                    : await UserSearch.bluesky(query)
                NSLog("User search probe (%@ '%@'): %d hits%@", which, query, hits.count,
                      hits.isEmpty ? "" : " — " + hits.map {
                          "\($0.displayName) @\($0.handle)"
                      }.joined(separator: ", "))
            }
        },
        // `-tokenSearch <query>` runs the token search and logs the matches.
        Hook(key: "tokenSearch") { query, _ in
            Task { @MainActor in
                let hits = await TokenWatch.search(query)
                NSLog("Token search probe ('%@'): %d hits%@", query, hits.count,
                      hits.isEmpty ? "" : " — " + hits.map {
                          "\($0.name) $\($0.symbol) (\($0.chain))"
                      }.joined(separator: ", "))
            }
        },
        // `-walletAddress <0x…>` (or `<0x…>|<Label>`) watches a wallet headlessly.
        Hook(key: "walletAddress") { spec, context in
            let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
            guard let address = parts.first else { return }   // "" crashed on parts[0]
            WalletStore.shared.add(address, label: parts.count > 1 ? parts[1] : "")
            Task { @MainActor in
                let n = await WalletIngest.refresh(context: context)
                NSLog("Wallet probe: %@ new", n.map(String.init) ?? "FAILED")
            }
        },
        // `-pinWallet YES` pins every currently-watched wallet's holdings
        // treemap to Home headlessly — pairs with `-walletAddress` for
        // testing that module. Pin is per-address now (2026-07-09).
        Hook(key: "pinWallet") { _, _ in
            for i in WalletStore.shared.addresses.indices {
                WalletStore.shared.addresses[i].pinnedToHome = true
            }
            NSLog("Pin-wallet probe: pinned %d address(es)", WalletStore.shared.addresses.count)
        },
        // `-unpinAll YES` removes every pinned app from Home — screenshot
        // verification of the no-pins state. (Pinning is per-APP now, so this
        // clears HomePinnedSources, not any thing flag.)
        Hook(key: "unpinAll") { _, _ in
            let store = HomePinnedSources.shared
            let sources = store.sources
            for source in sources { store.clear(source) }
            for source in HomePinnedSources.autoSocial { store.setHidden(source, true) }
            CorpusSignal.shared.bump()
            NSLog("Unpin probe: cleared %d pinned app(s)", sources.count)
        },
        // `-appleMusic YES` runs the real Apple Music connect+ingest and
        // logs the outcome (or the underlying MusicKit error).
        Hook(key: "appleMusic") { _, context in
            Task { @MainActor in
                let n = await AppleMusicIngest.connectAndIngest(context: context)
                NSLog("Apple Music probe: %@", n.map { "\($0) in" } ?? "FAILED (see error above)")
            }
        },
        // `-connectPhotos YES` runs the real Photos connect+ingest.
        Hook(key: "connectPhotos") { _, context in
            Task { @MainActor in
                guard let n = await ScreenshotIngest.connectAndIngest(context: context) else {
                    NSLog("Photos probe: FAILED (access denied)"); return
                }
                NSLog("Photos probe: connected, %d in", n)
            }
        },
        // `-reingestPhotos YES` calls the bare re-scan BridgeRefresh now
        // uses (no permission request) — headless test that a photo added
        // AFTER connect is picked up on the next pass (report 2026-07-09).
        Hook(key: "reingestPhotos") { _, context in
            let n = ScreenshotIngest.ingest(context: context)
            NSLog("Photos re-ingest probe: %d new", n)
        },
        // `-connectStrava YES` runs the Strava connect — the Health-store
        // read filtered to workouts Strava wrote (no Strava account
        // anywhere). On the sim the store is empty: expect "0 in".
        Hook(key: "connectStrava") { _, context in
            Task { @MainActor in
                guard let n = await HealthIngest.connectAndIngest(
                    context: context, healthOn: false, stravaOn: true,
                    counting: "Strava") else {
                    NSLog("Strava probe: FAILED (Health unavailable)"); return
                }
                NSLog("Strava probe: connected, %d in", n)
            }
        },
        // `-ghFeeds "stars,releases,gists"` sets which GitHub feeds are on
        // (comma list of feed keys or titles) — headless staging of the picker.
        Hook(key: "ghFeeds") { spec, _ in
            let names = spec.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let feeds = Set(GitHubFeed.allCases.filter {
                names.contains($0.rawValue.lowercased()) || names.contains($0.title.lowercased())
            })
            GitHubFeeds.shared.set(feeds)
            NSLog("GitHub feeds probe: enabled %@",
                  feeds.map(\.rawValue).sorted().joined(separator: ", "))
        },
        // `-ghFeedProbe "<feed>"` fetches one GitHub feed with the stored token
        // and logs the count — a bogus token logs FAILED (the honest 401 path),
        // no real token needed to verify the plumbing.
        Hook(key: "ghFeedProbe") { name, _ in
            let key = name.trimmingCharacters(in: .whitespaces).lowercased()
            guard let feed = GitHubFeed.allCases.first(where: {
                $0.rawValue.lowercased() == key || $0.title.lowercased() == key
            }) else { NSLog("GitHub feed probe: unknown feed %@", name); return }
            guard let token = TokenVault.get(TokenBridge.github.tokenKey) else {
                NSLog("GitHub feed probe: no token — connect GitHub first"); return
            }
            Task { @MainActor in
                guard let login = await GitHubFeedFetch.login(token: token) else {
                    NSLog("GitHub feed probe (%@): FAILED — token rejected", feed.rawValue); return
                }
                let things = await GitHubFeedFetch.fetch(feed, login: login, token: token)
                NSLog("GitHub feed probe (%@): %@", feed.rawValue,
                      things.map { "\($0.count) things" } ?? "FAILED")
            }
        },
        // `-ghGraphDemo YES` seeds a synthetic contribution year and pins +
        // fake-connects GitHub so the Home contribution-graph tile renders on
        // the simulator (no real account needed). Screenshot/staging only.
        Hook(key: "ghGraphDemo") { _, _ in
            UserDefaults.standard.set(true, forKey: "ghGraphDemo")
            if TokenVault.get(TokenBridge.github.tokenKey) == nil {
                TokenVault.set("demo", for: TokenBridge.github.tokenKey)
            }
            if !HomePinnedSources.shared.isPinned("GitHub") {
                HomePinnedSources.shared.toggle("GitHub")
            }
            CorpusSignal.shared.bump()
            NSLog("GitHub graph demo: seeded + pinned GitHub")
        },
        // `-ghDeviceProbe YES` runs the GitHub device-flow start request and
        // logs the outcome — with no client id it logs the honest unavailable
        // line (the setup screen shows paste-only in that state).
        Hook(key: "ghDeviceProbe") { _, _ in
            Task { @MainActor in
                guard GitHubDeviceFlow.isAvailable else {
                    NSLog("GitHub device probe: no client id — paste flow only")
                    return
                }
                let code = await GitHubDeviceFlow.start()
                NSLog("GitHub device probe: user_code=%@ interval=%d",
                      code?.userCode ?? "nil (start failed)", code?.interval ?? 0)
            }
        },
        // `-wipeAccessProbe YES` runs the Delete-access internals (vault-wide
        // credential wipe + MCP pairing reset) and logs before/after state —
        // the tray's confirm is the same code with consent in front.
        Hook(key: "wipeAccessProbe") { _, _ in
            let sampled = [TokenBridge.todoist.tokenKey, AgentProvider.anthropic.vaultKey]
            let before = sampled.filter { TokenVault.get($0) != nil }.count
            TokenVault.deleteAll()
            MCPPairing.reset()
            let after = sampled.filter { TokenVault.get($0) != nil }.count
            NSLog("Wipe access probe: sampled credentials %d before → %d after", before, after)
        },
        // `-intentProbe "<query>"` runs the Shortcuts intents' shared corpus
        // matcher (IntentCorpus.match — Search/Ask ground on it) and logs the
        // hits, so the intent path verifies without driving the Shortcuts app.
        Hook(key: "intentProbe") { query, _ in
            Task { @MainActor in
                let hits = (try? IntentCorpus.match(query, limit: 5)) ?? []
                NSLog("Intent probe: %d hits — %@", hits.count,
                      hits.map { "\($0.title) (\($0.source))" }.joined(separator: " · "))
            }
        },
        // `-writeProbe "todoist:<id>"` or `-writeProbe "<github issue/PR
        // url>"` performs the bridge write with the stored token and logs the
        // honest outcome — with no token it logs the not-connected line.
        Hook(key: "writeProbe") { spec, _ in
            Task { @MainActor in
                let write: BridgeWrite? = if spec.hasPrefix("todoist:") {
                    .todoistComplete(taskID: String(spec.dropFirst("todoist:".count)))
                } else if let t = BridgeWrites.githubTarget(in: spec) {
                    .githubClose(owner: t.owner, repo: t.repo, number: t.number)
                } else { nil }
                guard let write else {
                    NSLog("Write probe: unparseable spec %@", spec)
                    return
                }
                let outcome = await BridgeWrites.perform(write)
                NSLog("Write probe: ok=%d — %@", outcome.ok ? 1 : 0, outcome.line)
            }
        },
        // `-seedThing "Source:delay"` lands a link thing for that source
        // after the delay — flips the chip's "new" ring mid-visit exactly
        // the way a foreground sync does (motion verification).
        Hook(key: "seedThing") { spec, context in
            let parts = spec.split(separator: ":")
            guard let src = parts.first.map(String.init) else { return }
            let delay = parts.count > 1 ? Double(parts[1]) ?? 0 : 0
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                let t = Thing(kind: .link, title: "Ring demo", source: src,
                              sourceRef: "probe:ring-demo-\(UUID().uuidString)")
                context.insert(t)
                try? context.save()
                NSLog("Seed thing probe: landed for %@", src)
            }
        },
        // `-clearSeedThings YES` deletes every thing a `-seedThing` probe
        // planted (sourceRef "probe:ring-demo-…") — staging cleanup so demo
        // recordings don't show "Ring demo" litter.
        Hook(key: "clearSeedThings") { _, context in
            let all = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
            let litter = all.filter { $0.sourceRef?.hasPrefix("probe:ring-demo") == true }
            for t in litter { context.delete(t) }
            try? context.save()
            NSLog("Seed-thing cleanup probe: deleted %d", litter.count)
        },
        // `-healPhotos YES` runs the screenshot heal sweep (thumbnails +
        // confirmed-gone removal) and logs both counts. `-healPhotos
        // seed-dangling` first plants a screenshot thing with a ref no
        // asset will ever match — the removal path, end to end.
        Hook(key: "healPhotos") { spec, context in
            Task { @MainActor in
                if spec == "seed-dangling" {
                    let ghost = Thing(kind: .screenshot, title: "Screenshot",
                                      source: "Photos",
                                      sourceRef: "phasset:DEAD-BEEF-PROBE/L0/001")
                    context.insert(ghost)
                    try? context.save()
                    NSLog("Photos heal probe: dangling thing seeded")
                }
                let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                let r = await ScreenshotIngest.heal(context: context)
                let all = ((try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == "Photos" }))) ?? [])
                    .filter { $0.kind == .screenshot }
                NSLog("Photos heal probe: auth=%d, %d thumbed, %d OCRed, %d removed, %d/%d have stored thumbs, %d carry text",
                      auth.rawValue, r.thumbed, r.ocred, r.removed,
                      all.filter { $0.previewImageData != nil }.count, all.count,
                      all.filter { !$0.content.isEmpty }.count)
            }
        },
        // `-setHomeBanner <color-name|photo>` sets the Home cover
        // headlessly — screenshot verification of the picker's two kinds.
        Hook(key: "setHomeBanner") { spec, _ in
            if spec == "clear" {
                HomeBackgroundStore.shared.clear()
                NSLog("Home background probe: cleared")
            } else if let swatch = HomeBackgroundStore.swatches.first(where: { $0.name == spec }) {
                HomeBackgroundStore.shared.setColor(swatch)
                NSLog("Home background probe: color %@", spec)
            } else {
                let size = CGSize(width: 400, height: 400)
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = 1
                let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                    UIColor.systemBlue.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                }
                HomeBackgroundStore.shared.setPhoto(img)
                NSLog("Home background probe: photo")
            }
        },
        // `-twitchAuth YES` starts the device flow headlessly: NSLogs the
        // code for the person to approve at twitch.tv/activate, polls up to
        // five minutes, then runs the first sync. Sim verification only.
        Hook(key: "twitchAuth") { _, context in
            Task { @MainActor in
                guard let code = await TwitchAuth.startDeviceFlow() else {
                    NSLog("Twitch probe: device flow FAILED"); return
                }
                NSLog("Twitch probe: enter code %@ at twitch.tv/activate", code.userCode)
                let ok = await TwitchAuth.poll(code, attempts: 60)
                guard ok else { NSLog("Twitch probe: NOT approved"); return }
                let n = await TwitchIngest.refresh(context: context)
                NSLog("Twitch probe: connected, %@ live", n.map(String.init) ?? "FAILED")
            }
        },
        // `-obsidianVault <path>` points the vault at a folder headlessly
        // (an in-sandbox path needs no security scope — sim testing only).
        Hook(key: "obsidianVault") { path, context in
            guard ObsidianStore.shared.setVault(url: URL(fileURLWithPath: path)) else {
                NSLog("Obsidian probe: bookmark FAILED"); return
            }
            Task { @MainActor in
                let n = await ObsidianIngest.refresh(context: context)
                NSLog("Obsidian probe: %@ new", n.map(String.init) ?? "FAILED")
            }
        },
        // `-steamBridge "<key>:<profile>"` connects Steam headlessly.
        Hook(key: "steamBridge") { spec, context in
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            TokenVault.set(parts[0], for: SteamBridge.tokenKey)
            SteamBridge.profile = parts[1]
            Task { @MainActor in
                let n = await SteamIngest.refresh(context: context)
                NSLog("Steam probe: %@ new", n.map(String.init) ?? "FAILED")
            }
        },
        // `-mailBridge "<icloud|gmail>:<address>:<app-password>"` connects a
        // mail account headlessly.
        Hook(key: "mailBridge") { spec, context in
            let parts = spec.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3,
                  var provider = MailProvider.allCases.first(where: {
                      $0.bridgeID == parts[0] || $0.rawValue.lowercased().contains(parts[0].lowercased())
                  }) else { return }
            provider.address = parts[1]
            TokenVault.set(parts[2], for: provider.passwordKey)
            Task { @MainActor in
                let n = await MailIngest.refresh(provider, context: context)
                NSLog("Mail probe (%@): %@ new", provider.rawValue, n.map(String.init) ?? "FAILED")
            }
        },
        // `-rssFeed <url>` follows a feed and syncs — headless bridge test.
        Hook(key: "rssFeed") { url, context in
            RSSStore.shared.add(url)
            Task { @MainActor in
                let n = await RSSIngest.refresh(context: context)
                NSLog("RSS probe: %@ new things", n.map(String.init) ?? "FAILED")
            }
        },
        // `-pinSource <source>` pins that APP to Home — headless test of the
        // pinned app tile (waits up to 5s for an async ingest hook like
        // -watchToken to land the source's first thing, since a pinned app
        // with no things shows no tile).
        Hook(key: "pinSource") { source, context in
            Task { @MainActor in
                for _ in 0..<25 {
                    var descriptor = FetchDescriptor<Thing>(
                        predicate: #Predicate<Thing> { $0.source == source },
                        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
                    )
                    descriptor.fetchLimit = 1
                    if (try? context.fetch(descriptor))?.first != nil {
                        HomePinnedSources.shared.toggle(source)
                        CorpusSignal.shared.bump()
                        NSLog("Pin probe: pinned app '%@'", source)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                NSLog("Pin probe: FAILED to find a thing from %@", source)
            }
        },
    ]
}
#endif
