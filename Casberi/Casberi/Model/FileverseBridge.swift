import Foundation
import SwiftData

/// The Fileverse seat (prd §1339, §1342, §1346): your dDocs, read on this
/// phone. READ ONLY (user, 2026-10-16: "yes i guess read only then is what we
/// want"); writing stays behind a measured write (§1339 item 3).
///
/// THE KEYS. Fileverse's own sign-in, in `FileverseLoginSheet`, leaves each
/// portal's keys on its page; the sheet keeps only what a read needs — the
/// portal's address and its `appDecryptionKey` (a 32-byte secp256k1 scalar,
/// checked against its public half before it is kept) — device-only in the
/// Keychain. Nothing that could re-derive or write (`ownerSecret`, the account
/// key pair, the signed message) is ever read off the page.
enum FileverseAuth {
    static let seatID = "fileverse"
    private static let portalsKey = "fileverse.portals"

    struct Portal: Codable, Equatable {
        /// The portal contract on Gnosis Chain.
        let address: String
        /// `appDecryptionKey`, base64, as the page holds it.
        let key: String
    }

    static var portals: [Portal] {
        guard let raw = TokenVault.get(portalsKey), let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([Portal].self, from: data) else { return [] }
        return list
    }

    static var connected: Bool { !portals.isEmpty }

    static func store(_ portals: [Portal]) {
        guard let data = try? JSONEncoder().encode(portals),
              let raw = String(data: data, encoding: .utf8) else { return }
        TokenVault.set(raw, for: portalsKey)
    }

    /// Clears the keys only. The documents already landed are the person's
    /// record, not the session's (Privy's rule, §803c).
    static func clear() {
        TokenVault.delete(portalsKey)
        UserDefaults.standard.removeObject(forKey: FileverseLive.readKey)
        UserDefaults.standard.removeObject(forKey: FileverseLive.blockKey)
    }
}

/// The sweep: each portal's live files off its contract's log, each new or
/// edited one fetched from IPFS, opened, and landed as a note you can read.
enum FileverseLive {
    static let source = "Fileverse"
    /// `ref → contentCID` of what was last read, so a document is re-read only
    /// when its content changed on chain. Not a secret: CIDs of ciphertext.
    static let readKey = "fileverse.read"
    /// `ref → block` of the version last read, so a re-read only moves forward.
    static let blockKey = "fileverse.block"
    /// Measured 2026-10-16: Fileverse's own `/ipfs/` path 404s and the
    /// public gateways 429 under load; Pinata's answered every CID. Asked in
    /// this order, first 200 wins.
    static let gateways = ["https://gateway.pinata.cloud/ipfs/", "https://ipfs.io/ipfs/", "https://dweb.link/ipfs/"]
    private static let blockscout = "https://gnosis.blockscout.com/api"
    /// New or changed documents opened per pass; the rest wait for the next.
    static let readCap = 20

    struct Report {
        var portals = 0
        var live = 0
        var landed = 0
        var reread = 0
        var pruned = 0
        var failed = 0
        var unreadable = 0
    }

    private static var running = false

    /// The page that opens a document in Fileverse — a row's door.
    static func docURL(ddocId: String?) -> String {
        guard let id = ddocId, !id.isEmpty else { return "https://docs.fileverse.io" }
        return "https://docs.fileverse.io/document/\(id)"
    }

    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        await pass(context: context)?.landed
    }

    @MainActor
    static func pass(context: ModelContext) async -> Report? {
        let portals = FileverseAuth.portals
        guard !portals.isEmpty, !running else { return nil }
        running = true
        defer { running = false }

        var report = Report(portals: portals.count)
        let landedByRef = IngestSupport.thingsByRef(context, source: source)
        var read = UserDefaults.standard.dictionary(forKey: readKey) as? [String: String] ?? [:]
        var blocks = UserDefaults.standard.dictionary(forKey: blockKey) as? [String: Int] ?? [:]
        var budget = readCap
        var reindex: [Thing] = []
        var removed: [UUID] = []

        for portal in portals {
            let address = portal.address.lowercased()
            guard let scalar = try? FileverseCrypto.base64(portal.key), scalar.count == 32,
                  let logs = await portalLogs(address) else {
                report.unreadable += 1
                continue
            }
            let files = FileverseChain.liveFiles(logs)
            report.live += files.count

            for file in files where budget > 0 {
                let r = ref(address, file.fileId)
                let thing = landedByRef[r].flatMap { $0.isLive ? $0 : nil }
                // Re-read when the content changed on chain — or when the row
                // predates its door (`externalLink`, a one-time repair).
                guard thing == nil || read[r] != file.contentCID || thing?.externalLink == nil else { continue }
                // Never backwards: a partial log can hold an older edit of a
                // doc, and reading it would roll the words back.
                if thing != nil, let seen = blocks[r], file.block < UInt64(seen) { continue }
                budget -= 1
                guard let doc = await open(file, scalar: scalar) else {
                    report.failed += 1
                    continue
                }
                let when = await blockDate(file.block) ?? .now
                if let thing {
                    thing.title = doc.title
                    thing.content = doc.excerpt.isEmpty ? docURL(ddocId: doc.ddocId) : doc.excerpt
                    thing.externalLink = docURL(ddocId: doc.ddocId)
                    thing.capturedAt = when
                    if thing.enrichedText != doc.markdown {
                        thing.enrichedText = doc.markdown
                        thing.embedding = nil
                    }
                    reindex.append(thing)
                    report.reread += 1
                } else {
                    // The row reads the doc's first words, as a vault note's
                    // does; the door to Fileverse is `externalLink`, which
                    // the doc page's Open in Fileverse takes.
                    let new = Thing(kind: .note, title: doc.title,
                                    content: doc.excerpt.isEmpty ? docURL(ddocId: doc.ddocId) : doc.excerpt,
                                    source: source, capturedAt: when, sourceRef: r)
                    new.externalLink = docURL(ddocId: doc.ddocId)
                    new.enrichedText = doc.markdown
                    context.insert(new)
                    reindex.append(new)
                    report.landed += 1
                }
                read[r] = file.contentCID
                blocks[r] = Int(file.block)
            }

            // Remove only what the portal DELETED, by its own event (prd
            // §1346). A doc missing from one read stays: a short answer from
            // a public node is an outage, not a deletion.
            let gone = FileverseChain.deletedIDs(logs)
            for fileId in gone {
                let r = ref(address, fileId)
                guard let thing = landedByRef[r], thing.isLive else { continue }
                removed.append(thing.id)
                context.delete(thing)
                read.removeValue(forKey: r)
                blocks.removeValue(forKey: r)
                report.pruned += 1
            }
        }

        UserDefaults.standard.set(read, forKey: readKey)
        UserDefaults.standard.set(blocks, forKey: blockKey)
        if report.landed > 0 || report.reread > 0 || report.pruned > 0 {
            context.saveHonestly()
            if !removed.isEmpty { SpotlightIndex.remove(ids: removed) }
            if !reindex.isEmpty { SpotlightIndex.index(reindex) }
        }
        NSLog("[Casberi] fileverse| portals %d · live %d · landed %d · reread %d · pruned %d · failed %d · unreadable %d",
              report.portals, report.live, report.landed, report.reread, report.pruned, report.failed, report.unreadable)
        return report
    }

    static func ref(_ portal: String, _ fileId: String) -> String { "fileverse:\(portal):\(fileId)" }

    // MARK: Reads

    /// Every log the portal wrote: the RPC's full range, else Blockscout's.
    /// Nil when neither answered — never an empty list, which would prune.
    private static func portalLogs(_ address: String) async -> [[String: Any]]? {
        let filter: [String: Any] = ["address": address, "fromBlock": "0x0", "toBlock": "latest"]
        if let logs = await GnosisChainRPC.read(method: "eth_getLogs", params: [filter]) as? [[String: Any]] {
            return logs
        }
        var all: [[String: Any]] = []
        for page in 1..<20 {
            let url = "\(blockscout)?module=logs&action=getLogs&address=\(address)&fromBlock=0&toBlock=latest&page=\(page)&offset=1000"
            guard let root = await IngestSupport.getJSON(url) as? [String: Any] else { return nil }
            guard let rows = root["result"] as? [[String: Any]] else {
                // "No records found" is an answer; anything else is not.
                return (root["message"] as? String)?.lowercased().contains("no ") == true ? all : nil
            }
            all += rows
            if rows.count < 1000 { break }
        }
        return all
    }

    private static func ipfs(_ cid: String) async -> Data? {
        for g in gateways {
            guard let url = URL(string: g + cid) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            if let (data, http) = await IngestSupport.sendRequest(request), http.statusCode == 200 {
                return data
            }
        }
        return nil
    }

    private static func blockDate(_ block: UInt64) async -> Date? {
        guard block > 0,
              let b = await GnosisChainRPC.read(method: "eth_getBlockByNumber",
                                                params: [String(format: "0x%llx", block), false]) as? [String: Any],
              let ts = b["timestamp"] as? String,
              let seconds = UInt64(ts.dropFirst(2), radix: 16) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    struct Doc: Sendable {
        let title: String
        let markdown: String
        /// The first words, for the row and search's excerpt.
        let excerpt: String
        let ddocId: String?
    }

    /// Fetches a file's metadata and content and opens them off the main
    /// actor: a long document is tens of thousands of Yjs units.
    private static func open(_ file: FileverseChain.File, scalar: Data) async -> Doc? {
        guard let metadata = await ipfs(file.metadataCID),
              let content = await ipfs(file.contentCID) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> Doc? in
            guard let opened = try? FileverseCrypto.open(metadata: metadata, content: content,
                                                         sharedPoint: FileverseKey.sharedPoint(scalar: scalar)),
                  let nodes = try? Yjs.read(update: opened.update) else { return nil }
            let meta = (try? JSONSerialization.jsonObject(with: metadata)) as? [String: Any]
            let title = opened.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let plain = FileverseDoc.plainText(nodes).replacingOccurrences(of: "\n", with: " ")
            return Doc(title: title.isEmpty ? String(localized: "Untitled") : title,
                       markdown: FileverseDoc.markdown(nodes),
                       excerpt: String(plain.prefix(300)),
                       ddocId: meta?["ddocId"] as? String)
        }.value
    }
}
