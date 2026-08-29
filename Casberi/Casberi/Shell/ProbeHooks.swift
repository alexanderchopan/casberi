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
        // `-receiptsForget YES` empties the network receipts ledger, so a
        // measurement that follows describes only what happened AFTER it
        // (2026-08-15).
        //
        // The ledger is CUMULATIVE and persisted, which is right for the screen
        // it serves — "what this app has actually reached" is a running record,
        // not a session. But it makes any "did X reach anything?" check a
        // statement about the whole life of that install, and `verify.sh`'s
        // "Demo reaches nothing" step was exactly that check with no way to
        // establish a baseline. On a clean CI container it was correct; on a
        // dev machine that had spent an afternoon syncing a real wallet it
        // failed confidently, naming 29 hosts, none of which the demo had
        // touched — the cry-wolf class this repo's audits go out of their way
        // to avoid. Measured the same day: with the ledger cleared first, the
        // demo reaches ZERO hosts.
        //
        // Declared BEFORE `receiptsProbe` — hooks run in list order, so a
        // launch passing both clears and then dumps an empty ledger, which is
        // the useful reading ("start from nothing") rather than a dump followed
        // by a wipe of the thing just read.
        Hook(key: "receiptsForget") { _, _ in
            NetworkLedger.shared.forget()
            NSLog("Receipts probe: ledger cleared")
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
            // The two repairs of 2026-08-13 (prd §375), on their own line and
            // for the cap's reason: both are INVISIBLE in every other reading
            // of this probe. A long post that arrived clipped and one that
            // arrived whole are both "1 post"; a picture post landed as its own
            // t.co shortlink and one landed as a picture are both "1 post"
            // too. A zero here on an archive full of long posts means the
            // `note-tweet.js` join found nothing — which is the bug, and the
            // rows look perfect either way.
            NSLog("X probe: longform=%d photoPosts=%d, %d replies awaiting context",
                  summary.longform, summary.photos,
                  XArchiveImport.pendingContextCount(context: context))
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
        // `-xReplyContext <limit|YES>` runs the oEmbed pass that fills in what
        // each reply was ANSWERING (2026-08-13, prd §375) — the second half of
        // the same second act, exactly as in the UI.
        //
        // `gone` is its own number and not a miss, the faces probe's rule:
        // there X tells us the post you LIKED has died, here that the post you
        // ANSWERED has, and only the second leaves your own row intact. The
        // still-waiting count is what separates "this archive's replies are all
        // to yourself, already filled for free" from "the pass isn't running".
        Hook(key: "xReplyContext") { spec, context in
            Task { @MainActor in
                let limit = Int(spec) ?? 200
                let outcome = await XArchiveImport.fetchReplyContext(limit: limit, context: context)
                NSLog("X reply-context probe: %d filled, %d gone, %d missed, unreachable=%d, %d still waiting",
                      outcome.filled, outcome.gone, outcome.missed,
                      outcome.unreachable ? 1 : 0,
                      XArchiveImport.pendingContextCount(context: context))
            }
        },
        // `-xPersonProbe <handle>` — your years with one person (2026-08-18,
        // prd §396), line by line: one `xPerson|` per year, then the card's
        // own sentence.
        //
        // It exists because an EMPTY card has five causes that render as one
        // silence, and only one of them is a bug: the handle is spelled
        // differently in the archive than you typed it, `fetchFaces` has never
        // run so no liked post names an author, this person really does appear
        // fewer than `XPerson.minimumSightings` times (the common case — most
        // handles in a long archive appear once), the room was never imported,
        // or the join stopped reaching `parent`. The per-kind counts are what
        // separate them: replies at 0 with mentions non-zero is the join, and
        // liked at 0 across every handle is the face pass.
        //
        // One NSLog per line — a joined multi-line message gets truncated by
        // the log reader (the `-todayProbe` lesson).
        Hook(key: "xPersonProbe") { handle, context in
            let all = (try? context.fetch(FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> { $0.source == "X" }))) ?? []
            let rows = XPersonSource.rows(all, handle: handle)
            NSLog("xPerson| handle=%@ room=%d matched=%d", handle, all.count, rows.count)
            guard let person = XPersonSource.compose(all, handle: handle) else {
                NSLog("xPerson| no card — under %d sightings, or nothing matched",
                      XPerson.minimumSightings)
                return
            }
            NSLog("xPerson| replies=%d mentions=%d liked=%d span=%d silent=%d",
                  person.replies, person.mentions, person.liked,
                  person.span, person.silent)
            for year in person.years {
                NSLog("xPersonYear| %@ replies=%d mentions=%d liked=%d",
                      XPerson.plainYear(year.year), year.replies, year.mentions, year.liked)
            }
            NSLog("xPerson| headline=%@", XPerson.headline(person, handle: handle))
            NSLog("xPerson| note=%@", XPerson.note(person))
        },
        // `-dayoneImport <path>` imports a Day One export — the unzipped FOLDER
        // (which brings the photographs) or the `.json` on its own.
        //
        // `dropped` and `with photos` are reported beside the landed count and
        // are the two facts a bare total cannot carry (prd §398): a truncated
        // import and a complete one read identically, and so do a run that
        // found the pictures and one whose `photos/` was never reachable.
        Hook(key: "dayoneImport") { path, context in
            Task { @MainActor in
                let url = URL(fileURLWithPath: path)
                let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory == true
                guard let json = isFolder ? DayOneImport.findJSON(inFolder: url) : url,
                      let data = FileManager.default.contents(atPath: json.path) else {
                    NSLog("Day One probe: no .json at %@", path)
                    return
                }
                let summary = await DayOneImport.run(
                    data: data, context: context,
                    exportRoot: isFolder ? url : url.deletingLastPathComponent())
                NSLog("Day One probe: %d imported, %d skipped, %d dropped, %d with photos, failed=%d",
                      summary.imported, summary.skipped, summary.dropped,
                      DayOneImport.thumbnailed(source: "Day One", context: context),
                      summary.failed ? 1 : 0)
            }
        },
        // `-journalImport <path>` imports an unzipped Apple Journal export folder.
        Hook(key: "journalImport") { path, context in
            Task { @MainActor in
                let summary = await JournalImport.run(folder: URL(fileURLWithPath: path), context: context)
                NSLog("Journal probe: %d imported, %d skipped, %d dropped, %d with photos, failed=%d",
                      summary.imported, summary.skipped, summary.dropped,
                      DayOneImport.thumbnailed(source: "Apple Journal", context: context),
                      summary.failed ? 1 : 0)
            }
        },
        // `-telegramChannelProbe <@handle|t.me link>` resolves a public
        // channel and reports what the parse actually got, one NSLog per fact
        // (the `-todayProbe` truncation lesson).
        //
        // It exists because an empty Telegram room has FIVE causes that render
        // as one silence and only the last is a bug: the name is not a channel
        // at all (a group, a user, a typo — `standing` says which), the
        // channel turned its web preview off, the host did not answer, the
        // channel genuinely has not posted, or the page's markup moved under
        // the parser. This is scrape-grade with no contract (prd §456), so
        // that last one is a real and recurring risk.
        Hook(key: "telegramChannelProbe") { raw, _ in
            Task { @MainActor in
                let handle = TelegramChannel.normalizeHandle(raw)
                guard TelegramChannel.isValidHandle(handle) else {
                    NSLog("telegramChannel: %@ → REFUSED (not a channel name Telegram could serve)", handle)
                    return
                }
                guard let url = URL(string: TelegramChannel.previewURL(for: handle)),
                      let data = await FeedFetch.data(url, as: "Telegram"),
                      let html = String(data: data, encoding: .utf8) else {
                    NSLog("telegramChannel: %@ → UNREACHABLE (no preview answered)", handle)
                    return
                }
                guard let channel = TelegramChannel.parse(html, handle: handle) else {
                    // The preview refused it; the LANDING page says why.
                    var verdict = "unknown"
                    if let landing = URL(string: "https://t.me/" + handle),
                       let body = await FeedFetch.data(landing, as: "Telegram"),
                       let text = String(data: body, encoding: .utf8) {
                        verdict = "\(TelegramChannel.standing(text))"
                    }
                    NSLog("telegramChannel: %@ → NOT A FOLLOWABLE CHANNEL (%@)", handle, verdict)
                    return
                }
                NSLog("telegramChannel: %@ | title=%@ | avatar=%@ | %d posts",
                      channel.handle, channel.title,
                      channel.avatarURL == nil ? "none" : "yes", channel.posts.count)
                let dated = channel.posts.filter { $0.date != nil }.count
                let pictures = channel.posts.filter { $0.photoURL != nil }.count
                NSLog("telegramChannel: dated=%d/%d | pictures=%d | videos=%d | forwards=%d",
                      dated, channel.posts.count, pictures,
                      channel.posts.filter(\.hasVideo).count,
                      channel.posts.filter { $0.forwardedFrom != nil }.count)
                for post in channel.posts.suffix(5) {
                    NSLog("telegramPost| %@ | %@ | photo=%@ | %@",
                          post.ref,
                          post.date.map { IngestSupport.isoString($0) } ?? "UNDATED",
                          post.photoURL == nil ? "no" : "yes",
                          String(post.text.prefix(80)))
                }
            }
        },
        // `-telegramImport <path>` imports an unzipped Telegram Desktop export
        // folder (result.json at its root). Chats and groups ride
        // `ImportOptions.includeMessages` exactly as they do in the UI, so a
        // run without it lands Saved Messages and channels alone.
        Hook(key: "telegramImport") { path, context in
            Task { @MainActor in
                let summary = await TelegramImport.run(folder: URL(fileURLWithPath: path),
                                                       context: context)
                NSLog("Telegram probe: saved=%d channels=%d conversations=%d",
                      summary.saved, summary.channelPosts, summary.conversations)
                NSLog("Telegram probe: %d imported, %d skipped, %d dropped by cap, failed=%d",
                      summary.imported, summary.skipped, summary.dropped,
                      summary.failed ? 1 : 0)
                if let reason = summary.reason {
                    NSLog("Telegram probe: reason=%@", reason)
                }
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
        // The three WALLET-RIDING room heads (2026-08-10, prd §349). Each rides
        // the watched wallets — no key, no account — so all three are probed by
        // landing rows and nothing else; pair with `-walletAddress` plus the
        // seat's own sync probe (`-peerProbe`, `-privacyPoolsProbe`,
        // `-gnosisPayProbe`) to land some first.
        //
        // Each `probeLines` names every cause of an empty head, because for
        // these seats "nothing" is usually the HEALTHY answer — most wallets
        // have never touched Peer, never deposited into a pool, and hold no
        // Gnosis Pay card — and only one or two causes per room are bugs.
        // `-xRoomProbe YES` — the X room's head, year by year (2026-08-13,
        // prd §375). No key, no network, no bridge state: it composes off the
        // rows an import already landed, which is why the fetch below takes the
        // whole room rather than a page of it — a span is not a span if it is
        // computed over the newest five hundred posts of fifteen years.
        //
        // `probeLines` names every cause of an empty head; the one worth the
        // probe on its own is the pair of coverage numbers it prints, since a
        // card with no subjects is healthy right after an import (the topic
        // sweep runs bounded, on foregrounds) and a bug a week later.
        Hook(key: "xRoomProbe") { _, context in
            let source = XRoomSource.source
            let descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source })
            let rows = (try? context.fetch(descriptor)) ?? []
            for line in XRoomSource.probeLines(things: rows) {
                NSLog("[Casberi] %@", line)
            }
        },
        // `-instagramRoomProbe YES` — the Instagram room's head, account by
        // account (2026-08-18, prd §395). No key, no network, no bridge state:
        // it composes off the rows an import already landed, which is why the
        // fetch below takes the WHOLE room rather than a page of it — "from 380
        // accounts" computed over the newest five hundred saves of a decade is
        // the §83 fake status in the largest type on the card.
        //
        // `probeLines` names every cause of an empty head, and prints the two
        // coverage numbers the card deliberately does not carry: how many kept
        // posts have their words back, and how many have a cover. Both are
        // `InstagramCaptions` walking the library slowly in the background, and
        // no screen anywhere says how far it has got — a probe can ask
        // `enrichedText`/`previewImageData` once, where a card would fault every
        // row of the room on every re-draw to do it.
        Hook(key: "instagramRoomProbe") { _, context in
            let source = InstagramRoomSource.source
            let descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source })
            let rows = (try? context.fetch(descriptor)) ?? []
            for line in InstagramRoomSource.probeLines(things: rows) {
                NSLog("[Casberi] %@", line)
            }
        },
        // `-journalRoomProbe YES` — the journal rooms' head, year by year
        // (2026-08-17, prd §398). No key, no network, no bridge state: it
        // composes off the rows an import already landed, which is why the
        // fetch takes the WHOLE room rather than a page of it — a span is not a
        // span if it is computed over the newest five hundred entries of a
        // decade.
        //
        // BOTH journals in one launch, named apart. They share a composer and a
        // card and have entirely separate corpora, so the failure this catches
        // is one of them composing while the other silently doesn't — and a
        // probe that reported a single merged answer could not see it.
        Hook(key: "journalRoomProbe") { _, context in
            for name in JournalRoomSource.sources.sorted() {
                let descriptor = FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == name })
                let rows = (try? context.fetch(descriptor)) ?? []
                NSLog("[Casberi] journalRoom| — %@ —", name)
                for line in JournalRoomSource.probeLines(things: rows) {
                    NSLog("[Casberi] %@", line)
                }
            }
        },
        // `-agentRoomProbe YES` — the four agent rooms' heads, month by month
        // (2026-08-23, prd §457). ChatGPT/Claude/Gemini/Claude Code in one
        // launch, named apart — the journal probe's shape, for its reason:
        // four separate corpora, one composer, and the failure worth catching
        // is one room composing while a sibling silently doesn't.
        //
        // NO fetch limit, matching the journal probe: a room's span is not a
        // span computed over the newest few hundred rows of a longer history.
        Hook(key: "agentRoomProbe") { _, context in
            for name in AgentRoomSource.sources.sorted() {
                let descriptor = FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == name })
                let rows = (try? context.fetch(descriptor)) ?? []
                NSLog("[Casberi] agentRoom| — %@ —", name)
                for line in AgentRoomSource.probeLines(source: name, things: rows, context: context) {
                    NSLog("[Casberi] %@", line)
                }
            }
        },
        Hook(key: "peerRoomProbe") { _, context in
            let source = PeerRoomSource.source
            var descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source })
            descriptor.fetchLimit = 500
            let rows = (try? context.fetch(descriptor)) ?? []
            for line in PeerRoomSource.probeLines(things: rows) {
                NSLog("[Casberi] %@", line)
            }
        },
        Hook(key: "privacyPoolsRoomProbe") { _, context in
            let source = PrivacyPoolsRoomSource.source
            var descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source })
            descriptor.fetchLimit = 500
            let rows = (try? context.fetch(descriptor)) ?? []
            for line in PrivacyPoolsRoomSource.probeLines(things: rows) {
                NSLog("[Casberi] %@", line)
            }
        },
        // Card spends are NOT rare (`GnosisPayBridge` lands them uncapped for
        // exactly that reason), so this one fetches the widest window of the
        // three. The head reads a 30-day window off the newest of them; a limit
        // that cut into the room's history would make `knowsPriorWindow` answer
        // no and silently withdraw the comparison.
        Hook(key: "gnosisPayRoomProbe") { _, context in
            let source = GnosisPayRoomSource.source
            var descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source })
            descriptor.fetchLimit = 2000
            let rows = (try? context.fetch(descriptor)) ?? []
            for line in GnosisPayRoomSource.probeLines(things: rows) {
                NSLog("[Casberi] %@", line)
            }
        },
        // The fourth wallet-riding room head (2026-08-11) — pair with
        // `-railgunProbe` to land moves first.
        Hook(key: "railgunRoomProbe") { _, context in
            let source = RailgunRoomSource.source
            var descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source })
            descriptor.fetchLimit = 500
            let rows = (try? context.fetch(descriptor)) ?? []
            for line in RailgunRoomSource.probeLines(things: rows) {
                NSLog("[Casberi] %@", line)
            }
        },
        // The fifth wallet-riding room head (2026-08-11) — its subject is
        // mostly `SafeBridge`'s own tracking state, the `ASCRoomSource` shape.
        // It reads rows for ONE thing (2026-08-17): the ref a module-only card
        // opens, which is the whole reason that card stopped being a dead
        // control. Pair with `-approvalProbe`/`-safeProbe` to land a pending
        // queue first.
        Hook(key: "safeRoomProbe") { _, context in
            let source = SafeRoomSource.source
            var descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source })
            descriptor.fetchLimit = 500
            let rows = (try? context.fetch(descriptor)) ?? []
            for line in SafeRoomSource.probeLines(things: rows) {
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
        // `-cardPointersProbe YES` — CardPointers phase by phase with the
        // STORED token (prd §420). Every read there needs CardPointers+, so
        // the subscription state is printed BEFORE anything is called: an
        // account without it refuses all five tools while `tools/list` still
        // answers, which is a subscription state and not a broken connection,
        // and the two are indistinguishable from the room. Prints answer
        // LENGTHS, never content — this is somebody's card book.
        Hook(key: "cardPointersProbe") { _, _ in
            Task { @MainActor in await CardPointersAuth.diagnose() }
        },
        // `-cardPointersRoomProbe YES` — the room head off landed rows alone
        // (prd §420). No network and no subscription needed, so it works
        // against the demo corpus and against whatever the last real sync
        // left behind. One NSLog per line (the `-todayProbe` lesson).
        Hook(key: "cardPointersRoomProbe") { _, context in
            Task { @MainActor in
                for line in CardPointersRoomSource.probeLines(context: context) {
                    NSLog("[Casberi] cardPointersRoom| %@", line)
                }
            }
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
        // `-walletbeatWatch "<name[,name]>"` — watch wallets by DISPLAY NAME
        // (matched against the bundled directory) and sync, so the whole seat
        // exercises headlessly. Names, not ids, because the id is Walletbeat's
        // internal spelling ("mtpelerin" is Bridge Wallet) and a probe nobody
        // can type from memory does not get used.
        Hook(key: "walletbeatWatch") { spec, context in
            Task { @MainActor in
                var named: [String] = []
                for raw in spec.split(separator: ",") {
                    let q = String(raw).trimmingCharacters(in: .whitespaces).lowercased()
                    guard !q.isEmpty else { continue }
                    guard let entry = WalletbeatDirectory.wallets.first(where: {
                        $0.name.lowercased() == q || $0.id == q
                    }) ?? WalletbeatDirectory.wallets.first(where: {
                        $0.name.lowercased().hasPrefix(q)
                    }) else {
                        NSLog("[Casberi] walletbeat| NOT RATED: %@", q)
                        continue
                    }
                    _ = WalletbeatWatch.add(entry, context: context)
                    named.append(entry.id)
                }
                let added = await WalletbeatIngest.refresh(context: context)
                NSLog("[Casberi] walletbeat| watching %@ — %@ new",
                      named.isEmpty ? "NOTHING" : named.joined(separator: ","),
                      added.map(String.init) ?? "UNREACHABLE")
            }
        },
        // `-walletbeatFollow YES|NO` — the free tier, headless (prd §421).
        //
        // Declared BEFORE the probes (hooks run in list order) so a run can follow and
        // then read in one launch. It exists because following with NOTHING watched is
        // the state that could not be reached any other way here: the connect screen's
        // button is the only door, and no simulator run taps it.
        Hook(key: "walletbeatFollow") { value, context in
            let on = value.uppercased() != "NO"
            WalletbeatWatch.following = on
            Task { @MainActor in
                let added = on ? await WalletbeatIngest.refresh(context: context) : nil
                NSLog("[Casberi] walletbeatFollow| following=%@ watched=%d landed=%@",
                      on ? "YES" : "NO",
                      WalletbeatWatch.watchedIDs(context: context).count,
                      added.map(String.init) ?? (on ? "UNREACHABLE" : "-"))
            }
        },
        // `-walletbeatConnectedApp "<name[,name]>"|clear` — pretend a wallet app
        // announced itself over WalletConnect (prd §430).
        //
        // Declared BEFORE the probes (hooks run in list order) so a run can seed a
        // sighting and read the join in one launch. It exists because the state it
        // seeds is UNREACHABLE any other way here: the real record is written from a
        // settled WalletConnect session's peer metadata, no simulator has a wallet app
        // to settle one, and this project has never observed a real `AppMetadata.name`.
        // So the resolver's own fixtures live in the harness and this is what proves
        // the wiring — that a name really reaches the setup screen's offer, the
        // directory's marker and the room's button.
        //
        // Takes the app's OWN name ("Safe{Wallet}", "Ledger"), never a Walletbeat id:
        // feeding it an id would test the table against itself and prove nothing about
        // the transform that makes the join work at all.
        Hook(key: "walletbeatConnectedApp") { spec, context in
            if spec.lowercased() == "clear" {
                WalletConnectApps.forgetAll()
                NSLog("[Casberi] walletbeatApp| cleared")
                return
            }
            for raw in spec.split(separator: ",") {
                let name = String(raw).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                WalletConnectApps.record(appNamed: name)
                let id = WalletbeatMatch.walletID(
                    forAppNamed: name,
                    in: WalletbeatDirectory.wallets.map { (id: $0.id, name: $0.name) })
                NSLog("[Casberi] walletbeatApp| \"%@\" key=%@ → %@",
                      name, WalletbeatMatch.key(name) ?? "-", id ?? "NOT RATED")
            }
            Task { @MainActor in
                let offered = WalletbeatWatch.connectedSuggestions(context: context)
                NSLog("[Casberi] walletbeatApp| offering=%@",
                      offered.isEmpty ? "NOTHING" : offered.map(\.name).joined(separator: ","))
            }
        },
        // `-walletbeatProbe YES` — the read phase by phase, then one line per
        // watched wallet's ratings and one per landed incident. An empty room
        // has five causes that render as one silence (nothing watched, a first
        // sync still in flight, ratings that failed to decode, an unreachable
        // host, a directory the wallet has left) and only two are bugs.
        Hook(key: "walletbeatProbe") { _, context in
            Task { @MainActor in
                for line in WalletbeatRoomSource.probeLines(context: context) {
                    NSLog("[Casberi] walletbeat| %@", line)
                }
                let files = await WalletbeatFetch.newsFiles()
                NSLog("[Casberi] walletbeat| newsIndex=%@",
                      files.map { "\($0.count) entries" } ?? "UNREACHABLE")
                for id in WalletbeatWatch.watchedIDs(context: context) {
                    guard let card = await WalletbeatFetch.card(walletID: id) else {
                        NSLog("[Casberi] walletbeatLive| %@ UNREACHABLE", id)
                        continue
                    }
                    let c = card.overall
                    NSLog("[Casberi] walletbeatLive| %@ judged=%d/%d coverage=%@ lead=%@",
                          id, c.judged, c.applicable, String(describing: card.coverage),
                          String(describing: card.lead))
                }
            }
        },
        // `-walletbeatRoomProbe YES` — the head alone, no network.
        Hook(key: "walletbeatRoomProbe") { _, context in
            for line in WalletbeatRoomSource.probeLines(context: context) {
                NSLog("[Casberi] walletbeatRoom| %@", line)
            }
        },
        // `-walletbeatSheetProbe YES` — which anatomy each landed row's sheet draws, and
        // whether the facts behind it are actually there (prd §419 amendment).
        //
        // It exists because a sheet falling back to the GENERIC anatomy looks like a
        // deliberate design rather than a bug: a title, a link and some tags is a
        // perfectly plausible screen. The two ways it happens are a ref namespace that
        // stopped matching (§311's silent-quiet class) and an incident whose facts were
        // never recorded, and only the second is visible from the row itself.
        Hook(key: "walletbeatSheetProbe") { _, context in
            let rows = ((try? context.fetch(FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> { $0.source == "Walletbeat" },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []).live
            let book = WalletbeatIncidentBook.all()
            NSLog("[Casberi] walletbeatSheet| rows=%d incidentBook=%d cards=%d",
                  rows.count, book.count, WalletbeatState.cards().count)
            for thing in rows.prefix(30) {
                let shape = WalletbeatSheetSource.shape(for: thing)
                var detail = "—"
                switch shape {
                case .wallet:
                    let id = WalletbeatWatch.walletID(from: thing) ?? "?"
                    detail = "card=\(WalletbeatState.card(id) != nil ? "read" : "NOT READ")"
                case .incident:
                    if let facts = WalletbeatIncidentBook.facts(ref: thing.sourceRef) {
                        detail = "severity=\(facts.severity?.rawValue ?? "none") status=\(facts.status.rawValue) sources=\(facts.sources.count)"
                    } else {
                        detail = "NO FACTS — the sheet falls back to prose only"
                    }
                case .revision:
                    if let (rev, attribute) = WalletbeatSheetSource.revisionAttribute(for: thing) {
                        // The BEFORE is the §430 field and is printed apart from the
                        // after: a row landed before it existed reads `before=none`,
                        // which is the honest state and not a parse failure.
                        detail = "\(rev.walletID).\(rev.attributeID) \(rev.before?.rawValue ?? "none")→\(rev.after.rawValue) named=\(attribute != nil)"
                    } else {
                        detail = "REF UNPARSED — the sheet falls back to generic"
                    }
                case .none:
                    detail = "GENERIC (import receipt, or a ref no namespace matches)"
                }
                NSLog("[Casberi] walletbeatSheet| %@ · %@ · %@",
                      shape?.rawValue ?? "generic", thing.title.prefix(46).description, detail)
            }
        },
        // `-l2beatFollow YES|NO` — the free tier, headless (prd §428).
        //
        // Declared BEFORE the probes (hooks run in list order) so a run can follow and
        // then read in one launch. It exists because following with NOTHING watched is
        // the state that could not be reached any other way here: the connect screen's
        // button is the only door, and no simulator run taps it.
        Hook(key: "l2beatFollow") { value, context in
            let on = value.uppercased() != "NO"
            L2beatWatch.following = on
            Task { @MainActor in
                let added = on ? await L2beatIngest.refresh(context: context) : nil
                NSLog("[Casberi] l2beatFollow| following=%@ watched=%d landed=%@",
                      on ? "YES" : "NO",
                      L2beatWatch.watchedIDs(context: context).count,
                      added.map(String.init) ?? (on ? "UNREACHABLE" : "-"))
            }
        },
        // `-l2beatWatch "<id[,id]>"` — watch chains headlessly, by L2BEAT's own project
        // id (`arbitrum`, `zksync2`, `optimism` — the REPO id, not the URL slug; those
        // differ for ten of the 105 and the probe says so when an id misses).
        //
        // Resolved against the bundled directory, so it needs no network and works on a
        // device that has never synced.
        Hook(key: "l2beatWatch") { value, context in
            var watched: [String] = []
            var missed: [String] = []
            for raw in value.split(separator: ",") {
                let id = raw.trimmingCharacters(in: .whitespaces)
                guard !id.isEmpty else { continue }
                guard let project = L2beatState.best(id) else { missed.append(id); continue }
                if L2beatWatch.add(project, context: context) != nil { watched.append(id) }
            }
            NSLog("[Casberi] l2beatWatch| added=%@ alreadyOrMissing=%@ watching=%d",
                  watched.joined(separator: ",").isEmpty ? "-" : watched.joined(separator: ","),
                  missed.joined(separator: ",").isEmpty ? "-" : missed.joined(separator: ","),
                  L2beatWatch.watchedIDs(context: context).count)
        },
        // `-l2beatProbe YES` — the read phase by phase, then one line per watched chain
        // and the milestone walk's own targets.
        //
        // An empty room has five causes that render as one silence (nothing watched and
        // nothing followed, a first sync still in flight, an assessment that failed to
        // decode, an unreachable host, a chain that left L2BEAT's registry) and only two
        // are bugs. One NSLog per line, the `-todayProbe` truncation lesson.
        Hook(key: "l2beatProbe") { _, context in
            Task { @MainActor in
                for line in L2beatRoomSource.probeLines(context: context) {
                    NSLog("[Casberi] l2beat| %@", line)
                }
                let watched = L2beatWatch.watchedIDs(context: context)
                let targets = L2beatIngest.milestoneTargets(watched: watched)
                NSLog("[Casberi] l2beat| milestoneTargets=%d [%@]",
                      targets.count, targets.prefix(12).joined(separator: ","))
                let fresh = await L2beatFetch.summary()
                NSLog("[Casberi] l2beat| summary=%@",
                      fresh.isEmpty ? "UNREACHABLE" : "\(fresh.count) projects")
                for id in watched {
                    guard let live = fresh.first(where: { $0.id == id }) else {
                        NSLog("[Casberi] l2beatLive| %@ — NOT IN L2BEAT'S SUMMARY", id)
                        continue
                    }
                    NSLog("[Casberi] l2beatLive| %@ stage=%@ review=%@ flagged=%d/%d",
                          live.name, live.stage?.rawValue ?? "-",
                          live.underReview ? "YES" : "no", live.flagged, live.risks.count)
                }
            }
        },
        // `-l2beatRoomProbe YES` — the head alone, no network.
        Hook(key: "l2beatRoomProbe") { _, context in
            for line in L2beatRoomSource.probeLines(context: context) {
                NSLog("[Casberi] l2beatRoom| %@", line)
            }
        },
        // `-l2beatSheetProbe YES` — which anatomy each landed row's sheet draws, and
        // whether the facts behind it are actually there (prd §428).
        //
        // It exists because a sheet falling back to the GENERIC anatomy looks like a
        // deliberate design rather than a bug: a title, a link and some tags is a
        // perfectly plausible screen. The two ways it happens are a ref namespace that
        // stopped matching (§311's silent-quiet class) and a milestone whose facts were
        // never recorded, and only the second is visible from the row itself.
        Hook(key: "l2beatSheetProbe") { _, context in
            let rows = ((try? context.fetch(FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> { $0.source == "L2BEAT" },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []).live
            let book = L2beatMilestoneBook.all()
            NSLog("[Casberi] l2beatSheet| rows=%d milestoneBook=%d assessments=%d",
                  rows.count, book.count, L2beatState.projects().count)
            for thing in rows.prefix(30) {
                let shape = L2beatSheetSource.shape(for: thing)
                var detail = "—"
                switch shape {
                case .chain:
                    let id = L2beatWatch.chainID(from: thing) ?? "?"
                    let read = L2beatState.project(id) != nil
                        ? "live" : (L2beatDirectory.project(id) != nil ? "bundled" : "NONE")
                    detail = "assessment=\(read)"
                case .milestone:
                    if let facts = L2beatMilestoneBook.facts(ref: thing.sourceRef) {
                        detail = "kind=\(facts.kind.rawValue) chain=\(facts.projectID) url=\(facts.url != nil)"
                    } else {
                        detail = "NO FACTS — the sheet falls back to prose only"
                    }
                case .revision:
                    if let (rev, project, risk) = L2beatSheetSource.revisionSubject(for: thing) {
                        let subject = rev.isStageMove
                            ? "stage→\(rev.afterStage?.rawValue ?? "?")"
                            : "\(rev.axis?.rawValue ?? "?")→\(rev.afterSentiment?.rawValue ?? "?")"
                        detail = "\(rev.projectID).\(subject) named=\(project != nil) risk=\(risk != nil)"
                    } else {
                        detail = "REF UNPARSED — the sheet falls back to generic"
                    }
                case .none:
                    detail = "GENERIC (import receipt, or a ref no namespace matches)"
                }
                NSLog("[Casberi] l2beatSheet| %@ · %@ · %@",
                      shape?.rawValue ?? "generic", thing.title.prefix(46).description, detail)
            }
        },
        // `-widgetProbe YES` — everything the Home Screen would draw this
        // launch (prd §382).
        //
        // Publishes, then reads the payloads back through the SAME readers the
        // widget extension uses — which is what makes it a test of the ROUND
        // TRIP rather than of the gather. The encode and the decode are the
        // one place these two processes can silently disagree (see
        // `WidgetPayload.encoder`), and a payload that fails to decode is
        // indistinguishable from one that was never published: every tile
        // empties at once with nothing in any log to say why.
        //
        // It exists because an empty tile has causes that render identically
        // and only some are bugs — nothing kept, nothing due, no wallet
        // watched, a reading aged past its own freshness window, or a publish
        // that never ran. The widget extension cannot be attached to in a
        // simulator run, so this is the only headless view of it there is.
        Hook(key: "widgetProbe") { _, context in
            WidgetPublish.probe(context: context)
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
                // The SAME rows production sweeps, not a fresh whole-store
                // fetch (2026-08-12). `runNotifySweep` scopes its read to the
                // news/away window plus the dated rows, so a probe that reads
                // everything would be exercising an input the sweep never
                // sees — and this probe is the only exerciser there is, since
                // the simulator never runs a `BGAppRefreshTask`. A probe that
                // measures a different thing than the code it reports on is
                // worse than no probe.
                let things = WalletBackgroundRefresh.sweepCorpus(context) ?? []
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
        // `-radicleSeed <host>` — point at a seed node (prd §400). Declared
        // BEFORE the watch/probe hooks: hooks run in list order, and both must
        // read a seed that is already set.
        Hook(key: "radicleSeed") { spec, _ in
            guard let host = RadicleWire.normalizeSeed(spec) else {
                NSLog("radicleSeed: REFUSED %@", spec); return
            }
            RadicleStore.shared.seed = host
            Task { @MainActor in
                let (ok, version) = await RadicleIngest.probeSeed(host)
                NSLog("radicleSeed: %@ | httpd=%@ | apiVersion=%@",
                      host, ok ? "YES" : "NO", version ?? "-")
            }
        },
        // `-radicleWatch "<rid[,rid]>"` — watch repos and sync.
        Hook(key: "radicleWatch") { spec, context in
            Task { @MainActor in
                var added: [String] = []
                for raw in spec.split(separator: ",") {
                    let one = String(raw).trimmingCharacters(in: .whitespaces)
                    guard let id = RadicleWire.normalizeRID(one) else {
                        NSLog("radicleWatch: REFUSED %@", one); continue
                    }
                    if RadicleStore.shared.add(id) { added.append(id) }
                }
                let n = await RadicleIngest.refresh(context: context)
                NSLog("radicleWatch: +%d watched | seed=%@ | %@ new",
                      added.count, RadicleStore.shared.seed,
                      n.map(String.init) ?? "FAILED")
            }
        },
        // `-radicleProbe YES` — the sweep, then what the seat HOLDS, one NSLog
        // per row (the `-todayProbe` truncation lesson).
        //
        // It exists because an empty Radicle room has SIX causes that render as
        // one silence and only the last is a bug: nothing watched, the seed
        // unreachable, the seed simply not seeding that repo (no global index —
        // the most likely and most confusing one), a repo with no patches or
        // issues, everything already landed, or the payload shape drifting. The
        // per-repo line separates them — it prints the counts the sweep read, so
        // a repo answering `patches=0 issues=0` is a quiet repo while a repo
        // that failed to parse prints `UNREADABLE`, which is the shape-drift
        // signal (§400 quirk 6: `meta` lives under `payloads`, and reading it
        // flat yields an empty room with no error).
        Hook(key: "radicleProbe") { _, context in
            Task { @MainActor in
                let store = RadicleStore.shared
                let seed = store.seed
                let (ok, version) = await RadicleIngest.probeSeed(seed)
                NSLog("radicleProbe: seed=%@ | httpd=%@ | apiVersion=%@ | watching %d",
                      seed, ok ? "YES" : "NO", version ?? "-", store.repos.count)
                // `refreshWaiting`, not `refresh` — a `-radicleWatch` in the
                // SAME launch is still in flight, and the plain guard would
                // hand this 0 and let it dump an empty corpus.
                let n = await RadicleIngest.refreshWaiting(context: context)
                NSLog("radicleProbe: %@ new", n.map(String.init) ?? "FAILED")
                for rid in store.repos {
                    if let snap = store.snapshot(for: rid) {
                        NSLog("radicleRepo| %@ | name=%@ | head=%@ | patches o%d/d%d/a%d/m%d | issues o%d/c%d",
                              rid, store.name(for: rid) ?? "-", snap.head ?? "-",
                              snap.patchesOpen, snap.patchesDraft,
                              snap.patchesArchived, snap.patchesMerged,
                              snap.issuesOpen, snap.issuesClosed)
                    } else {
                        NSLog("radicleRepo| %@ | UNREADABLE", rid)
                    }
                }
                let rows = (try? context.fetch(
                    FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Radicle" })
                )) ?? []
                for thing in rows.filter(\.isLive)
                    .sorted(by: { $0.capturedAt > $1.capturedAt }).prefix(30) {
                    NSLog("radicleRow| %@ | ref=%@ | who=%@ | tags=%@",
                          thing.title, thing.sourceRef ?? "-",
                          thing.authorHandle ?? "-", thing.tags.joined(separator: ","))
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
        // `-nftPicks "<network|contract[,…]>"|clear` seeds the NFT pick book for
        // the FIRST watched wallet headlessly (prd §387), so the shelf's read
        // and its card verify without driving the picker. Declared BEFORE
        // `-nftShelfProbe` — hooks run in list order and the probe must read a
        // seeded book. Each entry is a pick key exactly as the picker makes one
        // ("eth-mainnet|0xbc4c…"); a malformed one is REPORTED rather than
        // dropped, since a silently-ignored seed reads as a broken shelf.
        Hook(key: "nftPicks") { spec, _ in
            Task { @MainActor in
                guard let entry = WalletStore.shared.addresses.first else {
                    NSLog("nftPicks: no watched wallet — pair with -walletAddress")
                    return
                }
                if spec == "clear" {
                    WalletNFTStore.shared.clear(wallet: entry.address)
                    NSLog("nftPicks: cleared %@", entry.address)
                    return
                }
                var ok = 0, bad = 0
                for raw in spec.split(separator: ",").map(String.init) {
                    let key = raw.trimmingCharacters(in: .whitespaces)
                    guard let parts = NFTPickKey.split(key) else { bad += 1; continue }
                    WalletNFTStore.shared.toggle(
                        wallet: entry.address,
                        collection: NFTPickKey.make(network: parts.network, contract: parts.contract))
                    ok += 1
                }
                NSLog("nftPicks: %d picked, %d malformed, %d now on %@",
                      ok, bad, WalletNFTStore.shared.book.picks(wallet: entry.address).count,
                      entry.address)
            }
        },
        // `-nftCollectionsProbe YES` reads what the picker would LIST for every
        // watched wallet (prd §387): one `nftCollection|` line per collection
        // with its pick key, held count, whether Alchemy flags it spam, whether
        // artwork resolved, and whether it is currently picked — one NSLog each
        // (the `-todayProbe` truncation lesson).
        //
        // It exists because an empty picker has FIVE causes that render as one
        // sentence — no watched wallet, a Solana-only wallet (Alchemy's NFT API
        // is EVM-only, so this is a fact and not a failure), a wallet that holds
        // nothing on the five chains, every read failing, or the shared
        // `getContractsForOwner` parse drifting — and only the last two are
        // bugs. The `read=` line separates them: a chain that answered is listed
        // even when it holds nothing, a chain that failed is named.
        //
        // Spends NOTHING in the common case: this is the same cached read the
        // wallet refresh already made for the NFT spam allowlist.
        Hook(key: "nftCollectionsProbe") { _, _ in
            Task { @MainActor in
                let watched = WalletStore.shared.addresses
                guard !watched.isEmpty else {
                    NSLog("nftCollections: no watched wallet — pair with -walletAddress")
                    return
                }
                for entry in watched {
                    let resolved = await WalletIngest.resolvedAddresses([entry.address])
                    let byKey = await WalletNFTShelf.collections(addresses: resolved)
                    let evm = resolved.filter { ENS.isHexAddress($0) }
                    NSLog("nftCollections| wallet=%@ resolved=%d evm=%d chainsRead=%d of %d",
                          entry.address, resolved.count, evm.count,
                          byKey.count, evm.count * WalletNFTShelf.networks.count)
                    for collection in NFTCollectionOrder.sorted(byKey.values.flatMap { $0 }) {
                        NSLog("nftCollection| %@ count=%d spam=%@ art=%@ picked=%@ name=%@",
                              collection.id, collection.count,
                              collection.isSpam ? "YES" : "no",
                              (collection.imageURL?.isEmpty == false) ? "YES" : "no",
                              WalletNFTStore.shared.isPicked(wallet: entry.address,
                                                             collection: collection.id) ? "YES" : "no",
                              collection.name)
                    }
                }
            }
        },
        // `-nftOriginProbe YES|"<network>|<hash>"` — the NFT-origin rule (prd
        // §481), which decides whether an NFT arriving at a watched wallet
        // becomes a row. One NSLog per fact (the `-todayProbe` truncation
        // lesson).
        //
        // Bare `YES` prints the rule's INPUTS per wallet: how many collections
        // each chain answered with, how many OpenSea has safelisted, how many
        // are picked, and how many known-good counterparties the corpus knows.
        // It exists because "a spam mint still showed" and "a mint of mine
        // disappeared" have SIX causes that look identical from the feed — no
        // watched wallet, the collections read failing (so every arm fails open
        // and NOTHING is filtered), a receipt host not answering (same), the
        // pass exceeding `nftReceiptBudget`, the void sitting in known-good
        // because this wallet once burned something, or the rule working
        // exactly as designed — and only two of them are bugs. `verified=0`
        // beside a healthy `collections=` is the shape of a drifted
        // `safelistRequestStatus` parse; `knownGoodVoid=YES` is the shape of the
        // rule being switched off by an old burn.
        //
        // Given a "<network>|<hash>" it asks the DECISIVE question for one
        // transaction, through the same read the ingest makes: did this wallet
        // send it? `sent=unread` is the fail-open case and is not a failure.
        //
        // Spends nothing in the census case (the collections read is the cached
        // one the wallet refresh already made) and one keyless receipt read in
        // the hash case — no Alchemy credits either way.
        Hook(key: "nftOriginProbe") { value, _ in
            Task { @MainActor in
                let watched = WalletStore.shared.addresses
                guard !watched.isEmpty else {
                    NSLog("nftOrigin: no watched wallet — pair with -walletAddress")
                    return
                }
                let spec = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
                if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                    for entry in watched {
                        let resolved = await WalletIngest.resolvedAddresses([entry.address])
                        for address in resolved.filter({ ENS.isHexAddress($0) }) {
                            let sent = await WalletIngest.nftTransactionWasSent(
                                network: parts[0], hash: parts[1], address: address)
                            let verdict = sent.map { $0 ? "YES" : "no" }
                                ?? "unread (fails open — the row is kept)"
                            NSLog("nftOrigin| wallet=%@ network=%@ hash=%@ sent=%@",
                                  address, parts[0], parts[1], verdict)
                        }
                    }
                    return
                }
                for entry in watched {
                    let resolved = await WalletIngest.resolvedAddresses([entry.address])
                    let evm = resolved.filter { ENS.isHexAddress($0) }
                    let byKey = await WalletNFTShelf.collections(addresses: resolved)
                    let verified = await WalletIngest.verifiedNFTKeys(addresses: evm)
                    let picks = WalletNFTStore.shared.book.picks(wallet: entry.address)
                    let held = byKey.values.reduce(0) { $0 + $1.count }
                    NSLog("nftOrigin| wallet=%@ evm=%d chainsRead=%d of %d collections=%d verified=%d picked=%d",
                          entry.address, evm.count, byKey.count,
                          evm.count * WalletNFTShelf.networks.count,
                          held, verified.count, picks.count)
                    NSLog("nftOrigin| budget=%d per pass; a chain that did not answer fails OPEN",
                          WalletIngest.nftReceiptBudgetForProbe)
                }
            }
        },
        // `-nftShelfProbe YES` composes the shelf the Wallet room would draw
        // (prd §387) for every watched wallet with picks: the header line, then
        // one `nftPiece|` line per piece with the OpenSea door it opens.
        //
        // `pieces=0` is a REAL state with four causes and only one is a bug —
        // nothing picked (so no request is made at all, which is the resting
        // state for most wallets), every picked piece lacking artwork we can
        // draw, the pieces having moved out since the pick, or the narrow read
        // failing. The `picks=` count beside it is what separates the first
        // from the rest.
        Hook(key: "nftShelfProbe") { _, _ in
            Task { @MainActor in
                let watched = WalletStore.shared.addresses
                guard !watched.isEmpty else {
                    NSLog("nftShelf: no watched wallet — pair with -walletAddress")
                    return
                }
                let book = WalletNFTStore.shared.book
                for entry in watched {
                    let picks = book.picks(wallet: entry.address)
                    let pieces = await WalletNFTShelf.pieces(for: entry.address, book: book)
                    NSLog("nftShelf| wallet=%@ picks=%d chains=%@ pieces=%d",
                          entry.address, picks.count,
                          book.networks(wallet: entry.address).joined(separator: "+"),
                          pieces.count)
                    for piece in pieces {
                        NSLog("nftPiece| %@ collection=%@ name=%@ door=%@",
                              piece.id, piece.collection, piece.name,
                              piece.openSeaURL?.absoluteString ?? "NONE")
                    }
                }
            }
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
        // `-connectPickerProbe "<addr[,addr]>"` — the connect picker's plan
        // (2026-08-13, prd §376), over addresses standing in for what a
        // settled WalletConnect session would have shared, against the REAL
        // watch list and the REAL Safe reverse-lookup.
        //
        // A stand-in rather than a handshake because there is no other way:
        // no simulator has a wallet app, so `-wcConnectProbe` can only ever
        // reach `.timedOut` (it says so itself) and the picker that follows a
        // settle is unreachable on every automated run this project has. The
        // `SHAPE`/`LIVE` split `-appleWalletProbe` uses for the same reason.
        //
        // It exists because the numbers this sheet states are exactly the ones
        // that were silently wrong before it: `room=` and `overflow=` are the
        // watch cap's arithmetic, and `overflow` was previously unrepresented
        // anywhere in the app, which is what let a connect drop accounts
        // without a word. One NSLog per row (the `-todayProbe` truncation
        // lesson), each naming the origin and whether it was pre-ticked —
        // "shared" and "found" are pre-selected differently on purpose, and a
        // joined dump can't show that held.
        //
        // Pair with `-walletAddress` (on earlier launches) to move `room=`.
        Hook(key: "connectPickerProbe") { spec, _ in
            let shared = spec.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !shared.isEmpty else {
                NSLog("connectPicker| no addresses given")
                return
            }
            Task { @MainActor in
                let lookup = await SafeBridge.signerSafes(for: shared)
                let plan = WalletConnectPlan.make(
                    shared: shared.map { (address: $0,
                                          namespace: ENS.isHexAddress($0)
                                              ? WalletConnectBridge.evmNamespace
                                              : WalletConnectBridge.solanaNamespace) },
                    safes: lookup.safes,
                    watched: WalletStore.shared.addresses.map(\.address),
                    limit: WalletStore.watchLimit)
                NSLog("connectPicker| shared=%d safes=%d reachable=%@ truncated=%@",
                      shared.count, lookup.safes.count,
                      lookup.reachable ? "YES" : "NO",
                      lookup.truncated ? "YES" : "NO")
                NSLog("connectPicker| watched=%d limit=%d room=%d pickable=%d overflow=%d ceiling=%d",
                      WalletStore.shared.addresses.count, WalletStore.watchLimit,
                      plan.roomLeft, plan.pickable.count, plan.overflow, plan.selectionCeiling)
                for row in plan.rows {
                    let origin: String
                    switch row.origin {
                    case .shared: origin = "shared"
                    case .safe(let via, let chain):
                        origin = "safe(via \(WalletStore.shortAddress(via)) on \(chain))"
                    }
                    NSLog("connectPickerRow| %@ | %@ | watching=%@ | ticked=%@",
                          row.address, origin,
                          row.alreadyWatching ? "YES" : "NO",
                          plan.preselected.contains(row.key) ? "YES" : "NO")
                }
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
        // `-altanaProbe YES` — the Altana keystore read on its own
        // (2026-08-18, prd §402): which credentials can sign as each watched
        // wallet, their role, expiry, and whether they have ever signed. One
        // NSLog per line (the `-todayProbe` truncation lesson).
        //
        // Separate from `-actingPartiesProbe` even though the inventory folds
        // it in, because an empty keystore reading has FOUR causes that render
        // as the same silence — no EVM wallet watched, the RPC did not answer,
        // the wallet genuinely has nothing registered (which today is the
        // correct answer for every wallet but Altana's own deployer), or the
        // decoder refused a reply whose shape it did not recognise. Only the
        // last two are worth acting on, and `unreadable` vs `keys=0` is the
        // line that separates them.
        //
        // Pair with `-walletAddress` to point it at a specific account. Reads
        // only: no write selector is ever constructed (`AltanaKeystore.writeSelectors`
        // exists to be checked against, and the self-test fails the build on
        // one appearing at a call site).
        Hook(key: "altanaProbe") { _, _ in
            Task { @MainActor in
                for line in await AltanaKeystore.probeLines() {
                    NSLog("altana| %@", line)
                }
            }
        },
        // `-altanaSync YES` — run the keystore sweep and land rows, without
        // waiting for a foreground wallet pass. Declared BEFORE the room
        // probe (hooks run in list order) so a single launch can sync and
        // then read the card it just made possible.
        Hook(key: "altanaSync") { _, context in
            Task { @MainActor in
                let n = await AltanaKeystore.sync(context: context)
                NSLog("altanaSync| landed=%d", n)
            }
        },
        // `-altanaRoomProbe YES` — the room head (prd §403): the stored
        // readings, then the composed card line by line. One NSLog each (the
        // `-todayProbe` truncation lesson).
        //
        // It reads the SNAPSHOT, never the chain, which is the whole contract
        // of this head — so an empty card here means the sweep hasn't run or
        // found nothing, never that the RPC was slow. Pair with `-altanaSync`
        // on the same launch to prove the round trip.
        Hook(key: "altanaRoomProbe") { _, _ in
            Task { @MainActor in
                for line in AltanaRoom.probeLines() {
                    NSLog("altanaRoom| %@", line)
                }
            }
        },
        // `-signerProbe YES` — this phone as a Safe co-signer (prd §425),
        // one NSLog per fact (the `-todayProbe` truncation lesson).
        //
        // It exists because "no Sign button" has SEVEN causes that render as
        // one blank space and only two are bugs: no key on this phone, no
        // pending Safe transaction in the corpus, the Safe is on a chain the
        // rail cannot read, the threshold is 1, this phone is not an owner,
        // the chain did not answer, or the hashes disagree. The last is the
        // only one that means something is WRONG, and it is the one that must
        // never be mistaken for a network hiccup.
        //
        // It SIGNS NOTHING. There is no biometric prompt in a headless run and
        // never should be — a probe that could spend a Face ID is a probe
        // nobody can put in a sweep. Everything up to the tap is exercised,
        // which is every refusal.
        Hook(key: "signerProbe") { _, context in
            Task { @MainActor in
                NSLog("signer| key=%@ address=%@ biometry=%@",
                      String(describing: SignerKey.presence()),
                      SignerKey.address() ?? "-",
                      SignerKey.biometryAvailable() ? "yes" : "no")
                // The N-of-N reading (prd §426). It is the one fact on this
                // probe that is about the SAFE rather than the phone, and the
                // one whose absence is silent: a 2-of-2 looks exactly like a
                // 2-of-3 everywhere else in the app.
                let standing = await SafeSigner.standing()
                NSLog("signer| signsFor=%d reachable=%@ truncated=%@",
                      standing.safes.count,
                      standing.reachable ? "yes" : "no",
                      standing.truncated ? "yes" : "no")
                for safe in standing.safes {
                    NSLog("signer| %@ %@ %d-of-%d spare=%d noSpareOwner=%@",
                          safe.seg, safe.safeAddress, safe.threshold, safe.ownerCount,
                          safe.spareOwners, safe.hasNoSpareOwner ? "YES" : "no")
                }
                var descriptor = FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == "Safe" })
                descriptor.fetchLimit = 50
                let rows = (try? context.fetch(descriptor)) ?? []
                let pending = rows.compactMap(\.sourceRef)
                    .filter { $0.hasPrefix("wallet:safe:") }
                NSLog("signer| pendingRows=%d", pending.count)
                for ref in pending.prefix(5) {
                    let bits = ref.split(separator: ":", maxSplits: 3).map(String.init)
                    guard bits.count == 4 else { continue }
                    let seg = bits[2], hash = bits[3]
                    guard SafeSigner.canSign(onSegment: seg) else {
                        NSLog("signer| %@ chainUnsupported=%@", hash, seg); continue
                    }
                    switch await SafeSigner.prepare(seg: seg, safeTxHash: hash) {
                    case .success(let ready):
                        NSLog("signer| %@ READY have=%d/%d reading=%@ decoded=%@",
                              hash, ready.have, ready.required,
                              String(describing: ready.reading), ready.reading.isDecoded ? "yes" : "no")
                    case .failure(let refusal):
                        NSLog("signer| %@ REFUSED %@", hash, String(describing: refusal))
                    }
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
        // `-sheetShapeProbe YES` — CAN THE DEMO REACH EVERY SHEET ANATOMY?
        //
        // Five anatomies decide what a thing sheet IS, each by a DATA test
        // over the record: `SocialSheet` (post/person/save/transcript),
        // `NoteSheet` (entry/note/passage), `AgentSheet`
        // (conversation/grant), `PurchaseStage` (receipt/watch) and
        // `WorkStage`. A shape no demo row can reach is a feature a
        // first-time opener cannot see, and nothing else in the tree can
        // notice: the rows are all present, every static check passes, and
        // the room renders — the sheet just quietly takes a weaker branch.
        //
        // Found by hand four times before this existed, always the same
        // shape and never by a check: `.person` was unreachable because no
        // demo row set `socialContext == "follow"`, and `.note` because the
        // vault's rows wore `demo:obsidian:N` refs while `isNamed` asks
        // `ObsidianLink.relativePath` for an `obsidian:` one — the identical
        // ref-shape miss CLAUDE.md already records for Peer, Privacy Pools
        // and Cloudflare. This is that hand-check, mechanised.
        //
        // Counts, never a verdict: the probe reports what the corpus can
        // reach and `verify.sh` decides what a gap is. A shape legitimately
        // absent (no watched Trello card, say) is a seeding decision, not a
        // bug this file can rule on.
        // `-floorProbe YES` — THE STATE THAT SITS UNDER A CONTROL'S MINIMUM.
        //
        // The quietest demo failure there is. A control that gates on a count
        // (`addresses.count > 1`, `series.count >= 14`, `imageURLs.count > 1`)
        // does not fail when the demo is under its floor — it simply does not
        // draw, and every other check passes: the rows are there, the room
        // renders, the anatomy is right. There is no error to find.
        //
        // Four of these were found by eye this week and each took a
        // screenshot to notice: the wallet face rail (one watched wallet, so
        // `count > 1` never held), PostHog's card (14 days of series), the
        // social face rail, and `NoteSheet`'s read-time (100 words, and the
        // demo's vault notes were ten). A fifth was found the same day by
        // seeding a ONE-element `imageURLs` — `PostCard` only switches to the
        // grid at two or more and falls back to a field that was never set,
        // so it drew nothing at all.
        //
        // CURATED, NOT ALL 82. The tree holds 82 `.count >= N` gates and most
        // are formatting — `parts.count > 1` choosing a separator,
        // `words.count > 100` choosing a type size — where being under the
        // floor is the correct answer. Asserting those would demand the demo
        // satisfy every branch of every layout, which is the lint nobody keeps.
        // These are the ones where a whole CONTROL disappears.
        Hook(key: "floorProbe") { _, context in
            let things = ((try? context.fetch(FetchDescriptor<Thing>())) ?? []).live
            // (name, what it gates, measured, floor, REQUIRED)
            //
            // `required` is the ruling, and it is the point of the registry.
            // A floor the demo sits under is not automatically a gap: the
            // address book's filter field appears at nine entries because a
            // book of eight does not need searching, so a demo of eight is
            // CORRECT and saying otherwise would be padding the demo to
            // satisfy a check. The wallet rail is the opposite — the demo
            // intends three wallets and the rail is a shipped feature, so one
            // is a bug. `verify.sh` fails on the required ones and prints the
            // rest, which keeps the decision written down instead of implied
            // by whether somebody padded a list.
            var rows: [(String, String, Int, Int, Bool)] = []
            rows.append(("wallet.addresses", "the wallet face rail + per-row wallet names",
                         WalletStore.shared.addresses.count, 2, true))
            rows.append(("farcaster.accounts", "Farcaster's face rail",
                         FarcasterStore.shared.accounts.count, 2, true))
            rows.append(("bluesky.accounts", "Bluesky's face rail",
                         BlueskyStore.shared.accounts.count, 2, true))
            rows.append(("nostr.accounts", "Nostr's face rail",
                         NostrStore.shared.accounts.count, 2, true))
            rows.append(("addressbook.entries", "the address book's filter field",
                         AddressBook.shared.all.count, 9, false))
            // A sparkline needs two points to be a line at all. The pulse
            // cache is IN-MEMORY (prices are perishable), so a probe-only
            // launch has not necessarily hit the foreground gate that
            // reseeds it — measuring first would report 0 and blame the seed
            // for the probe's own timing. Both reseeds are idempotent and
            // demo-gated.
            TokenPulse.shared.reseedDemoIfNeeded()
            PredictionPulse.shared.reseedDemoIfNeeded()
            let closes = TokenPulse.shared.pulses.values.map(\.closes.count).max() ?? 0
            rows.append(("token.closes", "the token sparkline", closes, 2, true))
            let series = PostHogState.all().values.map(\.series.count).max() ?? 0
            rows.append(("posthog.series", "the PostHog metric card", series, 14, true))
            // The post image GRID, as opposed to a single image.
            let images = things.map(\.imageURLs.count).max() ?? 0
            rows.append(("post.imageURLs", "PostCard's image grid", images, 2, true))
            // A vault note long enough to earn a read time.
            let words = things.filter { $0.source == "Obsidian" }
                .map { ($0.enrichedText ?? "").split(whereSeparator: \.isWhitespace).count }
                .max() ?? 0
            rows.append(("vault.words", "NoteSheet's read-time reading", words, 100, true))

            NSLog("[Casberi] floor| %d controls checked", rows.count)
            for (name, gates, got, need, required) in rows {
                let verdict = got >= need ? "ok" : (required ? "UNDER" : "under (optional)")
                NSLog("[Casberi] floor| %@ = %d (need %d) %@ — %@",
                      name, got, need, verdict, gates)
            }
        },
        Hook(key: "sheetShapeProbe") { _, context in
            let things = ((try? context.fetch(FetchDescriptor<Thing>())) ?? []).live
            var census: [String: Int] = [:]
            for thing in things {
                if let s = SocialSheetSource.shape(for: thing) {
                    census["social.\(s.rawValue)", default: 0] += 1
                }
                if let s = NoteSheetSource.shape(for: thing) {
                    census["note.\(s.rawValue)", default: 0] += 1
                }
                if let s = AgentSheetSource.shape(for: thing) {
                    census["agent.\(s.rawValue)", default: 0] += 1
                }
                if let r = PurchaseStageSource.reading(for: thing) {
                    census["purchase.\(r.archetype.rawValue)", default: 0] += 1
                }
                if !thing.facts.isEmpty {
                    census["life.facts", default: 0] += 1
                }
                // Work's anatomy is keyed by FACE, not by a shape enum — the
                // face is what changes the layout (prose, code, money, a star
                // rating), so counting readings alone would report coverage
                // while three of the four faces went undrawn. `WorkStage.Row`
                // is built inline in `ThingSheetView`, so this mirrors it —
                // exactly the drift `verify.sh`'s step has to watch.
                let workRow = WorkStage.Row(
                    source: thing.source, sourceRef: thing.sourceRef, title: thing.title,
                    tags: thing.tags, mark: thing.mark.rawValue,
                    projectField: thing.authorHandle,
                    hasPrice: thing.priceValue != nil && thing.priceCurrency != nil)
                if let reading = WorkStage.reading(workRow) {
                    census["work.\(reading.face.rawValue)", default: 0] += 1
                }
                // The money receipt (§363/§369) — nine sources, one anatomy.
                if MoneyReceiptSource.receipt(for: thing) != nil {
                    census["money.receipt", default: 0] += 1
                }
            }
            NSLog("[Casberi] sheetShape| corpus=%d anatomies=%d", things.count, census.count)
            // One NSLog per line — a joined multi-line message gets truncated
            // by the log reader (the `-todayProbe` lesson).
            for (key, n) in census.sorted(by: { $0.key < $1.key }) {
                NSLog("[Casberi] sheetShape| %@ = %d", key, n)
            }
        },
        // `-agentNoticeProbe YES` — today's deterministic notice (prd §384),
        // or the honest reasons there isn't one. Clears the day stamp first so
        // a probe run always re-observes; the once-ever ledger is NOT cleared
        // (that's the behaviour under test — a notice re-firing daily is the
        // bug this exists to catch). Logs the line, the kind key and the
        // evidence count; never a full title beyond what the line itself says.
        Hook(key: "agentNoticeProbe") { _, context in
            UserDefaults.standard.removeObject(forKey: "agent.noticed.day")
            AgentNoticed.shared.refresh(context: context)
            if let n = AgentNoticed.shared.notice {
                NSLog("[Casberi] agentNotice| line=%@", n.line)
                NSLog("[Casberi] agentNotice| key=%@ evidence=%d glint=%@",
                      n.key, n.ids.count, AgentNoticed.shared.glint ? "YES" : "NO")
            } else {
                NSLog("[Casberi] agentNotice| none (no anniversary, no cross-source tag today, no record day — or all already shown once)")
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
        // `-addressNote "<address>:<note>"` — seed a note on an entry
        // headlessly (2026-08-27, the address-book unification). Splits on
        // the FIRST colon after the address (an address contains no colon; a
        // note may) — the mirror of `-addressBook`'s LAST-colon split, which
        // exists because a NAME may carry its own colon-free structure while
        // a note is free prose. Declared before `-addressBookProbe` so the
        // seed lands before the read (hooks run in list order). No-op for an
        // address the book doesn't already hold — pair with `-addressBook`
        // or `-vibenetWatch` first.
        Hook(key: "addressNote") { spec, _ in
            guard let colon = spec.firstIndex(of: ":") else { return }
            let address = String(spec[spec.startIndex..<colon])
            let note = String(spec[spec.index(after: colon)...])
            AddressBook.shared.setNote(note, for: address)
            NSLog("Address-note probe: note=%d chars on %@",
                  note.count, AddressBook.key(for: address))
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
                // THE FILTER STRIP (prd §498) — which chips the book would
                // offer, and how many rows each holds. A chip filtering the
                // wrong population renders as an ordinary shorter list, so
                // this is the only place the two can be compared; and an
                // ABSENT chip has two causes that look identical from the
                // screen (no members, or a `matches` arm that stopped taking
                // a kind), which the per-chip count separates.
                let bookKinds = AddressBook.shared.all.map(\.kind.rawValue)
                let offered = AddressBookShape.availableFilters(kinds: bookKinds)
                NSLog("Address-book probe: chips=%@",
                      offered.map { filter in
                          let n = bookKinds.filter { filter.matches(kind: $0) }.count
                          return "\(filter.rawValue)(\(n))"
                      }.joined(separator: ", "))
                for entry in AddressBook.shared.all {
                    // networks/note appended 2026-08-27 (the address-book
                    // unification) — a landed count alone can't separate "no
                    // vibenet tag ever reached this row" from "the read never
                    // ran", and note LENGTH (never the text — same caution
                    // `-secretScanProbe` takes) proves the field round-trips
                    // without printing anyone's private words to a log.
                    NSLog("  %@ · %@ · kind=%@%@%@%@%@%@%@", entry.name, entry.short,
                          entry.kind.rawValue,
                          watched.contains(entry.id) ? " · WATCHED" : "",
                          entry.provenance.map { " · from \($0)" } ?? "",
                          entry.groupNames.isEmpty ? ""
                            : " · in \(entry.groupNames.joined(separator: "/"))",
                          (entry.networks ?? []).isEmpty ? ""
                            : " · networks=\((entry.networks ?? []).joined(separator: "/"))",
                          entry.note.map { " · note=\($0.count)chars" } ?? "",
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
                // The doc's SHAPE, never a phrase in it (fixed 2026-08-22).
                // This asked whether line 0 contained "Across your wallets" —
                // a title the combined branch has not used since 2026-07-21,
                // when it was changed to "What you hold" precisely because the
                // balance headline already owned that phrase. So the one check
                // this probe exists to make ("did the crown feature actually
                // MERGE, or is this the first wallet's map wearing a new
                // title") has reported `per-wallet` for every combined read
                // for a month, and now that the title is empty entirely it
                // could never be right again. The shape is exact and carries
                // no copy: the combined branch emits ONE line (`root =
                // TagMap`), the per-wallet branch always emits a `root =
                // Stack` plus one `TagMap` per group, so it is two lines even
                // for a single wallet.
                let combined = read.doc.count == 1
                NSLog("Portfolio probe: scope=%@ total=%@ tokens=%d wallets=%d map=%@",
                      scope ?? "ALL", TokenStats.compact(p.totalUSD), p.tokenCount,
                      p.walletCount, combined ? "COMBINED" : "per-wallet")
                // The card's whole tail, and its halves apart — `shapeLine` is
                // what the row DRAWS, but a nil there has two causes (an
                // unpriced/single-position book, no stables above the floor)
                // and only the pair separates them.
                NSLog("Portfolio probe: shape=%@ (concentration=%@ stables=%@)",
                      p.shapeLine ?? "—", p.concentrationShort ?? "—",
                      p.stableShort ?? "—")
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
        // `-receiptProbe "<title prefix>"` — the money receipt a thing sheet
        // would draw (prd §369), line by line, plus what the app would say
        // about it. Keyed on a title prefix for the `-openThing` reason: a UUID
        // changes every install, a title doesn't.
        //
        // One NSLog per line (the `-todayProbe` truncation lesson), and it
        // exists because a PLAIN-looking receipt has six causes and only two are
        // bugs — see `MoneyReceiptSource.probeLines`. The `stamped …` line is
        // the decisive one: a receipt leading with its title rather than a
        // figure is correct when the bridge stamped no amount, and a defect when
        // it did.
        Hook(key: "receiptProbe") { prefix, context in
            Task { @MainActor in
                var descriptor = FetchDescriptor<Thing>(
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
                descriptor.fetchLimit = 500
                let all = (try? context.fetch(descriptor)) ?? []
                guard let subject = all.first(where: {
                    $0.isLive && $0.title.lowercased().hasPrefix(prefix.lowercased())
                }) else {
                    NSLog("receiptProbe: no thing whose title starts with %@", prefix)
                    return
                }
                for line in MoneyReceiptSource.probeLines(for: subject, in: context) {
                    NSLog("[Casberi] %@", line)
                }
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
                // The whole census, one line per scheme (2026-08-14). Added
                // with the Calendar 2.1(a) fix: a gated verb that VANISHES and
                // a gated verb that never existed look identical from outside,
                // so the only way to tell "correctly dropped on Mac" from
                // "accidentally dropped on iOS" is to read what each platform
                // actually claims. `claimed` is ground truth; `inSet` is what
                // the verbs are gated on, and a disagreement means the scheme
                // is missing from LSApplicationQueriesSchemes.
                // POLLED, not read once: `refresh()` runs off the scenePhase
                // activation, which lands WELL after the 2s above — measured
                // on a cold sim launch, where a single read reported every
                // scheme `inSet=NO` including `photos-redirect`, which is
                // correctly declared and correctly claimed. A census that
                // always says NO is a broken instrument, so this waits for
                // the set to populate and says so if it never does.
                var populated = false
                for _ in 0..<20 {
                    if !HandOffState.installedSchemes.isEmpty { populated = true; break }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if !populated {
                    NSLog("[Casberi] handoffScheme| set still EMPTY after 10s — refresh() never ran")
                }
                for scheme in HandOffState.probeCandidates {
                    let ok = URL(string: "\(scheme)://").map {
                        UIApplication.shared.canOpenURL($0)
                    } ?? false
                    NSLog("[Casberi] handoffScheme| %@ claimed=%@ inSet=%@",
                          scheme, ok ? "YES" : "NO",
                          HandOffState.installedSchemes.contains(scheme) ? "YES" : "NO")
                }
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
        // `-filesRevealProbe YES|"<title prefix>"` — the folder door on a
        // folder-picked file (2026-08-19, prd §408): what the sheet's "From"
        // row SAYS, and where pressing it would land.
        //
        // Bare `YES` takes the newest Files thing; a prefix picks one by title
        // (`-openThing`'s rule — a UUID changes every install, a title
        // doesn't). One NSLog per fact rather than a joined line (the
        // `-todayProbe` truncation lesson).
        //
        // IT EXISTS BECAUSE THE URL IS UNMEASURED. iOS publishes no public API
        // that reveals a file, so this rides the Files app's own
        // `shareddocuments://` scheme — and a wrong PATH and an unclaimed
        // SCHEME both end the same way from outside (the person lands
        // somewhere that isn't their folder), while only one of them is
        // fixable here. `claimed` is ground truth, `inSet` is what the verb is
        // gated on, and `url` is the exact string handed to LaunchServices, so
        // one launch separates all three. A missing door has four causes and
        // three are healthy: no folder connected, the bookmark stopped
        // resolving, the row belongs to another bridge (Dropbox lands `.file`
        // rows whose bytes are not on this device), or the scheme is
        // unclaimed — which on Mac Catalyst is the correct answer.
        //
        // Delayed for `HandOffState`'s reason: the set it reads is written by
        // the first foreground pass, which has not run when `runAll` fires.
        Hook(key: "filesRevealProbe") { spec, context in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                let scheme = FilesLocation.revealScheme
                let claimed = URL(string: "\(scheme)://").map {
                    UIApplication.shared.canOpenURL($0)
                } ?? false
                NSLog("[Casberi] filesReveal| scheme=%@ claimed=%@ inSet=%@",
                      scheme, claimed ? "YES" : "NO",
                      HandOffState.installedSchemes.contains(scheme) ? "YES" : "NO")
                NSLog("[Casberi] filesReveal| connected=%@ folderName=%@ resolves=%@",
                      FilesStore.shared.connected ? "YES" : "NO",
                      FilesStore.shared.folderName.isEmpty ? "(none)" : FilesStore.shared.folderName,
                      FilesStore.shared.folderURL()?.path ?? "(unresolvable)")
                var descriptor = FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.source == "Files" },
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
                descriptor.fetchLimit = 300
                let files = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
                let prefix = (spec == "YES" || spec.isEmpty) ? "" : spec.lowercased()
                let rows = prefix.isEmpty
                    ? Array(files.prefix(5))
                    : files.filter { $0.title.lowercased().hasPrefix(prefix) }
                guard !rows.isEmpty else {
                    NSLog("[Casberi] filesReveal| no Files thing%@ in the corpus",
                          prefix.isEmpty ? "" : " whose title starts with \(spec)")
                    return
                }
                for thing in rows {
                    NSLog("[Casberi] filesRow| %@ · ref=%@", thing.title,
                          thing.sourceRef ?? "(none)")
                    NSLog("[Casberi] filesRow|   from=\"%@\" · url=%@",
                          PlaceWords.line(for: thing),
                          FilesIngest.revealURL(for: thing.sourceRef)?.absoluteString ?? "(none)")
                    let discs = VerbDerivation.verbs(for: thing)
                        .map { VerbDial.dialLabel(for: $0) }.joined(separator: ", ")
                    NSLog("[Casberi] filesRow|   discs=%@", discs.isEmpty ? "(none)" : discs)
                }
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
                note("walletbeatHead", source == WalletbeatRoomSource.source
                     ? WalletbeatRoomSource.compose(things: things).map {
                        "\(WalletbeatRoom.headline($0)) · \($0.items.count) wallets"
                     } : nil)
                note("l2beatHead", source == L2beatRoomSource.source
                     ? L2beatRoomSource.compose(things: things).map {
                        "\(L2beatRoom.headline($0)) · \($0.items.count) chains"
                     } : nil)
                note("cardPointersHead", source == CardPointersRoomSource.source
                     ? CardPointersRoomSource.compose(things: things).map {
                        "\($0.headline) · \($0.deadlines.count) deadlines"
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
                // The two CODE heads (prd §401). `githubHead` reads `things`
                // like `cursorHead` above — the notifications ARE the subject.
                // `radicleHead` reads NONE and is the only line in this block
                // that doesn't: its subject is bridge state, since no landed
                // row can say a patch is still unresolved (`ASCRoomSource`'s
                // situation, and the `appStoreConnect` line's).
                note("githubHead", source == GitHubRoomSource.source
                     ? GitHubRoomSource.compose(things: things).map {
                        "\($0.headline) · \($0.items.count) waiting"
                     } : nil)
                note("radicleHead", source == RadicleRoomSource.source
                     ? RadicleRoomSource.compose(things: things).map {
                        "\($0.items.count) open · \($0.repos) repos · \($0.drafts) drafts"
                     } : nil)
                // The three wallet-riding heads (2026-08-10, prd §349). Like
                // `cursorHead` these read `things` — the fills, the deposits
                // and the spends ARE the subject — so each `compose` would
                // already answer nil for another room's rows on its own. Gated
                // anyway, so every line in this block reads the same way.
                note("peerHead", source == PeerRoomSource.source
                     ? PeerRoomSource.compose(things: things).map {
                        "\(PeerRoom.headline($0)) · \($0.rails.count) rails"
                     } : nil)
                note("privacyPoolsHead", source == PrivacyPoolsRoomSource.source
                     ? PrivacyPoolsRoomSource.compose(things: things).map {
                        "\(PrivacyPoolsRoom.headline($0)) · \($0.deposits) deposits"
                     } : nil)
                note("gnosisPayHead", source == GnosisPayRoomSource.source
                     ? GnosisPayRoomSource.compose(things: things).map {
                        "\(GnosisPayRoom.headline($0)) · \($0.currencies.count) currencies"
                     } : nil)
                // The fourth wallet-riding head (2026-08-11).
                note("railgunHead", source == RailgunRoomSource.source
                     ? RailgunRoomSource.compose(things: things).map {
                        "\(RailgunRoom.headline($0)) · \($0.tokens.count) tokens"
                     } : nil)
                // The fifth (2026-08-11). The three counts are printed apart
                // because they are three different states that render as one
                // number in `pendingCount` alone: a fully-signed transaction
                // needs an execution, not a signature, and a contested pair
                // needs neither from whoever loses.
                note("safeHead", source == SafeRoomSource.source
                     ? SafeRoomSource.compose(things: things).map {
                        "\(SafeRoom.headline($0)) · \($0.pendingCount) pending"
                        + " · \($0.awaitsYouCount) awaiting you · \($0.readyCount) ready"
                        + " · \($0.contestedCount) contested"
                     } : nil)
                // Three more per-source heads that shipped without a line
                // here — exactly the drift this probe's own header warns
                // against, and exactly how it was found (2026-08-10): a
                // `-roomInsightProbe` sweep across every `SourceHead` case
                // reported "leads with NOTHING" for all three, which read as
                // three demo gaps until this probe's own card list turned
                // out to be the thing that had drifted, not the demo.
                note("appleWallet", source == AppleWalletBridge.sourceName
                     ? AppleWalletRoomSource.compose(things: things).map {
                        "\($0.headline) · \($0.merchants.count) merchants"
                     } : nil)
                note("x402", source == X402Ingest.source
                     ? X402RoomSource.compose(things: things).map {
                        "\(X402Room.headline($0)) · \($0.sellers) sellers"
                     } : nil)
                note("appStoreConnect", source == ASCShape.source
                     ? ASCRoomSource.compose(things: things).map {
                        "\(ASCRoom.headline($0)) · \($0.apps.count) apps"
                     } : nil)
                // The thirteenth (2026-08-13, prd §375) — and the first over an
                // IMPORT rather than a bridge, which is also the first that can
                // DISPLACE a card below it: when this composes it takes the
                // slot `topicMap` held for this room. Both lines print either
                // way, so the trade is visible here rather than inferred.
                note("xHead", source == XRoomSource.source
                     ? XRoomSource.compose(things: things).map {
                        "\(XRoom.note($0)) · \($0.span) years · \($0.silent) silent"
                     } : nil)
                // The fourteenth (2026-08-18, prd §395) — the second over an
                // import, and the second that displaces a card below it: when
                // this composes it takes the slot `leaderboard` held for this
                // room. Both lines print either way, so the trade is visible
                // here rather than inferred.
                note("instagramHead", source == InstagramRoomSource.source
                     ? InstagramRoomSource.compose(things: things).map {
                        "\(InstagramRoom.headline($0)) · \($0.accounts.count) rows · \($0.gone) gone"
                     } : nil)
                // The journal rooms (2026-08-17, prd §398) — one composer
                // serving TWO rooms, and the only line in this list with two
                // names.
                //
                // That is deliberate, not drift: `verify.sh`'s room-head
                // coverage is a zsh associative array keyed by the name printed
                // here, so a single shared label could only ever assert that ONE
                // of the two journals composes. They have separate corpora and
                // separate demo seeds, which is exactly the gap that check
                // exists to catch — the §349 finding, where three rooms' heads
                // were each broken in a different way and every one of them
                // rendered as the same silent nothing.
                let journalLabel = source == "Apple Journal" ? "appleJournalHead" : "dayOneHead"
                note(journalLabel, JournalRoomSource.sources.contains(source)
                     ? JournalRoomSource.compose(things: things).map {
                        "\(JournalRoom.headline($0) ?? JournalRoom.note($0))"
                        + " · \($0.span) years · \($0.silent) silent"
                        + " · \($0.days) days · streak \($0.streak)"
                     } : nil)
                // The four AGENT rooms (2026-08-23, prd §457) — one composer
                // serving FOUR rooms, and so the second entry here with more
                // than one name, for `journalLabel`'s reason exactly: the
                // coverage check is keyed by the name printed here, so one
                // shared label would assert that ONE of the four composes
                // while three sat broken behind it. They have four separate
                // corpora and four separate demo seats.
                let agentLabel = ["ChatGPT": "chatgptHead", "Claude": "claudeHead",
                                  "Gemini": "geminiHead",
                                  ClaudeCodeImport.source: "claudeCodeHead"][source]
                note(agentLabel ?? "agentHead", agentLabel == nil ? nil
                     : AgentRoomSource.compose(
                        source: source, things: things,
                        rivals: AgentRoomSource.rivals(besides: source, context: context)).map {
                        "\(AgentRoom.headline($0) ?? AgentRoom.note($0))"
                        + " · \($0.span) months · \($0.silent) silent"
                        + " · \($0.total) conversations · \($0.turns) turns"
                        + " · rivals \($0.rivals.count)"
                     })
                // 2. the anniversary — the memories room's pictures, and (since
                // §398) the two journals' entries. It OUTRANKS every head above
                // in `shapedSections`, so it is printed after them and the
                // `leader` below still names the right winner only because
                // every head above answers nil for these three rooms.
                let echo = source == "Snapchat"
                    ? OnThisDay.find(in: things.filter {
                        $0.kind == .file && $0.previewImageData != nil })
                    : JournalRoomSource.sources.contains(source)
                        ? OnThisDay.find(in: things.filter {
                            $0.kind == .note && !Corpus.isImportReceipt($0) })
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
        // `-ghWatchPerson "<username|@username|profile URL>"` — watch a GitHub
        // person headlessly (prd §519). Declared BEFORE `-ghPeopleProbe`:
        // hooks run in list order, so one launch can watch somebody and then
        // report the pass that reads them. NSLogs the PARSE separately from
        // the LOOKUP, because they fail for opposite reasons — a refused parse
        // means the string was a repo URL or an impossible login (nothing was
        // requested), a failed lookup means GitHub said no such account.
        Hook(key: "ghWatchPerson") { spec, context in
            let q = spec.trimmingCharacters(in: .whitespaces)
            guard let parsed = GitHubLinks.personLogin(from: q) else {
                NSLog("ghWatchPerson: %@ → REFUSED by the parse (a repo URL, a foreign host, or not a login)", q)
                return
            }
            NSLog("ghWatchPerson: %@ → login=%@", q, parsed)
            guard let token = TokenVault.get(TokenBridge.github.tokenKey) else {
                NSLog("ghWatchPerson: no stored token — connect via -tokenBridge \"GitHub:<token>\""); return
            }
            Task { @MainActor in
                guard let resolved = await GitHubPersonWatch.resolve(q, token: token) else {
                    NSLog("ghWatchPerson: %@ → GitHub has no such account (or the token was refused)", parsed)
                    return
                }
                guard let thing = GitHubPersonWatch.add(resolved, context: context) else {
                    NSLog("ghWatchPerson: %@ → already watched", resolved.login); return
                }
                NSLog("ghWatchPerson: watching %@ (login=%@ face=%@) → %@",
                      thing.title, resolved.login,
                      resolved.avatarURL == nil ? "none" : "yes",
                      GitHubLinks.personRef(resolved.login))
            }
        },
        // `-ghPeopleProbe YES` — the watched-people activity pass, phase by
        // phase (prd §519). One NSLog per person (the `-todayProbe`
        // truncation lesson).
        //
        // It exists because `0 landed` is the HEALTHY answer here and has FIVE
        // causes that render as one silence: nobody watched, no token, the
        // only person watched is YOU with the contributions feed already
        // reading you (so this pass correctly reads nothing), a genuinely
        // quiet account, or GitHub refusing the events endpoint. Only the last
        // is a bug. The `fetching=` line is what separates the third from the
        // rest in a single launch.
        Hook(key: "ghPeopleProbe") { _, context in
            Task { @MainActor in
                let watched = GitHubPersonWatch.watchedPeople(context: context)
                let feeds = GitHubFeeds.enabledFromDefaults()
                NSLog("ghPeople| watched=%d [%@] contributionsFeed=%@",
                      watched.count, watched.joined(separator: ", "),
                      feeds.contains(.contributions) ? "on" : "off")
                guard let token = TokenVault.get(TokenBridge.github.tokenKey) else {
                    NSLog("ghPeople| no stored token — connect via -tokenBridge \"GitHub:<token>\""); return
                }
                guard let identity = await GitHubFeedFetch.login(token: token) else {
                    NSLog("ghPeople| token REFUSED by GitHub — nothing can be read"); return
                }
                let fetching = GitHubLinks.activityLogins(
                    watched: watched, ownLogin: identity.login,
                    contributionsOn: feeds.contains(.contributions))
                NSLog("ghPeople| you=%@ fetching=%d [%@]%@",
                      identity.login, fetching.count, fetching.joined(separator: ", "),
                      fetching.count < watched.count
                        ? " (your own account is already read by the contributions feed)" : "")
                for login in fetching {
                    let rows = await GitHubFeedFetch.eventsProbe(login: login, token: token)
                    NSLog("ghPersonRow| %@ → %@", login,
                          rows.map { "\($0.count) events, newest: \($0.first ?? "—")" }
                            ?? "UNREADABLE (GitHub refused /users/\(login)/events)")
                }
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
        // `-demoCorpusClear YES` — remove the BASE dev corpus (`DemoCorpus`),
        // the half `-demoSeed clear` cannot reach. Those rows carry no
        // `sourceRef`, so no prefix sweep can find them, and until `clear()`
        // existed there was no way to take them back out of an install that
        // had ever run a DEBUG build. It also switches `demo.corpusAllowed`
        // off, or the next DEBUG launch re-seeds what this just removed and
        // the whole exercise reads as having done nothing.
        // `-devReset YES` — put a dev-polluted install back to what a real
        // release install looks like: no seeded seats, and none of the rows a
        // seeded seat caused to be ingested.
        //
        // It exists because clearing the CORPUS is not enough on its own.
        // `BridgeStore.init` falls back to `BridgeApp.demo` whenever
        // `DemoState.seedsDemoData` is true, and that init runs BEFORE any
        // hook — so a DEBUG launch that clears rows still comes up with every
        // seat "connected", and any seat with a real device source behind it
        // (Contacts, Photos, Calendar, Reminders) then ingests the person's
        // ACTUAL data on the first foreground sweep. Measured: one such launch
        // landed 23 real contacts nobody asked for.
        //
        // So this switches the seeding flag off FIRST — a later launch cannot
        // re-seed — then empties the seat list and removes the rows those
        // phantom seats pulled in. Rows are matched by their own ref prefixes,
        // never by source name alone, so a row that arrived legitimately from
        // another device keeps its place.
        Hook(key: "devReset") { _, context in
            Task { @MainActor in
                UserDefaults.standard.set(false, forKey: "demo.corpusAllowed")
                let removedCorpus = DemoCorpus.clear(context)
                let prefixes = ["contact:", "homekit:"]
                var pulled = 0
                if let all = try? context.fetch(FetchDescriptor<Thing>()) {
                    for thing in all where thing.isLive {
                        guard let ref = thing.sourceRef,
                              prefixes.contains(where: { ref.hasPrefix($0) }) else { continue }
                        context.delete(thing)
                        pulled += 1
                    }
                    context.saveHonestly()
                }
                let left = (try? context.fetchCount(FetchDescriptor<Thing>())) ?? 0
                NSLog("[Casberi] devReset: corpus=%d ingested=%d left=%d",
                      removedCorpus, pulled, left)
            }
        },
        Hook(key: "demoCorpusClear") { _, context in
            Task { @MainActor in
                let gone = DemoCorpus.clear(context)
                UserDefaults.standard.set(false, forKey: "demo.corpusAllowed")
                let left = (try? context.fetchCount(FetchDescriptor<Thing>())) ?? 0
                NSLog("[Casberi] demoCorpusClear: removed %d, %d things left", gone, left)
            }
        },
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
        //
        // Reports the address's own VERDICT beside the count (2026-08-16):
        // "0 new things" has always had two very different causes, and a
        // pasted page that publishes no feed at all is one of them — the case
        // this probe would most likely be run to check.
        Hook(key: "rssFeed") { url, context in
            let followed = RSSStore.shared.normalized(url)
            RSSStore.shared.add(url)
            Task { @MainActor in
                // `waitForInFlight`, or a launch whose foreground sweep is
                // still going reports 0 for a feed it never read.
                let n = await RSSIngest.refresh(context: context, waitForInFlight: true)
                let verdict = followed.map { FeedFreshness.noFeedFound(at: $0) ? "NO FEED AT THAT ADDRESS" : "is a feed" }
                NSLog("RSS probe: %@ new things | %@", n.map(String.init) ?? "FAILED",
                      verdict ?? "not a web address")
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
            // `noFeed` is the column a status code cannot explain (2026-08-16):
            // a soft-404 site answers 200 with zero failures forever, so it is
            // indistinguishable here from a healthy feed that is merely quiet.
            NSLog("feedHealthProbe: %d feeds tracked | %d conditional | %d failing | %d with no feed",
                  census.count, census.filter(\.conditional).count,
                  census.filter { $0.failures > 0 }.count,
                  census.filter(\.noFeed).count)
            for row in census.prefix(60) {
                let ago = row.successAt.map { Int(-$0.timeIntervalSinceNow / 3600) }
                NSLog("feedHealth| %@ | lastOK=%@ | fails=%d | status=%d | cond=%@ | noFeed=%@ | says=%@",
                      row.url,
                      ago.map { "\($0)h ago" } ?? "never",
                      row.failures, row.lastStatus,
                      row.conditional ? "YES" : "NO",
                      row.noFeed ? "YES" : "NO",
                      FeedFreshness.trouble(for: row.url) ?? "-")
            }
            // What each READING ROOM would say about its own feeds (prd §455,
            // 2026-08-23) — the line the room draws, above its head.
            //
            // Reported per room rather than left to be inferred from the
            // census above, because the two answer different questions and can
            // legitimately disagree: the census is keyed by URL and knows
            // nothing about who follows what, so a failing record belonging to
            // an UNFOLLOWED feed (a record outlives a removal only until
            // `forget` runs) shows there and must never reach a room. The
            // other direction is the one worth watching for: a follow whose
            // feed URL was never resolved is deliberately excluded (see
            // `FeedRoomHealth`'s stated ceiling), so `feeds=3 quiet=0` beside a
            // census full of failures is CORRECT and not a bug.
            for room in ["RSS", "Substack", "Reddit", "YouTube", "Podcasts"] {
                let feeds = FeedRoomHealthSource.feeds(for: room)
                let standing = FeedRoomHealthSource.standing(for: room)
                NSLog("feedRoomHealth| %@ | feeds=%d | resolved=%d | quiet=%d | says=%@",
                      room, feeds.count,
                      feeds.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
                      standing?.quiet.count ?? 0,
                      standing?.line ?? "(nothing to say)")
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
        // `WalletDemoState` behind the `viz.demo` UserDefaults flag, which
        // stays DEBUG-only (no shipping build can set it) — but the STRUCT
        // itself is no longer `#if DEBUG` (2026-08-11), because the furnished
        // demo (`DemoMode.isActive`) reads the same synthetic books in
        // Release, where it ships. Every thing this hook lands carries a
        // `vizdemo:` ref so `-seedVizDemo clear` can take exactly its own
        // rows back out without touching a real corpus.
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
        // `-quickActionProbe YES` — the "Daily Brief" quick action's LANDING,
        // without a long press (2026-08-14). Fires `QuickAction.receive` after
        // the launch activation has already drained everything, so the only
        // door left is the warm one: the `QuickAction.received` observer on
        // `RootShell`'s body. A pass logs `quickAction:` then `briefRequest:`
        // and the agent rises on the brief.
        //
        // **A green probe is NOT evidence the quick action works.** It
        // exercises the half that lives in this process; the half it cannot
        // reach is UIKit's delivery into `SceneDelegate`, and that delivery is
        // exactly where this feature was broken from the day it shipped
        // (2026-08-03) until 2026-08-14 — an app-delegate callback a
        // scene-based app never calls. No simulator gesture can long-press a
        // Home Screen icon, so that half is verifiable on a device and nowhere
        // else. The probe's value is that it makes the OTHER half provable, so
        // a future report can be narrowed to one side in a single launch.
        Hook(key: "quickActionProbe") { _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                QuickAction.receive(UIApplicationShortcutItem(
                    type: QuickAction.dailyBrief, localizedTitle: "Daily Brief"))
            }
        },
        // `-vibenetWatch "<0xaddr[,0xaddr]>"` — watch vibenet devnet
        // addresses headlessly. No resolution needed (there's no name
        // registrar on vibenet) — a plain `0x` hex address is added
        // directly, or reported invalid.
        // `-hegotaWatch "<0xaddr[,0xaddr]>"` — watch Hegotá addresses
        // headlessly. Declared BEFORE the probes: hooks run in list order and
        // a probe must see a watch list that already exists.
        Hook(key: "hegotaWatch") { value, _ in
            var watched: [String] = []
            var rejected: [String] = []
            for raw in value.split(separator: ",") {
                let address = raw.trimmingCharacters(in: .whitespaces)
                guard !address.isEmpty else { continue }
                if HegotaWatch.shared.add(address) { watched.append(address) }
                else { rejected.append(address) }
            }
            NSLog("[Casberi] hegotaWatch| added=%@ invalidOrDuplicate=%@ watching=%d",
                  watched.joined(separator: ",").isEmpty ? "-" : watched.joined(separator: ","),
                  rejected.joined(separator: ",").isEmpty ? "-" : rejected.joined(separator: ","),
                  HegotaWatch.shared.addresses.count)
        },
        // `-hegotaProbe YES` — the whole read, phase by phase, then ONE LINE
        // PER ACCOUNT and one per scope (the `-todayProbe` truncation lesson:
        // a joined multi-line NSLog gets cut by the log reader).
        //
        // It exists because a blank Hegotá room has SIX causes that render as
        // one silence and only two are bugs: nothing watched, no host answered,
        // the address is genuinely one of the 150-odd on this chain that only
        // ever received a transfer, the coin logs read but a spent bit did not
        // (so the set was refused), the whole-chain set did not reconcile, or a
        // parse drifted. The `reached=` / `reconciled=` / `coins=` triple is
        // what separates them in a single launch.
        Hook(key: "hegotaProbe") { _, _ in
            Task { @MainActor in
                let watched = HegotaWatch.shared.addresses
                NSLog("[Casberi] hegota| watching=%d", watched.count)
                guard !watched.isEmpty else {
                    NSLog("[Casberi] hegota| nothing watched — pass -hegotaWatch first")
                    return
                }
                await HegotaLiveState.shared.refresh()
                let accounts = HegotaLiveState.shared.accounts
                // **IS IT STILL THE SAME CHAIN?** First, because it governs how
                // everything below reads: on a relaunched devnet every account
                // answers perfectly and with nothing, and `reached=YES
                // balance=0 moves=0` is otherwise indistinguishable from an
                // address that never did anything.
                NSLog("[Casberi] hegotaChain| genesis=%@",
                      HegotaLiveState.shared.genesis.rawValue)
                for a in accounts {
                    NSLog("[Casberi] hegotaAccount| %@ reached=%@ balance=%@ moves=%d coins=%d unspent=%@ reconciled=%@ lanes=%d sponsored=%d",
                          a.address,
                          a.reached ? "YES" : "NO",
                          a.balanceWei.map { "\(HegotaCoins.eth($0))" } ?? "unread",
                          a.moves.count,
                          a.coins.count,
                          a.unspent.map { "\($0.count)" } ?? "REFUSED",
                          a.reconciled ? "YES" : "NO",
                          a.lanes.count,
                          a.sponsored.count)
                    // The chain's own send counter beside the moves we can see.
                    // A `valueless=` above zero is the Frames scope's whole
                    // premise made concrete: sends that verified, checked or
                    // called and paid nobody, which no transfer log can show.
                    NSLog("[Casberi] hegotaNonce| %@ chainCount=%@ valueless=%@",
                          a.address,
                          a.nonceCount.map { "\($0)" } ?? "unread",
                          a.valuelessSends.map { "\($0)" } ?? "-")
                    // The census the reconciliation already proved and used to
                    // throw away. `share=` is our slice of the WHOLE vault, so
                    // a share of 100% on a chain with several owners is the
                    // shape of a mis-scoped denominator.
                    if let c = a.census {
                        NSLog("[Casberi] hegotaCensus| %@ chainCoins=%d owners=%d vault=%@ mine=%d share=%@ sole=%@",
                              a.address, c.coins, c.owners,
                              "\(HegotaCoins.eth(c.wei))", c.mineCoins,
                              c.share.map { String(format: "%.4f", $0) } ?? "undefined",
                              c.soleOwner ? "YES" : "NO")
                    }
                    for lane in a.lanes {
                        NSLog("[Casberi] hegotaLane| %@ key=%@ seq=%@ sends=%d",
                              a.address, lane.key, lane.seq ?? "-", lane.sends)
                    }
                    for coin in (a.unspent ?? []) {
                        NSLog("[Casberi] hegotaCoin| %@ index=%llu value=%@ change=%@ source=%@",
                              a.address, coin.index, "\(HegotaCoins.eth(coin.wei))",
                              coin.isChange ? "YES" : "NO", coin.source)
                    }
                    for move in a.moves.prefix(HegotaRPC.frameDepth) {
                        NSLog("[Casberi] hegotaMove| %@ %@ %@ frames=%@ payer=%@ sponsored=%@",
                              move.incoming ? "in" : "out",
                              WalletStore.shortAddress(move.counterparty),
                              "\(HegotaCoins.eth(move.wei))",
                              move.frames.map { f in f.map(\.mode.rawValue).joined(separator: ">") } ?? "-",
                              move.payer ?? "-",
                              move.isSponsored ? "YES" : "NO")
                    }
                }
                if let head = HegotaRoom.head(accounts) {
                    NSLog("[Casberi] hegotaHead| lead=%@ reached=%d/%d coins=%d lanes=%d sponsored=%d moves=%d",
                          head.lead.rawValue, head.reached, head.watched,
                          head.coinCount, head.laneCount, head.sponsoredCount, head.moveCount)
                }
                // The frame anatomy across everything whose receipt was read —
                // the Frames scope's own figure, and the only place its
                // ranking is observable without a screenshot.
                if let mix = HegotaFrameMix.of(accounts.flatMap(\.moves)) {
                    NSLog("[Casberi] hegotaFrames| transactions=%d steps=%d failed=%d unknown=%d mix=%@",
                          mix.transactions, mix.total, mix.failed, mix.unknown,
                          mix.slices.map { "\($0.mode.rawValue):\($0.count)" }
                              .joined(separator: ","))
                    // **`leaders` is what the CAPTION reads and `slices` is
                    // what the drawing reads** (prd §510), and they answer
                    // differently on a tie — which is the one caption failure
                    // a screenshot cannot be read for, because "mostly Send
                    // steps" over a 7–7 split looks exactly like a real
                    // superlative until you count the legend beneath it.
                    // Logged apart from `mix=` for that reason.
                    NSLog("[Casberi] hegotaFramesLead| commonest=%@ leaders=%@",
                          mix.hasCommonest ? "YES" : "NO",
                          mix.leaders.map { "\($0.mode.rawValue):\($0.count)" }
                              .joined(separator: ","))
                }
                NSLog("[Casberi] hegotaScopes| %@",
                      HegotaRoom.sections(accounts).map(\.rawValue).joined(separator: ","))
            }
        },
        Hook(key: "vibenetWatch") { value, _ in
            var watched: [String] = []
            var rejected: [String] = []
            for raw in value.split(separator: ",") {
                let address = raw.trimmingCharacters(in: .whitespaces)
                guard !address.isEmpty else { continue }
                if VibenetWatch.shared.add(address) { watched.append(address) }
                else { rejected.append(address) }
            }
            NSLog("[Casberi] vibenetWatch| added=%@ invalidOrDuplicate=%@ watching=%d",
                  watched.joined(separator: ",").isEmpty ? "-" : watched.joined(separator: ","),
                  rejected.joined(separator: ",").isEmpty ? "-" : rejected.joined(separator: ","),
                  VibenetWatch.shared.addresses.count)
        },
        // `-vibenetProbe YES` — the whole read, phase by phase (config fetch
        // → per address: established? → the actor-discovery log read → each
        // surviving actor's live config → lock status). One NSLog per fact,
        // the `-todayProbe` truncation lesson — an empty room here has FIVE
        // causes that render as one silence (nothing watched, the config
        // fetch unreachable, an account genuinely not established, an
        // account established with no live actors, a flaky devnet RPC) and
        // only the last is a bug this probe is meant to catch.
        Hook(key: "vibenetProbe") { _, _ in
            Task { @MainActor in
                guard let contracts = await VibenetConfig.current() else {
                    NSLog("[Casberi] vibenet| config UNREACHABLE — api.vibes.base.org didn't answer")
                    return
                }
                NSLog("[Casberi] vibenet| config branch=%@ commit=%@ keystore=%@",
                      contracts.branch ?? "?", contracts.commit ?? "?", contracts.keystore)
                // WHICH CHAIN THIS IS (prd §515a) — printed BEFORE any account,
                // because on 2026-08-29 every line below it was a true report
                // about a chain that had been wiped the night before, and
                // nothing on any screen said so.
                let liveChain = await VibenetChain.chainIdentifier()
                let verdict = await VibenetSeenChain.check()
                NSLog("[Casberi] vibenet| chain id=%@ tip=%@ verdict=%@",
                      liveChain.map(String.init) ?? "UNREACHABLE",
                      (await VibenetChain.cachedTip()).map(String.init) ?? "UNREACHABLE",
                      VibenetSeenChain.describe(verdict))
                let addresses = VibenetWatch.shared.addresses
                guard !addresses.isEmpty else {
                    NSLog("[Casberi] vibenet| watch EMPTY — nothing to read")
                    return
                }
                for address in addresses {
                    // The gate, as shipped: `eth_getCode`, never a Keystore
                    // view method (prd §515a).
                    guard let code = await VibenetChain.getCode(address: address) else {
                        NSLog("[Casberi] vibenet| %@ deployed=UNREACHABLE — the node did not answer eth_getCode", address)
                        continue
                    }
                    let established = VibenetDeployment.isDeployed(code: code)
                    NSLog("[Casberi] vibenet| %@ deployed=%@ shape=%@", address,
                          established ? "YES" : "no",
                          VibenetDeployment.isDelegation(code: code)
                              ? "7702→" + (VibenetDeployment.delegate(code: code) ?? "?")
                              : (established ? "contract" : "counterfactual"))

                    guard let ids = await VibenetRead.actorIDs(account: address, keystore: contracts.keystore)
                    else {
                        NSLog("[Casberi] vibenet| %@ actorLog=UNREACHABLE", address)
                        continue
                    }
                    NSLog("[Casberi] vibenet| %@ actorLog=%d surviving id(s)", address, ids.count)
                    let known = contracts.knownAuthenticators
                    for id in ids {
                        if let actor = await VibenetRead.actor(account: address, keystore: contracts.keystore,
                                                               actorId: id, known: known) {
                            NSLog("[Casberi] vibenet| %@ actor %@ kind=%@ scope=%@ expiry=%llu",
                                  address, String(id.prefix(10)), actor.kind.label,
                                  actor.scope.summary, actor.expiry)
                        } else {
                            NSLog("[Casberi] vibenet| %@ actor %@ CONFIRM-FAILED (revoked, or unreachable)",
                                  address, String(id.prefix(10)))
                        }
                    }

                    guard let lockRaw = await VibenetChain.ethCall(
                        to: contracts.keystore, data: VibenetABI.lockStatusCall(address))
                    else {
                        NSLog("[Casberi] vibenet| %@ lockStatus=UNREACHABLE", address)
                        continue
                    }
                    let locked = VibenetABI.boolWord(lockRaw, at: 0)
                    let initiated = VibenetABI.boolWord(lockRaw, at: 1)
                    NSLog("[Casberi] vibenet| %@ lockStatus locked=%@ unlockInitiated=%@",
                          address, locked ? "YES" : "no", initiated ? "YES" : "no")

                    // R2: the key-history strip and the sync chips, off the
                    // SAME composed read `VibenetRoomSource` draws from —
                    // reported here rather than re-derived inline, so this
                    // probe can never quietly disagree with what the card
                    // shows. An empty history is usually correct (most
                    // accounts have never rotated a key); a non-empty one
                    // with no dates means the block-time lookups failed.
                    let item = await VibenetRead.account(address, contracts: contracts)
                    if item.history.isEmpty {
                        NSLog("[Casberi] vibenet| %@ history EMPTY", address)
                    } else {
                        for moment in item.history {
                            NSLog("[Casberi] vibenet| %@ history block=%d logIndex=%d %@ kind=%@ date=%@",
                                  address, moment.block, moment.logIndex,
                                  moment.authorized ? "added" : "revoked",
                                  moment.kind?.label ?? "unresolved",
                                  moment.date.map { "\($0)" } ?? "UNREACHABLE")
                        }
                    }
                    if let cs = item.changeSequences {
                        NSLog("[Casberi] vibenet| %@ changeSequences multichain=%llu localEpoch=%d localSequence=%d",
                              address, cs.multichain, cs.localEpoch, cs.localSequence)
                    } else {
                        NSLog("[Casberi] vibenet| %@ changeSequences UNREACHABLE", address)
                    }
                }
            }
        },

        // `-vibenetRoomProbe YES` — WHICH OF THE FOUR CARDS THE ROOM WOULD
        // DRAW, and what each one says (prd §468).
        //
        // It exists because §467 split this room's head from one surface into
        // four independently-gated ones (balance, holdings, keys, linked) and
        // nothing can see them. `verify.sh`'s demo room-head coverage step is
        // keyed on `FeedScreen.SourceHead` cases reached through
        // `-roomInsightProbe`, and this room's head is a `FeedScreen.Shape`
        // case instead — so it has never been in that map, and each of those
        // four gates can now decline silently over a demo corpus that cannot
        // furnish it. A card that draws nothing and a card that was never
        // built look identical from outside.
        //
        // One NSLog per card and per reading (the `-todayProbe` truncation
        // lesson). Composes through `VibenetRoomSource.card()`, the same
        // synchronous door the feed head uses, so what this prints is what
        // that head draws rather than a second opinion.
        Hook(key: "vibenetRoomProbe") { _, _ in
            Task { @MainActor in
                guard let room = VibenetRoomSource.card() else {
                    NSLog("[Casberi] vibenetRoom| NO ROOM — not connected, or no read has ever completed here")
                    return
                }
                NSLog("[Casberi] vibenetRoom| accounts=%d lead=%@ configReached=%@ readAt=%@",
                      room.items.count,
                      room.lead.map { VibenetRoom.shortAddress($0.address) } ?? "none",
                      room.configReached ? "YES" : "no",
                      room.readAt.map { "\($0)" } ?? "UNSTAMPED")
                NSLog("[Casberi] vibenetRoom| note=%@",
                      VibenetRoom.note(room, drawn: room.items.count) ?? "(none)")

                if let balance = VibenetBalanceAggregation.compose(room.items) {
                    NSLog("[Casberi] vibenetCard| balance DRAWS heading=%@ plain=%@ native=%@ read=%d/%d unreached=%@",
                          balance.nativeHeading, balance.plainLine,
                          balance.nativeTotal.map { VibenetBalanceFormat.line($0) } ?? "UNREAD",
                          balance.readCount, balance.accountCount,
                          balance.unreachedLine ?? "(none)")
                    let cells = VibenetBalanceTreemap.cells(balance)
                    NSLog("[Casberi] vibenetCard| holdings %@ cells=%d",
                          cells.isEmpty ? "SILENT (one asset or none)" : "DRAWS", cells.count)
                } else {
                    NSLog("[Casberi] vibenetCard| balance SILENT — no accounts at all")
                    NSLog("[Casberi] vibenetCard| holdings SILENT — no accounts at all")
                }

                if let keys = VibenetKeyAggregation.compose(room.items, now: .now) {
                    NSLog("[Casberi] vibenetCard| keys DRAWS plain=%@ unreached=%@ runway=%d soonest=%@",
                          keys.plainLine, keys.unreachedLine ?? "(none)",
                          keys.futureExpiries.count,
                          keys.soonestExpiry.map { $0.line(now: .now) } ?? "(none)")
                    for entry in VibenetPolicyAggregation.compose(room.items) {
                        NSLog("[Casberi] vibenetPolicy| %@ = %d", entry.label, entry.count)
                    }
                } else {
                    NSLog("[Casberi] vibenetCard| keys SILENT — no key on any watched account")
                }

                let links = VibenetAccountMapping.links(room.items)
                NSLog("[Casberi] vibenetCard| linked %@ links=%d",
                      links.isEmpty ? "SILENT (nobody delegates)" : "DRAWS", links.count)

                // THE ACCOUNTS CARD, row by row (prd §476) — the section the
                // room had no equivalent of until §476, and the one a person
                // opens this room to read. One NSLog per account (the
                // `-todayProbe` truncation lesson).
                //
                // `faucet=` is the half worth watching: an undeployed account
                // states its explainer from a pure function and needs nothing,
                // while the DOOR beside it is gated on the cached config
                // naming a faucet — which a demo install had never fetched, so
                // the demo drew the problem and withheld the button that
                // answers it (§476). "explains but no faucet" is that gap, and
                // it reads as an ordinary row from outside.
                let faucet = VibenetConfig.cached()?.faucetAddress
                NSLog("[Casberi] vibenetCard| accounts DRAWS rows=%d faucetKnown=%@",
                      room.items.count, faucet == nil ? "NO" : "yes")
                for item in room.items {
                    let undeployed = VibenetRoom.undeployedExplainer(item) != nil
                    NSLog("[Casberi] vibenetAccount| %@ state=%@ balance=%@ %@",
                          VibenetRoom.shortAddress(item.address),
                          VibenetRoom.rowLine(item),
                          item.nativeBalance.map { VibenetBalanceFormat.line($0) } ?? "UNREAD",
                          undeployed
                              ? (faucet == nil ? "UNDEPLOYED explains but NO FAUCET DOOR"
                                               : "UNDEPLOYED explains + faucet")
                              : "")
                }

                // The since-you-last-looked ledger, WITHOUT spending it — a
                // probe that marked the room as read would erase the very
                // thing the next launch is meant to show.
                let changes = VibenetKeysSeen.changes(in: room.items)
                NSLog("[Casberi] vibenetChanges| new=%d revoked=%d line=%@",
                      changes.added.count, changes.revokedCount, changes.line ?? "(silent)")
            }
        },

        // `-vibenetLedgerProbe YES` — WHAT MOVED, WHAT THE CHAIN IS DOING,
        // AND WHERE EACH ACCOUNT CAME FROM (prd §507).
        //
        // It exists because every reading this pass added has SEVERAL causes
        // that render as one silence and only some of them are bugs. An empty
        // ledger means: the config named no token, this account has never
        // moved one, the bounded walk did not reach far enough, or the log
        // read failed. An absent origin means: the account was created under
        // a Keystore this config no longer names (ordinary on a chain that
        // redeploys), or the read failed. A missing pulse means the tip or
        // its block time did not answer — which is NOT the same as a stalled
        // chain, and this is the one place the difference is visible.
        //
        // One NSLog per fact (the `-todayProbe` truncation lesson). Reads the
        // saved snapshot, so it spends nothing and prints what the room draws
        // rather than a second opinion.
        Hook(key: "vibenetLedgerProbe") { _, _ in
            Task { @MainActor in
                guard let room = VibenetRoomSource.card() else {
                    NSLog("[Casberi] vibenetLedger| NO ROOM — not connected, or no read has ever completed here")
                    return
                }
                if let pulse = room.pulse {
                    NSLog("[Casberi] vibenetPulse| tip=%d lastBlock=%@ rate=%@ verdict=%@ line=%@",
                          pulse.tip,
                          pulse.lastBlockAt.map { "\($0)" } ?? "UNREAD",
                          pulse.rateLine ?? "UNMEASURED",
                          pulse.verdict().rawValue,
                          pulse.line() ?? "(silent — the chain is moving)")
                } else {
                    NSLog("[Casberi] vibenetPulse| UNREAD — the tip or its block time did not answer. NOT the same as stalled.")
                }
                if let contracts = VibenetConfig.cached() {
                    // The three config fields that were parsed and read by
                    // nothing until this pass — printed so a run can say which
                    // of them this deployment actually names.
                    NSLog("[Casberi] vibenetConfig| tokens=%@ defaultAccount=%@ highRatePayer=%@",
                          contracts.tokenContracts.map { $0.symbol ?? "(symbol read live)" }
                            .joined(separator: ",").isEmpty
                              ? "NONE NAMED"
                              : contracts.tokenContracts.map { $0.symbol ?? "(live)" }.joined(separator: ","),
                          contracts.defaultAccount ?? "(none)",
                          contracts.canonicalHighRatePayerAccount ?? "(none)")
                }
                NSLog("[Casberi] vibenetLedger| implementations=%@",
                      room.implementationDrift ?? "all the same (or unread)")

                for item in room.items {
                    let short = VibenetRoom.shortAddress(item.address)
                    NSLog("[Casberi] vibenetOrigin| %@ created=%@ impl=%@ tx=%@",
                          short,
                          item.origin?.createdAt.map { "\($0)" } ?? "UNREAD",
                          item.origin?.implementationLabel ?? "(none)",
                          item.origin?.txHash ?? "(none)")
                    NSLog("[Casberi] vibenetLedger| %@ transfers=%d capped=%@ lastMove=%@",
                          short, item.transfers.count,
                          item.transfersCapped ? "YES — this is a partial history" : "no",
                          VibenetLedger.lastMoveLine(item.transfers, now: .now) ?? "(nothing has moved)")
                    for transfer in item.transfers.prefix(12) {
                        NSLog("[Casberi] vibenetMove| %@ %@ %@ with=%@ at=%@ tx=%@",
                              short, transfer.direction.rawValue, transfer.display,
                              VibenetRoom.shortAddress(transfer.counterparty),
                              transfer.at.map { "\($0)" } ?? "UNDATED — lands no row",
                              transfer.txHash)
                    }
                    // The balance series the chain can reconstruct, per token
                    // — `isComplete=NO` is the honest half: the walk is
                    // bounded, so the earliest point is where our reading
                    // starts, not where the account did.
                    for balance in item.tokenBalances {
                        guard let series = VibenetLedger.series(
                            symbol: balance.symbol, current: balance.amount,
                            transfers: item.transfers, now: .now,
                            capReached: item.transfersCapped) else {
                            NSLog("[Casberi] vibenetSeries| %@ %@ NO CURVE — under two points",
                                  short, balance.symbol)
                            continue
                        }
                        NSLog("[Casberi] vibenetSeries| %@ %@ points=%d complete=%@ first=%@ last=%@",
                              short, balance.symbol, series.points.count,
                              series.isComplete ? "YES" : "NO — a partial history",
                              series.points.first.map { VibenetBalanceFormat.line($0.balance) } ?? "-",
                              series.points.last.map { VibenetBalanceFormat.line($0.balance) } ?? "-")
                    }
                    NSLog("[Casberi] vibenetPolicy| %@ runs=%d caller=%@",
                          short, item.policyRuns.count,
                          VibenetPolicyRuns.callerLine(item.policyRuns, account: item.address)
                            ?? "(nobody to name: none, several, or the account itself)")
                }
                for party in VibenetLedger.counterparties(room.allTransfers) {
                    NSLog("[Casberi] vibenetParty| %@ %@",
                          VibenetRoom.shortAddress(party.address), party.line)
                }
                // The backfill's own ledger — an account marked done whose
                // curve is still thin is a node that would not answer a
                // historical balance, which is a real and permanent state
                // rather than a failure to retry.
                for item in room.items {
                    NSLog("[Casberi] vibenetBackfill| %@ done=%@ points=%d",
                          VibenetRoom.shortAddress(item.address),
                          VibenetBackfillLedger.isDone(item.address) ? "YES" : "no",
                          VibenetValueStore.samples(for: item.address).count)
                }
            }
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
