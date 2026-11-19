import Foundation

/// Who sent a transaction, kept: "network|hash|wallet" → the wallet acted in
/// it. The fake-transfer rule's third half (`WalletSafety.isFakeOutboundTransfer`)
/// asks a receipt, and a receipt never changes, so each is asked once per phone.
///
/// Only an ANSWER is kept. A receipt nobody could read is absent, and is asked
/// again next pass.
@MainActor
final class SendVerdicts {
    static let shared = SendVerdicts()

    private static let key = "wallet.sendVerdicts.v1"
    /// Past this the store starts over: every entry can be read again.
    private static let cap = 2_000

    private var verdicts: [String: Bool]
    private var dirty = false

    private init() {
        verdicts = (UserDefaults.standard.data(forKey: Self.key))
            .flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
    }

    subscript(key: String) -> Bool? {
        get { verdicts[key] }
        set {
            guard verdicts[key] != newValue else { return }
            if verdicts.count >= Self.cap { verdicts.removeAll() }
            verdicts[key] = newValue
            dirty = true
        }
    }

    /// Through `DefaultsWrite`, off the main thread (prd §721).
    func save() {
        guard dirty, let data = try? JSONEncoder().encode(verdicts) else { return }
        dirty = false
        DefaultsWrite.set(data, forKey: Self.key)
    }
}
