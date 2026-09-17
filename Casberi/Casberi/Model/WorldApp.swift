import Foundation

/// World App's money on World Chain, the pure half (prd §795, 2026-09-16):
/// the WLD Vault balance, the grant calendar, and a World App username.
/// Foundation-only, so `scripts/world-app-selftest.sh` compiles it whole;
/// every read lives in `WorldAppDeFi`.
///
/// Everything here was MEASURED against the live chain or World's own
/// published sources the same day — the notes say which.
enum WorldApp {

    static let network = "worldchain-mainnet"
    /// WLD on World Chain (World's "Useful Contract Deployments").
    static let wld = "0x2cfc85d8e48f8eab294be644d9e25c3030863003"
    /// World App's WLD savings vault (World's published list, and World App's
    /// own core, `worldcoin/bedrock` wld_legacy_vault.rs). Not an ERC-4626:
    /// `balanceOf(owner)` IS the owner's WLD, principal plus the yield that
    /// accrues block by block — bedrock reads it exactly that way. Measured:
    /// three recent depositors read 127.3, 99.98 and 39.5 WLD, and the
    /// Portfolio read showed none of it.
    static let wldVault = "0x14a028cc500108307947dca4a1aa35029fb66ce0"
    /// World's published `RecurringGrantDrop`; `grant()` names the contract
    /// that prices each grant (read live, never hardcoded).
    static let recurringGrantDrop = "0x2c1ca1fbbd5f28e5492cc6bf8c4e8c57354eb162"

    // MARK: - Calldata

    /// Selectors are computed off `Keccak256` at call time, never typed from
    /// memory (`WorldID`'s rule) — this file's first draft hardcoded two, and
    /// both were wrong; the harness pins all three against an outside keccak.
    static func selector(_ signature: String) -> String {
        Keccak256.hexString(Array(Keccak256.hash(Array(signature.utf8)).prefix(4)))
    }

    static func balanceOfCalldata(owner: String) -> String? {
        addressWord(owner).map { "0x" + selector("balanceOf(address)") + $0 }
    }

    static var grantCalldata: String { "0x" + selector("grant()") }

    static func getAmountCalldata(grantId: Int) -> String? {
        guard grantId >= 0 else { return nil }
        let hex = String(grantId, radix: 16)
        return "0x" + selector("getAmount(uint256)") + String(repeating: "0", count: 64 - hex.count) + hex
    }

    static func addressWord(_ address: String) -> String? {
        let a = address.lowercased()
        guard a.count == 42, a.hasPrefix("0x"), a.dropFirst(2).allSatisfy(\.isHexDigit) else { return nil }
        return String(repeating: "0", count: 24) + a.dropFirst(2)
    }

    // MARK: - Return words

    /// An 18-decimal token amount from a one-word `eth_call` return. Nil for
    /// anything that is not exactly one word — a revert, an empty `0x`, a
    /// truncated body — because a missing balance is not a zero balance.
    static func amount18(fromWord raw: String?) -> Double? {
        guard let raw, raw.hasPrefix("0x") else { return nil }
        let body = raw.dropFirst(2)
        guard body.count == 64, body.allSatisfy(\.isHexDigit) else { return nil }
        // Decimal arithmetic on the full 256-bit word: a Double read of the
        // raw integer loses nothing that matters at 18 decimals for a person's
        // balance, but the parse must not overflow a UInt64 (> 18.4 WLD).
        var value = 0.0
        for ch in body {
            value = value * 16 + Double(ch.hexDigitValue ?? 0)
        }
        return value / 1e18
    }

    /// The contract an address word names (`grant()`'s return).
    static func address(fromWord raw: String?) -> String? {
        guard let raw, raw.hasPrefix("0x"), raw.count == 66 else { return nil }
        let a = "0x" + raw.suffix(40).lowercased()
        return addressWord(a) == nil ? nil : a
    }

    // MARK: - The grant calendar

    /// World's `WLDGrant` numbers grants by calendar MONTH in UTC:
    /// `39 + months since August 2024`, and a grant stays claimable for its
    /// own month and the next (`activeGrants()` returns `(38+m, 39+m)`).
    /// MEASURED 2026-09-16: `checkValidity` passes for 63 and 64 only, and
    /// September 2026 is month 25.
    static func grantId(at date: Date) -> Int {
        let c = utc.dateComponents([.year, .month], from: date)
        let months = ((c.year ?? 2024) - 2024) * 12 + (c.month ?? 8) - 8
        return 39 + max(0, months)
    }

    /// When the next grant opens: the first instant of next month, UTC.
    static func nextGrantOpens(after date: Date) -> Date? {
        let c = utc.dateComponents([.year, .month], from: date)
        guard let start = utc.date(from: DateComponents(year: c.year, month: c.month, day: 1)) else { return nil }
        return utc.date(byAdding: .month, value: 1, to: start)
    }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // MARK: - Approval logs off Blockscout (prd §797)

    /// World Chain's Blockscout — its `module=logs&action=getLogs` answers an
    /// owner-filtered query across the WHOLE chain in one call (MEASURED:
    /// every approval a real World App wallet ever made, in one request),
    /// where the public RPCs cap `eth_getLogs` at 100 blocks and the app's
    /// Alchemy key at 10.
    static let blockscoutAPI = "https://worldchain-mainnet.explorer.alchemy.com/api"

    static func blockscoutLogsURL(address: String?, topic0: String, topic1: String,
                                  from: Int, to: Int) -> String {
        var url = blockscoutAPI + "?module=logs&action=getLogs"
            + "&fromBlock=\(from)&toBlock=\(to)"
            + "&topic0=\(topic0.lowercased())&topic1=\(topic1.lowercased())&topic0_1_opr=and"
        if let address { url += "&address=\(address.lowercased())" }
        return url
    }

    /// Blockscout's answer as `eth_getLogs` logs, or nil when it did not answer.
    /// Two shapes differ from a node's and both matter:
    /// - "No logs found" is `status: "0"` with an EMPTY result — an answer, not
    ///   a failure, so it is `[]` and the approval cursor may advance.
    /// - `topics` is padded to four with `null`. The approval parser reads the
    ///   topic COUNT to tell an ERC-20 grant (3) from an ERC-721 one (4), so
    ///   an unstripped pad would drop every real ERC-20 approval.
    static func blockscoutLogs(fromJSON object: Any?) -> [[String: Any]]? {
        guard let root = object as? [String: Any],
              let result = root["result"] as? [[String: Any]] else { return nil }
        let status = root["status"] as? String
        let message = (root["message"] as? String) ?? ""
        guard status == "1" || (result.isEmpty && message == "No logs found") else { return nil }
        return result.map { log in
            var out = log
            if let topics = log["topics"] as? [Any] {
                out["topics"] = topics.compactMap { $0 as? String }
            }
            return out
        }
    }

    // MARK: - Usernames

    /// A World App username and picture from World's public usernames service
    /// (`usernames.worldcoin.org/api/v1/<address>`, documented on World's
    /// "Usernames" page). A body that is not a record for THIS address — the
    /// service's `{"error":"Record not found."}`, or a record naming a
    /// different address — is nil, never a guess.
    struct Username: Equatable, Sendable, Codable {
        let name: String
        let pictureURL: String?
    }

    static func username(fromJSON object: Any?, for address: String) -> Username? {
        guard let dict = object as? [String: Any],
              let name = dict["username"] as? String, !name.isEmpty,
              let recordAddress = dict["address"] as? String,
              recordAddress.lowercased() == address.lowercased() else { return nil }
        let picture = (dict["minimized_profile_picture_url"] as? String)
            ?? (dict["profile_picture_url"] as? String)
        let safePicture = picture.flatMap { URL(string: $0)?.scheme == "https" ? $0 : nil }
        return Username(name: name, pictureURL: safePicture)
    }
}
