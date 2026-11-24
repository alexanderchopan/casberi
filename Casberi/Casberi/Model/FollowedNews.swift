import Foundation
import Observation
import SwiftData

/// **THE WALLETS YOU FOLLOW ARE NEVER YOUR MONEY (prd §1969).** Your money is
/// your Casberi account and the apps, exchanges and banks you connect; a
/// wallet you follow stands in Following alone, never in Home's balance,
/// Holdings, Activity, Spending or the Feed. This is the one rule for which
/// addresses those are, and what each did since you last looked.
@MainActor
@Observable
final class FollowedNews {
    static let shared = FollowedNews()

    /// Each followed wallet's moves since you last opened it, by its watched
    /// spelling (`WalletStore.WatchedAddress.address`).
    private(set) var moves: [String: [FollowedSince.Move]] = [:]
    /// Bumped by every refresh, so a view keyed on it reads again.
    private(set) var revision = 0

    private static let seenKey = "following.seenAt.v1"

    // MARK: - Who

    /// Every watched address but your own Casberi account (the demo's too).
    static var followed: [String] {
        let own = YourAccountDemo.shownAddress
        return WalletStore.shared.addresses.map(\.address)
            .filter { a in own.map { !WalletWatch.sameAddress(a, $0) } ?? true }
    }

    /// Whether a row landed for a wallet you follow: one test, every list.
    static func isFollowedRow(_ thing: Thing, followed: [String]) -> Bool {
        guard let stored = thing.walletAddress, !followed.isEmpty else { return false }
        let store = WalletStore.shared
        return followed.contains { store.scopeMatches(stored, scope: $0) }
    }

    /// Whether `address` is a wallet you follow (never your own account).
    static func isFollowed(_ address: String?) -> Bool {
        guard let address else { return false }
        return followed.contains { WalletWatch.sameAddress($0, address) }
    }

    // MARK: - Since you looked

    /// When you last opened each wallet's page, read once, kept in memory,
    /// written through `DefaultsWrite` (never a `UserDefaults` write here,
    /// §721).
    private static var seenCache: [String: Double]?

    private static var seen: [String: Double] {
        if let seenCache { return seenCache }
        let read = UserDefaults.standard.data(forKey: seenKey)
            .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        seenCache = read
        return read
    }

    /// When you last opened this wallet's page; a week back if never.
    static func seenAt(_ address: String, now: Date = .now) -> Date {
        if let raw = seen[address.lowercased()] { return Date(timeIntervalSince1970: raw) }
        return now.addingTimeInterval(-FollowedSince.firstLook)
    }

    /// Opening a followed wallet's page reads its news.
    func markSeen(_ address: String, now: Date = .now) {
        var all = Self.seen
        all[address.lowercased()] = now.timeIntervalSince1970
        Self.seenCache = all
        if let data = try? JSONEncoder().encode(all) { DefaultsWrite.set(data, forKey: Self.seenKey) }
        if moves[address]?.isEmpty == false { moves[address] = [] }
        revision &+= 1
    }

    /// One bounded fetch of the Wallet's rows back to the oldest look, split
    /// by followed wallet. In a task, never a body (§628).
    func refresh(_ context: ModelContext, now: Date = .now) {
        let followed = Self.followed
        guard !followed.isEmpty else {
            if !moves.isEmpty { moves = [:]; revision &+= 1 }
            return
        }
        let seen = Dictionary(uniqueKeysWithValues: followed.map { ($0, Self.seenAt($0, now: now)) })
        let oldest = seen.values.min() ?? now
        let sources = RoomAccounts.roomSources(CategoryFold.walletRoom)
        var fetch = FetchDescriptor<Thing>(
            predicate: #Predicate { sources.contains($0.source) && $0.capturedAt > oldest },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        fetch.fetchLimit = 600
        let rows = (try? context.fetch(fetch)) ?? []
        let store = WalletStore.shared
        var out: [String: [FollowedSince.Move]] = [:]
        for address in followed { out[address] = [] }
        for thing in rows where thing.isLive && thing.securityFlag == nil {
            guard let stored = thing.walletAddress,
                  let address = followed.first(where: { store.scopeMatches(stored, scope: $0) }),
                  let since = seen[address], thing.capturedAt > since else { continue }
            out[address, default: []].append(.init(title: thing.title, at: thing.capturedAt))
        }
        if out != moves { moves = out }
        revision &+= 1
    }

    /// The wallets with news, newest move first, then the quiet ones in the
    /// order you follow them.
    func ordered(_ addresses: [String]) -> [String] {
        let newest: (String) -> Date? = { self.moves[$0]?.map(\.at).max() }
        let busy = addresses.filter { newest($0) != nil }.sorted { newest($0)! > newest($1)! }
        return busy + addresses.filter { newest($0) == nil }
    }

    /// How many followed wallets did something since you looked.
    var newCount: Int { Self.followed.filter { !(moves[$0] ?? []).isEmpty }.count }
}
