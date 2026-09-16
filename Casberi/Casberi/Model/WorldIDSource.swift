import Foundation
import Observation

/// The reads behind `WorldID` (prd §784, 2026-09-16) — kept apart from the
/// encoders so that file stays Foundation-only and its harness can compile it
/// whole, the `WeiNames`/`WeiNamesSource` split.
///
/// One keyless `eth_call` per address, against World Chain's public RPC. No
/// key, no account, no seat — and no dependency on World Chain being switched
/// on in the wallet (`WalletChainStore`): this book is a fact about an address,
/// not a chain you follow.
///
/// ## The rules it inherits from `AddressNames`, and why they are the same
///
/// A book of three hundred addresses is ordinary here, and entries land by
/// themselves — counterparties, Safe signers, the devnet signers. So:
///
///  · **a read is bought by an INTENT, never by a row scrolling past.** Only
///    opening an address card and opening a person's room ask. Rows draw what
///    is already known and trigger nothing;
///  · **the miss is the answer worth keeping.** Almost every address on earth
///    is absent from this book, so an unkept miss is the expensive case;
///  · **asked-and-nothing is not never-asked** (`WorldID.Status.absent` vs
///    `.unknown`). Neither draws anything, but the store must still tell them
///    apart or every card would re-ask on every visit.
///
/// **Nothing here writes a `Thing`.** A verification is a fact about an
/// address, not an event in your corpus — it has no moment, it was not
/// addressed to you, and it would sit in the feed under a day it did not
/// happen on.
@MainActor
@Observable
final class WorldIDSource {
    static let shared = WorldIDSource()

    /// One address's answer. `untilUnix == 0` is a real answer — the book has
    /// nothing for this address — and is kept, not discarded, so a second
    /// visit costs no request.
    struct Record: Codable, Equatable {
        var untilUnix: Int
        var askedAt: Date
    }

    private static let storeKey = "worldID.v1"

    /// How long an answer stands. Shorter than `AddressNames`' fortnight
    /// because this one can change in both directions — an address can be
    /// verified after we looked, and a verification expires — and longer than
    /// a day because neither happens often and the read is not free.
    private static let freshness: TimeInterval = 7 * 24 * 3600

    /// The most addresses one pass will look up, `AddressNames`' rule: a
    /// person's room resolving several verified addresses must not turn one
    /// screen open into an unbounded run of chain reads.
    static let perPassBudget = 6

    /// OBSERVED: a card draws off this, so an answer landing while it is open
    /// has to re-render it.
    private var records: [String: Record] = [:]

    /// In flight right now — so a card and the room behind it do not each buy
    /// the same call for one address.
    @ObservationIgnored
    private var asking: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        }
    }

    private static func key(for address: String) -> String { address.lowercased() }

    /// What the book says, as of now. `.unknown` until something answered —
    /// which is what an address nobody has looked up draws, and it draws
    /// nothing.
    func status(for address: String, asOf now: Date = .now) -> WorldID.Status {
        guard let record = records[Self.key(for: address)] else { return .unknown }
        return WorldID.status(untilUnix: record.untilUnix, asOf: now)
    }

    /// True once this address has been asked about at all — the honest test a
    /// surface needs before it could ever say "no verification" out loud.
    /// Nothing says that today (§83), and this exists so that nothing has to
    /// re-derive it from `.unknown` if one ever does.
    func hasAnswer(for address: String) -> Bool {
        records[Self.key(for: address)] != nil
    }

    private func isStale(_ record: Record) -> Bool {
        Date.now.timeIntervalSince(record.askedAt) > Self.freshness
    }

    /// Asks for one address unless it was asked recently. Safe to call from a
    /// `.task`: it returns immediately for anything already known, in flight,
    /// or not a hex address.
    func fill(_ address: String) async {
        guard !DemoMode.isActive, ENS.isHexAddress(address) else { return }
        let key = Self.key(for: address)
        guard !asking.contains(key) else { return }
        if let existing = records[key], !isStale(existing) { return }
        guard let data = WorldID.verifiedUntilCalldata(address: address) else { return }
        asking.insert(key)
        defer { asking.remove(key) }
        guard let returned = await ethCall(data: data),
              let seconds = WorldID.verifiedUntilSeconds(from: returned) else { return }
        // Only a READ answer is written. A chain that did not answer leaves
        // the record alone — writing a zero there would turn "we could not
        // reach World Chain" into "this address is not verified", which is
        // the one lie this file exists to avoid.
        records[key] = Record(untilUnix: seconds, askedAt: .now)
        persist()
    }

    /// Asks for a list, bounded by `perPassBudget`. Sequential on purpose:
    /// these reads share one public host, and a `TaskGroup` would arrive as a
    /// burst (`WeiNamesSource`'s measured lesson).
    func fill(_ addresses: [String]) async {
        var spent = 0
        for address in addresses {
            guard spent < Self.perPassBudget else { return }
            let key = Self.key(for: address)
            if let existing = records[key], !isStale(existing) { continue }
            guard ENS.isHexAddress(address) else { continue }
            await fill(address)
            spent += 1
        }
    }

    /// The first of these addresses the book verifies, if any — what a
    /// person's room asks, since one person's several addresses are one
    /// person.
    func fillAndFindVerified(_ addresses: [String]) async -> WorldID.Status {
        await fill(addresses)
        for address in addresses {
            let status = status(for: address)
            if status.isVerified { return status }
        }
        // A lapsed mark is worth more than nothing here — it says somebody
        // was verified once — so it wins over `.absent` when no live one is
        // found.
        for address in addresses {
            if case .lapsed = status(for: address) { return status(for: address) }
        }
        return addresses.contains(where: { hasAnswer(for: $0) }) ? .absent : .unknown
    }

    /// Drops what is known for an address — called when a book entry is
    /// removed, so a re-added address asks again rather than showing a verdict
    /// from a previous life.
    func forget(_ address: String) {
        records.removeValue(forKey: Self.key(for: address))
        persist()
    }

    func forgetAll() {
        records = [:]
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storeKey)
    }

    // MARK: - The read

    private func ethCall(data: String) async -> String? {
        let body: [String: Any] = [
            "id": 1, "jsonrpc": "2.0", "method": "eth_call",
            "params": [["to": WorldID.addressBook, "data": data], "latest"],
        ]
        // Named to the ledger (prd §289): this host is a `g.alchemy.com`
        // subdomain, which the receipts screen would otherwise file under the
        // Wallet bridge — and this read happens whether or not a wallet is
        // watched, so that attribution would be wrong in the direction that
        // matters.
        guard let root = await IngestSupport.postJSON(WorldID.rpc, body: body,
                                                      service: "World ID") as? [String: Any],
              let result = root["result"] as? String else { return nil }
        return result
    }

    #if DEBUG
    /// `-worldIDProbe <0x…|YES>` — the read, step by step.
    ///
    /// It exists because every interesting answer here is a silence with
    /// several causes and only one of them is a bug: an address shows no mark
    /// because it is not in the book (the ordinary case), because the chain
    /// did not answer, because the selector is wrong and the call reverted, or
    /// because the read never ran. The RAW word is printed for the reason
    /// `WorldID`'s header gives — a permanent verification stored as a
    /// sentinel rather than a second is UNMEASURED here, and this line is how
    /// it is found out.
    ///
    /// ONE LINE PER FACT — a joined NSLog is truncated past its own length
    /// limit and silently drops the later ones (the `-todayProbe` lesson).
    static func probe(_ spec: String) async -> [String] {
        var lines: [String] = ["demo=\(DemoMode.isActive ? "ACTIVE — every read returns nil" : "off")"]
        lines.append("book=\(WorldID.addressBook) chain=\(WorldID.chainId) rpc=\(WorldID.rpc)")
        lines.append("selector=0x\(WorldID.selector(WorldID.verifiedUntilSignature)) \(WorldID.verifiedUntilSignature)")

        let asked = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        var addresses: [String] = []
        if ENS.isHexAddress(asked) {
            addresses = [asked]
        } else {
            addresses = WalletStore.shared.addresses.map(\.address).filter(ENS.isHexAddress)
            lines.append("no address given — reading the \(addresses.count) watched wallet(s)")
        }
        guard !addresses.isEmpty else {
            lines.append("nothing to read: watch a wallet, or pass a 0x address")
            return lines
        }
        let source = WorldIDSource.shared
        for address in addresses.prefix(perPassBudget) {
            guard let data = WorldID.verifiedUntilCalldata(address: address) else {
                lines.append("\(address) REFUSED — not a hex address")
                continue
            }
            lines.append("call \(address)")
            lines.append("  data=\(data)")
            guard let returned = await source.ethCall(data: data) else {
                lines.append("  UNREACHABLE — World Chain did not answer")
                continue
            }
            lines.append("  raw=\(returned)")
            guard let seconds = WorldID.verifiedUntilSeconds(from: returned) else {
                lines.append("  UNREADABLE — the return is not one word this file can read")
                continue
            }
            switch WorldID.status(untilUnix: seconds, asOf: .now) {
            case .absent:
                lines.append("  → absent (0) — this book has no verification for it")
            case .verified(let until):
                lines.append("  → verified until \(until) (\(seconds))")
            case .lapsed(let at):
                lines.append("  → lapsed at \(at) (\(seconds))")
            case .unknown:
                lines.append("  → unknown")
            }
        }
        return lines
    }
    #endif
}
