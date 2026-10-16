import Foundation

/// A Fileverse portal's documents, as its contract logged them on Gnosis Chain
/// (prd §1339). Foundation only, so `fileverse-selftest.sh` compiles it whole.
///
/// The portal logs `AddedFile` and `EditedFile` with the file's three CIDs
/// (metadata, content, gate) and `DeletedFile` with nothing but the id, so the
/// live set is a replay of the log in block order: the last add or edit wins,
/// a delete removes. Every other event a portal writes (ownership,
/// collaborators, key verifiers — nine of them on a fresh portal, measured)
/// is skipped by topic.
enum FileverseChain {
    /// keccak256 of each event signature (@fileverse/api 1.0.10's portal ABI).
    static let added = "0x24bd87843ea516b51224a725fc0fc4ab1cda5b5e230a1336ab2c95e44f9b59ee"
    static let edited = "0xf028563d2345adc3d637a9feb14b1efed35475941d470680aab940a12f7714f4"
    static let deleted = "0xd19645dd7d7a5b32ef1ee9a5e9b05fb622540a0c783d072d20f7a172eda26bc4"

    struct File: Equatable {
        let fileId: String
        let appFileId: String
        let fileType: Int
        let metadataCID: String
        let contentCID: String
        let version: Int
        /// The block of the add or edit that made this version, for its date.
        let block: UInt64
    }

    /// The live files, newest id first. Logs are `eth_getLogs` objects (an
    /// RPC's or Blockscout's: both carry `topics`, `data`, `blockNumber` and
    /// `logIndex`, Blockscout spelling a zero index "0x").
    static func liveFiles(_ logs: [[String: Any]]) -> [File] { replay(logs).live }

    /// The ids the log shows DELETED and not added again since — the only
    /// grounds for removing a landed doc (prd §1346). A doc merely missing
    /// from a read (a public node's short answer, a page that failed) is an
    /// outage, never a deletion; only the portal's own `DeletedFile` says a
    /// doc is gone.
    static func deletedIDs(_ logs: [[String: Any]]) -> Set<String> { replay(logs).deleted }

    private static func replay(_ logs: [[String: Any]]) -> (live: [File], deleted: Set<String>) {
        func n(_ v: Any?) -> UInt64 {
            guard let s = v as? String else { return 0 }
            let hex = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
            return hex.isEmpty ? 0 : UInt64(hex, radix: 16) ?? 0
        }
        let ordered = logs.sorted {
            let a = (n($0["blockNumber"]), n($0["logIndex"])), b = (n($1["blockNumber"]), n($1["logIndex"]))
            return a < b
        }
        var files: [String: File] = [:]
        var deleted = Set<String>()
        for log in ordered {
            guard let topics = log["topics"] as? [Any], topics.count >= 2,
                  let t0 = (topics[0] as? String)?.lowercased(),
                  let idHex = topics[1] as? String else { continue }
            let fileId = decimal(idHex)
            switch t0 {
            case Self.deleted:
                files.removeValue(forKey: fileId)
                deleted.insert(fileId)
            case Self.added, Self.edited:
                guard let data = log["data"] as? String,
                      let fields = decode(data, ["string", "uint", "string", "string", "string", "uint"]),
                      case .string(let appFileId) = fields[0], case .uint(let type) = fields[1],
                      case .string(let meta) = fields[2], case .string(let content) = fields[3],
                      case .uint(let version) = fields[5] else { continue }
                deleted.remove(fileId)
                files[fileId] = File(fileId: fileId, appFileId: appFileId, fileType: Int(type),
                                     metadataCID: meta, contentCID: content, version: Int(version),
                                     block: n(log["blockNumber"]))
            default:
                continue
            }
        }
        let live = files.values.sorted { ($0.fileId.count, $0.fileId) > ($1.fileId.count, $1.fileId) }
        return (live, deleted)
    }

    // MARK: ABI

    enum Word: Equatable { case string(String), uint(UInt64) }

    /// Head/tail ABI decoding for strings and small uints, nil on anything
    /// that does not fit (a short body, an offset past the end).
    static func decode(_ hex: String, _ types: [String]) -> [Word]? {
        guard let bytes = bytes(hex) else { return nil }
        func word(_ at: Int) -> [UInt8]? { at >= 0 && at + 32 <= bytes.count ? Array(bytes[at..<(at + 32)]) : nil }
        func uint(_ w: [UInt8]) -> UInt64? {
            guard w[0..<24].allSatisfy({ $0 == 0 }) else { return nil }
            return w[24...].reduce(0) { $0 << 8 | UInt64($1) }
        }
        var out: [Word] = []
        for (i, type) in types.enumerated() {
            guard let w = word(i * 32), let v = uint(w) else { return nil }
            if type == "uint" {
                out.append(.uint(v))
            } else {
                let at = Int(v)
                guard let lw = word(at), let len = uint(lw), at + 32 + Int(len) <= bytes.count else { return nil }
                out.append(.string(String(decoding: bytes[(at + 32)..<(at + 32 + Int(len))], as: UTF8.self)))
            }
        }
        return out
    }

    private static func bytes(_ hex: String) -> [UInt8]? {
        let h = hex.hasPrefix("0x") ? Array(hex.utf8.dropFirst(2)) : Array(hex.utf8)
        guard h.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(h.count / 2)
        var i = 0
        while i < h.count {
            guard let b = UInt8(String(decoding: h[i..<(i + 2)], as: UTF8.self), radix: 16) else { return nil }
            out.append(b)
            i += 2
        }
        return out
    }

    /// A 32-byte topic as a decimal id (file ids are small counters).
    static func decimal(_ topic: String) -> String {
        let hex = topic.hasPrefix("0x") ? String(topic.dropFirst(2)) : topic
        let trimmed = hex.drop { $0 == "0" }
        if trimmed.isEmpty { return "0" }
        if trimmed.count <= 15, let v = UInt64(trimmed, radix: 16) { return String(v) }
        return "0x" + trimmed
    }
}
