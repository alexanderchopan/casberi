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
    /// Launch args whose VALUE is a credential. `probeArgs:` prints the args
    /// verbatim so a stale/missing binary is obvious — but that printed the
    /// real Venice/Anthropic/GitHub keys straight into the sim log, defeating
    /// the whole point of keeping them in the Keychain and inlining them at
    /// use-time (scripts/dev-keys.sh). The flag still prints; the value doesn't.
    ///
    /// This is a denylist, so it FAILS OPEN: a new keyed probe leaks until its
    /// flag lands here. Add the flag in the same commit as the probe.
    private static let secretArgKeys: Set<String> = [
        "-byokKey", "-openSeaKey", "-tokenBridge", "-wcProjectID", "-ghClientID",
    ]

    /// `-byokKey venice:vk-abc` → `-byokKey venice:‹redacted›`, but
    /// `-byokKey sk-ant-x:y` → `-byokKey ‹redacted›`.
    ///
    /// A prefix survives ONLY when it's a name we can VERIFY isn't a secret —
    /// a real `AgentProvider` case, a real `BridgeCatalog` offer. Trusting the
    /// first colon instead would leak: `-byokKey` also takes a bare key (bare =
    /// anthropic), `-openSeaKey` and `-wcProjectID` have no prefix grammar at
    /// all, and any of those values containing a colon would print everything
    /// before it — half the credential this function exists to hide.
    private static func redactedValue(for flag: String, _ value: String) -> String {
        let redacted = "‹redacted›"
        guard let colon = value.firstIndex(of: ":") else { return redacted }
        let prefix = String(value[value.startIndex..<colon])
        let prefixIsKnownName: Bool
        switch flag {
        case "-byokKey":     prefixIsKnownName = AgentProvider(rawValue: prefix) != nil
        case "-tokenBridge": prefixIsKnownName = BridgeCatalog.offers.contains { $0.name == prefix }
        default:             prefixIsKnownName = false
        }
        return prefixIsKnownName ? "\(prefix):\(redacted)" : redacted
    }

    static func redactedArgs(_ args: [String]) -> [String] {
        var out: [String] = []
        var flagAwaitingSecret: String?
        for arg in args {
            if let flag = flagAwaitingSecret {
                flagAwaitingSecret = nil
                out.append(redactedValue(for: flag, arg))
                continue
            }
            out.append(arg)
            if secretArgKeys.contains(arg) { flagAwaitingSecret = arg }
        }
        return out
    }

    static func runAll(context: ModelContext) {
        NSLog("[Casberi] probeArgs: %@",
              redactedArgs(Array(ProcessInfo.processInfo.arguments.dropFirst()))
                .joined(separator: " "))
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
            Task { @MainActor in
                let summary = await JournalImport.run(folder: URL(fileURLWithPath: path), context: context)
                NSLog("Journal probe: %d imported, %d skipped, failed=%d",
                      summary.imported, summary.skipped, summary.failed ? 1 : 0)
            }
        },
        // `-bookmarksImport <path>` imports a Netscape Bookmark File Format
        // export (.html) from Safari or Chrome — lands ALL entries headlessly
        // (the UI's Reading-List-only split is a person's choice, not a probe's).
        Hook(key: "bookmarksImport") { path, context in
            guard let data = FileManager.default.contents(atPath: path),
                  let parsed = BookmarksImport.parse(data: data) else { return }
            let summary = BookmarksImport.land(parsed.entries, context: context)
            NSLog("Bookmarks probe: %d imported, %d skipped, failed=%d, readingList=%d",
                  summary.imported, summary.skipped, summary.failed ? 1 : 0, parsed.readingListCount)
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
        // `-oneclawProbe YES` walks the 1Claw access read with the STORED key
        // (connect first via `-tokenBridge "1Claw:<key>"`), logging each step
        // — scopes, vaults, per-vault grant counts or the honest "unreadable"
        // — so a missing grant table and an empty one stop looking identical.
        Hook(key: "oneclawProbe") { _, _ in
            Task { await OneClawFetch.probe() }
        },
        // `-privacyProbe YES` reads the STORED Privacy key (connect first via
        // `-tokenBridge "Privacy:<key>"`) and NSLogs the RAW transactions
        // shape — HTTP status, envelope keys, count, and the first txn's
        // fields — the measure tool for an UNMEASURED API. Reads only.
        Hook(key: "privacyProbe") { _, _ in
            Task { await PrivacyFetch.probe() }
        },
        // `-posthogHost <host>` / `-posthogProject <id>` — the two settings a
        // fresh connect would pick by hand, so a headless run can reach the
        // scoped reads. Declared BEFORE `-posthogProbe`: hooks run in list
        // order, and the probe must read a configured account.
        Hook(key: "posthogHost") { host, _ in
            PostHogAccount.host = host
            NSLog("[Casberi] posthogHost: %@", host)
        },
        Hook(key: "posthogProject") { id, _ in
            PostHogAccount.projectID = id
            NSLog("[Casberi] posthogProject: %@", id)
        },
        // `-posthogWatch "<event[,event]>"` — watch metrics headlessly, so a
        // probe run has something to read (the watch IS the thing, so this is
        // the same act the omnibox performs).
        Hook(key: "posthogWatch") { spec, context in
            for name in spec.split(separator: ",") {
                PostHogWatch.add(String(name).trimmingCharacters(in: .whitespaces),
                                 context: context)
            }
            NSLog("[Casberi] posthogWatch: %@",
                  PostHogWatch.watchedEvents(context: context).joined(separator: ","))
        },
        // `-posthogProbe YES` reads the STORED PostHog key (connect first via
        // `-tokenBridge "PostHog:<key>"` plus `-posthogProject`) and NSLogs
        // the RAW shapes — per-endpoint status, resolved projects, annotation
        // count, and each watched metric's series/total/next-rung — the
        // measure tool for an UNMEASURED API. Reads only.
        Hook(key: "posthogProbe") { _, context in
            Task { await PostHogIngest.probe(context: context) }
        },
        // `-posthogSeed "<event>:<c,c,c>[|total]"` — plant a metric's reading
        // without a live project, so the roster disc, the milestone ring, the
        // crossing and the SILENCE branch all verify headlessly. Silence
        // otherwise needs a real event to really stop firing for two days,
        // which no probe can wait for.
        Hook(key: "posthogSeed") { spec, _ in
            let parts = spec.split(separator: "|", maxSplits: 1)
            guard let head = parts.first, let colon = head.lastIndex(of: ":") else { return }
            let event = String(head[head.startIndex..<colon])
            let series = head[head.index(after: colon)...]
                .split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            var metric = PostHogState.get(event)
            metric.series = series
            metric.total = parts.count > 1 ? (Int(parts[1]) ?? series.reduce(0, +))
                                           : series.reduce(0, +)
            metric.fetchedAt = .now
            PostHogState.set(event, metric)
            NSLog("[Casberi] posthogSeed: %@ days=%d total=%d next=%@",
                  event, series.count, metric.total,
                  PostHogIngest.formatted(PostHogMilestone.next(after: metric.total)))
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
                // Resurfaced is reported beside landed on purpose: a like of a
                // cast the corpus already holds lands NOTHING, so "0 new things"
                // is what a working pass says when the whole job was moving a
                // held post back into view.
                NSLog("Farcaster likes probe: %@ new things, %d resurfaced",
                      added.map(String.init) ?? "FAILED", FarcasterIngest.resurfaced)
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
        // `-fcHealProbe YES` runs the delete-sync reconcile headlessly over
        // already-watched accounts and NSLogs how many stale casts it
        // removed. `force: true` bypasses heal's own hourly throttle.
        Hook(key: "fcHealProbe") { _, context in
            Task { @MainActor in
                let n = await FarcasterIngest.heal(context: context, force: true)
                NSLog("Farcaster heal probe: %d removed", n)
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
        // `-bskyFeed <query|at-uri>` follows a Bluesky FEED headlessly and
        // syncs — Bluesky's answer to a Farcaster channel (2026-07-16). A bare
        // word searches the feed directory and takes the top hit; an at-uri
        // follows that feed exactly.
        Hook(key: "bskyFeed") { query, context in
            Task { @MainActor in
                let feed = await BlueskyIngest.followFeed(query)
                let n = await BlueskyIngest.refresh(context: context)
                NSLog("Bluesky feed probe: %@ followed, %@ new things",
                      feed?.name ?? "NONE", n.map(String.init) ?? "FAILED")
            }
        },
        // `-followsProbe "<Bluesky|Farcaster>:<handle>"` reads that account's
        // follow graph and reports what came back (2026-07-16, prd 87) — the
        // read behind the "Who they follow" picker, headless. It WATCHES
        // NOBODY: the graph is a read, and the taps that watch are the
        // person's, so a probe that imported would be testing a path the app
        // doesn't have. `truncated` is the honesty check — the sheet's "first
        // N" line is only true if this says so.
        Hook(key: "followsProbe") { spec, _ in
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                NSLog("followsProbe: expected \"<Bluesky|Farcaster>:<handle>\", got %@", spec)
                return
            }
            Task { @MainActor in
                let graph = await SocialFollows.graph(source: parts[0], handle: parts[1])
                // `reachable` is the one that can't be inferred from the count:
                // 0 people means "follows nobody" ONLY if the read got through.
                NSLog("followsProbe %@ @%@: %d follows, truncated=%@, reachable=%@",
                      parts[0], parts[1], graph.people.count,
                      graph.truncated ? "YES" : "no",
                      graph.reachable ? "yes" : "NO")
                // A count alone can't tell a hydrated row from an empty one —
                // the picker needs a face and a name per person, so print what
                // the rows would actually wear.
                let faces = graph.people.filter { $0.avatarURL != nil }.count
                let named = graph.people.filter { $0.displayName != $0.handle }.count
                NSLog("followsProbe hydration: %d with a face, %d with a display name",
                      faces, named)
                for p in graph.people.prefix(3) {
                    NSLog("followsProbe · %@ (@%@) fid=%@ face=%@",
                          p.displayName, p.handle, p.fid.map(String.init) ?? "nil",
                          p.avatarURL ?? "nil")
                }
            }
        },
        // `-starterPackProbe "<query>"` searches Bluesky starter packs and
        // reads the first hit's members (item 4, 2026-07-27) — the read
        // behind `StarterPackImportSheet`, headless. Both
        // `app.bsky.graph.searchStarterPacks` and `.getList` are keyless;
        // this is the live re-measure the standing discipline calls for
        // before leaning on a new keyless endpoint in a release build.
        Hook(key: "starterPackProbe") { query, _ in
            Task { @MainActor in
                let packs = await BlueskyStarterPacks.search(query)
                NSLog("starterPackProbe %@: %d packs", query, packs.count)
                for pack in packs.prefix(3) {
                    NSLog("starterPackProbe · %@ (by @%@)", pack.name, pack.creatorHandle)
                }
                guard let first = packs.first else { return }
                let members = await BlueskyStarterPacks.members(of: first)
                let faces = members.filter { $0.avatarURL != nil }.count
                NSLog("starterPackProbe first pack \"%@\": %d members, %d with a face",
                      first.name, members.count, faces)
                for m in members.prefix(3) {
                    NSLog("starterPackProbe member · %@ (@%@)",
                          m.displayName ?? m.handle, m.handle)
                }
            }
        },
        // `-socialProbe <Bluesky|Farcaster>` reports what the enrichment
        // actually landed across that source's corpus (2026-07-16) — how many
        // posts carry their full text, pictures, a quote, a parent, a context
        // marker — so the batch verifies headlessly instead of by eye. Also
        // prints the first enriched post, since a count can be right while the
        // content is wrong.
        Hook(key: "socialProbe") { source, context in
            Task { @MainActor in
                let all = (try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == source }))) ?? []
                let withText = all.filter { ($0.postText ?? "").isEmpty == false }
                let longer = withText.filter { ($0.postText ?? "").count > $0.title.count }
                NSLog("""
                      socialProbe %@: %d things, %d with full text (%d longer than title), \
                      %d with images, %d quoting, %d replying, %d marked, %d in a channel
                      """,
                      source, all.count, withText.count, longer.count,
                      all.filter { !$0.imageURLs.isEmpty }.count,
                      all.filter { $0.quote != nil }.count,
                      all.filter { $0.parent != nil }.count,
                      all.filter { $0.socialContext != nil }.count,
                      all.filter { $0.channelName != nil }.count)
                if let sample = longer.first ?? withText.first {
                    NSLog("socialProbe sample: title=%@ | postText=%@",
                          sample.title, sample.postText ?? "nil")
                }
                // `ref` is what makes a quote WALKABLE (its own thread) — a
                // card carrying a permalink but no ref opens to a dead end, so
                // the probe reports it rather than leaving it to a tap to find.
                NSLog("socialProbe walkable quotes: %d of %d",
                      all.filter { $0.quote?.ref != nil }.count,
                      all.filter { $0.quote != nil }.count)
                if let quoted = all.first(where: { $0.quote != nil }), let q = quoted.quote {
                    NSLog("socialProbe quote: @%@ (ref %@) said %@",
                          q.handle, q.ref ?? "NONE", q.text)
                    // The deep link to a RICH post — quote card, full text, the
                    // lot — so the sheet can be opened headlessly
                    // (`casberi://thing/<id>`) instead of hunting for a row to tap.
                    NSLog("socialProbe quoteThing: casberi://thing/%@",
                          quoted.id.uuidString)
                }
                if let replying = all.first(where: { $0.parent != nil }) {
                    NSLog("socialProbe replyThing: casberi://thing/%@",
                          replying.id.uuidString)
                }
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
        // `-bskyHealProbe YES` runs the delete-sync reconcile headlessly over
        // already-watched accounts/feeds and NSLogs how many stale posts it
        // removed. `force: true` bypasses heal's own hourly throttle.
        Hook(key: "bskyHealProbe") { _, context in
            Task { @MainActor in
                let n = await BlueskyIngest.heal(context: context, force: true)
                NSLog("Bluesky heal probe: %d removed", n)
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
        // `-nostrPubkey <npub|hex|name@domain[,...]>` connects Nostr headlessly
        // (appends, so a comma-separated list watches several — dedupes, safe
        // to re-fire).
        Hook(key: "nostrPubkey") { spec, context in
            for n in spec.split(separator: ",") { NostrStore.shared.add(String(n)) }
            Task { @MainActor in
                let n = await NostrIngest.refresh(context: context)
                NSLog("Nostr probe: %@ new things", n.map(String.init) ?? "FAILED")
            }
        },
        // `-nostrHashtag <tag[,tag]>` follows Nostr hashtags headlessly (no
        // resolve step, unlike a Farcaster channel — a hashtag is just
        // itself) and syncs.
        Hook(key: "nostrHashtag") { tags, context in
            Task { @MainActor in
                var followed = 0
                for t in tags.split(separator: ",") {
                    if NostrIngest.followHashtag(String(t)) != nil { followed += 1 }
                }
                let n = await NostrIngest.refresh(context: context)
                NSLog("Nostr hashtag probe: %d followed, %@ new things",
                      followed, n.map(String.init) ?? "FAILED")
            }
        },
        // `-nostrLikes <npub|hex|name@domain>` watches an account's
        // REACTIONS (adding the account if new) and syncs — reacted-to notes
        // land as things.
        Hook(key: "nostrLikes") { name, context in
            let n = NostrStore.normalize(name)
            NostrStore.shared.add(n)
            NostrStore.shared.setLikes(true, for: n)
            Task { @MainActor in
                let added = await NostrIngest.refresh(context: context)
                // Resurfaced beside landed on purpose — see the Farcaster
                // likes probe's own comment: a reaction to a note the corpus
                // already holds lands NOTHING new, so "0 new things" is what
                // a working pass says when the whole job was a resurface.
                NSLog("Nostr likes probe: %@ new things, %d resurfaced",
                      added.map(String.init) ?? "FAILED", NostrIngest.resurfaced)
            }
        },
        // `-nostrMentions <npub|hex|name@domain>` watches MENTIONS of an
        // account (`#p` tag) and syncs.
        Hook(key: "nostrMentions") { name, context in
            let n = NostrStore.normalize(name)
            NostrStore.shared.add(n)
            NostrStore.shared.setMentions(true, for: n)
            Task { @MainActor in
                let added = await NostrIngest.refresh(context: context)
                NSLog("Nostr mentions probe: %@ new things",
                      added.map(String.init) ?? "FAILED")
            }
        },
        // `-nostrHealProbe YES` runs the delete-sync reconcile headlessly
        // over already-watched accounts and NSLogs how many stale notes it
        // removed. `force: true` bypasses heal's own hourly throttle.
        Hook(key: "nostrHealProbe") { _, context in
            Task { @MainActor in
                let n = await NostrIngest.heal(context: context, force: true)
                NSLog("Nostr heal probe: %d removed", n)
            }
        },
        // `-nostrReplies <0xeventid>` fetches a note's thread by its raw
        // event id (a Nostr thing's sourceRef is "nostr:<event-id>"; no
        // author needed, unlike Farcaster's fid-keyed lookup) and NSLogs the
        // count + first line, headless.
        Hook(key: "nostrReplies") { eventID, _ in
            Task { @MainActor in
                let replies = await NostrIngest.replies(eventID: eventID)
                NSLog("Nostr replies probe: %d replies%@", replies.count,
                      replies.first.map { " — @\(SocialThread.shortHandle($0.handle)): \(String($0.text.prefix(60)))" } ?? "")
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
        // `-stockWatch "<query[,query]>"` — resolve each on Stocktwits, watch
        // it, then sync the streams; NSLogs tickers + new posts (headless
        // bridge test).
        Hook(key: "stockWatch") { spec, context in
            Task { @MainActor in
                var symbols: [String] = []
                for raw in spec.split(separator: ",") {
                    let q = String(raw).trimmingCharacters(in: .whitespaces)
                    guard let hit = await StockWatch.resolve(q) else { continue }
                    _ = StockWatch.add(hit, context: context)
                    symbols.append(hit.symbol)
                }
                let n = await StocktwitsIngest.refresh(context: context)
                NSLog("Stocktwits probe: watching %@ — %@ new posts",
                      symbols.isEmpty ? "NOTHING (resolve failed)" : symbols.joined(separator: ","),
                      n.map(String.init) ?? "FAILED")
            }
        },
        // `-stockChartProbe <ticker>` — fetch the Yahoo v8 curve on-device and
        // NSLog points/price/change (verifies the UA quirk holds from the
        // app's URLSession, not just curl).
        Hook(key: "stockChartProbe") { ticker, _ in
            Task { @MainActor in
                let t = ticker.trimmingCharacters(in: .whitespaces).uppercased()
                if let c = await StockChart.fetch(ticker: t, range: .day) {
                    NSLog("Stock chart probe: %@ — %d points, $%.2f, %+.1f%%",
                          t, c.closes.count, c.price, c.change * 100)
                } else {
                    NSLog("Stock chart probe: %@ — FAILED", t)
                }
            }
        },
        // `-weatherProbe YES` — fetch today's WeatherKit forecast headless
        // (one-shot location + WeatherService) and NSLog the summary, or an
        // honest FAILED on denial/unavailability.
        Hook(key: "weatherProbe") { _, _ in
            Task { @MainActor in
                if let summary = await WeatherEnrichment.todaySummary() {
                    NSLog("Weather probe: %@", summary)
                } else {
                    NSLog("Weather probe: FAILED (denied or unavailable)")
                }
            }
        },
        // `-homeKitProbe YES` — connects HomeKit headlessly and NSLogs the
        // accessory count. Simulator caveat: no real HomeKit accessories
        // exist there — expect 0 unless paired with the HomeKit Accessory
        // Simulator or run on a real device (same honest-zero shape as the
        // Strava probe).
        Hook(key: "homeKitProbe") { _, context in
            Task { @MainActor in
                let n = await HomeKitIngest.connectAndIngest(context: context)
                NSLog("HomeKit probe: %@", n.map { "\($0) accessories" } ?? "FAILED (denied)")
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
        // `-clearWallets YES` empties the watch list. The only way to test a
        // SINGLE-family watch list (Solana-only, say) on a device that already
        // watches others: `simctl spawn defaults delete` can't do it — the
        // CLI's write races cfprefsd and the app reads the stale value anyway
        // (paid for 2026-07-16). Declared BEFORE `walletAddress` because hooks
        // run in list order, so this clears first and the add lands after.
        Hook(key: "clearWallets") { _, _ in
            let before = WalletStore.shared.addresses.count
            WalletStore.shared.addresses = []
            NSLog("Clear-wallets probe: %d -> 0", before)
        },
        // `-walletAddress <0x…|ENS|.sol>` (or `<addr>|<Label>`) watches a wallet
        // headlessly. A Solana address/name needs its chain on or it can never
        // read — the same guard the Wallet screen's add path applies.
        Hook(key: "walletAddress") { spec, context in
            let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
            guard let address = parts.first else { return }   // "" crashed on parts[0]
            if !BitcoinAddress.isAddress(address),
               SNS.isAddress(address) || SNS.looksLikeName(address) {
                WalletChainStore.shared.ensureEnabled("solana-mainnet")
            }
            WalletStore.shared.add(address, label: parts.count > 1 ? parts[1] : "")
            Task { @MainActor in
                let n = await WalletIngest.refresh(context: context)
                NSLog("Wallet probe: %@ new", n.map(String.init) ?? "FAILED")
            }
        },
        // `-seedWalletHistory "<usd,usd,…>[|<watched address>]"` writes a
        // synthetic ValueSample line for a watched wallet (the first one, or
        // the named one), spaced 4h+ apart so the real `recordSample` throttle
        // can never fold them into one point — headless test of the Wallet
        // row's/feed's balance sparkline (prd 126), which draws off exactly
        // this history and otherwise only gains a second point after 4 real
        // hours of use. Declared AFTER `walletAddress` (hooks run in list
        // order) so the wallet exists to key the history to.
        //
        // The address selector (2026-07-21) is what makes the COMBINED line
        // testable: `combinedValueSamples` only starts once EVERY watched
        // wallet has a sample, so a two-wallet stack (prd §155's banded hero)
        // needs two seeded lines, one per launch.
        //
        // Each sample also carries a holdings snapshot so the attribution
        // paths (`holdingsDeltas` → the headline's "Mostly ETH" whisper and
        // the combined sheet's "What moved") have a pair to difference.
        //
        // Two properties are load bearing (both paid for 2026-07-21, shooting
        // the Wallet App Store preview):
        //
        // 1. The composition is the wallet's REAL one, taken from its newest
        //    genuinely-recorded sample and scaled to each seeded total — not a
        //    hardcoded 60/40 ETH/USDC. The hardcoded pair differenced against
        //    real holdings the moment a real sample landed on top of the line,
        //    printing "Mostly ETH · −$593K" under a GREEN +3.0% pill: a whisper
        //    that contradicted the delta beside it. Falls back to the old
        //    synthetic pair only when nothing real has been recorded yet.
        //
        // 2. The newest seeded sample sits 5 MINUTES back, not 4 hours. The old
        //    spacing put it at exactly `recordSample`'s 4h throttle boundary, so
        //    the next real fetch ALWAYS appended on top of the seeded line and
        //    the seam above was unavoidable. Five minutes is inside the throttle,
        //    so the seeded line stays the whole line for the run. Earlier points
        //    keep the 4h spacing so nothing folds together.
        Hook(key: "seedWalletHistory") { spec, _ in
            let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
            let values = (parts.first ?? "").split(separator: ",").compactMap { Double($0) }
            let target = parts.count > 1
                ? WalletStore.shared.addresses.first { WalletWatch.sameAddress($0.address, parts[1]) }
                : WalletStore.shared.addresses.first
            guard let entry = target, !values.isEmpty else {
                NSLog("Seed-wallet-history probe: no matching watched wallet")
                return
            }
            // The real composition, if this wallet has ever priced.
            let real = WalletStore.shared.valueSamples(forAddress: entry.address)
                .last { ($0.holdings?.isEmpty == false) }?.holdings
            let realTotal = real?.values.reduce(0, +) ?? 0
            let newest = Date.now.addingTimeInterval(-300)
            let samples = values.enumerated().map { i, usd in
                let holdings: [String: Double]
                if let real, realTotal > 0 {
                    holdings = real.mapValues { $0 / realTotal * usd }
                } else {
                    holdings = ["ETH": usd * 0.6, "USDC": usd * 0.4]
                }
                return WalletStore.ValueSample(
                    at: newest.addingTimeInterval(Double(i - (values.count - 1)) * 4 * 3600),
                    usd: usd,
                    holdings: holdings)
            }
            if let data = try? JSONEncoder().encode(samples) {
                UserDefaults.standard.set(data, forKey: "wallet.history.\(entry.address.lowercased())")
            }
            NSLog("Seed-wallet-history probe: %d samples for %@ (composition: %@)",
                  samples.count, entry.address, real == nil ? "synthetic" : "real")
        },
        // `-approvalProbe <blocksBack|YES>` runs the token-approval sync over
        // the watched wallets and NSLogs the landed count. A numeric spec
        // rewinds every cursor that many blocks first, so real past approvals
        // land and the whole path verifies without waiting for a live one.
        // Pairs with `-walletAddress`.
        Hook(key: "approvalProbe") { spec, context in
            Task { @MainActor in
                let n = await WalletApprovals.probe(context: context, blocksBack: Int(spec))
                NSLog("Approval probe: %d landed", n)
            }
        },
        // `-prepareProbe YES` runs the approval PREPARE path (prd §112) over
        // the newest landed approval thing — receipt refetch → live
        // allowance/operator read → revoke calldata → fee quote — and NSLogs
        // each fact. Reads only, nothing signed or sent. Pairs with
        // `-approvalProbe <blocksBack>` to land an approval thing first.
        Hook(key: "prepareProbe") { _, context in
            Task { @MainActor in
                let line = await WalletPrepare.probe(context: context)
                NSLog("Prepare probe: %@", line)
            }
        },
        // `-delegationProbe YES` reports each watched wallet's CURRENT
        // EIP-7702 delegate per active EVM chain (2026-07-20), bypassing the
        // land-on-change gate so it verifies without needing a live
        // delegation change. Pairs with `-walletAddress`.
        Hook(key: "delegationProbe") { _, _ in
            Task { @MainActor in
                let line = await WalletSafety.probe()
                NSLog("Delegation probe: %@", line)
            }
        },
        // `-worthALookProbe YES` runs the full Worth-a-look roll-up
        // (`WalletWatch.liveState`, the exact read `FeedScreen` uses) over
        // the watched wallets and NSLogs every section's count — the fastest
        // way to verify the tray's type-split (2026-07-23, prd §196) actually
        // sees position risk, flagged transfers, ACTIVE approvals, delegations,
        // and Safe signatures without driving the UI. Pairs with
        // `-walletAddress` + `-approvalProbe`/`-poisoningProbe`/
        // `-symbolProbe`/`-delegationProbe` to land the underlying things.
        Hook(key: "worthALookProbe") { _, context in
            Task { @MainActor in
                let state = await WalletWatch.liveState(context: context)
                let liquidation = state.warnings.filter { $0.kind == .liquidation }.count
                let delegations = state.warnings.filter { $0.kind == .delegation }.count
                let safe = state.warnings.filter { $0.kind == .safe }.count
                NSLog("WorthALook probe: position=%d transfers=%d approvals=%d delegations=%d safe=%d",
                      liquidation, state.flagged.count, state.activeApprovals.count,
                      delegations, safe)
            }
        },
        // `-poisoningProbe YES` runs the address-poisoning fuzzy-match rule
        // over already-landed Wallet things and reports how many it would
        // flag — a read-only scan of the matching logic itself, no live
        // poisoning transfer needed. Pairs with `-walletAddress`.
        Hook(key: "poisoningProbe") { _, context in
            let line = WalletSafety.poisoningProbe(context: context)
            NSLog("Poisoning probe: %@", line)
        },
        // `-symbolProbe YES` runs the confusable-symbol rule (prd §160) over
        // already-landed Wallet things and reports every spoofed symbol it
        // finds, WITH each one's scalars (`U+0055 U+0301 U+0405 …`) — the
        // only form in which "ÚЅDС" and "USDC" are distinguishable in a log,
        // which is the whole point of the feature. Read-only. Pairs with
        // `-walletAddress` (poap.eth held several on 2026-07-21).
        Hook(key: "symbolProbe") { _, context in
            let line = WalletSafety.symbolProbe(context: context)
            NSLog("Symbol probe: %@", line)
        },
        // `-gasSpentProbe YES` NSLogs the running gas total per watched
        // wallet (per chain and combined USD). Pairs with `-walletAddress`
        // (and a real refresh/`-walletAddress` re-fire to have landed at
        // least one outgoing transaction to accumulate against).
        Hook(key: "gasSpentProbe") { _, _ in
            Task { @MainActor in
                let line = await WalletGas.probe()
                NSLog("Gas spent probe: %@", line)
            }
        },
        // `-defiProbe YES` NSLogs each watched wallet's Aave collateral/debt/
        // health-factor across every active Aave-supported chain (or the
        // honest "no positions found"). Pairs with `-walletAddress`.
        Hook(key: "defiProbe") { _, _ in
            Task { @MainActor in
                let line = await WalletDeFi.probe()
                NSLog("DeFi probe: %@", line)
            }
        },
        // `-morphoProbe <daysBack|YES>` NSLogs each watched wallet's Morpho
        // book (market positions with health factors, vault deposits, or
        // the honest miss). A numeric spec ALSO rewinds every Morpho
        // activity cursor that many DAYS (timestamps, not blocks — Morpho's
        // API filters on time) and runs the settled-activity sweep, so real
        // past events land headlessly. Pairs with `-walletAddress`.
        Hook(key: "morphoProbe") { spec, context in
            Task { @MainActor in
                let line = await MorphoDeFi.probe(context: context, daysBack: Int(spec))
                NSLog("Morpho probe: %@", line)
            }
        },
        // `-safeProbe YES` NSLogs which watched wallets are detected Safes
        // per chain and their pending queue counts (or the honest
        // unreachable/none). Pairs with `-walletAddress` (a Safe address, to
        // exercise anything).
        Hook(key: "safeProbe") { _, _ in
            Task { @MainActor in
                let line = await SafeBridge.probe()
                NSLog("Safe probe: %@", line)
            }
        },
        // `-peerProbe <blocksBack|YES>` switches the Peer seat on and runs the
        // fill sweep over the watched wallets, NSLogging the landed count. A
        // numeric spec rewinds every Peer cursor that many blocks below the
        // Base head first, so real past fills land and the whole path (logs →
        // signal join → deposit token → titles → things) verifies headlessly.
        // Pairs with `-walletAddress`.
        Hook(key: "peerProbe") { spec, context in
            // No seat to switch on anymore (automatic, prd §207) — `probe`
            // rewinds cursors and runs the sweep over the watched wallets
            // directly, so pair this with `-walletAddress`.
            Task { @MainActor in
                let n = await PeerBridge.probe(context: context, blocksBack: Int(spec))
                NSLog("Peer probe: %@ landed", n.map(String.init) ?? "FAILED")
            }
        },
        // `-privacyPoolsProbe <blocksBack|YES>` switches the Privacy Pools
        // seat on and runs the deposit sweep + ASP status poll over the
        // watched wallets, NSLogging the landed count and the pending
        // watchlist. A numeric spec rewinds every cursor that many blocks
        // below the mainnet head first; a fresh install backfills from the
        // deploy block by design (prd §162), so a plain YES already lands
        // real deposits for a wallet that has used Privacy Pools. Pairs with
        // `-walletAddress <a depositor wallet>`.
        // `-privacyPoolsSeedPending "<label>[|<scope>]"` plants a PENDING
        // baseline for a real deposit label, so the next
        // `-privacyPoolsProbe` exercises the status-alert branch against the
        // live ASP instead of waiting days for a real review to clear.
        // Declared BEFORE the probe hook so list order runs the seed first.
        Hook(key: "privacyPoolsSeedPending") { spec, _ in
            PrivacyPoolsBridge.seedPending(spec: spec)
            NSLog("Privacy Pools seed: %@", PrivacyPoolsBridge.pendingSummary())
        },
        Hook(key: "privacyPoolsProbe") { spec, context in
            // Automatic seat (prd §207) — `probe` runs the sweep directly;
            // pair with `-walletAddress <a depositor wallet>`.
            Task { @MainActor in
                let n = await PrivacyPoolsBridge.probe(context: context, blocksBack: Int(spec))
                NSLog("Privacy Pools probe: %@ landed; %@",
                      n.map(String.init) ?? "FAILED",
                      PrivacyPoolsBridge.pendingSummary())
            }
        },
        // `-gnosisPayProbe <blocksBack|YES>` runs the Gnosis Pay card-spend
        // sweep over the watched wallets, NSLogging the landed count and
        // which watched wallets turned out to be card accounts. A numeric
        // spec rewinds every cursor that many blocks below the Gnosis Chain
        // head first, so real past spends land instead of waiting for someone
        // to buy something. Pair with `-walletAddress <a card Safe>`.
        // NOTE the measured ceiling (prd §222): an `eth_getLogs` range much
        // over 500k blocks comes back EMPTY rather than erroring, so a spec
        // far past that reads as "no spends" — the sweep chunks internally,
        // but a probe asking for millions is testing the wrong thing.
        Hook(key: "gnosisPayProbe") { spec, context in
            Task { @MainActor in
                let n = await GnosisPayBridge.probe(context: context, blocksBack: Int(spec))
                NSLog("Gnosis Pay probe: %@ landed; %@",
                      n.map(String.init) ?? "FAILED",
                      GnosisPayBridge.accountSummary())
            }
        },
        // `-bitcoinHalvingHorizon <days>` widens the window in which the
        // halving row is allowed to land. The real next halving is ~90,000
        // blocks out — well past the shipped 180-day horizon — so without
        // this the landing branch could not be exercised until 2028. The
        // probe logs the arithmetic either way; this makes the ROW testable.
        // Declared BEFORE `-bitcoinProbe` so list order applies it first.
        Hook(key: "bitcoinHalvingHorizon") { spec, _ in
            BitcoinBridge.halvingHorizonOverrideDays = Int(spec)
            NSLog("[Casberi] bitcoinHalvingHorizon: %@ days", spec)
        },
        // `-bitcoinProbe <address>` runs the Bitcoin sweep for one address
        // directly (bypassing the watch list) and NSLogs balance, tx count,
        // landed things, pending confirmations, and the two one-shot
        // insights' verdicts. Pair with `-walletAddress <a BTC address>` to
        // also exercise the watched-wallet path (holdings fold, per-wallet
        // card) rather than just the sweep itself.
        Hook(key: "bitcoinProbe") { address, context in
            Task { @MainActor in
                _ = await BitcoinBridge.probe(context: context, address: address)
            }
        },
        // `-solNameProbe <name.sol>` resolves a Solana name through SNS and
        // NSLogs the address (or the honest miss) — the fastest check that the
        // resolver still answers, without touching the corpus.
        Hook(key: "solNameProbe") { spec, _ in
            Task {
                let address = await SNS.resolve(spec)
                NSLog("SOL name probe: %@ -> %@", spec, address ?? "UNRESOLVED")
            }
        },
        // `-corpusDupeProbe YES` reports any sourceRef the corpus holds TWICE.
        // `Thing.sourceRef` carries no unique constraint, so every bridge's
        // dedupe rests entirely on its own `existing.contains(ref)` check — and
        // re-landing is the wallet path's historical bug class (the swap-legs
        // fix of 2026-07-13 exists for exactly this). A standing probe turns
        // "did it re-land?" from an argument into a number.
        Hook(key: "corpusDupeProbe") { _, context in
            let refs = ((try? context.fetch(FetchDescriptor<Thing>())) ?? [])
                .compactMap(\.sourceRef)
            var counts: [String: Int] = [:]
            for ref in refs { counts[ref, default: 0] += 1 }
            let dupes = counts.filter { $0.value > 1 }
            NSLog("Corpus dupe probe: %d ref(s), %d distinct, %d DUPLICATED",
                  refs.count, counts.count, dupes.count)
            for (ref, n) in dupes.sorted(by: { $0.value > $1.value }).prefix(5) {
                NSLog("  x%d %@", n, ref)
            }
        },
        // `-solActivityProbe <base58>` walks the Solana activity read for one
        // address and NSLogs each step — signatures in, what moved, whether it
        // was signed, the spam verdict, and the title it would land. The count
        // alone (`-walletAddress`) can't tell "nothing happened" from "the
        // filter ate it", and for Solana that distinction IS the feature.
        Hook(key: "solActivityProbe") { address, _ in
            Task { @MainActor in
                let key = IngestSupport.alchemyKey
                guard let moves = await SolanaActivity.moves(address: address, key: key) else {
                    NSLog("SOL activity probe: FAILED — RPC unreachable")
                    return
                }
                let price = await SolanaActivity.solPrice(key: key)
                let held = await WalletIngest.heldPricedContracts(addresses: [address])
                let symbols = await SolanaActivity.symbols(for: moves.flatMap { $0.legs.map(\.mint) })
                NSLog("SOL activity probe: %d move(s) with legs (SOL $%@, held %@)",
                      moves.count, price.map { String(format: "%.2f", $0) } ?? "?",
                      held.map { "\($0.count)" } ?? "UNREAD")
                for m in moves {
                    let news = SolanaActivity.isNews(m, heldPriced: held, solPrice: price)
                    let title = SolanaActivity.title(for: m, symbols: symbols)
                    NSLog("  %@ signed=%@ legs=%d → %@",
                          news ? "NEWS " : "drop ", m.signed ? "Y" : "n", m.legs.count,
                          news ? (title ?? "UNNAMEABLE (dropped)") : "—")
                }
            }
        },
        // `-solStakeProbe <base58>` reads one address's Solana stake accounts
        // headlessly and NSLogs each one's amount and status — the
        // getProgramAccounts memcmp-on-withdrawer read `SolanaStaking`
        // folds into the combined total (rotki-comparison gap, 2026-07-27).
        Hook(key: "solStakeProbe") { address, _ in
            Task { @MainActor in
                NSLog("SOL stake probe: %@", await SolanaStaking.probe(address: address))
            }
        },
        // `-ethValidatorWatch "<index[,index]>"` — watches each index headlessly
        // (no ingest to run — a validator has no "new posts", just live state)
        // and NSLogs the read. `-ethValidatorProbe "<index[,index]>"` reads
        // without watching, for checking the beacon API alone.
        Hook(key: "ethValidatorWatch") { spec, _ in
            Task { @MainActor in
                let indices = spec.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                for index in indices { EthValidatorStore.shared.add(index: index) }
                NSLog("ETH validator watch: %@", await EthValidatorRead.probe(indices: indices))
            }
        },
        Hook(key: "ethValidatorProbe") { spec, _ in
            Task { @MainActor in
                let indices = spec.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                NSLog("ETH validator probe: %@", await EthValidatorRead.probe(indices: indices))
            }
        },
        // `-holdingsProbe YES` runs the Diagnostics sheet's holdings walk
        // headlessly, NSLogging each step — the treemap's read (resolution →
        // Portfolio call → cells) verified without driving the UI. Pairs with
        // `-walletAddress`.
        Hook(key: "holdingsProbe") { _, _ in
            Task { @MainActor in
                for line in await WalletIngest.holdingsDiagnostic() {
                    NSLog("Holdings probe: %@", line)
                }
            }
        },
        // `-holdingsWindowProbe YES` — the freshness window's own test
        // (2026-07-25). Reads holdings three times and NSLogs each verdict:
        // live → window HIT (no metered call) → invalidate → live again. That
        // sequence is the whole contract: the window saves the repeat read,
        // and a deliberate pull-to-refresh always defeats it. Costs exactly
        // TWO metered `/positions` reads, not three, which is the point.
        // Pair with `-walletAddress`. `-holdingsWindow <seconds>` overrides the
        // window (0 disables it) for a probe that needs a genuinely live read.
        Hook(key: "holdingsWindowProbe") { _, _ in
            Task { @MainActor in
                NSLog("[Casberi] holdingsWindowProbe: read 1 (cold — expect MISS) → %@",
                      await WalletIngest.holdingsWindowRead())
                NSLog("[Casberi] holdingsWindowProbe: read 2 (expect HIT) → %@",
                      await WalletIngest.holdingsWindowRead())
                NSLog("[Casberi] holdingsWindowProbe: invalidating (pull-to-refresh)")
                await WalletIngest.invalidateHoldingsCache()
                NSLog("[Casberi] holdingsWindowProbe: read 3 (expect MISS) → %@",
                      await WalletIngest.holdingsWindowRead())
                NSLog("[Casberi] holdingsWindowProbe: done")
            }
        },
        // `-addressBook "<Name>:<address>[,<Name>:<address>…]"|clear` — seed the
        // address book headlessly (prd §169). `clear` empties it. Splits each
        // pair on the LAST colon so a name may carry its own.
        Hook(key: "addressBook") { spec, _ in
            if spec == "clear" {
                for entry in AddressBook.shared.all { AddressBook.shared.remove(entry.address) }
                NSLog("Address-book probe: cleared")
                return
            }
            var landed = 0
            for pair in spec.split(separator: ",") {
                let text = String(pair)
                guard let colon = text.lastIndex(of: ":") else { continue }
                let name = String(text[text.startIndex..<colon])
                let address = String(text[text.index(after: colon)...])
                if AddressBook.shared.setName(name, for: address) != nil { landed += 1 }
            }
            NSLog("Address-book probe: %d named, %d in book", landed, AddressBook.shared.count)
        },
        // `-addressBookProbe YES` — report the book and the watch cap: every
        // entry with its detected kind and whether it's watched, plus how the
        // cap currently stands. The one check that naming and watching are
        // really two tiers over ONE ledger (prd §169/§170).
        Hook(key: "addressBookProbe") { _, _ in
            Task { @MainActor in
                await AddressKind.detectPending(limit: 12)
                let watched = Set(WalletStore.shared.addresses.map { AddressBook.key(for: $0.address) })
                NSLog("Address-book probe: %d named · %d/%d watched · canWatchMore=%@",
                      AddressBook.shared.count, WalletStore.shared.addresses.count,
                      WalletStore.watchLimit, WalletStore.shared.canWatchMore ? "YES" : "NO")
                for entry in AddressBook.shared.all {
                    NSLog("  %@ · %@ · kind=%@%@%@", entry.name, entry.short,
                          entry.kind.rawValue,
                          watched.contains(entry.id) ? " · WATCHED" : "",
                          entry.provenance.map { " · from \($0)" } ?? "")
                }
            }
        },
        // `-watchCapProbe <address>` — try to watch one more and NSLog the
        // OUTCOME word (added / alreadyWatching / limitReached / invalid), so
        // the cap's refusal is verifiable without driving the UI (prd §170).
        Hook(key: "watchCapProbe") { address, _ in
            let outcome = WalletStore.shared.outcome(ofAdding: address, label: "")
            NSLog("Watch-cap probe: %@ → %@ (%d/%d watched)", address, "\(outcome)",
                  WalletStore.shared.addresses.count, WalletStore.watchLimit)
        },
        // `-portfolioProbe YES|<watched address>` runs the COMBINED portfolio
        // read (prd §155) headlessly: the merged total, the token count, which
        // treemap shape the feed would paint (one combined map unscoped with
        // more than one wallet, per-wallet maps otherwise), the concentration
        // line, and the per-wallet holders behind the top positions. The one
        // check that the crown feature actually merges — a count alone can't
        // tell "combined" from "the first wallet's map wearing a new title".
        // Pass a watched address to probe the scoped shape instead. Pairs with
        // `-walletAddress`; reads only (it does spend the same Alchemy credits
        // the treemap's own read does).
        Hook(key: "portfolioProbe") { value, _ in
            Task { @MainActor in
                let scope = (value == "YES" || value.isEmpty) ? nil : value
                guard let read = await WalletIngest.portfolioRead(scopeTo: scope) else {
                    NSLog("Portfolio probe: nothing read (no watched wallet priced)")
                    return
                }
                let p = read.portfolio
                let combined = read.doc.count == 1 && read.doc[0].contains("Across your wallets")
                NSLog("Portfolio probe: scope=%@ total=%@ tokens=%d wallets=%d map=%@",
                      scope ?? "ALL", TokenStats.compact(p.totalUSD), p.tokenCount,
                      p.walletCount, combined ? "COMBINED" : "per-wallet")
                NSLog("Portfolio probe: concentration=%@", p.concentrationLine ?? "—")
                for position in p.positions.prefix(5) {
                    let held = position.holders
                        .map { "\($0.label) \(TokenStats.compact($0.usd))" }
                        .joined(separator: ", ")
                    NSLog("  %@ %@ (%d wallet%@: %@)", position.symbol,
                          TokenStats.compact(position.usd), position.holders.count,
                          position.holders.count == 1 ? "" : "s", held)
                }
                for line in read.doc { NSLog("Portfolio probe doc: %@", line) }
            }
        },
        // `-defillamaProbe <address>` walks the DeFiLlama price backstop (prd
        // §115) end-to-end for one wallet: how many held tokens Alchemy leaves
        // unpriced, and how many the keyless `coins.llama.fi` fill then rescues
        // (with each price + confidence, and which fell under the floor). The
        // count alone can't tell "Alchemy priced everything" from "the backstop
        // saved a vanishing token" — and that rescue IS the feature. Pair with
        // `-walletAddress`; reads only.
        Hook(key: "defillamaProbe") { address, _ in
            Task { @MainActor in
                for line in await WalletIngest.backstopDiagnostic(address: address) {
                    NSLog("DeFiLlama probe: %@", line)
                }
            }
        },
        // `-zerionProbe <address>` walks the Zerion holdings read (prd — the
        // Alchemy-reduction work, 2026-07-19) for one wallet: reachability,
        // holding count, priced-vs-unpriced, and the first rows. UNMEASURED
        // against the live API — this is the check that Zerion's `/positions`
        // returns what the Alchemy treemap shows before it's trusted as primary.
        // With no key set it says so and confirms the Alchemy fallback is live.
        // Pair with `-walletAddress`; reads only.
        Hook(key: "zerionProbe") { address, _ in
            Task { @MainActor in
                for line in await ZerionAPI.diagnostic(address: address) {
                    NSLog("Zerion probe: %@", line)
                }
            }
        },
        // `-zerionActivityProbe <address>` walks Zerion's `/transactions`
        // read for one wallet: reachability, fungible-leg count, and the
        // first rows (hash / chain / direction / symbol / amount / cp) —
        // compare against the Wallet feed's recent activity for that address
        // before trusting Zerion as the EVM-activity source. UNMEASURED
        // against the live API. Pair with `-walletAddress`; reads only.
        Hook(key: "zerionActivityProbe") { address, _ in
            Task { @MainActor in
                for line in await ZerionAPI.activityDiagnostic(address: address) {
                    NSLog("Zerion activity probe: %@", line)
                }
            }
        },
        // `-wcConnectProbe YES` proposes a read-only WalletConnect session and
        // NSLogs the EXACT namespaces payload plus the `wc:` URI. The payload
        // line is the point: it's the proof that "we ask for nothing" is real
        // rather than intended — if `methods` is ever non-empty there, the
        // Wallet screen's promise is broken and this probe is how we find out.
        // Pair with `-wcProjectID <id>`; with no id it logs the honest
        // unavailable line (the paste-only degrade).
        Hook(key: "wcConnectProbe") { _, _ in
            guard WalletConnectBridge.isAvailable else {
                NSLog("WalletConnect probe: unavailable (no project id) — paste-only")
                return
            }
            let namespaces = WalletConnectBridge.readOnlyNamespaces()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let json = try? encoder.encode(namespaces) {
                NSLog("WalletConnect probe: proposing %@", String(decoding: json, as: UTF8.self))
            }
            let methodCount = namespaces.values.reduce(0) { $0 + $1.methods.count }
            let eventCount = namespaces.values.reduce(0) { $0 + $1.events.count }
            NSLog("WalletConnect probe: methods=%d events=%d (both MUST be 0)",
                  methodCount, eventCount)
            Task { @MainActor in
                do {
                    // The full handshake, with `open` stubbed to report success
                    // without launching anything — the simulator has no wallet
                    // app, and a real `openURL` here would only ever log the
                    // `.noWalletApp` path. Minting the URI is a genuine relay
                    // round-trip (WebSocket connect, publish), so reaching this
                    // line at all proves the project id and socket work; the
                    // settle→read→teardown leg needs a wallet to approve, so
                    // headless this reports `.timedOut` after the timeout, which
                    // is itself the honest no-hang check.
                    let outcome = try await WalletConnectBridge.connect(
                        timeout: .seconds(WalletConnectProbe.timeout)
                    ) { url in
                        NSLog("WalletConnect probe: uri=%@", url.absoluteString)
                        return true
                    }
                    switch outcome {
                    case .connected(let accounts):
                        // Reaching here means teardown already SUCCEEDED —
                        // `connect` returns accounts on no other path. The
                        // namespace rides the log because "did the Solana arm
                        // actually answer" is the whole question this probe
                        // gets asked now.
                        let rendered = accounts
                            .map { "\($0.namespace):\($0.address)" }
                            .joined(separator: ",")
                        NSLog("WalletConnect probe: connected %d account(s) %@ — session torn down",
                              accounts.count, rendered)
                    case .noWalletApp:
                        NSLog("WalletConnect probe: no wallet app claimed the wc: scheme")
                    case .timedOut:
                        // The uri= line above always precedes this one (the
                        // stub only runs after the mint), so it already says
                        // minting worked — no need to restate it here.
                        NSLog("WalletConnect probe: no approval within %.0fs — proposal expired, nothing survives",
                              WalletConnectProbe.timeout)
                    }
                } catch WalletConnectBridge.ConnectError.tearDownFailed(let topic, let underlying) {
                    NSLog("WalletConnect probe: TEARDOWN FAILED topic=%@ %@ — a live session survived the read",
                          topic, String(describing: underlying))
                } catch {
                    NSLog("WalletConnect probe: FAILED %@", String(describing: error))
                }
            }
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
        // `-photoHealProbe YES` runs the Photos HEAL directly — the pass that
        // OCRs, thumbnails, retitles (§218) and prunes. `-reingestPhotos` only
        // LANDS assets; OCR has always lived here, which is why a landing probe
        // alone leaves every row still saying "Screenshot". Logs what the pass
        // did, then every screenshot's title and how many OCR characters back
        // it — the one view that separates "OCR found nothing" (wordless, so
        // the row should be a picture) from "the retitle didn't fire".
        Hook(key: "photoHealProbe") { _, context in
            Task { @MainActor in
                let r = await ScreenshotIngest.heal(context: context)
                NSLog("[Casberi] photoHeal: thumbed=%d ocred=%d removed=%d",
                      r.thumbed, r.ocred, r.removed)
                let shots = (try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == "Photos" },
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
                for t in shots.prefix(12) {
                    NSLog("[Casberi] photoHealRow| ocr=%d title=%@",
                          t.content.count, t.title)
                }
            }
        },
        Hook(key: "reingestPhotos") { _, context in
            let n = ScreenshotIngest.ingest(context: context)
            NSLog("Photos re-ingest probe: %d new", n)
        },
        // `-photoBackfill YES|reset` walks one batch BACKWARDS through the
        // library — the 2026-07-25 fix for "older screenshots never show".
        // `reset` restarts the walk first, so a second run re-lands from the
        // top of the library instead of reporting an already-finished cursor.
        // A numeric spec sets the batch size, so the walk itself can be
        // stepped on a small library ("-photoBackfill 2" three times).
        Hook(key: "photoBackfill") { spec, context in
            if spec.lowercased().hasPrefix("reset") { ScreenshotIngest.resetBackfill() }
            let limited = ScreenshotIngest.accessIsLimited
            let batch = Int(spec.split(separator: " ").last.map(String.init) ?? "") ?? 200
            let n = ScreenshotIngest.backfill(context: context, batch: batch)
            let held = ((try? context.fetch(FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == "Photos" }))) ?? [])
                .filter { $0.kind == .screenshot }.count
            NSLog("Photos backfill probe: %d landed · %d in corpus · %@ · access=%@",
                  n, held,
                  ScreenshotIngest.backfillDone ? "walked to the end" : "more to walk",
                  limited ? "LIMITED" : (ScreenshotIngest.hasAccess ? "full" : "none"))
        },
        // `-connectStrava YES` runs the Strava connect — the Health-store
        // read filtered to workouts Strava wrote (no Strava account
        // anywhere). On the sim the store is empty: expect "0 in".
        Hook(key: "connectStrava") { _, context in
            Task { @MainActor in
                guard let r = await HealthIngest.connectAndIngest(
                    context: context, healthOn: false, stravaOn: true,
                    counting: "Strava") else {
                    NSLog("Strava probe: FAILED (Health unavailable)"); return
                }
                NSLog("Strava probe: connected, %d in%@", r.added,
                      r.likelyBlocked ? " (access may be off)" : "")
            }
        },
        // `-connectHealth YES` runs the plain Apple Health connect — workouts,
        // sleep, and (iOS 18+) State of Mind reflections, the same read
        // `-connectStrava` shares filtered the other way. On the sim the
        // store is usually empty: expect "0 in".
        Hook(key: "connectHealth") { _, context in
            Task { @MainActor in
                guard let r = await HealthIngest.connectAndIngest(context: context) else {
                    NSLog("Health probe: FAILED (Health unavailable)"); return
                }
                NSLog("Health probe: connected, %d in%@", r.added,
                      r.likelyBlocked ? " (access may be off)" : "")
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
        // `-ghGraphDemo YES` seeds a synthetic contribution year and
        // fake-connects GitHub so the contribution graph renders on the
        // simulator (no real account needed). The graph leads the GitHub SOURCE
        // FEED now (moved off Home 2026-07-18), so pair with `-feedSource GitHub`
        // to see it. Screenshot/staging only.
        Hook(key: "ghGraphDemo") { _, _ in
            UserDefaults.standard.set(true, forKey: "ghGraphDemo")
            if TokenVault.get(TokenBridge.github.tokenKey) == nil {
                TokenVault.set("demo", for: TokenBridge.github.tokenKey)
            }
            CorpusSignal.shared.bump()
            NSLog("GitHub graph demo: seeded + connected GitHub (shows in the GitHub source feed)")
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
                context.saveHonestly()
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
            context.saveHonestly()
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
                    context.saveHonestly()
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
        // `-filesFolder <path>` points the Files bridge at a folder headlessly
        // (an in-sandbox path needs no security scope — sim testing only).
        Hook(key: "filesFolder") { path, context in
            guard FilesStore.shared.setFolder(url: URL(fileURLWithPath: path)) else {
                NSLog("Files probe: bookmark FAILED"); return
            }
            Task { @MainActor in
                let n = await FilesIngest.refresh(context: context)
                NSLog("Files probe: %@ new", n.map(String.init) ?? "FAILED")
            }
        },
        // `-dropboxFolder <path>` points the Dropbox bridge at a folder
        // headlessly and syncs it — but only once the OAuth token is already
        // in the Keychain (PKCE needs a real browser hop, so unlike
        // `-filesFolder` this can't complete a fresh connect on its own:
        // connect once by hand in the simulator, then this probe can drive
        // that same connection on every later headless run). Blank ("") means
        // Dropbox's own root path.
        Hook(key: "dropboxFolder") { path, context in
            DropboxStore.shared.setFolder(path == "root" ? "" : path)
            Task { @MainActor in
                let n = await DropboxIngest.refresh(context: context)
                NSLog("Dropbox probe: %@ new (folder=%@)", n.map(String.init) ?? "FAILED",
                      DropboxStore.shared.folderPath.isEmpty ? "root" : DropboxStore.shared.folderPath)
            }
        },
        // `-dropboxProbe YES` re-syncs the ALREADY-connected, already-scoped
        // folder — the repeat-run form, exercising the delta cursor
        // (`list_folder/continue`) instead of `-dropboxFolder`'s fresh
        // `list_folder` reset.
        Hook(key: "dropboxProbe") { _, context in
            Task { @MainActor in
                let n = await DropboxIngest.refresh(context: context)
                NSLog("Dropbox probe: %@ new", n.map(String.init) ?? "FAILED")
            }
        },
        // `-slackProbe YES` re-syncs the ALREADY-connected session (mentions
        // of you via `search.messages`) — a connect can't be scripted, since
        // PKCE needs a live human tap through Slack's real consent screen;
        // connect once by hand in the simulator, then this probe re-syncs on
        // every later headless run.
        Hook(key: "slackProbe") { _, context in
            Task { @MainActor in
                let n = await SlackIngest.refresh(context: context)
                NSLog("Slack probe: %@ new", n.map(String.init) ?? "FAILED")
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
        // `-mailHealProbe <icloud|gmail>` runs the delete-sync reconcile
        // headlessly against the ALREADY-connected provider (no credential
        // on the command line) and NSLogs how many stale rows it removed.
        // `force: true` bypasses heal's own hourly throttle so a probe run
        // always actually checks.
        Hook(key: "mailHealProbe") { spec, context in
            guard let provider = MailProvider.allCases.first(where: {
                $0.bridgeID == spec || $0.rawValue.lowercased().contains(spec.lowercased())
            }) else { return }
            Task { @MainActor in
                let n = await MailIngest.heal(provider, context: context, force: true)
                NSLog("Mail heal probe (%@): %d removed", provider.rawValue, n)
            }
        },
        // `-seedMailBody YES` lands one mail thing with a realistic long,
        // multi-paragraph, unicode-bearing plain-text body (the shape
        // `MailMIME.plainText` hands back from a real message) — so the
        // sheet's real-body render path (2026-07-23) can be reproduced
        // headlessly, without live IMAP credentials. Pair with
        // `-openThing "Real body"` to drive straight into its sheet.
        Hook(key: "seedMailBody") { _, context in
            let body = """
            Hi there — your Pro plan renews on August 14 at $20/mo. No action needed if everything looks right.

            A few things worth knowing before then:
            • Your seat count went from 3 → 5 last month.
            • Usage-based billing kicks in above 100k requests/day.
            • Invoices land in your billing portal, not this inbox.

            Questions? Just reply — a real person reads this address. Ünïcödé test: café, naïve, 日本語, emoji 🎉.

            Thanks,
            The Vercel team

            On Mon, Jul 20, 2026 at 9:00 AM, Jane <jane@x.com> wrote:
            > Can you confirm the renewal date?
            > Thanks!

            --
            Sent from my iPhone
            """
            let t = Thing(kind: .mail, title: "Real body render test", content: body,
                          source: "iCloud Mail", sourceRef: "probe:mailbody-\(UUID().uuidString)")
            t.authorHandle = "billing@vercel.com"
            context.insert(t)
            context.saveHonestly()
            NSLog("seedMailBody: landed")
        },
        // `-rssFeed <url>` follows a feed and syncs — headless bridge test.
        Hook(key: "rssFeed") { url, context in
            RSSStore.shared.add(url)
            Task { @MainActor in
                let n = await RSSIngest.refresh(context: context)
                NSLog("RSS probe: %@ new things", n.map(String.init) ?? "FAILED")
            }
        },
        // `-seedInsightDemo YES` seeds synthetic things so the feed-head insight
        // heroes (FeedInsight) can be seen rendering on the simulator, where the
        // real bridges need keys/accounts the sim has none of — the same job
        // `-ghGraphDemo` does for the contribution graph. Reddit exercises the
        // ranked-bars leaderboard (grouped by subreddit via authorHandle);
        // OpenSea exercises the image mosaic (real remote images). Deduped by
        // sourceRef, so a re-run is a no-op.
        Hook(key: "seedInsightDemo") { _, context in
            let existing = IngestSupport.existingSourceRefs(context)
            var landed = 0
            func seed(_ ref: String, _ make: () -> Thing) {
                guard !existing.contains(ref) else { return }
                context.insert(make()); landed += 1
            }
            // Reddit — 12 posts across 4 subreddits, uneven so the bars rank.
            let subs = [("r/swift", 5), ("r/apple", 4), ("r/programming", 2), ("r/webdev", 1)]
            var n = 0
            for (sub, count) in subs {
                for i in 0..<count {
                    n += 1
                    let ref = "insightdemo:reddit:\(n)"
                    seed(ref) {
                        let t = Thing(kind: .link, title: "\(sub) post \(i + 1)",
                                      content: "https://reddit.com/\(sub)/comments/\(n)/post/",
                                      source: "Reddit",
                                      capturedAt: .now.addingTimeInterval(Double(-n) * 3600),
                                      sourceRef: ref)
                        t.authorHandle = sub
                        return t
                    }
                }
            }
            // OpenSea — 6 collections wearing real remote artwork for the mosaic.
            for i in 0..<6 {
                let ref = "insightdemo:opensea:\(i)"
                seed(ref) {
                    let t = Thing(kind: .link, title: "Collection \(i + 1)",
                                  content: "https://opensea.io/collection/demo\(i)",
                                  source: "OpenSea",
                                  capturedAt: .now.addingTimeInterval(Double(-i) * 3600),
                                  sourceRef: ref)
                    t.previewImageURL = "https://picsum.photos/seed/casberi\(i)/300"
                    return t
                }
            }
            context.saveHonestly()
            NSLog("Insight demo: seeded %d things (Reddit leaderboard + OpenSea mosaic)", landed)
        },
        // `-viProbe "<label,label>"` runs the Visual Intelligence label→corpus
        // matcher headlessly — the exact function the iOS 26 system query
        // calls (VI's own camera UI can't be driven on the sim). NSLogs the
        // matched titles, so "does looking at X surface the right things"
        // verifies in one launch.
        Hook(key: "viProbe") { spec, _ in
            let labels = spec.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let hits = VisualCorpusMatch.things(for: labels)
            NSLog("viProbe: %d hit(s) for [%@]: %@", hits.count,
                  labels.joined(separator: ", "),
                  hits.isEmpty ? "—" : hits.map(\.title).joined(separator: " · "))
        },
    ]
}

/// Tunables for `-wcConnectProbe`.
///
/// Declared below `ProbeHooks` rather than above it: sitting between that
/// type's doc comment and the type itself silently rebinds the whole comment
/// to this enum, leaving the probe registry undocumented.
enum WalletConnectProbe {
    /// How long the probe waits for an approval. 20s, not the handshake's real
    /// 5 minutes: headless there's no wallet to approve, so the default run
    /// would sit for five minutes to report what it already knows at twenty
    /// seconds. `-wcTimeout <s>` widens it for a device run where a real wallet
    /// IS going to answer.
    static var timeout: Double {
        let override = UserDefaults.standard.double(forKey: "wcTimeout")
        return override > 0 ? override : 20
    }
}
#endif
