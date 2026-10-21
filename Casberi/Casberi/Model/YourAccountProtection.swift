import Foundation
import Observation

/// **WHERE YOUR MONEY IS NOT YET COVERED BY THE RECOVERY KEY (prd §1442m).**
///
/// Your account exists on a network only after its first operation there,
/// only the iPhone that made it can make that operation (§1442k), and the
/// recovery key goes on network by network (§1427). So money sent to a
/// network the account was never opened on can be moved by one phone only,
/// and lost with it (measured 2026-10-20: ~$1 of ETH on Robinhood Chain).
///
/// Opening a network costs a fee in its own coin and a Face ID, so it is
/// never done behind your back: this reads, after each foreground sweep,
/// which networks hold money without the recovery key and can be fixed from
/// this phone, and the Wallet's Needs you asks (`RecoveryKeyNudge`). Security's
/// recovery row does the work (`MoveSecurity`'s Finish, `addRecovery`).
@MainActor @Observable
final class YourAccountProtection {
    typealias Op = YourAccountOp

    /// Observed, so Needs you draws the row the moment a check finds it.
    static let shared = YourAccountProtection()
    private(set) var ids: [Int] = UserDefaults.standard.array(forKey: storeKey) as? [Int] ?? []

    private static let storeKey = "yourAccount.unprotected"
    private static var lastCheck: Date?
    private static var checking = false

    /// The networks to ask about, in the account's network order.
    static var unprotected: [Op.Network] {
        let ids = Set(shared.ids)
        return Op.networks.filter { ids.contains($0.chainId) }
    }

    /// Drawn at all: an account here, and a network to protect.
    static var shown: Bool { YourAccountKey.address != nil && !unprotected.isEmpty }

    /// Money, for this rule: the network's own coin in any amount (it pays the
    /// fee, and it is never spam), or a token the Wallet prices at a cent or
    /// more. An unpriced token is what spam looks like, and is not a reason
    /// to spend a fee.
    nonisolated static func holdsMoney(_ held: [YourAccountTokens.Held]) -> Bool {
        held.contains { h in
            guard (Double(h.units) ?? 0) > 0 else { return false }
            return h.token.contract == nil || (h.usd ?? 0) >= 0.01
        }
    }

    /// Read every live network again; at most every ten minutes unless forced.
    static func check(force: Bool = false) async {
        guard let account = YourAccountKey.address, !checking else { return }
        #if DEBUG
        if previewing { return }
        #endif
        if !force, let lastCheck, Date.now.timeIntervalSince(lastCheck) < 600 { return }
        checking = true
        defer { checking = false }
        lastCheck = .now
        // No recovery key yet: every network with money wants one.
        var signer: String?
        if let key = YourAccountRecovery.publicKey(for: account) {
            signer = try? await YourAccountChain.recoverySigner(x: key.x, y: key.y)
            // A key we could not look up is an outage, not a missing key:
            // the last answer stands.
            guard signer != nil else { return }
        }
        let origin = YourAccountKey.holdsOrigin
        var found: [Int] = []
        for net in Op.networks where !net.isTest {
            guard holdsMoney(await YourAccountTokens.held(account, on: net)),
                  let deployed = try? await YourAccountChain.isDeployed(net, account) else { continue }
            if deployed {
                // This phone fixes it only where it signs.
                guard let x = try? await YourAccountChain.configuredX(net, account),
                      let i = YourAccountKey.index(matchingX: x), YourAccountKey.holds(i) else { continue }
                if let signer {
                    guard let state = try? await YourAccountChain.recoveryState(net, account, signer: signer) else { continue }
                    if state == .added { continue }
                }
            } else {
                // Not there yet: only the phone that made the account opens it.
                guard origin else { continue }
            }
            found.append(net.chainId)
        }
        UserDefaults.standard.set(found, forKey: storeKey)
        if shared.ids != found { shared.ids = found }
        #if DEBUG
        NSLog("yourAccountProtection| unprotected=%@", unprotected.map(\.name).joined(separator: ","))
        #endif
    }

    #if DEBUG
    /// `-recoveryNudgePreview "<chainId,…>"`: draw the row for these networks
    /// and stop checking, to look at it on a phone that is not the one that
    /// made the account (the only phone the row can really appear on).
    private static var previewing = false
    static func preview(_ ids: [Int]) {
        previewing = true
        shared.ids = ids
    }
    #endif
}
