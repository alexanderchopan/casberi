import Foundation

/// Solana native stake accounts (2026-07-27) — the gap a rotki feature
/// comparison surfaced: delegated SOL sits in its own stake account, never
/// in the wallet's own token balance, so every existing read (Alchemy's
/// Portfolio endpoint, the treemap, the combined total) is blind to it. A
/// wallet with 32 SOL delegated reads as holding none of it — the same
/// understatement §77 already treats as a honesty failure for the combined
/// number, just on the Solana side instead of the EVM one (a beacon-chain
/// ETH validator has the identical shape and is a separate, harder gap —
/// see `WalletDeFi`'s doc header for the EVM equivalent, unbuilt).
///
/// Read via `getProgramAccounts` on the Stake program, filtered to accounts
/// whose WITHDRAW authority is the watched wallet (`memcmp` at byte offset
/// 44) — the withdrawer, not the staker, is who a balance actually belongs
/// to; a wallet can delegate through a staking-as-a-service authority while
/// keeping withdraw rights, and that's still money the total must count.
/// `dataSize: 200` narrows to `StakeStateV2`'s fixed size first, which is
/// what makes the memcmp affordable — measured live 2026-07-27 filtering by
/// VOTER instead (to get a real sample) against a top validator's ~1,100
/// delegator accounts: one request, ~0.5s, over the same shared Alchemy
/// Solana RPC `SolanaActivity` already uses. Re-filtering that same result
/// set by WITHDRAWER on one of the returned accounts found exactly the one
/// row it should — the query shape is verified end to end, not assumed.
///
/// The `StakeStateV2` layout (bincode, not Borsh — Solana's stake program
/// predates Borsh) was decoded and checked against a real live account,
/// not taken on faith from the source: `[0..4)` enum discriminant,
/// `[4..12)` rent-exempt reserve, `[12..44)` staker authority, `[44..76)`
/// withdraw authority, `[76..124)` lockup, `[124..156)` delegated voter,
/// `[156..164)` **stake, lamports (LE u64)**, `[164..172)` **activation
/// epoch**, `[172..180)` **deactivation epoch** (`UInt64.max` sentinel =
/// not deactivating — mirrors `WalletDeFi`'s `type(uint256).max` "no debt"
/// read). Only the three bolded fields are needed, so a `dataSlice` of the
/// first 180 bytes keeps every response small without touching the rest.
enum SolanaStaking {

    struct Position {
        let stakeAccount: String
        let lamports: UInt64
        let activationEpoch: UInt64
        let deactivationEpoch: UInt64

        var sol: Double { Double(lamports) / 1e9 }
    }

    enum Status: String { case active, activating, deactivating, inactive }

    /// `inactive` only once the deactivation epoch has actually passed — a
    /// stake account mid-cooldown still holds real SOL, unlike a spent
    /// approval or a closed Aave position, so it stays counted right up
    /// until the epoch turns.
    static func status(_ p: Position, currentEpoch: UInt64) -> Status {
        if p.deactivationEpoch != .max, currentEpoch >= p.deactivationEpoch { return .inactive }
        if p.deactivationEpoch != .max { return .deactivating }
        if currentEpoch <= p.activationEpoch { return .activating }
        return .active
    }

    private static let stakeProgram = "Stake11111111111111111111111111111111111111"
    private static let withdrawerOffset = 44
    private static let dataSize = 200
    /// Through `deactivation_epoch` — the three fields this feature reads.
    private static let sliceLength = 180

    /// Every stake account this wallet can withdraw from, or nil when the
    /// RPC couldn't be reached at all — an EMPTY array is a real "nothing
    /// staked", the same honest-failure shape `SolanaActivity.moves` uses.
    static func positions(address: String, key: String) async -> [Position]? {
        let url = "https://\(SolanaActivity.network).g.alchemy.com/v2/\(key)"
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "getProgramAccounts",
            "params": [stakeProgram, [
                "encoding": "base64",
                "dataSlice": ["offset": 0, "length": sliceLength],
                "filters": [
                    ["dataSize": dataSize],
                    ["memcmp": ["offset": withdrawerOffset, "bytes": address]],
                ],
            ]],
        ]
        guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
              let result = root["result"] as? [[String: Any]] else { return nil }
        return result.compactMap { row in
            guard let pubkey = row["pubkey"] as? String,
                  let account = row["account"] as? [String: Any],
                  let dataPair = account["data"] as? [Any],
                  let b64 = dataPair.first as? String,
                  let data = Data(base64Encoded: b64), data.count >= sliceLength
            else { return nil }
            let lamports = readU64(data, at: 156)
            guard lamports > 0 else { return nil }   // a closed/withdrawn account, not a position
            return Position(stakeAccount: pubkey, lamports: lamports,
                            activationEpoch: readU64(data, at: 164),
                            deactivationEpoch: readU64(data, at: 172))
        }
    }

    /// Little-endian, byte by byte — no unaligned-load risk on a `Data`
    /// slice sourced from a base64 decode.
    private static func readU64(_ data: Data, at offset: Int) -> UInt64 {
        let start = data.startIndex + offset
        var value: UInt64 = 0
        for i in 0..<8 { value |= UInt64(data[start + i]) << (8 * i) }
        return value
    }

    /// The current epoch, cached — a staking status doesn't need tick
    /// accuracy, and this must not cost a call per wallet per pass. Mirrors
    /// `SolanaActivity.cachedSOL`'s 15-minute window.
    @MainActor private static var cachedEpoch: (epoch: UInt64, at: Date)?

    @MainActor
    static func currentEpoch(key: String) async -> UInt64? {
        if let cachedEpoch, cachedEpoch.at.timeIntervalSinceNow > -900 { return cachedEpoch.epoch }
        let url = "https://\(SolanaActivity.network).g.alchemy.com/v2/\(key)"
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "getEpochInfo", "params": []]
        guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let epoch = result["epoch"] as? Double else { return nil }
        let e = UInt64(epoch)
        cachedEpoch = (e, .now)
        return e
    }

    /// Total value across every non-inactive position — active, activating,
    /// or cooling down are all still the wallet's own money — what folds
    /// into the combined total under the plain `SOL` symbol. Mirrors
    /// `ExchangeBridge.normalizeKrakenAsset`'s reasoning for `ETH.S`: a
    /// staked balance is the same asset to a portfolio, the account it sits
    /// in says where, not what. nil only on an unreachable RPC — a wallet
    /// that reached the chain and holds nothing staked reports 0, same as
    /// `SolanaActivity.moves`' honest-empty rule.
    @MainActor
    static func stakedUSD(address: String, key: String, solPrice: Double) async -> Double? {
        guard let positions = await positions(address: address, key: key) else { return nil }
        guard !positions.isEmpty else { return 0 }
        guard let epoch = await currentEpoch(key: key) else { return nil }
        let live = positions.filter { status($0, currentEpoch: epoch) != .inactive }
        return live.reduce(0) { $0 + $1.sol * solPrice }
    }

    /// `-solStakeProbe <base58>` — NSLogs every position found for one
    /// address: account, SOL amount, and status, or the honest "none" /
    /// "unreachable" reads.
    static func probe(address: String) async -> String {
        let key = IngestSupport.alchemyKey
        guard let positions = await positions(address: address, key: key) else {
            return "couldn't reach the chain"
        }
        guard !positions.isEmpty else { return "no stake accounts" }
        guard let epoch = await currentEpoch(key: key) else { return "read positions but couldn't read the epoch" }
        return positions.map { p in
            "\(p.stakeAccount): \(WalletIngest.format(p.sol)) SOL, \(status(p, currentEpoch: epoch).rawValue)"
        }.joined(separator: " | ")
    }
}
