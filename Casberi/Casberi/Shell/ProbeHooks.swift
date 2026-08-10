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
        // Public by design (it names a Power-Up, not a person) — redacted for
        // the same reason `-wcProjectID` is: anything credential-shaped stays
        // out of the log, so nobody has to remember which ones are safe.
        "-trelloKey",
        // The `.p8` itself — a real ECDSA private key, and the most sensitive
        // value any probe in this file takes. `-ascKeyID`/`-ascIssuer` are
        // deliberately NOT here: they are identifiers, useless without the
        // key, and seeing them in `probeArgs:` is how a 401 gets diagnosed.
        "-ascKey",
        // A real email address — PII, not a secret the app treats as one,
        // redacted for Trello's reason: anything identifying stays out of the
        // log so nobody has to remember which ones are safe. `-jiraDomain` is
        // deliberately NOT here, `-ascKeyID`'s reasoning exactly: it's an
        // identifier, useless without the token, and seeing it in
        // `probeArgs:` is how a "couldn't reach the site" gets diagnosed.
        "-jiraEmail",
        // Not a credential the app USES, but by construction the value is a
        // sample secret — the whole point of the probe is to hand it one.
        // Printing it verbatim in `probeArgs:` would put a real key in the
        // sim log while testing the feature that exists to keep keys out of
        // logs (prd §277).
        "-secretScanProbe",
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
        // `-secretScanProbe corpus` names a MODE, not a sample — hiding it
        // made the log unable to say which of the two the run did.
        if flag == "-secretScanProbe", value == "corpus" { return value }
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
        // `-secretScanProbe "<text>"|corpus` runs the credential tripwire
        // (prd §277) and reports what it found: the KINDS, and the REDACTED
        // rendering — never the secret itself, which is the point of the
        // feature and so also the rule for its probe. `corpus` walks the
        // stored things instead and names the ones whose Spotlight/Siri
        // donation and keyed-agent grounding would carry hidden spans, which
        // is the only way to see the tripwire's real-world hit rate without
        // reading anyone's screenshots.
        Hook(key: "secretScanProbe") { spec, context in
            guard spec != "corpus" else {
                let things = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
                var flagged = 0
                for thing in things where thing.isLive {
                    let kinds = Set(SecretScan.scan(thing.title + "\n" + thing.content)
                        .map(\.kind.rawValue))
                    guard !kinds.isEmpty else { continue }
                    flagged += 1
                    // One NSLog per row — a joined multi-line message gets
                    // truncated by the log reader (the -todayProbe lesson).
                    NSLog("secretScanRow| %@ · %@ → %@", thing.source,
                          SecretScan.redacted(thing.title),
                          kinds.sorted().joined(separator: ","))
                }
                NSLog("secretScanProbe: corpus=%d flagged=%d", things.count, flagged)
                return
            }
            let findings = SecretScan.scan(spec)
            NSLog("secretScanProbe: found=%d kinds=%@", findings.count,
                  Set(findings.map(\.kind.rawValue)).sorted().joined(separator: ","))
            // On a MISS `redacted` returns the input untouched — printing it
            // would write the sample secret verbatim into the sim log, which
            // is the one thing this flag's denylist entry exists to prevent.
            // A false negative is exactly when that happens, so the miss
            // branch says nothing.
            NSLog("secretScanRedacted| %@", findings.isEmpty
                  ? "(nothing found — not echoing the input)"
                  : SecretScan.redacted(spec))
        },
        // `-keychainProbe YES` reports the vault's STORAGE POLICY — how many
        // items are device-only and how many are synchronizable — then forces
        // the hardening migration and reports again (prd §277). Counts only:
        // it never reads or logs a secret's value. The before/after pair is
        // the check that the migration actually re-writes old items, which is
        // invisible otherwise since a wrongly-stored key works perfectly.
        Hook(key: "keychainProbe") { _, _ in
            let before = TokenVault.policyCensus()
            NSLog("keychainProbe| before: total=%d deviceOnly=%d syncable=%d",
                  before.total, before.deviceOnly, before.synchronizable)
            let moved = TokenVault.migrateToDeviceOnly(force: true)
            NSLog("keychainProbe| migrate: hardened=%d alreadyRight=%d failed=%d",
                  moved.hardened, moved.alreadyRight, moved.failed)
            let after = TokenVault.policyCensus()
            NSLog("keychainProbe| after: total=%d deviceOnly=%d syncable=%d",
                  after.total, after.deviceOnly, after.synchronizable)
            NSLog("keychainProbe: %@",
                  after.total == after.deviceOnly && after.synchronizable == 0
                  ? "every item device-only and non-syncing"
                  : "STILL LOOSE — see the counts above")
        },
        // `-sweepTimerProbe YES` — where a FOREGROUND SWEEP's time goes
        // (2026-08-06). Turns `SweepClock` on (the flag itself does that, so
        // the instrument is live before the sweep it measures), waits for the
        // pass to finish, and dumps the summary: one `sweepPass|` line, then
        // one `sweepSlot|` per instrumented sweep, worst-stall first.
        //
        // It exists because this class of regression is invisible to every
        // other measurement we have. `perf.sh` times launch, steady RSS and
        // answer latency; a sweep that holds the main actor for two seconds
        // after the app is already up moves none of them, which is how the
        // nightly read green through the whole post-271 "feels laggy" report.
        //
        // The WAIT is not tunable padding: the automatic sweep holds a 1.8s
        // lead-in and then staggers 120ms per slot over ~45 slots
        // (2026-08-06), so the pass is still starting work seven seconds in,
        // and `SweepClock` only reports once nothing has been in flight for a
        // beat. A shorter wait reports a pass that hasn't happened yet and
        // reads as "nothing to fix".
        Hook(key: "sweepTimerProbe") { _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(25))
                // One NSLog per line — a joined multi-line message gets
                // truncated by the log reader (the `-todayProbe` lesson).
                for line in SweepClock.summary() { NSLog("[Casberi] %@", line) }
            }
        },
        // `-receiptsProbe YES` dumps the network receipts ledger (prd §277):
        // one line per host actually reached, with whether the "What this app
        // reaches" registry declares it. A host reading NOT-DECLARED is the
        // runtime form of the audit failure that shipped in build 214.
        //
        // Each line says HOW the host was accounted for, because the two ways
        // are not equally strong (2026-08-03). `by-host` is the registry
        // matching a declared host, which a static audit can prove. `named-by`
        // is the call site's own attribution, the only thing possible for a
        // host that comes out of the person's input (a feed, a store) — so a
        // row that ought to be `by-host` quietly turning into `named-by` is a
        // registry entry someone dropped, and it would be invisible in a
        // declared/undeclared tally alone.
        // `-bridgeHealthProbe YES` — who is still letting us in (2026-08-10).
        // One `bridgeHealth|` line per seat that has ever answered (the
        // `-todayProbe` truncation lesson), naming the last status, the last
        // 2xx, and whether it is currently shut out.
        //
        // It exists because "no seats flagged" is the HEALTHY answer and has
        // four other causes that read identically: nothing connected, no sweep
        // has run on this device yet (the record is per-device UserDefaults,
        // so a fresh install starts blank however long the bridge has been
        // connected), every host answering fine, or a host whose calls the
        // reach registry cannot attribute to a seat — and only the last is a
        // bug. The `attributed=` tally is what separates it.
        Hook(key: "bridgeHealthProbe") { _, _ in
            let book = BridgeHealth.allRecords()
            let iso = ISO8601DateFormatter()
            for row in book {
                NSLog("bridgeHealth| %@ · status=%@ · lastOK=%@ · shutOut=%@",
                      row.bridge,
                      row.record.lastStatus.map(String.init) ?? "never",
                      row.record.lastOK.map { iso.string(from: $0) } ?? "never",
                      row.record.authFailedAt.map { iso.string(from: $0) } ?? "no")
            }
            NSLog("bridgeHealthProbe: attributed=%d shutOut=%d",
                  book.count, BridgeHealth.allNeedingReconnect().count)
        },
        Hook(key: "receiptsProbe") { _, _ in
            let rows = NetworkLedger.shared.snapshot()
            var undeclared = 0
            for row in rows {
                let byHost = NetworkReach.service(forHost: row.host)
                let named = row.service.flatMap {
                    NetworkReach.declares(service: $0) ? $0 : nil
                }
                let verdict: String
                if let byHost {
                    verdict = "\(byHost) (by-host)"
                } else if let named {
                    verdict = "\(named) (named-by-caller)"
                } else {
                    undeclared += 1
                    verdict = "NOT-DECLARED"
                }
                NSLog("receipt| %@ · %d requests · %@", row.host, row.count, verdict)
            }
            NSLog("receiptsProbe: hosts=%d undeclared=%d", rows.count, undeclared)
            // …then the LEAD CARD's own reading (prd §299). One NSLog per cell
            // (the `-todayProbe` truncation lesson). It exists because the map
            // groups by SERVICE while the lines above are per HOST, so the two
            // can disagree in ways neither alone can show: a host whose
            // attribution the registry refuses lands as its own undeclared
            // cell, and five per-chain Alchemy hosts collapse into one Wallet
            // cell. A card that draws six plausible tiles looks correct
            // whichever happened.
            let resolved = rows.map { row -> NetworkReceiptsInsight.Row in
                let byHost = NetworkReach.service(forHost: row.host)
                let named = row.service.flatMap {
                    NetworkReach.declares(service: $0) ? $0 : nil
                }
                return .init(host: row.host, count: row.count, service: byHost ?? named)
            }
            if let reach = NetworkReceiptsInsight.compose(rows: resolved) {
                NSLog("reachCard| requests=%d services=%d hosts=%d undeclared=%d cells=%d",
                      reach.requests, reach.services, reach.hosts,
                      reach.undeclaredHosts, reach.cells.count)
                for cell in reach.cells {
                    NSLog("reachCell| %@ · %d · share=%.2f · %@%@",
                          cell.label, cell.count, cell.share,
                          cell.declared ? "declared" : "NOT-DECLARED",
                          cell.isTail ? " · tail" : "")
                }
            } else {
                NSLog("reachCard| (no card — the ledger is empty)")
            }
        },
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
        // `-instagramImport <path>` imports an UNZIPPED Instagram export
        // folder. Logs each category on its OWN line rather than one total:
        // the halves differ in kind (captions and comments are text, saves and
        // likes are named links), and a single number can't tell "the text
        // half was empty" from "the whole import failed" — which for this
        // export is the difference that matters most.
        Hook(key: "instagramImport") { path, context in
            Task { @MainActor in
            let summary = await InstagramImport.run(folder: URL(fileURLWithPath: path), context: context)
            NSLog("Instagram probe: posts=%d comments=%d saved=%d liked=%d",
                  summary.posts, summary.comments, summary.saved, summary.liked)
            NSLog("Instagram probe: %d imported, %d skipped, failed=%d",
                  summary.imported, summary.skipped, summary.failed ? 1 : 0)
            // The CAP's own line (prd §309). A truncated import is otherwise
            // indistinguishable from a complete one in every reading of this
            // probe: healthy counts, no failure flag, and the refused rows
            // appearing nowhere.
            NSLog("Instagram probe: %d dropped by cap", summary.dropped)
            }
        },
        // `-xArchiveImport <path>` imports an UNZIPPED X archive folder (the
        // one holding `data/`, or its parent). Logs each category on its OWN
        // line, plus the reposts it deliberately skipped: the halves differ in
        // kind (your posts are your words, likes are someone else's carrying
        // their own text), and a bare total can't tell "this account never
        // posted" from "the tweets file didn't parse" — which for an archive
        // whose files are JavaScript rather than JSON is the failure most
        // worth being able to see.
        Hook(key: "xArchiveImport") { path, context in
            Task { @MainActor in
            let summary = await XArchiveImport.run(folder: URL(fileURLWithPath: path), context: context)
            NSLog("X probe: posts=%d replies=%d liked=%d reposts-skipped=%d",
                  summary.posts, summary.replies, summary.liked, summary.retweets)
            NSLog("X probe: %d imported, %d skipped, failed=%d",
                  summary.imported, summary.skipped, summary.failed ? 1 : 0)
            // The CAP's own line (2026-08-05). It gets one because a truncated
            // import is otherwise indistinguishable from a complete one in
            // every reading of this probe: the landed counts are healthy, the
            // failure flag is clear, and the thousands of posts the cap refused
            // appear nowhere. That is exactly how a 3,500-post archive read as
            // a successful 1,500-row import for as long as it did.
            NSLog("X probe: dropped-by-cap posts=%d likes=%d, %d awaiting authors",
                  summary.droppedPosts, summary.droppedLikes,
                  XArchiveImport.pendingFaceCount(context: context))
            }
        },
        // `-xFaces <limit|YES>` runs the oEmbed author pass over the liked
        // posts already landed — the second act, exactly as in the UI.
        //
        // Reports named/missed SEPARATELY because they are different facts
        // about different things: a miss is a deleted or protected post and is
        // permanent, while every attempt missing is an endpoint that has
        // changed shape. `unreachable` is only claimed when every attempt
        // failed, since one deleted post legitimately answers 404 on its own.
        Hook(key: "xFaces") { spec, context in
            Task { @MainActor in
                let limit = Int(spec) ?? 200
                let outcome = await XArchiveImport.fetchFaces(limit: limit, context: context)
                NSLog("X faces probe: %d named, %d gone, %d missed, unreachable=%d, %d still waiting",
                      outcome.named, outcome.gone, outcome.missed,
                      outcome.unreachable ? 1 : 0,
                      XArchiveImport.pendingFaceCount(context: context))
            }
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
        // `-snapchatImport <path>` imports an unzipped Snapchat data export
        // folder (chat_history.json + memories_history.json, at the root or
        // one level down). Lands metadata only — the memories' pictures are
        // the separate `-snapchatMedia` pass, exactly as in the UI.
        Hook(key: "snapchatImport") { path, context in
            Task { @MainActor in
                let summary = await SnapchatImport.run(folder: URL(fileURLWithPath: path),
                                                       context: context)
                NSLog("Snapchat probe: %d chats, %d healed, %d memories, %d skipped, failed=%d",
                      summary.chats, summary.healed, summary.memories,
                      summary.skipped, summary.failed ? 1 : 0)
                NSLog("Snapchat probe: %d awaiting pictures, %d dropped by cap",
                      SnapchatImport.pendingMediaCount(context: context),
                      summary.dropped)
            }
        },
        // `-snapchatMedia <limit|YES>` runs the memories' picture fetch over
        // whatever is already landed. The one probe that can tell a dead
        // 7-day export window (every POST fails) from a working one — a
        // landed count alone can't, since a metadata-only import looks
        // identical either way.
        Hook(key: "snapchatMedia") { spec, context in
            Task { @MainActor in
                let limit = Int(spec) ?? 300
                let outcome = await SnapchatImport.fetchMedia(limit: limit, context: context)
                NSLog("Snapchat media probe: %d fetched, %d failed, expired=%d, %d still waiting",
                      outcome.fetched, outcome.failed, outcome.expired ? 1 : 0,
                      SnapchatImport.pendingMediaCount(context: context))
            }
        },
        // `-tiktokImport <path>` imports a TikTok export — the
        // `user_data_tiktok.json` file itself, or a folder holding it. Logs
        // each category on its OWN line for the Instagram reason: what you
        // MADE (your captions, your comments) is text and what you TAPPED
        // (saves, likes) is a bare link, so one total can't tell an export
        // with no text half from an import that failed.
        //
        // Lands metadata only. Giving those links their real faces is the
        // separate `-tiktokFaces` pass, exactly as in the UI.
        Hook(key: "tiktokImport") { path, context in
            Task { @MainActor in
            let summary = await TikTokImport.run(file: URL(fileURLWithPath: path), context: context)
            NSLog("TikTok probe: saved=%d liked=%d posts=%d comments=%d",
                  summary.saved, summary.liked, summary.posts, summary.comments)
            NSLog("TikTok probe: %d imported, %d skipped, failed=%d, %d awaiting faces",
                  summary.imported, summary.skipped, summary.failed ? 1 : 0,
                  TikTokImport.pendingFaceCount(context: context))
            NSLog("TikTok probe: %d dropped by cap", summary.dropped)
            }
        },
        // `-tiktokFaces <limit|YES>` runs the oEmbed face pass over whatever is
        // already landed: caption, creator and poster art per saved video.
        //
        // The one probe that can tell "the endpoint stopped answering the form
        // we send" from "there was nothing left to name" — a landed count
        // can't, since an import with no faces fetched looks identical either
        // way. `unreachable` is only claimed when every attempt failed, since
        // one deleted video legitimately answers 400 on its own.
        Hook(key: "tiktokFaces") { spec, context in
            Task { @MainActor in
                let limit = Int(spec) ?? 200
                let outcome = await TikTokImport.fetchFaces(limit: limit, context: context)
                NSLog("TikTok faces probe: %d named, %d gone, %d missed, unreachable=%d, %d still waiting",
                      outcome.named, outcome.gone, outcome.missed,
                      outcome.unreachable ? 1 : 0,
                      TikTokImport.pendingFaceCount(context: context))
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
        // `-trelloKey <key>` stores Trello's API key — the FIRST of its two
        // credentials. Declared BEFORE `-tokenBridge "Trello:<token>"`, since
        // hooks run in list order and the token's sync reads a stored key.
        Hook(key: "trelloKey") { spec, _ in
            let key = spec.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            if key == "clear" {
                TrelloAuth.clear()
                NSLog("[Casberi] trelloKey: cleared")
            } else {
                TrelloAuth.setKey(key)
                NSLog("[Casberi] trelloKey: stored (%d chars)", key.count)
            }
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
        // `-bitrefillBalanceProbe YES` — the low-balance crossing, phase by
        // phase (2026-08-09, connect first via `-tokenBridge "Bitrefill:<key>"`).
        // Runs the SAME balance read a real sync makes (no separate request),
        // and reports before/after/high-water-mark/bucket so the crossing
        // decision is visible without waiting for a real spending spree. An
        // account fresh to this device never lands an alert on its FIRST run
        // — the high-water mark has just been seeded from that very read, so
        // there's no history yet to call the balance low relative to.
        Hook(key: "bitrefillBalanceProbe") { _, _ in
            guard let token = TokenVault.get(TokenBridge.bitrefill.tokenKey) else {
                NSLog("[Casberi] bitrefillBalanceProbe: no stored token — connect via -tokenBridge \"Bitrefill:<key>\"")
                return
            }
            Task {
                let before = BitrefillBalance.rawAmount
                let alert = await BitrefillFetch.probeBalance(token: token)
                NSLog("[Casberi] bitrefillBalanceProbe: before=%@ now=%@ high=%@ bucket=%@",
                      before.map { String(format: "%.4f", $0) } ?? "none",
                      BitrefillBalance.rawAmount.map { String(format: "%.4f", $0) } ?? "none",
                      BitrefillBalance.highAmount.map { String(format: "%.4f", $0) } ?? "none",
                      BitrefillBalance.bucket ?? "none")
                if let alert {
                    NSLog("[Casberi] bitrefillBalanceProbe: WOULD LAND → %@", alert.title)
                } else {
                    NSLog("[Casberi] bitrefillBalanceProbe: nothing to land (no history yet, not low, or already alerted)")
                }
            }
        },
        // `-trelloProbe YES` reports Trello's read phase by phase with the
        // STORED credentials — the measure tool for a bridge authored against
        // the docs and never run live (see `TrelloAuth`'s UNMEASURED note).
        Hook(key: "trelloProbe") { _, _ in
            Task { @MainActor in await TrelloAuth.diagnose() }
        },
        // Jira takes THREE credentials too, so it takes three hooks — the two
        // below are declared BEFORE `-jiraProbe` and before the `-tokenBridge
        // "Jira:<token>"` line a launch would also pass, because hooks run in
        // list order and a request can only be built once all three have
        // landed (the `-ascKeyID`/`-trelloKey` rule).
        //
        // `-jiraDomain <site>.atlassian.net` — the site, normalized the same
        // way a pasted address-bar URL is (see `JiraAuth.normalizedDomain`).
        Hook(key: "jiraDomain") { value, _ in
            JiraAuth.setDomain(value)
            NSLog("[Casberi] jiraDomain: set")
        },
        // `-jiraEmail <email>` — the Atlassian account a token gets minted
        // for; Basic auth needs it on every request.
        Hook(key: "jiraEmail") { value, _ in
            JiraAuth.setEmail(value)
            NSLog("[Casberi] jiraEmail: set")
        },
        // `-jiraProbe YES` walks the Jira read phase by phase with the STORED
        // credentials (connect the token via `-tokenBridge "Jira:<token>"`) —
        // the measure tool for a bridge authored against the docs and never
        // run live (see `JiraAuth`'s UNMEASURED note).
        Hook(key: "jiraProbe") { _, _ in
            Task { @MainActor in await JiraAuth.diagnose() }
        },
        // `-cloudflareProbe YES` walks the Cloudflare read phase by phase with
        // the STORED token (connect first via `-tokenBridge "Cloudflare:<t>"`).
        // The `-kalshiBookProbe` lesson: an empty Cloudflare room has five
        // causes — no token, a refused token, a token missing a permission, an
        // account with no zones, and the healthy common case where everything
        // is simply current — and all five render as the same one sentence.
        Hook(key: "cloudflareProbe") { _, _ in
            Task { @MainActor in await CloudflareFetch.diagnose() }
        },
        // App Store Connect takes THREE credentials, so it takes three hooks —
        // and they are declared BEFORE `-ascProbe` because hooks run in list
        // order and a token can only be signed once all three have landed
        // (the `-trelloKey`/`-posthogHost` rule).
        //
        // `-ascKeyID <id>` — the ten characters printed beside the key.
        Hook(key: "ascKeyID") { value, _ in
            ASCAuth.setKeyID(value.trimmingCharacters(in: .whitespacesAndNewlines))
            NSLog("[Casberi] ascKeyID: set")
        },
        // `-ascIssuer <uuid>|clear` — EMPTY means an individual key, which is
        // Apple's own discriminator and not a fallback, so `clear` is a real
        // configuration rather than a reset (see `ASCJWT.payloadJSON`).
        Hook(key: "ascIssuer") { value, _ in
            let issuer = value == "clear" ? ""
                : value.trimmingCharacters(in: .whitespacesAndNewlines)
            ASCAuth.setIssuer(issuer)
            NSLog("[Casberi] ascIssuer: %@", issuer.isEmpty ? "empty (individual key)" : "set")
        },
        // `-ascKey <p8|clear>` — the private key. Takes the whole PEM, or just
        // its base64 body with the newlines stripped, which is what survives a
        // shell argument:
        //
        //   -ascKey "$(scripts/dev-keys.sh get asc-p8 | grep -v -- ----- | tr -d '\n')"
        //
        // Inline command substitution, per the dev-keys rule — the value never
        // enters a variable, and `secretArgKeys` keeps it out of `probeArgs:`.
        Hook(key: "ascKey") { value, _ in
            guard value != "clear" else {
                TokenVault.delete(ASCAuth.keyVaultKey)
                ASCAuth.clear()
                NSLog("[Casberi] ascKey: cleared")
                return
            }
            guard let pem = ASCJWT.normalizedPEM(value) else {
                NSLog("[Casberi] ascKey: NOT a readable private key — truncated paste, or the wrong file")
                return
            }
            TokenVault.set(pem, for: ASCAuth.keyVaultKey)
            ASCAuth.forgetToken()
            NSLog("[Casberi] ascKey: stored (%d bytes of PEM)", pem.count)
        },
        // `-ascProbe YES` walks the App Store Connect read phase by phase with
        // the STORED credentials, and dumps one `ascRow|` line per version,
        // review and build. Six causes render as one empty room here and only
        // one is a bug — see `ASCIngest.diagnose`. It is also the only way to
        // tell a 401 from the individual/team claim set being the wrong way
        // round, which is the single likeliest mistake with this credential.
        Hook(key: "ascProbe") { _, _ in
            Task { @MainActor in await ASCIngest.diagnose() }
        },
        // `-ascRoomProbe YES` — what the App Store Connect room LEADS with
        // (2026-08-06, prd §324): every stored standing, then the card's own
        // headline and ranked rows. One NSLog per line (the `-todayProbe`
        // truncation lesson). Spends NOTHING — it composes the card off stored
        // standings exactly as the room does, so it works against whatever the
        // last real sync left behind and needs no key.
        //
        // An empty head has four causes that render as one nothing: not
        // connected, no pass has run on this device (a fresh install syncs rows
        // but not UserDefaults, so the feed is full and the standings empty),
        // the key sees no apps, or the standings failed to decode. Only the
        // last is a bug. The `ascStanding|` lines are the raw reading BEFORE
        // ranking, so a card that led with the wrong app can be told from one
        // whose data was already wrong.
        Hook(key: "ascRoomProbe") { _, _ in
            for line in ASCRoomSource.probeLines() {
                NSLog("[Casberi] ascRoom| %@", line)
            }
        },
        // `-cursorRoomProbe YES` — the Cursor room head's reading, one line at
        // a time (2026-08-08, prd §340). An empty head has five causes that
        // render as one nothing, and only the last two are bugs: not
        // connected, fewer than two placed runs (the healthy new-connection
        // case), everything still in flight, a run whose repository could not
        // be named, or the outcome falling back to title-parsing on rows that
        // should carry the tag. `CursorRoomSource.probeLines` names which.
        Hook(key: "cursorRoomProbe") { _, context in
            var descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == "Cursor" })
            descriptor.fetchLimit = 200
            let rows = (try? context.fetch(descriptor)) ?? []
            for line in CursorRoomSource.probeLines(things: rows) {
                NSLog("[Casberi] %@", line)
            }
        },
        // `-cursorProbe YES` walks the Cursor read phase by phase with the
        // STORED key (connect first via `-tokenBridge "Cursor:<key>"`), and
        // dumps one `cursorAgent|` line per run. Same lesson as the two above:
        // an empty Cursor room has five causes — no key, a refused key, an
        // account that has genuinely never launched a cloud agent, every agent
        // still in flight, and shape drift — and only the last is a bug, while
        // all five render as the same one sentence. It is also the only way to
        // see a status value this build doesn't know, which lands nothing and
        // says nothing. See `CursorFetch.diagnose`.
        Hook(key: "cursorProbe") { _, _ in
            Task { @MainActor in await CursorFetch.diagnose() }
        },
        // `-cloudflareRunwayProbe YES` — what the Cloudflare room LEADS with
        // (2026-08-03, prd §296): the estate snapshot, then the card's own
        // headline, then one `cfRunwayRow|` line per deadline. One NSLog per
        // line (the `-todayProbe` truncation lesson). Reads the corpus and the
        // stored snapshot only — no network, so it costs nothing and works
        // against whatever the last real sync left behind.
        Hook(key: "cloudflareRunwayProbe") { _, context in
            Task { @MainActor in
                for line in CloudflareRunwaySource.probeLines(context: context) {
                    NSLog("[Casberi] cfRunway| %@", line)
                }
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
        // `-stripeProbe YES` reads the STORED Stripe key (connect first via
        // `-tokenBridge "Stripe:<rk_live_…>"`) and NSLogs the RAW shapes —
        // per-endpoint status, the resolved account, the balance buckets, and
        // one `stripeEvent|` line per event with the title it would land
        // wearing. The measure tool for an UNMEASURED API. Reads only, and it
        // does NOT advance the cursor, so it can be re-run over one window.
        Hook(key: "stripeProbe") { _, _ in
            Task { await StripeIngest.probe() }
        },
        // `-stripeRoomProbe YES` — the Stripe ROOM HEAD's reading, line by line
        // (2026-08-04, prd §298). One NSLog per line (the `-todayProbe`
        // truncation lesson). Spends nothing: it composes the card off landed
        // rows and the stored balance, exactly as the room does.
        //
        // It exists because an empty Stripe head has FOUR causes that render as
        // one nothing — not connected, a balance never read on this device (a
        // fresh install syncs rows but not UserDefaults), no row carrying a
        // `dueAt`, or every deadline outside the window — and only two of them
        // are worth acting on.
        Hook(key: "stripeRoomProbe") { _, context in
            for line in StripeRoomSource.probeLines(context: context) {
                NSLog("[Casberi] stripeRoom| %@", line)
            }
        },
        // `-posthogRoomProbe YES` — the same for PostHog's head. Pairs with
        // `-posthogSeed "<event>:<c,c,c>[|total]"`, which plants a reading, so
        // the whole card — discs, ring, silence ordering — verifies with no
        // account and no network at all.
        Hook(key: "posthogRoomProbe") { _, context in
            for line in PostHogRoomSource.probeLines(context: context) {
                NSLog("[Casberi] posthogRoom| %@", line)
            }
        },
        // `-notifyProbe YES` — what would notify, WITHOUT notifying (prd §306).
        //
        // Runs the real sweep over the real corpus in `dryRun`, so it needs no
        // permission grant and fires nothing: one `notifyPlan|` line per plan
        // naming its class, kind, the id it dedupes on, whether the ledger has
        // already spent it, what the right-hand slot resolved to, and whether
        // quiet hours would hold it. Then the whisper line, then the settings.
        //
        // It exists because an empty lock screen has SIX causes that all look
        // identical from outside — permission never asked, a class switched
        // off, the ledger already spent every id, nothing inside the news
        // window, a classify that matched nothing, or iOS simply never running
        // the background task — and only two of those are bugs. The simulator
        // NEVER runs a BGAppRefreshTask at all, so this is the only way to
        // exercise the sweep there.
        //
        // One NSLog per line, not one joined message: the `-todayProbe`
        // truncation lesson.
        Hook(key: "notifyProbe") { _, context in
            Task { @MainActor in
                let things = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
                let (plans, photos) = NotifySweep.plans(things: things)
                let s = Notifications.settings
                NSLog("[Casberi] notify| corpus=%d planned=%d alarms=%@ arrivals=%@ whisper=%@ asked=%@",
                      things.count, plans.count,
                      s.alarms ? "on" : "off", s.arrivals ? "on" : "off",
                      s.whisper ? "on" : "off", Notifications.hasAsked ? "YES" : "NO")
                // Why nothing planned, when nothing planned. One NSLog per
                // line (the `-todayProbe` truncation lesson).
                for line in NotifySweep.skipCensus(things: things) {
                    NSLog("[Casberi] notifySkip| %@", line)
                }
                let ledger = Notifications.ledger
                let cal = Calendar.current
                for plan in plans {
                    let hold = NotifyRules.holdUntil(plan: plan, now: .now,
                                                     quiet: s.quiet, calendar: cal)
                    // Which rung of the ladder the right-hand slot landed on.
                    // `photo` means real bytes are in hand; `remote` means a
                    // URL we would try and may still fall back from; `mark`
                    // means rung 2 outright.
                    let art: String
                    switch plan.art {
                    case .thing: art = photos[plan.id] != nil ? "photo" : "mark(photo-missing)"
                    case .remote: art = "remote→\(plan.source ?? "none")"
                    case .none: art = plan.source.map { "mark:\($0)" } ?? "none"
                    }
                    NSLog("[Casberi] notifyPlan| %@ %@ spent=%@ ts=%@ hold=%@ art=%@ id=%@ · %@",
                          plan.cls.rawValue, plan.kind.rawValue,
                          ledger.hasFired(plan.id) ? "YES" : "no",
                          plan.isTimeSensitive ? "YES" : "no",
                          hold.map { "\($0)" } ?? "no",
                          art, plan.id, plan.title)
                }
                // What `submit` would REALLY schedule — after the settings
                // filter, the ledger and the batching collapse. The gap between
                // this count and `planned=` above is the whole point: it is
                // where "and N more" happened, and where an already-spent id
                // dropped out.
                let live = await Notifications.submit(plans, photos: photos, dryRun: true)
                for plan in live {
                    NSLog("[Casberi] notifySend| %@ · %@ · %@",
                          plan.kind.rawValue, plan.title, plan.body)
                }
                NSLog("[Casberi] notifyWhisper| %@",
                      DayBrief.whisper(things: things.filter(\.isLive))?.detail ?? "(nothing to say)")
            }
        },
        // `-stripeShapeProbe YES` — the same five shapes with NO key and NO
        // network, over synthetic payloads in Stripe's documented envelope.
        // It exists because this bridge was authored against docs alone: the
        // titling, the `dueAt` extraction and the minor-unit maths are the part
        // that can be wrong without any live account to catch it, and they're
        // pure functions, so they can be checked for free. A zero-decimal
        // currency (JPY) rides along on purpose — hardcoding /100 is the Gnosis
        // Pay decimals bug in a new coin, and this is the line that catches it.
        Hook(key: "stripeShapeProbe") { _, _ in
            let due = Int(Date.now.addingTimeInterval(7 * 86_400).timeIntervalSince1970)
            let samples: [[String: Any]] = [
                ["type": "charge.dispute.created", "created": 1_760_000_000,
                 "data": ["object": ["id": "dp_1", "amount": 4900, "currency": "gbp",
                                     "evidence_details": ["due_by": due]]]],
                ["type": "charge.dispute.closed", "created": 1_760_000_100,
                 "data": ["object": ["id": "dp_1", "amount": 4900, "currency": "gbp",
                                     "status": "won"]]],
                ["type": "payout.paid", "created": 1_760_000_200,
                 "data": ["object": ["id": "po_1", "amount": 214_000, "currency": "gbp"]]],
                ["type": "payout.failed", "created": 1_760_000_300,
                 "data": ["object": ["id": "po_2", "amount": 214_000, "currency": "usd",
                                     "failure_message": "account closed"]]],
                ["type": "customer.subscription.deleted", "created": 1_760_000_400,
                 "data": ["object": ["id": "sub_1",
                                     "items": ["data": [["price": ["nickname": "Pro yearly"]]]]]]],
                ["type": "invoice.payment_failed", "created": 1_760_000_500,
                 "data": ["object": ["id": "in_1", "amount_due": 5000, "currency": "jpy",
                                     "next_payment_attempt": due]]],
            ]
            for sample in samples {
                let type = (sample["type"] as? String) ?? "?"
                guard let shaped = StripeShape.shape(sample) else {
                    NSLog("[Casberi] stripeShape| %@ → UNSHAPED", type)
                    continue
                }
                NSLog("[Casberi] stripeShape| %@ → %@ [%@]%@", type, shaped.title, shaped.tag,
                      shaped.dueAt == nil ? "" : " (carries a deadline)")
            }
        },
        // `-appleWalletProbe YES` — the whole Apple Wallet room, headless.
        //
        // Two halves, and the FIRST is the reason this exists. `SHAPE` composes
        // the real `AppleWalletRoom` over a synthetic corpus with NO
        // entitlement, NO FinanceKit and NO device — the only way to see this
        // card at all on a simulator, where `isDataAvailable` is false and
        // every model path takes its unavailable branch. The fixture carries a
        // subscription whose price rose, one that stopped, a pending charge and
        // a foreign one, so the four judgements that can be silently wrong all
        // render in one launch.
        //
        // `LIVE` then reports what the device itself can do — supported,
        // connected, how many rows landed, and whether the real corpus composes
        // a card. An empty Apple Wallet room has FIVE causes that render as one
        // silence (not supported, not connected, access denied, a US-only
        // product on a non-US account, or nothing spent yet) and only the last
        // is normal.
        //
        // One NSLog per line — a joined multi-line message gets truncated by
        // the log reader (the `-todayProbe` lesson).
        Hook(key: "appleWalletProbe") { _, _ in
            let now = Date.now
            func day(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }
            func s(_ m: String, _ a: Double, _ d: Double, cur: String = "USD",
                   settled: Bool = true, refund: Bool = false) -> AppleWalletRoom.Spend {
                AppleWalletRoom.Spend(merchant: m, amount: a, currency: cur,
                                      date: day(d), isSettled: settled, isRefund: refund)
            }
            let fixture: [AppleWalletRoom.Spend] = [
                s("Netflix", 15.49, 93), s("Netflix", 15.49, 62),
                s("Netflix", 15.49, 31), s("Netflix", 17.99, 2),
                s("Spotify", 11.99, 152), s("Spotify", 11.99, 121),
                s("Spotify", 11.99, 91), s("Spotify", 11.99, 60),
                s("Blue Bottle Coffee", 6.50, 1), s("Blue Bottle Coffee", 6.50, 4),
                s("Whole Foods", 88.20, 5), s("Amazon", 43.10, 6),
                s("Amazon", 12.00, 3, refund: true),
                s("Delta", 412.00, 0, settled: false),
                s("Muji", 3800, 8, cur: "JPY"),
            ]
            let dues = [AppleWalletRoom.Due(account: "Apple Card",
                                            date: now.addingTimeInterval(9 * 86_400),
                                            currency: "USD")]
            if let card = AppleWalletRoom.compose(spends: fixture, dues: dues, now: now) {
                NSLog("[Casberi] appleWallet| SHAPE headline: %@", card.headline)
                NSLog("[Casberi] appleWallet| SHAPE subline: %@", card.subline ?? "(none)")
                NSLog("[Casberi] appleWallet| SHAPE currency: %@ · note: %@",
                      card.currency, card.note ?? "(none)")
                for m in card.merchants {
                    NSLog("[Casberi] appleWalletMerchant| %@ · %@ · %d charges · %.0f%%",
                          m.name, AppleWalletRoom.money(m.total, m.currency),
                          m.count, m.share * 100)
                }
                if card.moreMerchants > 0 {
                    NSLog("[Casberi] appleWalletMerchant| (+%d folded)", card.moreMerchants)
                }
                if let c = card.creep {
                    NSLog("[Casberi] appleWalletCreep| %@ %@ → %@ (%+.0f%%)", c.merchant,
                          AppleWalletRoom.money(c.was, c.currency),
                          AppleWalletRoom.money(c.now, c.currency), c.fraction * 100)
                } else {
                    NSLog("[Casberi] appleWalletCreep| (no price rise)")
                }
                for q in card.silences {
                    NSLog("[Casberi] appleWalletSilence| %@ · every ~%dd · %dd overdue",
                          q.merchant, q.expectedEvery, q.overdueDays)
                }
                for u in card.upcoming {
                    NSLog("[Casberi] appleWalletUpcoming| %@ · %@ · %@", u.label,
                          u.kind == .payment ? "PAYMENT (theirs)" : "recurring (ours)",
                          u.isOverdue ? "overdue" : AppleWalletRoom.dayLabel(u.date))
                }
            } else {
                NSLog("[Casberi] appleWallet| SHAPE composed NOTHING — the fixture broke")
            }

            // WHAT WOULD LAND, without landing it. `landChanges` is the half no
            // screen can show: a price rise becomes a row in the feed, and on a
            // simulator the pass it runs in never executes at all. These are the
            // exact refs and titles the bridge would insert, so a dedupe key
            // that repeats on every refresh — or a title that goes stale a day
            // after it lands — is visible here in one launch.
            let fixtureSeries = AppleWalletRoom.recurringSeries(fixture, now: now)
            for c in AppleWalletRoom.creeps(fixtureSeries, now: now) {
                NSLog("[Casberi] appleWalletLand| CREEP %@ → %@",
                      AppleWalletRoom.creepRef(c), AppleWalletRoom.creepLine(c))
            }
            for q in AppleWalletRoom.silences(fixtureSeries, now: now) {
                NSLog("[Casberi] appleWalletLand| SILENCE %@ → %@ (stamped %@)",
                      AppleWalletRoom.silenceRef(q), AppleWalletRoom.silenceTitle(q),
                      AppleWalletRoom.dayLabel(AppleWalletRoom.silenceOccurredAt(q)))
            }
            if AppleWalletRoom.creeps(fixtureSeries, now: now).isEmpty
                && AppleWalletRoom.silences(fixtureSeries, now: now).isEmpty {
                NSLog("[Casberi] appleWalletLand| (nothing would land — the fixture broke)")
            }

            // NORMALIZATION, on the descriptor forms a card statement really
            // carries. The failure worth seeing is not a prefix that fails to
            // strip (one shop ranks as two, which the board shows) but a strip
            // that goes too far and MERGES two real merchants — a total nobody
            // spent, rendered perfectly. So the untouched cases are logged too.
            for raw in ["SQ *BLUE BOTTLE", "TST* BLUE BOTTLE", "PAYPAL *STEAM GAMES",
                        "Amazon.com*2H4KJ8", "AMZN Mktp US*PRIME", "SQUARE ENIX",
                        "Blue Bottle Coffee"] {
                let clean = AppleWalletRoom.normalizeMerchant(raw)
                NSLog("[Casberi] appleWalletName| %@ → %@%@", raw, clean,
                      clean == raw ? "  (untouched)" : "")
            }
            NSLog("[Casberi] appleWallet| LIVE supported=%@ connected=%@",
                  AppleWalletBridge.isSupported ? "YES" : "NO",
                  AppleWalletBridge.connected ? "YES" : "NO")
            for (account, text) in AppleWalletBridge.balances.sorted(by: { $0.key < $1.key }) {
                NSLog("[Casberi] appleWalletBalance| %@ · %@", account, text)
            }
            if AppleWalletBridge.balances.isEmpty {
                NSLog("[Casberi] appleWalletBalance| (none read on this device)")
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
                // Resurfaced is reported beside landed on purpose: a like of a
                // cast the corpus already holds lands NOTHING, so "0 new things"
                // is what a working pass says when the whole job was moving a
                // held post back into view.
                NSLog("Farcaster likes probe: %@ new things, %d resurfaced",
                      added.map(String.init) ?? "FAILED", FarcasterIngest.resurfaced)
            }
        },
        // `-fcRecasts <username>` watches an account's RECASTS (adding the
        // account if new) and syncs — what they rebroadcast lands as things,
        // stamped with the recast's time. Reports resurfaced beside landed for
        // the same reason `-fcLikes` does: a recast of a cast the corpus
        // already holds lands NOTHING and moves it instead.
        Hook(key: "fcRecasts") { name, context in
            let n = FarcasterStore.normalize(name)
            FarcasterStore.shared.add(n)
            FarcasterStore.shared.setRecasts(true, for: n)
            Task { @MainActor in
                let added = await FarcasterIngest.refresh(context: context)
                NSLog("Farcaster recasts probe: %@ new things, %d resurfaced",
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
        // `-fcMine <username>` marks a watched Farcaster account as YOURS and
        // syncs — the inbound half (replies to your casts, likes on them, new
        // followers). The follower ledger seeds SILENTLY on first sight, so
        // the first run of this reports 0 followers by design and the SECOND
        // is the one that can land any; `-inboundProbe YES` reports the state
        // either way.
        Hook(key: "fcMine") { name, context in
            let n = FarcasterStore.normalize(name)
            FarcasterStore.shared.add(n)
            FarcasterStore.shared.setMine(true, for: n)
            Task { @MainActor in
                let added = await FarcasterIngest.refresh(context: context)
                NSLog("Farcaster mine probe: %@ new things, %d resurfaced",
                      added.map(String.init) ?? "FAILED", FarcasterIngest.resurfaced)
            }
        },
        // `-fcSignerProbe <username|YES>` runs the signer sweep directly —
        // which apps can post as you (`Model/FarcasterSigners.swift`), the
        // WalletApprovals shape for social identity. A bare YES uses the first
        // account marked `mine`. Logs one line per landed grant/revocation
        // plus the whole inventory currently held, because the landed count
        // alone reports 0 on every pass after the first — which is what a
        // working sweep looks like once the inventory is in.
        Hook(key: "fcSignerProbe") { spec, context in
            Task { @MainActor in
                let store = FarcasterStore.shared
                let name = FarcasterStore.normalize(spec)
                let account = name.isEmpty || name == "yes"
                    ? store.accounts.first(where: \.mine) ?? store.accounts.first
                    : store.accounts.first { $0.username == name }
                guard let account, let fid = await FarcasterIngest.fid(forName: account.username)
                else { return NSLog("fcSignerProbe: no watched account to read") }
                var existing = IngestSupport.existingSourceRefs(context, source: "Farcaster")
                let added = await FarcasterSigners.sync(fid: fid, existing: &existing,
                                                        context: context)
                if added > 0 { context.saveHonestly() }
                NSLog("fcSignerProbe @%@ (fid %d): %d landed", account.username, fid, added)
                let held = IngestSupport.thingsByRef(context, source: "Farcaster")
                    .filter { $0.key.hasPrefix("farcaster:signer:") }
                    .values.filter(\.isLive)
                    .sorted { $0.capturedAt > $1.capturedAt }
                NSLog("fcSignerProbe inventory: %d held", held.count)
                for thing in held {
                    NSLog("fcSigner| %@ — %@", thing.title,
                          thing.capturedAt.formatted(date: .abbreviated, time: .omitted))
                }
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
        // `-fcPackProbe YES` reads then follows the pinned Farcaster starter
        // pack headlessly (`FarcasterStarterPack`, 2026-08-08) — no sheet
        // needed, since there's nothing to search or pick between (Farcaster's
        // client API has no keyless browse/search, so unlike Bluesky's this
        // pack is pinned in code, not fetched). Reports hydration the same way
        // `-followsProbe`/`-starterPackProbe` do — a landed count alone can't
        // tell a hydrated face from a blank one — then actually follows, so a
        // rerun's delta (should read 0 new) proves the dedupe.
        Hook(key: "fcPackProbe") { spec, _ in
            Task { @MainActor in
                let members = await FarcasterStarterPack.members()
                let faces = members.filter { $0.avatarURL != nil }.count
                let named = members.filter { $0.displayName != nil }.count
                NSLog("fcPackProbe: %d of %d pinned resolved, %d with a face, %d with a display name",
                      members.count, FarcasterStarterPack.people.count, faces, named)
                for m in members.prefix(3) {
                    NSLog("fcPackProbe member · %@ (@%@) fid=%d face=%@",
                          m.displayName ?? m.username, m.username, m.fid, m.avatarURL ?? "nil")
                }
                guard spec == "YES" else { return }
                let n = FarcasterStarterPack.followAll()
                NSLog("fcPackProbe: followed %d new", n)
            }
        },
        // `-inboundProbe YES` reports the INBOUND half's state across both
        // networks (2026-07-31) — which accounts are marked yours, how many of
        // your own recent posts are eligible for the likes/replies reads, how
        // many followers each ledger has recorded, and what actually landed
        // wearing each inbound marker. One NSLog per line (the `-todayProbe`
        // truncation lesson).
        //
        // The one check that the whole half works: a count of landed things
        // alone can't tell "nobody replied" from "the read never ran", and
        // first-sight follower seeding makes a silent pass the CORRECT first
        // result — so the ledger size is what says the read happened.
        Hook(key: "inboundProbe") { _, context in
            Task { @MainActor in
                for (source, prefix, mine) in [
                    ("Farcaster", "fc:",
                     FarcasterStore.shared.accounts.filter(\.mine).map(\.username)),
                    ("Bluesky", "bsky:",
                     BlueskyStore.shared.accounts.filter(\.mine).map(\.handle)),
                ] {
                    let landed = IngestSupport.thingsByRef(context, source: source)
                    NSLog("inbound %@: %d marked mine%@", source, mine.count,
                          mine.isEmpty ? "" : " — " + mine.joined(separator: ", "))
                    for handle in mine {
                        let own = SocialInbound.ownRecentPosts(landed, handle: handle,
                                                               refPrefix: prefix)
                        let key = source == "Farcaster"
                            ? FarcasterStore.followerLedgerKey(handle)
                            : BlueskyStore.followerLedgerKey(handle)
                        let ledger = SocialInbound.FollowerLedger(key: key)
                        // Whether the eligible posts came from the preferred
                        // window or the §331 fallback. Both are correct; the
                        // difference is worth printing because an account whose
                        // newest post is months old used to be read as "no
                        // eligible posts" and now is read at all — so a run
                        // saying `outside the window` is the fallback doing its
                        // job, not a stale corpus.
                        let cutoff = Date.now.addingTimeInterval(-SocialInbound.ownPostWindow)
                        let stale = own.allSatisfy { $0.capturedAt <= cutoff }
                        NSLog("inbound %@ @%@: %d own posts eligible%@, %d followers recorded%@",
                              source, handle, own.count,
                              own.isEmpty ? "" : (stale ? " (all outside the 7d window — newest-first fallback)" : ""),
                              ledger.seen.count,
                              ledger.isFirstSight ? " (FIRST SIGHT — next pass can land)" : "")
                    }
                    let live = landed.values.filter(\.isLive)
                    for marker in ["reply", "follow", "recast"] {
                        NSLog("inbound %@ %@: %d landed", source, marker,
                              live.filter { $0.socialContext == marker }.count)
                    }
                }
            }
        },
        // `-likersProbe YES` dumps WHO liked your posts (2026-08-07, prd §330)
        // — one `liker|` line per post the inbound read has a roll for: the
        // names it resolved, the total behind them, whether that total is a
        // floor (the page was full), and the line the row actually draws.
        //
        // It exists because an empty roll book has FIVE causes that all render
        // as a post with no "Liked by" line, and only the last is a bug: no
        // account is marked `mine`; the first sync of a new account has landed
        // no own posts yet, so `ownRecentPosts` is empty and the read never ran
        // (`-inboundProbe` reports that count); nobody has liked anything
        // inside `ownPostWindow`; the only liker was YOU (self-likes are
        // dropped from the names on purpose); or the node answered
        // `reactionsByCast` and then refused every `userDataByFid`, which is
        // the one that means something is broken — and it is invisible from the
        // outside, since a roll with no resolvable name is deliberately never
        // written at all.
        //
        // Prints the whole book, not just this source's, because the two arms
        // reach it by different roads — Bluesky's names ride the like itself,
        // Farcaster's cost a lookup each — so a book holding one network's
        // rolls and not the other's is the shape of the bug this fixed.
        Hook(key: "likersProbe") { _, _ in
            Task { @MainActor in
                let rolls = SocialLikers.shared.rolls
                NSLog("likersProbe: %d posts with a roll (cap %d, names %d each)",
                      rolls.count, SocialLikers.rollCap, SocialLikers.nameCap)
                for (ref, roll) in rolls.sorted(by: { $0.value.when > $1.value.when }) {
                    NSLog("liker| %@ named=%@ total=%d%@ when=%@ line=%@",
                          ref, roll.handles.joined(separator: ","),
                          roll.total, roll.atLeast ? " (floor — page was full)" : "",
                          ISO8601DateFormatter().string(from: roll.when),
                          roll.line ?? "NONE")
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
        // `-bskyReposts <handle>` watches what a Bluesky account REPOSTS
        // (adding it if new) and syncs — reposted posts land stamped with the
        // repost's time. Costs no extra request: reposts ride the same author
        // feed the account's own posts arrive on. Reports resurfaced beside
        // landed, the `-fcLikes` rule.
        Hook(key: "bskyReposts") { name, context in
            let h = BlueskyStore.normalize(name)
            BlueskyStore.shared.add(h)
            BlueskyStore.shared.setRecasts(true, for: h)
            Task { @MainActor in
                let added = await BlueskyIngest.refresh(context: context)
                NSLog("Bluesky reposts probe: %@ new things, %d resurfaced",
                      added.map(String.init) ?? "FAILED", BlueskyIngest.resurfaced)
            }
        },
        // `-bskyMine <handle>` marks a watched Bluesky account as YOURS and
        // syncs — same inbound half, same silent first-sight seeding as
        // `-fcMine`.
        Hook(key: "bskyMine") { name, context in
            let h = BlueskyStore.normalize(name)
            BlueskyStore.shared.add(h)
            BlueskyStore.shared.setMine(true, for: h)
            Task { @MainActor in
                let added = await BlueskyIngest.refresh(context: context)
                NSLog("Bluesky mine probe: %@ new things, %d resurfaced",
                      added.map(String.init) ?? "FAILED", BlueskyIngest.resurfaced)
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
        // `-x402Lane "<lane[,lane]>|YES"` connects Circle x402 (a comma-separated
        // list of Circle's own category names, e.g.
        // `FINANCIAL_ANALYSIS,PREDICTION_MARKETS`, or YES for every lane) and
        // syncs — headless bridge test. Declared BEFORE `-x402Probe`: hooks run
        // in list order and the probe must read a watched seat.
        Hook(key: "x402Lane") { spec, context in
            let lanes = spec.split(separator: ",")
                .compactMap { X402Category.from(String($0).trimmingCharacters(in: .whitespaces)) }
            if lanes.isEmpty { X402Store.shared.connectDefaults() }
            else { for lane in lanes { X402Store.shared.add(lane) } }
            Task { @MainActor in
                let n = await X402Ingest.refresh(context: context)
                NSLog("Circle x402 probe: %@ listed in", n.map(String.init) ?? "FAILED")
            }
        },
        // `-x402Probe YES` — the directory read PHASE BY PHASE, then one
        // `x402Row|` line per provider (the `-todayProbe` truncation lesson).
        // An empty x402 room has five causes that render as one silence — not
        // connected, the directory unreachable, everything already landed,
        // nothing in a watched lane, or shape drift — and only the last is a
        // bug. It also NAMES any category string this build can't map, which
        // otherwise lands rows in no lane and says nothing about why.
        Hook(key: "x402Probe") { _, context in
            Task { @MainActor in await X402Ingest.diagnose(context: context) }
        },
        // `-x402Faces <YES|reset>` — the second act: one page read per seller
        // for its own `og:image`. `reset` clears the asked-once ledger first,
        // which is the only way to re-ask a seller that answered with nothing
        // (that decline is remembered on purpose). Reports how many rows gained
        // a face, which a landed count can't tell you: a room where every
        // seller's page serves no image is indistinguishable from one where the
        // pass never ran.
        Hook(key: "x402Faces") { spec, context in
            Task { @MainActor in
                if spec.lowercased() == "reset" { X402Faces.reset() }
                let n = await X402Faces.heal(context: context)
                NSLog("x402Faces: %d row(s) gained a face", n)
            }
        },
        // `-sentryHost <host>` — the host to read against (declare it BEFORE
        // `-tokenBridge "Sentry:<token>"`: hooks run in list order, and the
        // token's validation must see the host already set). `-sentryOrg
        // <slug>` picks the organization without driving the picker, which is
        // the only way to reach a connected state headlessly.
        Hook(key: "sentryHost") { spec, _ in
            SentryAccount.host = spec
            NSLog("sentryHost: %@", SentryAccount.host)
        },
        Hook(key: "sentryOrg") { spec, _ in
            SentryAccount.org = spec.trimmingCharacters(in: .whitespaces)
            NSLog("sentryOrg: %@", SentryAccount.org)
        },
        // `-sentryProbe YES` — the read phase by phase, plus one `sentryIssue|`
        // line per issue. See `SentryIngest.diagnose` for the six causes of an
        // empty room that this separates.
        Hook(key: "sentryProbe") { _, _ in
            Task { @MainActor in await SentryIngest.diagnose() }
        },
        // `-vercelProbe YES` — the read phase by phase, plus one
        // `vercelDeploy|` line per deployment naming whether it would land.
        Hook(key: "vercelProbe") { _, _ in
            Task { @MainActor in await VercelFetch.diagnose() }
        },
        // `-pagerdutyProbe YES` — the read phase by phase, plus one
        // `pdIncident|` line per incident carrying BOTH timestamps, since a
        // missing `resolved_at` is what silently turns "resolved after 41 min"
        // into a bare "Resolved".
        Hook(key: "pagerdutyProbe") { _, _ in
            Task { @MainActor in await PagerDutyIngest.diagnose() }
        },
        // `-packageWatch "<npm|pypi>:<name[,name]>"` — watch packages and sync.
        // Splits on the FIRST colon, so a scoped npm name keeps its own
        // characters intact (`npm:@vercel/og`).
        Hook(key: "packageWatch") { spec, context in
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let registry = PackageRegistry(rawValue: parts[0].lowercased()) else {
                NSLog("packageWatch: expected \"<npm|pypi>:<name[,name]>\", got %@", spec)
                return
            }
            for raw in parts[1].split(separator: ",") {
                PackageStore.shared.add(registry, String(raw).trimmingCharacters(in: .whitespaces))
            }
            Task { @MainActor in
                let n = await PackageIngest.refresh(registry, context: context)
                NSLog("packageWatch: %@ | %@ | %@ in", registry.displayName,
                      PackageStore.shared.list(registry).joined(separator: ","),
                      n.map(String.init) ?? "FAILED")
            }
        },
        // `-packageProbe <npm|pypi>` — one `packageRow|` line per watched
        // package with its latest version, the version we already knew, and
        // whether a date could be read at all. The `date=` field is what
        // separates "nothing has been released" from shape drift.
        Hook(key: "packageProbe") { spec, context in
            guard let registry = PackageRegistry(rawValue: spec.lowercased()) else {
                NSLog("packageProbe: expected npm or pypi, got %@", spec)
                return
            }
            Task { @MainActor in await PackageIngest.diagnose(registry, context: context) }
        },
        // `-hfWatch "<author[,author]>"` — watch Hugging Face orgs/people and
        // sync. `-hfPapers YES|NO` switches Daily Papers (declare it BEFORE
        // this hook: hooks run in list order, and the sync must see the
        // flag already set).
        Hook(key: "hfPapers") { spec, _ in
            HuggingFaceStore.shared.dailyPapers = !(spec.lowercased() == "no" || spec == "0")
        },
        Hook(key: "hfWatch") { spec, context in
            for raw in spec.split(separator: ",") {
                HuggingFaceStore.shared.add(String(raw).trimmingCharacters(in: .whitespaces))
            }
            Task { @MainActor in
                let n = await HuggingFaceIngest.refresh(context: context)
                NSLog("hfWatch: %@ | papers=%@ | %@ in",
                      HuggingFaceStore.shared.authors.joined(separator: ","),
                      HuggingFaceStore.shared.dailyPapers ? "YES" : "NO",
                      n.map(String.init) ?? "FAILED")
            }
        },
        // `-hfProbe YES` — what the seat actually HOLDS, one NSLog per row (a
        // joined multi-line message gets truncated by the log reader — the
        // `-todayProbe` lesson). A landed count alone can't separate "this org
        // has published nothing new" from "the read never ran", and it can't
        // show whether a paper kept its abstract, which is the one field
        // nothing on any screen displays (enrichedText is retrieval-only).
        Hook(key: "hfProbe") { _, context in
            Task { @MainActor in
                // `refreshWaiting`, not `refresh` — a `-hfWatch` in the SAME
                // launch is still in flight here, and the plain guard would
                // hand this 0 and let it dump an empty corpus (see the
                // function's own note). So one launch can carry the whole
                // test, rather than the trap being documented around.
                let n = await HuggingFaceIngest.refreshWaiting(context: context)
                NSLog("hfProbe: %@ new | watching %d | papers=%@",
                      n.map(String.init) ?? "FAILED",
                      HuggingFaceStore.shared.authors.count,
                      HuggingFaceStore.shared.dailyPapers ? "YES" : "NO")
                let rows = (try? context.fetch(
                    FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Hugging Face" })
                )) ?? []
                for thing in rows.filter(\.isLive).sorted(by: { $0.capturedAt > $1.capturedAt }).prefix(30) {
                    NSLog("hfRow| %@ | ref=%@ | abstract=%d chars | image=%@",
                          thing.title, thing.sourceRef ?? "-",
                          thing.enrichedText?.count ?? 0,
                          thing.previewImageURL == nil ? "NO" : "YES")
                }
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
        // `-kalshiBookProbe YES` walks the browse room's read PHASE BY PHASE
        // and NSLogs one `kalshiBook|` line each — discovery status, the
        // categories it parsed, then per hydrated event the market count, the
        // quoted count, and the price-shaped keys actually on the wire.
        //
        // One NSLog per line on purpose (the `-todayProbe` truncation lesson).
        // Built for the 2026-08-03 report — "Kalshi says can't reach order
        // book" above a fully populated category strip, i.e. above proof the
        // book HAD been reached — where the room's single sentence covered
        // three different causes and no launch could tell them apart.
        Hook(key: "kalshiBookProbe") { _, _ in
            Task { @MainActor in
                for line in await KalshiWatch.diagnose() { NSLog("kalshiBook| %@", line) }
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
        // `-defiProbe YES` NSLogs each watched wallet's Aave AND Spark
        // (2026-07-30) collateral/debt/health-factor, tagged per protocol,
        // across every active chain (or the honest "no positions found").
        // Pairs with `-walletAddress`.
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
        // `-morphoDelightProbe YES` — forces a real reallocation-alert
        // firing (2026-07-30) by seeding a deliberately-different fake
        // "last seen" allocation snapshot for a held vault, then running
        // the vault-delight sync once. NSLogs the fake baseline, what
        // landed, and any rate-comparison moment that also fired.
        Hook(key: "morphoDelightProbe") { _, context in
            Task { @MainActor in
                let line = await MorphoDeFi.probeDelight(context: context)
                NSLog("Morpho delight probe: %@", line)
            }
        },
        // `-uniswapProbe <blocksBack|YES>` NSLogs each watched wallet's
        // Uniswap V3 book (pair, range status, uncollected fees, or the
        // honest miss). A numeric spec ALSO rewinds every activity cursor
        // that many BLOCKS (not Morpho's days — this rides raw RPC) and
        // runs the settled-activity sweep. Pairs with `-walletAddress` —
        // `0x7516d4e35a369fc18ddfeec0d69c28112fe13bf0` is a real,
        // live-verified out-of-range position on Ethereum (2026-07-30).
        Hook(key: "uniswapProbe") { spec, context in
            Task { @MainActor in
                let line = await UniswapLiquidity.probe(context: context, blocksBack: Int(spec))
                NSLog("Uniswap probe: %@", line)
            }
        },
        // `-uniswapDelightProbe YES` — flips a real held position's stored
        // range bucket to the opposite of its live state, so the
        // range-crossing thing fires deterministically without waiting for
        // a real tick move. NSLogs what landed.
        Hook(key: "uniswapDelightProbe") { _, context in
            Task { @MainActor in
                let line = await UniswapLiquidity.probeDelight(context: context)
                NSLog("Uniswap delight probe: %@", line)
            }
        },
        // `-hyperliquidProbe YES` NSLogs each watched wallet's Hyperliquid
        // book (perp positions with leverage/entry/liq price, spot
        // holdings, staked HYPE) or the honest miss, then runs the
        // position-transition + risk sync and the unlock sync once,
        // reporting what landed. Pairs with `-walletAddress`.
        Hook(key: "hyperliquidProbe") { _, context in
            Task { @MainActor in
                let lines = await HyperliquidDeFi.probe(context: context)
                for line in lines { NSLog("hyperliquidProbe| %@", line) }
            }
        },
        // `-aerodromeProbe YES` NSLogs each watched wallet's veAERO locks
        // (amount, decayed voting power, permanent?, lock end, last voted)
        // or the honest miss, plus the live epoch window, then runs the
        // vote-deadline + lock-expiry sync once. Pairs with `-walletAddress`.
        Hook(key: "aerodromeProbe") { _, context in
            Task { @MainActor in
                let lines = await AerodromeDeFi.probe(context: context)
                for line in lines { NSLog("aerodromeProbe| %@", line) }
            }
        },
        // `-etherfiUnstakeProbe YES` NSLogs each watched wallet's outstanding
        // ether.fi unstake requests (amount, queued vs CLAIMABLE) or the
        // honest miss, then runs the reconciling sync. The queued/claimable
        // split is the point: a count alone can't separate "nothing is
        // claimable yet" from "the finalized read didn't run". Pairs with
        // `-walletAddress`.
        Hook(key: "etherfiUnstakeProbe") { _, context in
            Task { @MainActor in
                let lines = await EtherFiUnstake.probe(context: context)
                for line in lines { NSLog("etherfiUnstakeProbe| %@", line) }
            }
        },
        // `-etherfiCashProbe <blocksBack|YES>` NSLogs, per watched wallet,
        // whether it's an ether.fi Cash account at all (the `isEtherFiSafe`
        // gate — "not a Cash account" and "couldn't reach Optimism" read
        // differently on purpose), then its collateral/debt/health, then runs
        // the spend sweep and the risk check. A numeric spec rewinds the
        // cursors so real past spends land headlessly. Pairs with
        // `-walletAddress <a Cash safe address>`.
        Hook(key: "etherfiCashProbe") { spec, context in
            let back = Int(spec)
            Task { @MainActor in
                let lines = await EtherFiCash.probe(context: context, blocksBack: back)
                for line in lines { NSLog("etherfiCashProbe| %@", line) }
            }
        },
        // `-compositionProbe YES` NSLogs the Wallet card's composition strip
        // (prd §240) — what's deposited into protocols, what's locked in its
        // own units, what's owed, and WHICH protocols each came from. One
        // NSLog per line (the `-todayProbe` truncation lesson). Reads the
        // same live state the feed reads, so it exercises the real gather
        // rather than a parallel one; pair with `-walletAddress`.
        Hook(key: "compositionProbe") { _, context in
            Task { @MainActor in
                let live = await WalletWatch.liveState(context: context)
                let composition = WalletComposition.from(
                    aave: live.positions, morpho: live.morpho, uniswap: live.uniswap,
                    hyperliquid: live.hyperliquid, aerodrome: live.aerodrome,
                    etherfiCash: live.etherfiCash, etherfiUnstake: live.etherfiUnstake)
                for line in composition.probeLines { NSLog("compositionProbe| %@", line) }
            }
        },
        // `-seedFlow "in:Coinbase:2100,out:Aave:1000[,…]"` plants priced
        // transfer things so the flow band draws headlessly (2026-08-01).
        //
        // It exists because the band's inputs are the most expensive in the
        // room to come by honestly: a landed transfer carrying a USD value
        // needs a keyed Zerion sync against a wallet that actually moved money
        // in the window. Without this the card could only ever be seen by
        // waiting for real money to move — the same reason `-posthogSeed`
        // plants a reading and `-seedWalletHistory` plants a line.
        //
        // Declared BEFORE `-flowProbe` (hooks run in list order), so one
        // launch can seed and then report. Spaced an hour apart so a window
        // narrower than a day still contains them.
        Hook(key: "seedFlow") { spec, context in
            let entries = spec.split(separator: ",")
            // Deduped on sourceRef like every real bridge, because re-running
            // a seed is the normal way to use it and a second run otherwise
            // silently DOUBLES every lane — which reads as the band computing
            // wrong rather than as the seed running twice (observed, 2026-08-01).
            let existing = Set(
                ((try? context.fetch(FetchDescriptor<Thing>())) ?? [])
                    .compactMap { $0.sourceRef })
            var planted = 0
            for (index, entry) in entries.enumerated() {
                // Split on the LAST TWO colons so a counterparty may carry its
                // own (the `-keepAskProbe` lesson).
                let parts = entry.split(separator: ":")
                guard parts.count >= 3, let usd = Double(parts[parts.count - 1]) else { continue }
                let received = parts[0] == "in"
                let name = parts[1..<(parts.count - 1)].joined(separator: ":")
                let ref = "seedflow:\(index):\(name):\(usd)"
                if existing.contains(ref) { continue }
                let thing = Thing(
                    kind: .transaction,
                    title: received ? "Received from \(name)" : "Sent to \(name)",
                    content: "https://etherscan.io/tx/0xseed\(index)",
                    source: "Wallet",
                    capturedAt: Date.now.addingTimeInterval(-Double(index + 1) * 3600),
                    sourceRef: ref)
                thing.transferDirection = received ? "received" : "sent"
                thing.transferCounterparty = name
                thing.transferAmount = String(format: "%.2f USDC", usd)
                thing.transferUSD = usd
                context.insert(thing)
                planted += 1
            }
            try? context.save()
            NSLog("seedFlow: planted %d transfer(s)", planted)
        },
        // `-flowProbe <days|YES>` NSLogs the flow band (2026-08-01) — the
        // window's in/out totals, every lane either side with what it was
        // worth and how many moves folded into it, and how many moves reached
        // us unpriced. A bare YES reads the whole record; a number bounds it
        // to that many days, which is how the room's own week/month windows
        // are exercised headlessly.
        //
        // Prices ride the transfer read itself (Zerion's `value`), so this
        // spends NOTHING beyond the corpus already on disk — but a corpus
        // synced before that field existed has no prices at all, and the
        // probe's `priced=` count is how that reads rather than an empty card
        // with no explanation.
        Hook(key: "flowProbe") { spec, context in
            Task { @MainActor in
                let days = Int(spec)
                for line in WalletFlowSource.probeLines(context: context, days: days) {
                    NSLog("flowProbe| %@", line)
                }
            }
        },
        // `-riskStripProbe YES` NSLogs the distance-to-liquidation strip
        // (2026-08-01) — each book's size, both protocol thresholds, and every
        // dot with its headroom, its axis position and its own protocol's
        // verdict. Reads the same live state the feed reads, so it exercises
        // the real gather rather than a parallel one; pair with
        // `-walletAddress <a wallet that actually borrows>`.
        Hook(key: "riskStripProbe") { _, context in
            Task { @MainActor in
                let live = await WalletWatch.liveState(context: context)
                let lines = WalletRiskScaleSource.probeLines(
                    aave: live.positions, morpho: live.morpho, hyperliquid: live.hyperliquid)
                for line in lines { NSLog("riskStripProbe| %@", line) }
            }
        },
        // `-exposureProbe YES` NSLogs the approvals card's whole reading
        // (2026-08-03, prd §292): the headline, then one `exposureRow|` line
        // per grant naming the four fields every shaping decision rests on —
        // the live allowance's verdict (unlimited/capped/forAll), the dollars
        // at stake, whether they could be known at all, and the grant's age.
        //
        // One NSLog per line, not one joined message (the `-todayProbe`
        // truncation lesson). Reads the same live state the room reads, so it
        // exercises the real gather rather than a parallel one.
        //
        // It exists because an empty or wrong-looking card has FOUR causes
        // that render identically — no watched wallet, no live grant, a
        // holdings read that didn't price the token, or a `decimals()` that
        // didn't answer — and only the last two are bugs. The `usd=unknown`
        // and `dec=?` fields are what separate them in one launch. Pair with
        // `-walletAddress` and `-approvalProbe <blocksBack>` to land grants
        // first.
        Hook(key: "exposureProbe") { _, context in
            Task { @MainActor in
                let live = await WalletWatch.liveState(context: context)
                let e = live.exposure
                NSLog("exposureProbe| %@", WalletApprovalExposure.headline(
                    spenders: e.spenderCount, total: e.total))
                NSLog("exposureProbe| priced=%d unpriced=%d total=%@",
                      e.priced.count, e.unpriced.count,
                      WalletApprovalExposure.money(e.total))
                for g in e.all {
                    NSLog("exposureRow| %@ | %@ | usd=%@ | granted=%@",
                          g.spender, g.stateLine,
                          g.usd.map(WalletApprovalExposure.money) ?? "unknown",
                          g.grantedAt.map { WalletApprovalAge.text($0) } ?? "unread")
                }
                if let target = e.oldestWorthReviewing {
                    NSLog("exposureProbe| button→ %@ (%@)", target.spender, target.stateLine)
                }
                if let note = e.unpricedNote { NSLog("exposureProbe| note: %@", note) }
            }
        },
        // `-connectionsProbe YES` — the address book's connections card
        // (2026-08-03, prd §295), phase by phase: how many wallets are
        // watched, how many transfers survived each exclusion, the headline,
        // then one `connRow|` line per connected address and one
        // `connWallet|` per wallet it reaches.
        //
        // One NSLog per line (the `-todayProbe` truncation lesson). It exists
        // because an empty card has FOUR causes that render as the same
        // silence — fewer than two wallets watched, no landed transfers, every
        // address reaching exactly one wallet (the honest common case), or an
        // exclusion eating them — and only the last is a bug. The
        // `excludedFlagged`/`excludedMachinery` tallies are what separate them
        // in one launch. Pair with `-walletAddress` (twice, on two launches —
        // the hook fires once per run).
        Hook(key: "connectionsProbe") { _, context in
            Task { @MainActor in
                for line in AddressConnections.probeLines(context: context) {
                    NSLog("connections| %@", line)
                }
            }
        },
        // `-userOpProbe YES` — who actually paid (2026-08-03, prd §293). Walks
        // the wallet's recent outgoing transactions, re-reads each receipt and
        // NSLogs one `userOp|` line per transaction naming the attribution the
        // gas total now uses: paid / sponsored (with the paymaster) / not
        // yours. Plus any UNKNOWN EntryPoint emitter, which is the drift line
        // — a new EntryPoint version shows up as gas we decline to correct
        // rather than as a wrong number.
        //
        // It exists because the old behaviour was invisible: a running total
        // renders perfectly whatever is in it, and a smart account was being
        // charged a whole bundle's gas (or a paymaster's) with nothing on any
        // screen to say so.
        Hook(key: "userOpProbe") { _, context in
            Task { @MainActor in
                for line in await WalletGas.attributionProbeLines(context: context) {
                    NSLog("userOp| %@", line)
                }
            }
        },
        // `-actingPartiesProbe YES` — what else can act as your account
        // (2026-08-03, prd §293): Safe modules (which move funds with NO
        // signature), the EIP-7702 delegate that runs as your wallet, and the
        // ERC-7579 `accountId()` naming what the address is. One NSLog per
        // line (the `-todayProbe` truncation lesson).
        //
        // `modulesUnreadable=YES` is the interesting field: a 7579 account's
        // installed modules structurally cannot be enumerated (the standard
        // has `isModuleInstalled` and no listing call), so an empty party list
        // on a smart account means "we can't see", never "nothing installed".
        Hook(key: "actingPartiesProbe") { _, _ in
            Task { @MainActor in
                for line in await WalletActingParties.probeLines() {
                    NSLog("actingParties| %@", line)
                }
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
        // `-peerSeedDeposit "<depositId>[|wallet]"` plants an open-deposits
        // watchlist entry for a real depositId, so the next `-peerProbe`
        // exercises the sell/stuck-intent paths (prd §237) against a
        // deposit's real signal history instead of waiting for a fresh
        // deposit to be made. Declared BEFORE `-peerProbe` (list order).
        Hook(key: "peerSeedDeposit") { spec, _ in
            PeerBridge.seedDeposit(spec: spec)
            NSLog("Peer seed: %@", PeerBridge.openDepositsSummary())
        },
        // `-peerProbe <blocksBack|YES>` switches the Peer seat on and runs the
        // fill sweep over the watched wallets, NSLogging the landed count. A
        // numeric spec rewinds every Peer cursor that many blocks below the
        // Base head first, so real past fills land and the whole path (logs →
        // signal join → deposit token → titles → things) verifies headlessly.
        // Also runs the sell-side deposit-discovery scan and polls the
        // open-deposits watchlist (prd §237), logged alongside the count.
        // Pairs with `-walletAddress`.
        Hook(key: "peerProbe") { spec, context in
            // No seat to switch on anymore (automatic, prd §207) — `probe`
            // rewinds cursors and runs the sweep over the watched wallets
            // directly, so pair this with `-walletAddress`.
            Task { @MainActor in
                let n = await PeerBridge.probe(context: context, blocksBack: Int(spec))
                NSLog("Peer probe: %@ landed; %@",
                      n.map(String.init) ?? "FAILED", PeerBridge.openDepositsSummary())
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
                let cover = await PrivacyPoolsBridge.coverSummary()
                NSLog("Privacy Pools probe: %@ landed; %@; %@",
                      n.map(String.init) ?? "FAILED",
                      PrivacyPoolsBridge.pendingSummary(), cover)
            }
        },
        // `-railgunProbe <blocksBack|YES>` runs the Railgun sweep over the
        // watched wallets, NSLogging the landed count, which watched wallets
        // turned out to use Railgun, and one line PER ROW with the amount it
        // actually wrote — a count alone can't tell a correct amount from one
        // off by twelve decimal places, which is the trap this bridge is most
        // exposed to (Railgun takes any ERC-20, so a pass sees 18-decimal
        // WETH beside 6-decimal USDC). A numeric spec rewinds every cursor
        // that many blocks below the mainnet head first; a fresh install
        // backfills from the deploy block by design, so a plain YES already
        // lands real history for a wallet that has used Railgun. Pair with
        // `-walletAddress <a Railgun user>`.
        Hook(key: "railgunProbe") { spec, context in
            Task { @MainActor in
                let n = await RailgunBridge.probe(context: context, blocksBack: Int(spec))
                NSLog("Railgun probe: %@ landed; %@",
                      n.map(String.init) ?? "FAILED",
                      RailgunBridge.accountSummary())
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
        // `-scopeMaterialProbe YES` — what each brief scope actually HAS to
        // draw with (2026-08-10). Written before building the four new scope
        // visualizations rather than after, because every one of them rests on
        // a field being populated often enough to make a shape, and "does the
        // corpus carry this" is exactly the question that gets assumed and
        // turns out false (§313's treemap counting t.co, §307's topicSource
        // returning nil for X). One line per scope: how many things, how many
        // carry a picture, a face, a deadline, a release-shaped event.
        //
        // Counts only — never a title, a handle or a URL. This walks somebody's
        // whole corpus, and a probe that prints what is in it is a probe nobody
        // can safely run in a sweep (`-secretScanProbe`'s own rule).
        Hook(key: "scopeMaterialProbe") { _, context in
            let all = ((try? context.fetch(FetchDescriptor<Thing>())) ?? []).live
            let now = Date.now
            for scope in BriefScope.scopes {
                let sources = Set(BridgeCatalog.offers
                    .filter { BriefScope.scope(forCatalogCategory: BridgeCatalog.category(of: $0)) == scope }
                    .map(\.name))
                let mine = all.filter { sources.contains($0.source) }
                // A PICTURE is any of the three the app can actually draw —
                // stored bytes, a preview URL, or a post's own image list.
                let pics = mine.filter {
                    $0.previewImageData != nil || !($0.previewImageURL ?? "").isEmpty
                        || !$0.imageURLs.isEmpty
                }
                let faces = mine.filter { !($0.authorAvatarURL ?? "").isEmpty }
                let named = Set(mine.compactMap { $0.authorHandle ?? $0.postAuthor })
                let due = mine.filter { $0.mark != .done && $0.dueAt != nil }
                let ahead = due.filter { ($0.dueAt ?? .distantPast) >= now }
                NSLog("scopeMaterial| %@ things=%d pics=%d faces=%d people=%d due=%d ahead=%d",
                      scope, mine.count, pics.count, faces.count, named.count, due.count, ahead.count)
            }
        },
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
                let colliding = AddressBook.shared.collidingKeys
                let groups = AddressBook.shared.groupNames
                NSLog("Address-book probe: groups=%@",
                      groups.isEmpty ? "(none)"
                        : groups.map { "\($0)(\(AddressBook.shared.entries(inGroup: $0).count))" }
                            .joined(separator: ", "))
                // LOOKALIKES on their own line, not folded into the roll below:
                // a poisoning collision is the one finding here that means
                // something is wrong rather than merely describing the book.
                NSLog("Address-book probe: lookalike collisions=%d", colliding.count)
                for entry in AddressBook.shared.all {
                    NSLog("  %@ · %@ · kind=%@%@%@%@%@", entry.name, entry.short,
                          entry.kind.rawValue,
                          watched.contains(entry.id) ? " · WATCHED" : "",
                          entry.provenance.map { " · from \($0)" } ?? "",
                          entry.groupNames.isEmpty ? ""
                            : " · in \(entry.groupNames.joined(separator: "/"))",
                          colliding.contains(entry.id) ? " · ⚠︎ LOOKALIKE" : "")
                }
            }
        },
        // `-retitleProbe YES|<address>` — run the counterparty rewrite that a
        // name triggers (2026-08-01) and NSLog how many landed things it
        // changed. `YES` brings the whole corpus in line with the whole book
        // (the bulk-paste path); an address does just that one (every other
        // naming door). The count IS the feature — naming an address rewrites
        // history, and this is the only headless way to see that happen. The
        // cascade the address card animates cannot be probed; the substance
        // underneath it can. Pair with `-addressBook "Mom:0x…"`, declared
        // first, since hooks run in list order.
        Hook(key: "retitleProbe") { spec, context in
            Task { @MainActor in
                let changed = spec == "YES" || spec.isEmpty
                    ? CounterpartyRetitle.applyBook(in: context)
                    : CounterpartyRetitle.applyCurrentName(for: spec, in: context)
                NSLog("Retitle probe: %@ → %d retitled (name=%@)",
                      spec.isEmpty ? "YES" : spec, changed,
                      spec == "YES" || spec.isEmpty
                        ? "whole book"
                        : (CounterpartyRetitle.realName(for: spec) ?? "(none — clause stripped)"))
            }
        },
        // `-addressGroup "<Group>:<address>[,<address>…]"` — file addresses
        // into a group headlessly (2026-08-01). Splits on the FIRST colon, so
        // the addresses that follow may carry their own. An address with no
        // entry yet is named with its short form first, exactly as the tap
        // does — a group can never name an address the book doesn't hold.
        //
        // Rides the BULK call (2026-08-01) because that is what the book-level
        // "New group" sheet calls — a probe walking the per-address loop would
        // be exercising a path the UI no longer takes. It also reports the
        // spelling actually filed under, which is the one outcome that differs
        // from what you asked for: "family" against a book already holding
        // "Family" joins the existing group rather than making a second one.
        Hook(key: "addressGroup") { spec, _ in
            guard let colon = spec.firstIndex(of: ":") else { return }
            let group = String(spec[spec.startIndex..<colon])
            let addresses = String(spec[spec.index(after: colon)...])
                .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let filed = AddressBook.shared.addToGroup(group, addresses: addresses)
            NSLog("Address-group probe: %@ → filed under %@, now holds %d",
                  group, filed ?? "(nothing — blank name or no addresses)",
                  filed.map { AddressBook.shared.entries(inGroup: $0).count } ?? 0)
        },
        // `-addressSafetyProbe <address>` — the two checks the omnibox makes
        // before you commit (2026-08-01), headless: the EIP-55 checksum
        // verdict and any book entry this address would print identically to.
        // One NSLog per fact — a joined line truncates (the `-todayProbe`
        // lesson), and these are read one at a time anyway.
        Hook(key: "addressSafetyProbe") { address, _ in
            let verdict: String
            switch AddressSafety.checksum(address) {
            case .verified: verdict = "verified"
            case .failed: verdict = "FAILED — a character is wrong"
            case .unavailable: verdict = "unavailable (no case to check)"
            }
            NSLog("Address-safety probe: %@", address)
            NSLog("  display=%@", AddressSafety.displayForm(address) ?? "(not a raw address)")
            NSLog("  checksum=%@", verdict)
            let twins = AddressBook.shared.lookalikes(of: address)
            NSLog("  lookalikes=%d", twins.count)
            for twin in twins {
                NSLog("  ⚠︎ prints as %@ but is %@ (%@)", twin.short, twin.address, twin.name)
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
        // `-photoHealProbe YES` runs the Photos HEAL directly — the additive
        // pass that OCRs, thumbnails and retitles (§218) — then `pruneDeleted`,
        // the deletion-sync pass (prd §231, 2026-07-30). `-reingestPhotos` only
        // LANDS assets; OCR has always lived here, which is why a landing probe
        // alone leaves every row still saying "Screenshot". Logs what the pass
        // did, then every screenshot's title and how many OCR characters back
        // it — the one view that separates "OCR found nothing" (wordless, so
        // the row should be a picture) from "the retitle didn't fire".
        Hook(key: "photoHealProbe") { _, context in
            Task { @MainActor in
                let r = await ScreenshotIngest.heal(context: context)
                let pruned = ScreenshotIngest.pruneDeleted(context: context)
                NSLog("[Casberi] photoHeal: thumbed=%d ocred=%d pruned=%d",
                      r.thumbed, r.ocred, pruned)
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
        // ── The on-device intelligence pass (prd §282, 2026-08-02) ──────────
        //
        // `-embeddingProbe YES` — the semantic index's LANGUAGE census. The
        // one view that shows whether multilingual keying is actually doing
        // anything: how many stored vectors are legacy (untagged, English by
        // definition), how many carry each language tag, and which language a
        // query would be embedded in. A count of embedded things alone can't
        // tell "the corpus is English" from "every Spanish note is still
        // wearing an English vector nothing will ever match" — which is the
        // exact failure this feature exists to end, and it is invisible at
        // runtime because retrieval degrades silently rather than erroring.
        Hook(key: "embeddingProbe") { _, context in
            Task { @MainActor in
                let things = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
                var tagged: [String: Int] = [:]
                var unembedded = 0, empty = 0
                for thing in things where thing.isLive {
                    guard let data = thing.embedding else { unembedded += 1; continue }
                    guard !data.isEmpty else { empty += 1; continue }
                    let language = EmbeddingIndex.Header.language(of: data)?.rawValue ?? "unreadable"
                    tagged[language, default: 0] += 1
                }
                // One NSLog per line — a joined multi-line message is
                // truncated by the log reader (the `-todayProbe` lesson).
                NSLog("embeddingProbe: corpus=%d embedded=%d pending=%d unembeddable=%d",
                      things.count, tagged.values.reduce(0, +), unembedded, empty)
                for (language, n) in tagged.sorted(by: { $0.value > $1.value }) {
                    NSLog("embeddingLang| %@ = %d", language, n)
                }
                NSLog("embeddingProbe: dominant=%@ queryLanguageForShortAsk=%@",
                      EmbeddingIndex.dominantLanguage?.rawValue ?? "—",
                      EmbeddingIndex.queryLanguage(for: "travel plans").rawValue)
                let fixed = await EmbeddingIndex.remedyMistagged(context: context)
                NSLog("embeddingProbe: remedyCleared=%d", fixed)
            }
        },
        // `-embedRaceProbe <rounds|YES>` — the ONE thing a build cannot prove
        // about the 2026-08-07 fix (builds 280 and 281): that several threads
        // may embed AT ONCE. `NLEmbedding` is not safe to call from two
        // threads and does not say so, and the app has always driven it from
        // two places that run in the same foreground pass — the backfill
        // sweep's detached utility task (`EmbeddingIndex.packedVectors`) and
        // the main actor's ask (`Retriever.rank` → `queryVector`). All four
        // crash stacks across the two reports bottomed out in the SAME
        // function, `EmbeddingIndex.vector(for:language:)`, so this hammers
        // exactly that function.
        //
        // FOUR concurrent embedders, not two, matching the experiment that
        // proved the race: four threads on one shared model died 3/3 unlocked
        // (SIGSEGV/SIGTRAP) and survived 12,000 inferences 3/3 serialized. Two
        // threads reproduce it too, but more slowly — and a probe that needs
        // several runs to fail is one somebody concludes is fine.
        //
        // WHAT A PASS AND A FAIL LOOK LIKE, because they are not symmetric: a
        // fail is a SIGSEGV inside `BNNSFilterApplyBatch` and the probe prints
        // NOTHING (the process is gone — the trapping-harness lesson from
        // `retriever-selftest`), so an absent `SURVIVED` line IS the failure.
        // A pass is one `SURVIVED` line with both counts non-zero. Run it
        // against a build WITHOUT the lock and it should die; that is the only
        // way to know this probe can fail at all.
        //
        // Both halves are pinned to `.english` deliberately. The race needs
        // ONE model object, and a corpus whose dominant language isn't English
        // would send the two halves to two different models — which is a
        // weaker test that would pass on the broken build too.
        Hook(key: "embedRaceProbe") { spec, context in
            let rounds = max(1, Int(spec) ?? 50)
            Task { @MainActor in
                guard EmbeddingIndex.isAvailable else {
                    NSLog("embedRaceProbe: NO SENTENCE MODEL here — the race cannot be run on this device")
                    return
                }
                // Real corpus text where there is any, so the inputs are the
                // lengths the app really embeds; a synthetic fallback so the
                // probe still works on an empty install. Mapped to `[String]`
                // ON THE MAIN ACTOR, before any suspension and before anything
                // is handed to a detached task — no `Thing` crosses a thread
                // or an `await` here (liveness corollary 6).
                let corpus = ((try? context.fetch(FetchDescriptor<Thing>())) ?? [])
                    .filter(\.isLive)
                let texts: [String] = corpus.isEmpty
                    ? (1...32).map { "Flight to Lisbon on the \($0)th, hotel near the water, dinner booked" }
                    : corpus.prefix(32).map(EmbeddingIndex.indexText(for:)).filter { !$0.isEmpty }
                guard !texts.isEmpty else {
                    NSLog("embedRaceProbe: nothing embeddable in this corpus")
                    return
                }
                NSLog("embedRaceProbe: rounds=%d texts=%d lanes=4 — 3 detached utility + main actor",
                      rounds, texts.count)
                // The SWEEP's half — THREE detached utility tasks, which is
                // the exact context `packedVectors` runs on and the queue the
                // crash reports name (com.apple.root.utility-qos.cooperative).
                // Three plus the main actor is the four-way contention the
                // race was proven with.
                let sweeps = (0..<3).map { lane in
                    Task.detached(priority: .utility) {
                        var n = 0
                        for round in 0..<rounds {
                            // Offset per lane so the three don't march in step
                            // through identical strings — identical inputs are
                            // the easiest case, not the hardest.
                            for i in texts.indices {
                                let text = texts[(i + lane) % texts.count]
                                if EmbeddingIndex.vector(for: text, language: .english) != nil { n += 1 }
                            }
                            if round.isMultiple(of: 8) { await Task.yield() }
                        }
                        return n
                    }
                }
                // The ASK's half — on the main actor, where `Retriever.rank`
                // embeds. `queryVector` once first so the real entry point is
                // exercised too, then the shared function both crash stacks
                // named.
                var asks = 0
                if EmbeddingIndex.queryVector(for: "travel plans") != nil { asks += 1 }
                for round in 0..<rounds {
                    if EmbeddingIndex.vector(for: "what did I save about travel \(round)",
                                             language: .english) != nil { asks += 1 }
                    await Task.yield()
                }
                var embeds = 0
                for sweep in sweeps { embeds += await sweep.value }
                NSLog("embedRaceProbe: SURVIVED asks=%d embeds=%d lanes=4", asks, embeds)
            }
        },
        // `-relatedProbe "<title prefix>"` — what the thing sheet would show
        // UNDER a thing: the earlier copy of it (deterministic), then its
        // semantic neighbours. Keyed on a title prefix, not a UUID, for the
        // `-openThing` reason: a UUID changes every install, a title doesn't.
        //
        // The two halves are logged separately because they answer differently
        // and fail differently — a missing "kept before" is usually correct
        // (most things are kept once), while empty neighbours on an embedded
        // corpus means the vectors aren't comparable, which is a bug.
        Hook(key: "relatedProbe") { prefix, context in
            Task { @MainActor in
                var descriptor = FetchDescriptor<Thing>(
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
                descriptor.fetchLimit = 300
                let all = (try? context.fetch(descriptor)) ?? []
                guard let subject = all.first(where: {
                    $0.isLive && $0.title.lowercased().hasPrefix(prefix.lowercased())
                }) else {
                    NSLog("relatedProbe: no thing whose title starts with %@", prefix)
                    return
                }
                NSLog("relatedProbe: subject=%@ · %@ embedded=%@", subject.title, subject.source,
                      (subject.embedding.map { !$0.isEmpty } ?? false) ? "YES" : "NO")
                if let earlier = RelatedThings.keptBefore(subject, in: all) {
                    NSLog("relatedKept| %@ · %@ · %@", earlier.title, earlier.source,
                          earlier.capturedAt.formatted(date: .abbreviated, time: .omitted))
                } else {
                    NSLog("relatedKept| none")
                }
                let near = RelatedThings.neighbours(of: subject, in: all)
                NSLog("relatedProbe: neighbours=%d", near.count)
                for t in near { NSLog("relatedNear| %@ · %@", t.title, t.source) }
            }
        },
        // `-linksProbe "<title prefix>"` — what the thing sheet's "Points at
        // this" shelf shows (prd §340): every other thing whose text names or
        // links this one, and why. Keyed on a title prefix like `-relatedProbe`.
        //
        // An empty result is the healthy common case (most things are pointed
        // at by nothing) — the probe exists to make sure a REAL edge (a note
        // that wikilinks the subject, a post whose text carries its link)
        // isn't silently missed, not to prove every thing has one.
        Hook(key: "linksProbe") { prefix, context in
            Task { @MainActor in
                var descriptor = FetchDescriptor<Thing>(
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
                descriptor.fetchLimit = 300
                let all = (try? context.fetch(descriptor)) ?? []
                guard let subject = all.first(where: {
                    $0.isLive && $0.title.lowercased().hasPrefix(prefix.lowercased())
                }) else {
                    NSLog("linksProbe: no thing whose title starts with %@", prefix)
                    return
                }
                NSLog("linksProbe: subject=%@ · %@ link=%@", subject.title, subject.source,
                      ThingLinks.canonicalLink(subject.content) ?? "none")
                let ties = ThingLinksSource.ties(for: subject, context: context)
                NSLog("linksProbe: pointingAt=%d", ties.count)
                for tie in ties {
                    NSLog("linksTie| %@ · %@ · %@", tie.title, tie.edge.reason, tie.source)
                }
            }
        },
        // `-factsProbe "<title prefix>"` — the upcoming moments a screenshot's
        // own OCR text names, and where each half came from. Logs the
        // DETERMINISTIC dates and the MODEL's label separately, on purpose:
        // the whole design rests on the date never being the model's, and a
        // combined line couldn't show that the split held.
        Hook(key: "factsProbe") { prefix, context in
            Task { @MainActor in
                var descriptor = FetchDescriptor<Thing>(
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
                descriptor.fetchLimit = 300
                let all = (try? context.fetch(descriptor)) ?? []
                guard let subject = all.first(where: {
                    $0.isLive && $0.title.lowercased().hasPrefix(prefix.lowercased())
                }) else {
                    NSLog("factsProbe: no thing whose title starts with %@", prefix)
                    return
                }
                let dates = ScreenshotFacts.dates(in: subject.content)
                NSLog("factsProbe: subject=%@ ocrChars=%d detectedDates=%d",
                      subject.title, subject.content.count, dates.count)
                for d in dates {
                    NSLog("factsDate| %@", d.formatted(date: .abbreviated, time: .shortened))
                }
                let label = await ScreenshotFacts.label(for: subject.content)
                NSLog("factsProbe: modelLabel=%@", label ?? "(declined or unavailable)")
                let facts = await ScreenshotFacts.facts(for: subject)
                for f in facts {
                    NSLog("factsRow| %@ · %@", f.label,
                          f.date.formatted(date: .abbreviated, time: .shortened))
                }
            }
        },
        // `-digestProbe YES` — run the thread-summary sweep and show what it
        // wrote. The per-thread lines matter more than the count: a summary
        // lands in `enrichedText`, which is retrieval-only and therefore
        // invisible on every screen, so this is the ONLY way to see whether
        // the model wrote something useful or something generic.
        Hook(key: "digestProbe") { _, context in
            Task { @MainActor in
                let n = await ThreadDigest.sweep(context: context)
                let all = (try? context.fetch(FetchDescriptor<Thing>(
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
                let threads = all.filter { $0.isLive && $0.kind == .chat }
                let pending = threads.filter(ThreadDigest.wants).count
                NSLog("digestProbe: modelAvailable=%@ summarized=%d threads=%d stillPending=%d",
                      OnDeviceModel.isAvailable ? "YES" : "NO", n, threads.count, pending)
                for t in threads.prefix(8) where t.enrichedText != nil {
                    NSLog("digestRow| %@ → %@", t.title, t.enrichedText ?? "")
                }
            }
        },
        // `-nameProbe YES` — run the screenshot-naming sweep. Logs each row's
        // BEFORE title beside what the model proposed and whether the
        // grounding check accepted it, because a rejected name is the
        // interesting case: it is the rail doing its job, and a run that
        // silently named nothing looks identical to a run where the model
        // never answered.
        Hook(key: "nameProbe") { _, context in
            Task { @MainActor in
                let descriptor = FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == "Photos" && $0.ocrAt != nil },
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
                let weak = ((try? context.fetch(descriptor)) ?? []).filter {
                    $0.isLive && $0.kind == .screenshot && !$0.content.isEmpty
                        && ScreenshotNaming.isWeak($0.title)
                }
                NSLog("nameProbe: modelAvailable=%@ weaklyTitled=%d",
                      OnDeviceModel.isAvailable ? "YES" : "NO", weak.count)
                for thing in weak.prefix(3) where thing.isLive {
                    let before = thing.title
                    let proposed = await ScreenshotNaming.name(text: thing.content)
                    let ok = proposed.map { ScreenshotNaming.grounded($0, in: thing.content) } ?? false
                    NSLog("nameRow| was=%@ proposed=%@ grounded=%@", before,
                          proposed ?? "(declined)", ok ? "YES" : "NO")
                }
                let n = await ScreenshotNaming.sweep(context: context)
                NSLog("nameProbe: named=%d", n)
            }
        },
        // `-photoVerbProbe YES` — what a screenshot's thing sheet OFFERS, and
        // whether each offer can actually land (2026-08-02).
        //
        // Built for the bug it verifies: the sheet's only screenshot verb was
        // "Open in Photos" and it did nothing at all on the reporter's device.
        // Nothing could see that, because the failure is INVISIBLE at the call
        // site — LaunchServices refuses an unclaimed scheme asynchronously in
        // its own daemon, and both `UIApplication.open`'s completion and
        // SwiftUI's `openURL` report success anyway (measured 2026-07-16 for
        // `wc:`). So the probe asks the only question that answers it —
        // `canOpenURL`, which needs the scheme declared in
        // LSApplicationQueriesSchemes — and prints the disc row beside it.
        //
        // One NSLog per line (the `-todayProbe` truncation lesson). The pixel
        // lines are the other half: a Zoom disc is only honest if a picture is
        // reachable, and `stored` vs `asset` separates "the corpus kept its own
        // copy" from "the original is still in the library" — the viewer needs
        // either, and a row with neither should be reporting that it's gone.
        Hook(key: "photoVerbProbe") { _, context in
            // Deliberately delayed: `HandOffState.installedSchemes` — the
            // snapshot the verb is GATED on — is written by the first
            // foreground pass, which has not run when `runAll` fires. Reading
            // it at launch would report an empty set and print a disc row
            // nobody will ever see. `claimed` is ground truth either way; the
            // two are logged separately so a disagreement is legible rather
            // than mysterious.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                let claimed = URL(string: "photos-redirect://").map {
                    UIApplication.shared.canOpenURL($0)
                } ?? false
                NSLog("[Casberi] photoVerb: photos-redirect claimed=%@ · inHandOffSet=%@",
                      claimed ? "YES" : "NO",
                      HandOffState.installedSchemes.contains("photos-redirect") ? "YES" : "NO")
                let shots = (try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == "Photos" },
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
                guard let shot = shots.first(where: { $0.kind == .screenshot }) else {
                    NSLog("[Casberi] photoVerb: no screenshot in the corpus to derive from")
                    return
                }
                NSLog("[Casberi] photoVerb: over %@", shot.title)
                for verb in VerbDerivation.verbs(for: shot) {
                    let destination: String
                    switch verb.action {
                    case .openURL(let url): destination = url.absoluteString
                    case .viewImage:        destination = "in-app viewer"
                    default:                destination = "\(verb.action)"
                    }
                    NSLog("[Casberi] photoVerbDisc| %@ → %@",
                          VerbDial.dialLabel(for: verb), destination)
                }
                let ref = shot.sourceRef ?? ""
                let assetAlive = ref.isEmpty || ref.hasPrefix("sample:")
                    ? false
                    : PHAsset.fetchAssets(
                        withLocalIdentifiers: [ref.replacingOccurrences(of: "phasset:", with: "")],
                        options: nil).firstObject != nil
                NSLog("[Casberi] photoVerbPixels| ref=%@ stored=%d bytes · assetInLibrary=%@",
                      ref.isEmpty ? "(none)" : ref,
                      shot.previewImageData?.count ?? 0,
                      assetAlive ? "YES" : "NO")
            }
        },
        // `-topicMapProbe YES` — the Photos feed's OCR treemap (2026-07-30),
        // headless. Runs the `ocrTopics` backfill first (reads the OCR text
        // already on each shot — no PHAsset walk), then composes
        // `FeedInsight.topicMap` over the corpus and logs every ranked cell
        // plus a sample of per-shot extracted terms — the one view that
        // separates "extraction found nothing" from "the ranking dropped it".
        // One NSLog per line (a joined multi-line message gets truncated by
        // the log reader — the `-todayProbe` lesson). Pair with a real
        // screenshot library (or `-connectPhotos`/`-photoHealProbe` to land OCR
        // first); the sim's seeds carry text, so it reports honestly there.
        // Takes an optional SOURCE (`-topicMapProbe Instagram`) since 2026-07-31
        // — the same treemap now maps an Instagram export's own captions and
        // comments ("What you write about"), whose terms come off `content` at
        // import with no OCR to wait for. Bare `YES` still means Photos.
        Hook(key: "topicMapProbe") { spec, context in
            let source = (spec == "YES" || spec.isEmpty) ? "Photos" : spec
            Task { @MainActor in
                let filled = await ScreenshotTopics.healTopics(source: source, context: context,
                                                              limit: 500)
                let shots = (try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == source },
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
                // The kinds a room's map really reads (fixed 2026-08-06). This
                // was `source == "Instagram" ? .note : .screenshot`, so for X
                // it filtered a room of `.note` posts down to `.screenshot`,
                // found nothing, and reported "no card" on every run — the one
                // headless view of this card was blind for X from the day the
                // seat shipped, and blind for TikTok and Files too once §309
                // gave the map a kind SET. Deliberately wide: the map narrows
                // by kind and tag itself, so handing it the room is right and
                // guessing its membership here is what broke.
                let screens = shots.filter { !Corpus.isImportReceipt($0) }
                let withTerms = screens.filter { !$0.ocrTopics.isEmpty }.count
                NSLog("[Casberi] topicMap: source=%@ backfilled=%d · rows=%d · withTerms=%d",
                      source, filled, screens.count, withTerms)
                if let map = FeedInsight.topicMap(source: source, things: screens) {
                    NSLog("[Casberi] topicMapCard| %@ · %@", map.title, map.subtitle)
                    for cell in map.cells {
                        NSLog("[Casberi] topicMapCell| %@ = %d", cell.label, cell.count)
                    }
                } else {
                    NSLog("[Casberi] topicMap: no card (too little text or spread)")
                }
                for t in screens.prefix(8) where !t.ocrTopics.isEmpty {
                    NSLog("[Casberi] topicMapTerms| %@ → %@",
                          t.title, t.ocrTopics.joined(separator: ", "))
                }
            }
        },
        // `-roomInsightProbe <Source>` — what a source's room would LEAD with
        // (2026-07-31). Every hero card is asked independently and logged with
        // its own answer, then the first non-nil in the documented order is
        // named. This is the check the delight pass needed and nothing else
        // could make: each card is individually easy to reason about, and the
        // bug that actually happens is one card silently owning the slot
        // another was built for (the §219 social roster spent weeks that way,
        // beaten by a heatmap nobody thought to rank against it). The ORDER
        // lives in `FeedScreen.shapedSections` — this mirrors it, so a change
        // there means a change here.
        //
        // One NSLog per card (the `-todayProbe` truncation lesson). Live
        // state — a Twitch stream, a social roster — is view-level and isn't
        // reachable from here; both outrank everything below and are noted as
        // unread rather than silently assumed absent.
        Hook(key: "roomInsightProbe") { spec, context in
            let source = spec == "YES" || spec.isEmpty ? "All" : spec
            Task { @MainActor in
                let things = ((try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == source },
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []).live
                NSLog("[Casberi] roomInsight: source=%@ things=%d (live stream / social roster not read here)",
                      source, things.count)

                var leader: String?
                func note(_ name: String, _ line: String?) {
                    NSLog("[Casberi] roomInsight| %@: %@", name, line ?? "nil")
                    if line != nil, leader == nil { leader = name }
                }

                // 1. the PER-SOURCE heads — each claims exactly one room, and
                // together they outrank everything below (`FeedScreen`'s own
                // `sourceHead`, 2026-08-04 prd §298; the runway 2026-08-03 prd
                // §296). Mirrored here the day each landed: this probe's whole
                // job is naming what really leads a room, and a card added to
                // `shapedSections` without a line here would make the probe
                // confidently report "leads with NOTHING" about a room that
                // leads with a card — the §219 failure inverted, which is the
                // one this probe exists to stop.
                //
                // They share rank 1 because they cannot compete: a room is
                // Cloudflare or Stripe or PostHog, never two. Reported as
                // separate lines anyway, so a room drawing the wrong one is
                // visible rather than folded into a single "sourceHead: yes".
                //
                // EACH IS GATED ON `source`, exactly as `FeedScreen.sourceHead`
                // is — and that gate is the whole correctness of these lines,
                // not a tidiness. These three compose from BRIDGE STATE, not
                // from `things`: a Stripe balance or a cached Cloudflare estate
                // is global, so an ungated `compose` answers for EVERY room.
                // Without the gate, `-roomInsightProbe Photos` on a device with
                // Stripe connected reported the Photos room as leading with
                // `stripeHead` — the §219 failure this probe exists to catch,
                // committed by the probe itself. (The runway line shipped with
                // that hole on 2026-08-03 and is fixed here too.)
                note("runway", source == "Cloudflare"
                     ? CloudflareRunwaySource.compose(things: things).map {
                        $0.items.isEmpty
                            ? "quiet · \($0.next.map { n in CloudflareRunway.quietHeadline(days: n.days) } ?? "—")"
                            : "\(CloudflareRunway.headline(items: $0.items, span: $0.span)) · \($0.items.count) rows"
                     } : nil)
                note("stripeHead", source == "Stripe"
                     ? StripeRoomSource.compose(things: things).map {
                        "\(StripeRoom.headline($0)) · \($0.total) deadlines"
                     } : nil)
                note("posthogHead", source == "PostHog"
                     ? PostHogRoomSource.compose(things: things).map {
                        "\(PostHogRoom.headline($0)) · \($0.metrics.count) metrics"
                     } : nil)
                // Unlike the three above this one DOES read `things` (the
                // runs ARE the subject — see `CursorRoomSource`'s own note),
                // so the gate here is belt-and-braces rather than the whole
                // correctness: `compose` already filters to `source ==
                // CursorRoomSource.source` internally, and would return nil
                // for any other room's `things` on its own. Gated anyway, so
                // this line reads the same way as its three neighbours.
                note("cursorHead", source == CursorRoomSource.source
                     ? CursorRoomSource.compose(things: things).map {
                        "\(CursorRoom.headline($0)) · \($0.repos.count) repos"
                     } : nil)
                // 2. the anniversary — memories room only, and only with pixels
                let echo = source == "Snapchat"
                    ? OnThisDay.find(in: things.filter {
                        $0.kind == .file && $0.previewImageData != nil })
                    : nil
                note("anniversary", echo.map { "\($0.label) → \($0.thing.title)" })
                // 3. the treemap
                let map = FeedInsight.topicMap(source: source, things: things)
                note("topicMap", map.map { "\($0.title) · \($0.subtitle) · \($0.cells.count) cells" })
                for cell in map?.cells ?? [] {
                    NSLog("[Casberi] roomInsightCell| %@ = %d", cell.label, cell.count)
                }
                // 4. the bars
                let board = FeedInsight.leaderboard(source: source, things: things)
                note("leaderboard", board.map { "\($0.title) · \($0.subtitle) · \($0.rows.count) rows" })
                for row in board?.rows ?? [] {
                    NSLog("[Casberi] roomInsightRow| %@ = %@", row.label, row.detail)
                }
                // 5. the split bar, 6. the wall
                note("distribution", FeedInsight.distribution(source: source, things: things)?.title)
                note("mosaic", FeedInsight.mosaic(source: source, things: things)
                        .map { "\($0.title) · \($0.tiles.count) tiles" })
                // 7. the grid — last, and reported with what it actually counts
                if let label = FeedHeatmap.label(for: source) {
                    let counted = FeedHeatmap.counted(things, label: label)
                    let year = ContributionYear.from(dates: counted.map(\.capturedAt),
                                                     columns: label.columns)
                    // `activeDays >= 4` is the screen's own render gate.
                    note("heatmap", year.activeDays >= 4
                         ? "\(label.title) · counted=\(counted.count) · activeDays=\(year.activeDays)"
                         : nil)
                    if year.activeDays < 4 {
                        NSLog("[Casberi] roomInsight| heatmap registered but too sparse (counted=%d activeDays=%d)",
                              counted.count, year.activeDays)
                    }
                } else {
                    note("heatmap", nil)
                }
                NSLog("[Casberi] roomInsight: leads with %@", leader ?? "NOTHING (rows only)")
            }
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
                guard let identity = await GitHubFeedFetch.login(token: token) else {
                    NSLog("GitHub feed probe (%@): FAILED — token rejected", feed.rawValue); return
                }
                let things = await GitHubFeedFetch.fetch(feed, login: identity.login, token: token)
                NSLog("GitHub feed probe (%@): %@", feed.rawValue,
                      things.map { "\($0.count) things" } ?? "FAILED")
            }
        },
        // `-githubRateLimitProbe YES` — the rate-limit crossing, phase by
        // phase (2026-08-09). Reads the STORED token, hits `/user` (the same
        // call `login(token:)` makes every refresh — no extra request), and
        // NSLogs the two headers plus the bucket decision, then whether a
        // Thing would land. An empty/quiet result has three causes and only
        // one is a bug: no token, GitHub didn't answer the two headers at
        // all (would be a real drift — they've been stable and documented for
        // years), or the budget is simply nowhere near the floor.
        Hook(key: "githubRateLimitProbe") { _, _ in
            guard let token = TokenVault.get(TokenBridge.github.tokenKey) else {
                NSLog("[Casberi] githubRateLimitProbe: no stored token — connect via -tokenBridge \"GitHub:<token>\"")
                return
            }
            Task {
                let (_, status, response) = await IngestSupport.getJSONResponse(
                    "https://api.github.com/user", auth: "Bearer \(token)")
                guard let response else {
                    NSLog("[Casberi] githubRateLimitProbe: HTTP %d — unreachable, no response to read headers from", status)
                    return
                }
                let remainingText = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "(absent)"
                let limitText = response.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "(absent)"
                let resetText = response.value(forHTTPHeaderField: "X-RateLimit-Reset") ?? "(absent)"
                NSLog("[Casberi] githubRateLimitProbe: HTTP %d remaining=%@ limit=%@ reset=%@",
                      status, remainingText, limitText, resetText)
                if let remaining = Int(remainingText), let limit = Int(limitText) {
                    NSLog("[Casberi] githubRateLimitProbe: low=%@ (floor=%.0f%% of %d = %d)",
                          GitHubRateLimit.isLow(limit: limit, remaining: remaining) ? "YES" : "no",
                          GitHubRateLimit.lowFraction * 100, limit,
                          Int(Double(limit) * GitHubRateLimit.lowFraction))
                }
                if let alert = GitHubRateLimit.checkLow(response) {
                    NSLog("[Casberi] githubRateLimitProbe: WOULD LAND → %@", alert.title)
                } else {
                    NSLog("[Casberi] githubRateLimitProbe: nothing to land (not low, or this crossing already alerted)")
                }
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
        // `-demoSeed force|clear` re-runs or removes the furnished demo corpus
        // (`DemoSeedAll`) — every room's rows plus the bridge state its heads
        // read. `force` ignores the stored version, which is what makes an
        // edit to the seed table verifiable without reinstalling; `clear`
        // removes the rows it owns and forgets the version, so the next launch
        // seeds again. Neither can fire in a release build or in `-fresh YES`
        // mode — `DemoSeedAll.seed` is gated the same way `DemoCorpus` is.
        Hook(key: "demoSeed") { spec, context in
            Task { @MainActor in
                if spec == "clear" {
                    let gone = DemoSeedAll.clear(context)
                    NSLog("Demo seed probe: cleared %d", gone)
                } else {
                    let before = (try? context.fetchCount(FetchDescriptor<Thing>())) ?? 0
                    DemoSeedAll.seed(context)
                    let after = (try? context.fetchCount(FetchDescriptor<Thing>())) ?? 0
                    UserDefaults.standard.set(DemoSeedAll.version, forKey: "demo.fullSeed.version")
                    NSLog("Demo seed probe: %d landed (%d → %d)", after - before, before, after)
                }
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
        // `-healPhotos YES` runs the screenshot heal sweep (thumbnails + OCR)
        // then `pruneDeleted` (prd §231 deletion sync) and logs the counts.
        // `-healPhotos seed-dangling` first plants a screenshot thing with a
        // ref no asset will ever match — the removal path, end to end. NOTE
        // pruneDeleted's `found.isEmpty` safety guard: on a sim with no REAL
        // screenshot assets the library read is empty, so the dangling seed
        // only prunes when at least one live asset also exists (the guard
        // treats a wholly-empty read as a Photos hiccup, not a mass delete).
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
                let pruned = ScreenshotIngest.pruneDeleted(context: context)
                let all = ((try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == "Photos" }))) ?? [])
                    .filter { $0.kind == .screenshot }
                NSLog("Photos heal probe: auth=%d, %d thumbed, %d OCRed, %d pruned, %d/%d have stored thumbs, %d carry text",
                      auth.rawValue, r.thumbed, r.ocred, pruned,
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
        // `-obsidianProbe YES` — one vault pass, reported job by job, plus one
        // `obsidianNote|` line PER note the pass touched (the `-todayProbe`
        // truncation lesson: a joined multi-line NSLog gets cut by the log
        // reader mid-document).
        //
        // It exists because a landed count of 0 is the HEALTHY answer for a
        // vault already in, and it has five other causes that render the same
        // way: nothing new, everything capped out and waiting for the next
        // pass, notes sitting un-downloaded in iCloud Drive, a one-time reader
        // repair still draining, or a walk that returned nothing at all. Only
        // the last is a bug, and only the phase lines can tell them apart.
        Hook(key: "obsidianProbe") { _, context in
            Task { @MainActor in
                guard ObsidianStore.shared.connected else {
                    NSLog("obsidian| NOT CONNECTED — no vault picked"); return
                }
                guard let report = await ObsidianIngest.pass(context: context) else {
                    NSLog("obsidian| UNREADABLE — vault moved, renamed, or permission lost")
                    return
                }
                NSLog("obsidian| vault=%@ walked=%d", ObsidianStore.shared.vaultName, report.walked)
                NSLog("obsidian| landed=%d reread=%d pruned=%d", report.landed,
                      report.reread, report.pruned)
                NSLog("obsidian| pending=%d notDownloaded=%d prunePassed=%@",
                      report.pending, report.notDownloaded, report.prunePassed ? "YES" : "NO")
                NSLog("obsidian| repairing=%@ repairDone=%@",
                      report.repairing ? "YES" : "NO", report.repairDone ? "YES" : "NO")
                let descriptor = FetchDescriptor<Thing>(
                    predicate: #Predicate<Thing> { $0.source == "Obsidian" })
                let notes = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
                NSLog("obsidian| corpus=%d", notes.count)
                for note in notes.prefix(40) {
                    // `words` is the retrieval body's length, and it is the
                    // field to read first: `content` looking right proves only
                    // that the excerpt landed, while a nil body means the
                    // reader never reached this note and nothing on any screen
                    // would show it.
                    NSLog("obsidianNote| %@ words=%d tags=%@ links=%d open=%@",
                          note.title,
                          (note.enrichedText ?? "").count,
                          note.tags.isEmpty ? "-" : note.tags.joined(separator: ","),
                          note.wikilinks.count,
                          ObsidianLink.openURL(vault: ObsidianStore.shared.vaultName,
                                               sourceRef: note.sourceRef)?.absoluteString ?? "none")
                }
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
        // `-filesHealProbe YES` runs the Files HEAL directly — the pass that
        // thumbnails and OCRs the image files a sync already landed (2026-07-27,
        // the same split `-photoHealProbe` exercises for Photos: landing alone
        // leaves every image row saying just its byte size). Logs what the pass
        // did, then each image's OCR character count and current title — the
        // same pairing that separates "OCR found nothing" from "the retitle
        // didn't fire".
        Hook(key: "filesHealProbe") { _, context in
            Task { @MainActor in
                let r = await FilesIngest.heal(context: context)
                NSLog("[Casberi] filesHeal: thumbed=%d ocred=%d", r.thumbed, r.ocred)
                let files = (try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == "Files" },
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
                for t in files.prefix(12) {
                    NSLog("[Casberi] filesHealRow| ocr=%d thumb=%@ title=%@",
                          t.content.count, t.previewImageData != nil ? "yes" : "no", t.title)
                }
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
        // `-feedFollow "<Substack|Reddit|YouTube|Podcasts>:<name[,name]>"` —
        // follow one or more names on a feed-follow bridge and sync, NSLogging
        // each entry's resolved feed URL and learned title.
        //
        // The four feed-follow bridges had NO headless door at all until now
        // (2026-08-06), which is not a small gap: they are four of the app's
        // most-used seats, and the resolver bug `YouTubeFollowRepair` exists to
        // clean up — every `@handle` follow landing a stranger's channel —
        // could not have been caught by any automated run, because nothing
        // could follow a channel without a person tapping. The resolved URL
        // and the learned title are logged together on purpose: that pairing
        // is the whole tell. A wrong resolution still produces a real feed
        // with real videos, and the only thing that reads as wrong is a title
        // that isn't the name you typed.
        Hook(key: "feedFollow") { spec, context in
            // Split on the FIRST colon: a Substack input can be a URL and
            // carry its own (the `-startFollow` rule).
            guard let colon = spec.firstIndex(of: ":") else {
                NSLog("feedFollow: expected \"<Kind>:<name[,name]>\"")
                return
            }
            let kindName = String(spec[spec.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard let kind = FeedFollowKind(rawValue: kindName) else {
                NSLog("feedFollow: unknown kind %@ — one of %@", kindName,
                      FeedFollowKind.allCases.map(\.rawValue).joined(separator: "/"))
                return
            }
            let names = String(spec[spec.index(after: colon)...])
                .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            for name in names where !name.isEmpty {
                kind.store.add(FeedFollowEntry(input: kind.normalize(name)))
            }
            Task { @MainActor in
                let n = await FeedFollowIngest.refresh(kind, context: context)
                NSLog("feedFollow: %@ | %@ %@ in", kind.source,
                      n.map(String.init) ?? "FAILED", kind.noun)
                for entry in kind.store.entries {
                    NSLog("feedFollowRow| %@ | input=%@ | title=%@ | feed=%@",
                          kind.source, entry.input,
                          entry.title.isEmpty ? "(unlearned)" : entry.title,
                          entry.feedURL.isEmpty ? "(unresolved)" : entry.feedURL)
                }
            }
        },
        // `-feedHealthProbe YES` — every tracked feed's HTTP record, one
        // `feedHealth|` line each (the `-todayProbe` truncation lesson).
        //
        // It exists because the conditional GET is INVISIBLE when it works
        // (2026-08-05): a feed answering 304 lands exactly what a feed
        // answering 200-with-nothing-new lands — nothing — so a build, a
        // screen sweep and a landed count are all identical whether the
        // validators are being sent, being ignored, or being sent wrong. The
        // `cond=YES` column is the only place that shows they were stored at
        // all, and `status` separates the three ways a feed goes quiet: 304
        // (working perfectly), 404 (moved, or YouTube throttling us — the two
        // are indistinguishable on the wire), 0 (offline).
        //
        // Counts, dates and statuses only. An ETag is an opaque publisher
        // token and there is no reason to print one.
        Hook(key: "feedHealthProbe") { _, _ in
            let census = FeedFreshness.census()
            NSLog("feedHealthProbe: %d feeds tracked | %d conditional | %d failing",
                  census.count, census.filter(\.conditional).count,
                  census.filter { $0.failures > 0 }.count)
            for row in census.prefix(60) {
                let ago = row.successAt.map { Int(-$0.timeIntervalSinceNow / 3600) }
                NSLog("feedHealth| %@ | lastOK=%@ | fails=%d | status=%d | cond=%@ | says=%@",
                      row.url,
                      ago.map { "\($0)h ago" } ?? "never",
                      row.failures, row.lastStatus,
                      row.conditional ? "YES" : "NO",
                      FeedFreshness.trouble(for: row.url) ?? "-")
            }
        },
        // `-articleTextProbe [limit]` — what a followed article actually SAYS
        // (2026-08-06, `FeedArticleText`), one `articleText|` line per row.
        //
        // The one pass in this file whose whole output is invisible on every
        // screen: `enrichedText` is retrieval-only by the 2026-07-15 ruling,
        // so a successful read and a read that never ran render identically.
        // `considered` is what separates the several reasons a pass does
        // nothing — no RSS/Substack rows, every recent row already read, every
        // summary already substantial (the good feeds), or the walk stopping.
        Hook(key: "articleTextProbe") { spec, context in
            Task { @MainActor in
                let limit = Int(spec.trimmingCharacters(in: .whitespaces))
                let r = await FeedArticleText.sweep(context: context, limit: limit, trace: true)
                NSLog("articleTextProbe: %d read | %d missed | %d considered | backedOff=%@",
                      r.enriched, r.failed, r.considered, r.backedOff ? "YES" : "NO")
            }
        },
        // `-ytRepairProbe YES|force` — re-resolve every YouTube follow and
        // report which ones were pointing at the WRONG channel (2026-08-05,
        // `YouTubeFollowRepair`). `force` ignores the done flag and the
        // per-entry ledger, which is the only way to re-run it once it has
        // retired itself.
        //
        // `wrong=0` is the healthy answer and it has two causes worth telling
        // apart, which is why `unresolved` is printed beside it: every follow
        // verified correct, or YouTube answered none of the channel pages (it
        // serves a throttled client a plain 404, so a silent pass looks
        // exactly like a clean one).
        Hook(key: "ytRepairProbe") { spec, context in
            Task { @MainActor in
                let force = spec.lowercased() == "force"
                guard let r = await YouTubeFollowRepair.run(context: context, force: force) else {
                    NSLog("ytRepairProbe: already done — pass `force` to re-run")
                    return
                }
                NSLog("ytRepairProbe: checked=%d wrong=%d pruned=%d unresolved=%d done=%@",
                      r.checked, r.wrong, r.pruned, r.unresolved, r.done ? "YES" : "NO")
            }
        },
        // `-ytChannelProbe <@handle|url|id>` — what a typed YouTube name
        // resolves to, and the feed that id actually serves.
        //
        // Two lines, because the bug this exists for lived entirely between
        // them: resolution succeeded, a real feed came back, real videos
        // landed — under a channel the person never chose. Printing the id
        // beside the feed's own `<title>` is what makes a wrong answer
        // readable at all.
        Hook(key: "ytChannelProbe") { spec, _ in
            Task { @MainActor in
                let input = spec.trimmingCharacters(in: .whitespaces)
                guard let id = await FeedFetch.resolveYouTubeChannelID(input) else {
                    NSLog("ytChannelProbe: %@ → UNRESOLVED (page unreachable, throttled, or no canonical link)",
                          input)
                    return
                }
                NSLog("ytChannelProbe: %@ → %@", input, id)
                let feed = "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)"
                guard let url = URL(string: feed),
                      let data = await FeedFetch.data(url, as: "YouTube") else {
                    NSLog("ytChannelProbe: feed UNREACHABLE — %@", feed)
                    return
                }
                let parsed = FeedParser.parse(data)
                NSLog("ytChannelProbe: feed title=%@ | %d entries | views=%@",
                      parsed.title.isEmpty ? "(none)" : parsed.title, parsed.items.count,
                      parsed.items.first?.viewCount.map(String.init) ?? "none")
            }
        },
        // `-ytShorts <limit|YES>` — classify landed YouTube rows as Short or
        // video (2026-08-06, `YouTubeShorts`), one `ytShort|` line each.
        //
        // `unclear` is the column that matters: a row YouTube declines to
        // answer about is NOT recorded, so it is asked again later — and a
        // pass that is all-unclear means the `/shorts/<id>` discriminator has
        // moved, which otherwise shows up as a room where nothing is ever
        // tagged and nothing is ever wrong.
        Hook(key: "ytShorts") { spec, context in
            Task { @MainActor in
                let limit = Int(spec.trimmingCharacters(in: .whitespaces))
                let r = await YouTubeShorts.sweep(context: context, limit: limit, trace: true)
                NSLog("ytShorts: asked=%d shorts=%d videos=%d unclear=%d considered=%d backedOff=%@",
                      r.asked, r.shorts, r.videos, r.unclear, r.considered,
                      r.backedOff ? "YES" : "NO")
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
        // `-seedVizDemo YES` — plants everything the ROOM HEADS need so each
        // visualization can be photographed from an account that isn't
        // connected to Cloudflare, Stripe or PostHog and holds no DeFi
        // position (2026-08-04, the website's visualization gallery).
        //
        // It is a marketing tool and says so: the wallet half rides
        // `WalletDemoState` behind the same `viz.demo` flag, which is DEBUG
        // -only and compiled out of any shipping build, and every thing it
        // lands carries a `vizdemo:` ref so `-seedVizDemo clear` can take
        // exactly its own rows back out without touching a real corpus.
        //
        // The alternative was mocking these charts in HTML for the website,
        // which is the thing that keeps getting rejected: a recreation drifts
        // from the design system the moment either changes, and it can claim
        // a shape the app never draws. Seeding the real app and photographing
        // it can't.
        Hook(key: "seedVizDemo") { spec, context in
            let clearing = spec.lowercased() == "clear"
            let all = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
            if clearing {
                var gone = 0
                for t in all where (t.sourceRef ?? "").hasPrefix("vizdemo:")
                    || (t.sourceRef ?? "").hasPrefix("cloudflare:") {
                    context.delete(t); gone += 1
                }
                CloudflareEstateStore.clear()
                StripeState.set(StripeState.Balance())
                UserDefaults.standard.set(false, forKey: "viz.demo")
                context.saveHonestly()
                NSLog("[Casberi] seedVizDemo: cleared %d demo things, wallet books off", gone)
                return
            }
            UserDefaults.standard.set(true, forKey: "viz.demo")
            let existing = Set(all.compactMap(\.sourceRef))
            var landed = 0
            func seed(_ ref: String, _ make: () -> Thing) {
                guard !existing.contains(ref) else { return }
                context.insert(make()); landed += 1
            }
            func days(_ n: Double) -> Date { .now.addingTimeInterval(n * 86_400) }

            // Cloudflare — the four deadline shapes the room ranks, each with
            // the real `dueAt` the rail is drawn from.
            // Refs are the bridge's OWN shapes ("cloudflare:cert:<zoneID>",
            // ":domain:<name>", ":token"), because `CloudflareRunwaySource`
            // reads the kind off the ref rather than the title — a `vizdemo:`
            // ref would land rows that the card then refuses to draw.
            var estate = CloudflareEstate()
            estate.zoneNames = ["zone-a": "yoursite.com", "zone-b": "staging.yoursite.com"]
            estate.autoRenew = ["yoursite.com": true]
            estate.zonesSeen = 2
            estate.zonesCovered = 2
            CloudflareEstateStore.save(estate)

            let cf: [(String, String, String, Double)] = [
                ("cloudflare:cert:zone-a", "yoursite.com — TLS certificate expires in 12 days",
                 "Certificates normally renew on their own about a month out. Seeing this means the renewal hasn't happened yet.", 12),
                ("cloudflare:domain:yoursite.com", "yoursite.com renews in 44 days",
                 "Set to renew automatically — which still fails if the card behind it has expired.", 44),
                ("cloudflare:token", "Your Cloudflare API token expires in 21 days",
                 "When it lapses, Casberi stops reading your Cloudflare account.", 21),
                ("cloudflare:cert:zone-b", "staging.yoursite.com — TLS certificate expires in 3 days",
                 "Cloudflare isn't serving this domain while it's in this state.", 3),
            ]
            for (i, row) in cf.enumerated() {
                seed(row.0) {
                    let t = Thing(kind: .reminder, title: row.1,
                                  content: "https://dash.cloudflare.com/",
                                  source: "Cloudflare",
                                  capturedAt: .now.addingTimeInterval(Double(-i) * 900),
                                  tags: ["Deadline"], sourceRef: row.0)
                    t.summary = row.2
                    t.dueAt = days(row.3)
                    return t
                }
            }

            // Stripe — money moving, which is the doctrine's one standing
            // exception to "a count is never a thing".
            // Only "Dispute" and "Dunning" carry a clock, and the rail draws
            // from exactly those two tags — a payout has no deadline and is
            // deliberately left off it.
            var bal = StripeState.Balance()
            bal.available = ["gbp": 812_450]
            bal.pending = ["gbp": 214_000]
            bal.arrivesAt = days(2)
            bal.fetchedAt = .now
            StripeState.set(bal)

            let stripe: [(String, String, [String], Double?)] = [
                ("Dispute opened · £49.00", "Evidence due Friday", ["Dispute"], 6),
                ("Dispute opened · £128.00", "Evidence due in three weeks", ["Dispute"], 19),
                ("Payment failed · ¥5,000", "Stripe retries in three days", ["Dunning"], 3),
                ("Paid out £2,140.00", "Arrived in your bank", ["Money"], nil),
                ("Pro yearly canceled", "The subscription ended", ["Money"], nil),
            ]
            for (i, row) in stripe.enumerated() {
                let ref = "vizdemo:stripe:\(i)"
                seed(ref) {
                    let t = Thing(kind: .link, title: row.0,
                                  content: "https://dashboard.stripe.com/",
                                  source: "Stripe",
                                  capturedAt: .now.addingTimeInterval(Double(-i) * 5_400),
                                  tags: row.2, sourceRef: ref)
                    t.summary = row.1
                    if let d = row.3 { t.dueAt = days(d) }
                    return t
                }
            }

            // Photos — the topic map needs six-plus shots carrying stamped
            // terms, with terms that RECUR (a map of singletons ranks nothing).
            let shots: [[String]] = [
                ["figma.com", "Figma"], ["figma.com", "recipes"], ["recipes", "figma.com"],
                ["receipts", "figma.com"], ["flights", "recipes"], ["receipts", "flights"],
                ["figma.com", "receipts"], ["recipes", "flights"], ["figma.com", "recipes"],
                ["receipts", "figma.com"], ["flights", "figma.com"], ["recipes", "receipts"],
            ]
            for (i, terms) in shots.enumerated() {
                let ref = "vizdemo:shot:\(i)"
                seed(ref) {
                    let t = Thing(kind: .screenshot, title: terms[0],
                                  content: terms.joined(separator: " "),
                                  source: "Photos",
                                  capturedAt: .now.addingTimeInterval(Double(-i) * 7_200),
                                  sourceRef: ref)
                    t.ocrTopics = terms
                    t.topicsAt = .now
                    return t
                }
            }
            context.saveHonestly()

            // PostHog — one climbing metric and one that stopped, since the
            // room's whole ranking rule is that a silent metric leads.
            var shipped = PostHogState.get("signed_up")
            shipped.series = [41, 52, 48, 63, 71, 68, 94]
            shipped.total = 9_420
            shipped.fetchedAt = .now
            PostHogState.set("signed_up", shipped)
            // The watch row IS the watch (the TokenWatch precedent), so the
            // roster only draws metrics that have one — a reading alone is
            // invisible.
            for event in ["signed_up", "checkout_completed"] {
                PostHogWatch.add(event, context: context)
            }

            var quiet = PostHogState.get("checkout_completed")
            quiet.series = [22, 19, 24, 17, 0, 0, 0]
            quiet.total = 3_180
            quiet.fetchedAt = .now
            PostHogState.set("checkout_completed", quiet)

            NSLog("[Casberi] seedVizDemo: landed %d things; wallet books ON; posthog seeded", landed)
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
        // `-cursorPRProbe YES` — what became of the pull requests your agents
        // opened, WITHOUT changing anything (2026-08-08, prd §340).
        //
        // An unchanged room has five causes that look identical from the feed:
        // no GitHub token, no Cursor row carrying a PR at all, every PR
        // already resolved, every PR still genuinely open, or a url shape this
        // build can't parse. Only the last is a bug, and it is the invisible
        // one — the row just keeps saying a pull request was opened, forever.
        // `parsed=NO` is what separates it in one launch.
        Hook(key: "cursorPRProbe") { _, context in
            Task { @MainActor in await CursorPullRequests.diagnose(context: context) }
        },
        // `-cursorPRSync YES` — actually run the loop-closer and report how
        // many rows changed. A DIFFERENT word from the probe above, not a flag
        // on it, for `-librarianProbe`'s reason: this one spends requests, so
        // it must never be something a headless sweep runs by accident.
        Hook(key: "cursorPRSync") { _, context in
            Task { @MainActor in
                let changed = await CursorPullRequests.reconcile(context: context)
                NSLog("[Casberi] cursorPRSync: %d row(s) resolved", changed)
            }
        },
        // `-mcpServe YES` — turn the loopback MCP listener on and hand a test
        // client what it needs to reach it (2026-08-08, prd §340).
        //
        // This exists because `MCPServer` could not be measured at all. It
        // compiles out everywhere but Catalyst, so no simulator can exercise
        // it; its switch lives in a Mac settings row, so no headless run can
        // reach it; and its pairing token is written to the DATA-PROTECTION
        // keychain, which `security(1)` cannot read — three separate walls
        // between a listener that says it is unproven and anything that could
        // prove it.
        //
        // **The token is written to a FILE, never logged.** It is the
        // credential — `MCPServerRow` copies it with `DSPasteboard.
        // copySensitive` for that reason — so this follows `-macSnapshot`'s
        // rule that the log line names the PATH and the value stays out of it.
        // Under DEBUG only, so it cannot ship; and the path is inside the
        // app's own container, which nothing else can read.
        Hook(key: "mcpServe") { _, _ in
            #if targetEnvironment(macCatalyst)
            MCPServer.isEnabled = true
            MCPServer.shared.start()
            // The listener reaches `.ready` on its own queue, so a census
            // taken synchronously here reports "not running" on a listener
            // that is seconds from being fine — the reason this waits before
            // it reports rather than reporting twice.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                let server = MCPServer.shared
                NSLog("[Casberi] mcpServe| endpoint=%@ running=%@ error=%@",
                      MCPServer.endpoint,
                      server.running ? "YES" : "no",
                      server.lastError ?? "—")
                let path = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mcp-pairing-token").path
                do {
                    try MCPPairing.token().write(toFile: path, atomically: true,
                                                 encoding: .utf8)
                    NSLog("[Casberi] mcpServe| tokenFile=%@", path)
                } catch {
                    NSLog("[Casberi] mcpServe| tokenFile FAILED: %@",
                          error.localizedDescription)
                }
            }
            #else
            NSLog("[Casberi] mcpServe| Catalyst only — there is no listener on this platform")
            #endif
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
