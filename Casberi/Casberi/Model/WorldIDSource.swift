import Foundation
import Observation

/// The reads behind `WorldID` (prd §785, 2026-09-16) — kept apart from the
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

    /// OBSERVED, and the surfaces read it DIRECTLY rather than copying it into
    /// `@State` (2026-09-16). A copy taken after `fill` returns is wrong in one
    /// real case: `fill` returns immediately when the same address is already
    /// in flight from another surface, so a card opened over a person room's
    /// pending read copied `.unknown` and kept it for the whole visit. Reading
    /// the store in the body means the answer draws whenever it lands, whoever
    /// bought it.
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
    ///
    /// **Answers whether it actually spent a request**, which is what lets the
    /// list below bound REQUESTS rather than loop iterations — counting an
    /// early return against the budget let six cached or in-flight addresses
    /// exhaust it and skip the one address nobody had asked about.
    @discardableResult
    func fill(_ address: String) async -> Bool {
        guard !DemoMode.isActive, ENS.isHexAddress(address) else { return false }
        let key = Self.key(for: address)
        guard !asking.contains(key) else { return false }
        if let existing = records[key], !isStale(existing) { return false }
        guard let data = WorldID.verifiedUntilCalldata(address: address) else { return false }
        asking.insert(key)
        defer { asking.remove(key) }
        guard let returned = await ethCall(data: data) else { return false }
        // Only a READ answer is written. A chain that did not answer leaves
        // the record alone — writing a zero there would turn "we could not
        // reach World Chain" into "this address is not verified", which is
        // the one lie this file exists to avoid.
        //
        // An answer this app cannot READ is still an answer, and it is kept
        // (`unreadableSeconds`): dropping it re-asked the same address on every
        // single visit, forever, for a word the chain was perfectly happy to
        // give — which is what a permanent-verification sentinel would be.
        let seconds = WorldID.verifiedUntilSeconds(from: returned) ?? WorldID.unreadableSeconds
        records[key] = Record(untilUnix: seconds, askedAt: .now)
        persist()
        return true
    }

    /// Asks for a list, bounded by `perPassBudget` REQUESTS. Sequential on
    /// purpose: these reads share one public host, and a `TaskGroup` would
    /// arrive as a burst (`WeiNamesSource`'s measured lesson). The staleness
    /// and shape tests are `fill(_:)`'s alone — a second copy here could
    /// disagree with the one that decides.
    func fill(_ addresses: [String]) async {
        var spent = 0
        for address in addresses {
            guard spent < Self.perPassBudget else { return }
            if await fill(address) { spent += 1 }
        }
    }

    /// The best answer the book holds about a PERSON — one person's several
    /// addresses are one person, so a room asks about the set and draws one
    /// line. Pure: it reads what is known and buys nothing, so a body may read
    /// it on every pass and the fill stays an intent's cost (`fill(_:)` above,
    /// called where the room can afford to wait).
    ///
    /// A live mark wins; a lapsed one beats `.absent`, because "was verified
    /// once" is worth more than "this book holds nothing"; `.unknown` is the
    /// answer only while nothing has been asked at all.
    func status(among addresses: [String], asOf now: Date = .now) -> WorldID.Status {
        var best: WorldID.Status = .unknown
        for address in addresses {
            let status = status(for: address, asOf: now)
            if status.isVerified { return status }
            if case .lapsed = status { best = status; continue }
            if case .absent = status, case .unknown = best { best = .absent }
        }
        return best
    }

    /// Drops every answer. **No caller today, and its doc no longer invents
    /// one** — an earlier version said it ran when a book entry was removed,
    /// which nothing did (`AddressBook.remove` is not main-actor isolated and
    /// calls nothing here). It is kept for the Data tray's wipe, one line from
    /// being real; the per-address twin was deleted rather than left claiming
    /// a behaviour the app does not have.
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
        // Annotated rather than inferred: a heterogeneous literal (a dict and
        // a string) inside a `[String: Any]` value only ever infers to `[Any]`
        // with a warning, and this repo's pass reads warnings.
        let params: [Any] = [["to": WorldID.addressBook, "data": data], "latest"]
        let body: [String: Any] = [
            "id": 1, "jsonrpc": "2.0", "method": "eth_call", "params": params,
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
