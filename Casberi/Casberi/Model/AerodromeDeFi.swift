import Foundation
import SwiftData

/// Aerodrome (2026-07-30) — veAERO locks for a watched wallet on Base, read
/// straight off the VotingEscrow and Voter contracts (`eth_call`, keyless,
/// riding `WalletApprovals.rpcRead(network: "base-mainnet", …)` — the same
/// shared host pool Peer/Gnosis Pay/Uniswap already use). Rides watched
/// wallets like Peer/Privacy Pools/Gnosis Pay — no account, no key, no
/// connect switch.
///
/// veAERO is a lock, not a balance: AERO is deposited into an NFT (a
/// "veNFT") for up to several years, in exchange for voting power that
/// decays toward the lock's end date (or never, for a PERMANENT lock) and
/// the right to vote every week on where emissions flow. Two things about
/// that shape are genuinely news, and nothing in Aerodrome's own UI pushes
/// either to you:
/// (1) THE WEEKLY VOTE DEADLINE — `syncEvents` lands a dated thing (`dueAt`,
///     the `ENSExpiry`/`KalshiWatch` shape) the moment a held lock hasn't
///     voted in the CURRENT epoch and the window is still open, so it rides
///     "Coming up" next to a real calendar event. Measured live: one sampled
///     lock holding 2,690 AERO (worth real votes) last voted April 2024 —
///     two years of missed epochs, exactly the gap this alert exists for.
/// (2) LOCK EXPIRY — the same reconciling-`dueAt` shape for a non-permanent
///     lock's own end date (permanent locks never land this — they don't
///     expire by definition).
///
/// `book(addresses:)` is LIVE STATE, the WalletDeFi/Morpho/Hyperliquid
/// split — read fresh every foreground pass, never landed on its own,
/// feeding the "melting lock" read (a lock's `votingPower` visibly declines
/// toward `amountAERO` as `lockEnd` approaches, for a non-permanent lock).
///
/// MEASURED (2026-07-30, live on Base — don't re-derive without
/// re-measuring):
/// - `Voter.ve()` returns exactly `0xeBf4…67E6B4` — confirms the VotingEscrow
///   address against the chain itself, not just the deployments file.
/// - `locked(tokenId)` returns `(int128 amount, uint256 end, bool
///   isPermanent)` — verified against real locks (2,690.13 AERO / end
///   2030-07-25 / not permanent; 390.38 AERO / permanent / no end).
///   `balanceOfNFT(tokenId)` (voting power, already decayed) reads LOWER
///   than `amount` for a decaying lock (2,690.13 amount → 2,681.06 voting
///   power) and EQUAL for a permanent one (390.38 → 390.38) — the melt is
///   real and visible in the data, not a derived estimate.
/// - `Voter.epochStart(uint256)`/`epochVoteEnd(uint256)` (called with the
///   CURRENT timestamp) read the real boundaries live rather than computing
///   them locally: epoch flips Thu 00:00 UTC, the vote window closes Wed
///   23:00 UTC — one hour before the flip, not exactly at it.
/// - `lastVoted(tokenId)` on the Voter is a LIFETIME timestamp (last vote
///   ever, not per-epoch) — "voted this epoch" is `lastVoted >= epochStart`,
///   read from the SAME pass's `epochStart` call rather than guessed at with
///   a day-window proxy.
/// - The Sugar contracts (`LpSugar`/`VeSugar`, batch-reading many locks in
///   one call) exist and would cut request count sharply, but `VeSugar
///   .byAccount`'s return is a dynamic array of structs that THEMSELVES
///   contain a dynamic array (`votes: DynArray[LpVotes]`) — correctly
///   hand-decoding nested dynamic ABI offsets with no ABI-decoding library
///   is a real way to silently ship a wrong number, which the honesty rule
///   forbids. This file instead walks the plain, single-return-value calls
///   (`balanceOf`/`ownerToNFTokenIdList`/`locked`/`balanceOfNFT`
///   /`lastVoted`) — more requests, every one independently verified above.
///
/// NOT built this pass, by scope, not oversight: LP gauge staking positions
/// (`LpSugar.positions`) — same nested-dynamic-struct decoding risk as
/// `VeSugar.byAccount`, deferred until it can be decoded confidently rather
/// than guessed at.
enum AerodromeDeFi {

    private static let veAERO = "0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4"
    private static let voter = "0x16613524e02ad97eDfeF371bC883F2F5d6C480A5"
    private static let network = "base-mainnet"

    /// Locks read per wallet per pass — bounds request volume against the
    /// single shared Base host. Every measured real wallet so far has held
    /// under 10; a wallet past this cap still gets its biggest/first-found
    /// locks (enumeration order), never a silent guess at the rest.
    private static let maxLocksPerWallet = 10

    /// Which watched wallets actually hold a veAERO lock — the catalog seat's
    /// gate (2026-07-30). See `WalletSeatEvidence` for why a seat is
    /// evidence-gated rather than lit for every watched wallet.
    static let evidence = WalletSeatEvidence("aerodrome.accounts")

    /// Wallet unwatch takes this seat's mark with it, or the seat stays lit
    /// for a wallet that's gone (`WalletSeatEvidence` rule 2). There is no
    /// cursor or bucket to clear beside it: both events this file lands are
    /// reconciling `dueAt` rows read fresh from the chain every pass (the
    /// ENSExpiry shape), so nothing here can back-fill an unwatched gap.
    static func clearState(address: String) {
        evidence.forget(address)
    }

    struct Lock: Equatable, Sendable {
        let owner: String
        let tokenId: Int
        let amountAERO: Double
        let votingPower: Double
        /// nil for a permanent lock — it has no end by definition.
        let lockEnd: Date?
        let isPermanent: Bool
        /// nil = this veNFT has never voted.
        let lastVoted: Date?
    }

    struct Book: Equatable, Sendable {
        var locks: [Lock] = []
        var isEmpty: Bool { locks.isEmpty }
    }

    private static let cache = CoalescingCache<Book>()

    // MARK: - Live state

    static func book(addresses: [String]) async -> Book? {
        guard !addresses.isEmpty else { return Book() }
        let key = addresses.map { $0.lowercased() }.sorted().joined(separator: ",")
        return await cache.value(key: key, ttl: 60) {
            await fetchBook(addresses: addresses)
        }
    }

    private static func fetchBook(addresses: [String]) async -> Book? {
        var book = Book()
        var reached = false
        for address in addresses {
            guard let countHex = await ethCall(to: veAERO,
                data: selector("balanceOf(address)") + padAddress(address)) as? String,
                let countWord = word(countHex, 0)
            else { continue }
            reached = true
            let count = WalletIngest.hexToInt("0x" + countWord)
            guard count > 0 else { continue }
            for i in 0..<min(count, maxLocksPerWallet) {
                guard let idHex = await ethCall(to: veAERO,
                    data: selector("ownerToNFTokenIdList(address,uint256)") + padAddress(address) + padUint(i)) as? String,
                    let idWord = word(idHex, 0)
                else { continue }
                let tokenId = WalletIngest.hexToInt("0x" + idWord)
                guard tokenId > 0, let lock = await fetchLock(tokenId: tokenId, owner: address) else { continue }
                book.locks.append(lock)
            }
        }
        return reached ? book : nil
    }

    private static func fetchLock(tokenId: Int, owner: String) async -> Lock? {
        guard let lockedHex = await ethCall(to: veAERO,
            data: selector("locked(uint256)") + padUint(tokenId)) as? String,
            let amountWord = word(lockedHex, 0), let endWord = word(lockedHex, 1), let permWord = word(lockedHex, 2)
        else { return nil }
        let amount = WalletIngest.hexToDouble("0x" + amountWord) / 1e18
        guard amount > 0 else { return nil }
        let endRaw = WalletIngest.hexToInt("0x" + endWord)
        let isPermanent = WalletIngest.hexToInt("0x" + permWord) != 0

        var votingPower = amount
        if let vpHex = await ethCall(to: veAERO,
            data: selector("balanceOfNFT(uint256)") + padUint(tokenId)) as? String,
           let vpWord = word(vpHex, 0) {
            votingPower = WalletIngest.hexToDouble("0x" + vpWord) / 1e18
        }

        var lastVoted: Date? = nil
        if let lvHex = await ethCall(to: voter,
            data: selector("lastVoted(uint256)") + padUint(tokenId)) as? String,
           let lvWord = word(lvHex, 0) {
            let lv = WalletIngest.hexToInt("0x" + lvWord)
            if lv > 0 { lastVoted = Date(timeIntervalSince1970: Double(lv)) }
        }

        return Lock(owner: owner.lowercased(), tokenId: tokenId, amountAERO: amount,
                    votingPower: votingPower,
                    lockEnd: (endRaw > 0 && !isPermanent) ? Date(timeIntervalSince1970: Double(endRaw)) : nil,
                    isPermanent: isPermanent, lastVoted: lastVoted)
    }

    // MARK: - Epoch (read live, never computed locally — see file header)

    private static func epochBounds() async -> (start: Date, voteEnd: Date)? {
        let now = padUint(Int(Date.now.timeIntervalSince1970))
        // Sequential, not `async let` — every real network hit routes
        // through `ethCall`'s own pacing (see its doc), which only spaces
        // out calls it can see happen one after another.
        guard let startHex = await ethCall(to: voter, data: selector("epochStart(uint256)") + now) as? String,
              let startWord = word(startHex, 0),
              let endHex = await ethCall(to: voter, data: selector("epochVoteEnd(uint256)") + now) as? String,
              let endWord = word(endHex, 0)
        else { return nil }
        let start = WalletIngest.hexToInt("0x" + startWord)
        let end = WalletIngest.hexToInt("0x" + endWord)
        guard start > 0, end > 0 else { return nil }
        return (Date(timeIntervalSince1970: Double(start)), Date(timeIntervalSince1970: Double(end)))
    }

    // MARK: - Events (weekly vote deadline + lock expiry, both reconciling
    // `dueAt` — the ENSExpiry shape: a landed row's date can MOVE, never
    // just gets landed once and left stale)

    /// Lands (or reconciles) the vote-deadline row for every held lock that
    /// hasn't voted this epoch, plus the lock-expiry row for every
    /// non-permanent lock. Returns landed count, nil when the read reached
    /// nothing at all.
    @MainActor
    static func syncEvents(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let book = await book(addresses: addresses) else { return nil }
        var added = 0

        // The catalog seat's evidence mark (2026-07-30) — a veAERO lock is
        // proof this wallet is an Aerodrome voter. Read off this pass's own
        // `book`, so it costs nothing extra; never unstamped on an empty
        // book (`WalletSeatEvidence`'s stamp-never-unstamp rule), which also
        // means a lock withdrawn and re-made doesn't flap the seat.
        for lock in book.locks { evidence.remember(lock.owner) }

        if let bounds = await epochBounds(), bounds.voteEnd > .now {
            for lock in book.locks {
                let votedThisEpoch = (lock.lastVoted ?? .distantPast) >= bounds.start
                guard !votedThisEpoch else { continue }
                let ref = "aerodrome:vote:\(lock.owner):\(lock.tokenId)"
                // Weekday ALONE is ambiguous for a date days out ("closes
                // Wed 4:00 PM" doesn't say which Wednesday) — caught live
                // (2026-07-30): the epoch's own start/voteEnd both format to
                // "Wed" in Pacific time due to the UTC offset, reading as if
                // voteEnd preceded start. Month+day disambiguates.
                let voteEndText = bounds.voteEnd.formatted(
                    .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                let fresh = String(localized:
                    "veAERO #\(lock.tokenId) hasn't voted — Aerodrome voting closes \(voteEndText)")
                if existing.contains(ref) {
                    if let landed = try? context.fetch(FetchDescriptor<Thing>(
                        predicate: #Predicate { $0.sourceRef == ref })).first,
                       landed.dueAt != bounds.voteEnd || landed.title != fresh {
                        landed.dueAt = bounds.voteEnd
                        landed.title = fresh
                    }
                    continue
                }
                let thing = Thing(kind: .link, title: fresh,
                                  content: "https://aerodrome.finance/vote",
                                  source: "Wallet", capturedAt: .now, sourceRef: ref)
                thing.dueAt = bounds.voteEnd
                thing.walletAddress = lock.owner
                context.insert(thing)
                SpotlightIndex.index([thing])
                added += 1
            }
        }

        guard let horizon = Calendar.current.date(byAdding: .day, value: 60, to: .now),
              let grace = Calendar.current.date(byAdding: .day, value: -14, to: .now)
        else {
            if added > 0 { _ = context.saveHonestly() }
            return added
        }
        for lock in book.locks {
            guard let end = lock.lockEnd else { continue }
            let ref = "aerodrome:lockend:\(lock.owner):\(lock.tokenId)"
            let when = end.formatted(.dateTime.month(.abbreviated).day())
            let fresh = end < .now
                ? String(localized: "veAERO #\(lock.tokenId) (\(WalletIngest.format(lock.amountAERO)) AERO) expired \(when)")
                : String(localized: "veAERO #\(lock.tokenId) (\(WalletIngest.format(lock.amountAERO)) AERO) expires \(when)")
            if existing.contains(ref) {
                if let landed = try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.sourceRef == ref })).first,
                   landed.dueAt != end || landed.title != fresh {
                    landed.dueAt = end
                    landed.title = fresh
                }
                continue
            }
            guard end <= horizon, end >= grace else { continue }
            let thing = Thing(kind: .link, title: fresh,
                              content: "https://aerodrome.finance/lock/\(lock.tokenId)",
                              source: "Wallet", capturedAt: .now, sourceRef: ref)
            thing.dueAt = end
            thing.walletAddress = lock.owner
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { _ = context.saveHonestly() }
        return added
    }

    // MARK: - RPC + ABI helpers

    /// Paces every `eth_call` through the single shared `base-mainnet` host
    /// (`WalletApprovals`' pool carries only `mainnet.base.org` for Base —
    /// no fallback). MEASURED (2026-07-30): a full lock read is 5 sequential
    /// calls, plus 2 more for the epoch — fired back-to-back with no spacing
    /// this file's own live probe caught the host 429ing mid-read (confirmed
    /// the host itself was fine seconds later, standalone). A plain actor,
    /// the `CoalescingCache` idiom, so pacing holds even if two book reads
    /// for different wallets happen to be in flight together.
    private actor RequestPacer {
        private var last: Date = .distantPast
        func wait(_ interval: TimeInterval) async {
            let elapsed = Date.now.timeIntervalSince(last)
            if elapsed < interval {
                try? await Task.sleep(nanoseconds: UInt64((interval - elapsed) * 1_000_000_000))
            }
            last = .now
        }
    }
    private static let pacer = RequestPacer()

    private static func ethCall(to: String, data: String) async -> Any? {
        await pacer.wait(0.2)
        return await WalletApprovals.rpcRead(network: network, method: "eth_call",
                                             params: [["to": to, "data": data], "latest"])
    }

    /// A function selector, computed at call time off `Keccak256` (already
    /// verified against pycryptodome + EIP-55 vectors — see its own header)
    /// rather than hardcoded from memory.
    private static func selector(_ signature: String) -> String {
        Keccak256.hexString(Array(Keccak256.hash(Array(signature.utf8)).prefix(4)))
    }

    private static func padAddress(_ address: String) -> String {
        let hex = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex.lowercased()
    }

    private static func padUint(_ n: Int) -> String {
        let hex = String(n, radix: 16)
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex
    }

    /// The nth 32-byte word (no `0x`) of an `0x`-prefixed `eth_call` return,
    /// lowercased — nil on a short/malformed response.
    private static func word(_ hex: String, _ n: Int) -> String? {
        let s = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let start = n * 64, end = start + 64
        guard s.count >= end else { return nil }
        let i0 = s.index(s.startIndex, offsetBy: start)
        let i1 = s.index(s.startIndex, offsetBy: end)
        return String(s[i0..<i1]).lowercased()
    }

    #if DEBUG
    /// `-aerodromeProbe YES` — NSLogs each watched wallet's veAERO locks
    /// (amount, decayed voting power, permanent?, lock end, last voted) or
    /// the honest miss, plus the live epoch window, then runs the vote-
    /// deadline + lock-expiry sync once and reports what landed. Pairs with
    /// `-walletAddress`. Returns ONE LINE PER LOCK — joined into one NSLog
    /// call this truncates past NSLog's own length limit and silently hides
    /// later locks (the `-todayProbe` lesson, caught live 2026-07-30 hiding
    /// this file's own second real lock on a first pass). The hook logs
    /// each element separately.
    @MainActor
    static func probe(context: ModelContext) async -> [String] {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return ["no EVM wallets watched"] }
        guard let book = await book(addresses: addresses) else { return ["book UNREACHABLE"] }
        var lines: [String] = []
        if book.isEmpty { lines.append("no veAERO locks (a real empty book, not a miss)") }
        for l in book.locks {
            let end = l.isPermanent ? "permanent" : (l.lockEnd.map { $0.formatted(.dateTime.month().day().year()) } ?? "?")
            let voted = l.lastVoted.map { $0.formatted(.dateTime.month().day().year()) } ?? "never"
            lines.append("\(WalletStore.shortAddress(l.owner)) #\(l.tokenId): \(WalletIngest.format(l.amountAERO)) AERO, votes=\(WalletIngest.format(l.votingPower)), end=\(end), lastVoted=\(voted)")
        }
        if let bounds = await epochBounds() {
            let fmt = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
            lines.append("epoch: start=\(bounds.start.formatted(fmt)) voteEnd=\(bounds.voteEnd.formatted(fmt))")
        } else {
            lines.append("epoch: UNREACHABLE")
        }
        let landed = await syncEvents(context: context, addresses: addresses,
                                      existing: IngestSupport.existingSourceRefs(context, source: "Wallet"))
        lines.append("sync: \(landed.map(String.init) ?? "FAILED") landed")
        return lines
    }
    #endif
}
