import Foundation
import SwiftData

/// Lightning (prd §1098) — a Lightning wallet read over Nostr Wallet Connect:
/// its balance into the Wallet's total, its settled payments as rows. Any
/// wallet that hands out an NWC connection (Alby Hub, Coinos, Primal, and
/// the rest) is one seat; the protocol is the door, so the seat is named for
/// the money, not for a product.
///
/// The connection string is the credential and lives in the Keychain only.
/// It is kept only when the wallet says the connection cannot pay
/// (`NostrWalletConnect.spendingMethods`), checked on save in
/// `LightningScreen`; nothing here ever sends a method but `get_balance` and
/// `list_transactions`.
enum LightningAuth {
    static var tokenVaultKey: String { TokenBridge.lightning.tokenKey }

    static var connection: NostrWalletConnect.Connection? {
        TokenVault.get(tokenVaultKey).flatMap(NostrWalletConnect.parse)
    }

    static var configured: Bool { connection != nil }

    static func clear() {
        TokenVault.delete(tokenVaultKey)
        LightningState.clear()
    }

    enum Outcome: Equatable {
        case kept
        /// Not a connection string; the sentence says what is missing.
        case malformed(String)
        case canPay
        case cannotRead
        case unreachable
        /// The wallet would not say what the connection may do.
        case undisclosed
    }

    /// Checks a pasted connection and keeps it only when it cannot pay — the
    /// one door both the account page and `-lightningConnect` go through.
    /// Nothing is stored on any other outcome, so a refused Replace leaves
    /// the working connection in place.
    @MainActor
    static func connect(_ raw: String) async -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let connection = NostrWalletConnect.parse(trimmed) else {
            return .malformed(NostrWalletConnect.looksLikeConnection(trimmed)
                ? String(localized: "That connection is missing its relay or secret. Copy the whole string.")
                : String(localized: "Paste the connection string that starts nostr+walletconnect://."))
        }
        switch await NostrWalletConnect.methods(connection) {
        case .success(let allowed):
            guard allowed.isDisjoint(with: NostrWalletConnect.spendingMethods) else { return .canPay }
            guard allowed.contains("get_balance") || allowed.contains("list_transactions") else {
                return .cannotRead
            }
            // A different wallet: nothing read with the old one carries over.
            if self.connection?.walletPubkey != connection.walletPubkey { LightningState.clear() }
            TokenVault.set(trimmed, for: tokenVaultKey)
            return .kept
        case .failure(.unreachable):
            return .unreachable
        case .failure:
            return .undisclosed
        }
    }

    static func sentence(_ outcome: Outcome) -> String? {
        switch outcome {
        case .kept: return nil
        case .malformed(let line): return line
        case .canPay:
            return String(localized: "That connection can pay. Make one with only Read balance and Read transactions.")
        case .cannotRead:
            return String(localized: "That connection can't read a balance or payments. Allow Read balance and Read transactions.")
        case .unreachable:
            return String(localized: "Couldn't reach the relay in that connection — check your connection.")
        case .undisclosed:
            return String(localized: "Your wallet didn't say what this connection can do, so it wasn't kept.")
        }
    }
}

/// The balance the last read found, beside its time — a state, never a row.
enum LightningState {
    private static let msatsKey = "lightning.balance.msats"
    private static let atKey = "lightning.balance.at"

    static func set(msats: Int) {
        UserDefaults.standard.set(msats, forKey: msatsKey)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: atKey)
    }

    static var balanceSats: Int? {
        guard UserDefaults.standard.object(forKey: msatsKey) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: msatsKey) / 1000
    }

    static var readAt: Date? {
        let t = UserDefaults.standard.double(forKey: atKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: msatsKey)
        UserDefaults.standard.removeObject(forKey: atKey)
    }
}

enum LightningIngest {
    static let source = "Lightning"

    @MainActor private static var running = false
    @MainActor static var lastPassFailure: String?

    /// One pass: the balance, then the newest payments. A payment lands once,
    /// when it has SETTLED — a pending invoice is not money yet, and a failed
    /// or expired one never was. nil when the wallet could not be reached.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard let connection = LightningAuth.connection, !running else { return running ? 0 : nil }
        running = true
        defer { running = false }
        lastPassFailure = nil

        switch await NostrWalletConnect.balanceMsats(connection) {
        case .success(let msats): LightningState.set(msats: msats)
        case .failure(let failure):
            lastPassFailure = sentence(failure)
            if failure == .unreachable { return nil }
        }

        let list: [NostrWalletConnect.Transaction]
        switch await NostrWalletConnect.transactions(connection) {
        case .success(let page): list = page
        case .failure(let failure):
            lastPassFailure = sentence(failure)
            return failure == .unreachable ? nil : 0
        }

        let existing = IngestSupport.existingSourceRefs(context, source: source)
        let price = await BitcoinBridge.priceUSD()
        let wallet = String(connection.walletPubkey.prefix(16))
        var landed: [Thing] = []
        for payment in list {
            guard isSettled(payment) else { continue }
            let ref = "lightning:\(wallet):\(payment.paymentHash)"
            guard !existing.contains(ref) else { continue }
            let sats = payment.amountMsats / 1000
            guard sats > 0 else { continue }
            let thing = Thing(kind: .transaction, title: title(payment),
                              content: "lightning:\(payment.paymentHash)", source: source,
                              capturedAt: payment.settledAt ?? payment.createdAt, sourceRef: ref)
            thing.transferDirection = payment.incoming ? "received" : "sent"
            thing.transferAmount = BitcoinBridge.formatAmount(sats: sats)
            thing.transferVenue = String(localized: "Lightning")
            if let price {
                thing.priceValue = Double(sats) / 100_000_000 * price
                thing.priceCurrency = "USD"
            }
            landed.append(thing)
        }
        guard !landed.isEmpty else { return 0 }
        for thing in landed {
            context.insert(thing)
            SpotlightIndex.index([thing])
        }
        return context.saveHonestly() ? landed.count : nil
    }

    /// A wallet older than NIP-47's `state` field lists settled payments only,
    /// and stamps `settled_at` on them.
    static func isSettled(_ p: NostrWalletConnect.Transaction) -> Bool {
        if let state = p.state { return state == "settled" }
        return p.settledAt != nil
    }

    /// The memo — "Coffee for Ana" — the payer's or payee's own words and the
    /// only name a Lightning payment carries; else which way it went. Never
    /// the amount: the row's trailing slot already stands it, signed, and a
    /// title carrying it too left no room for the memo.
    static func title(_ p: NostrWalletConnect.Transaction) -> String {
        guard let memo = p.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !memo.isEmpty, !memo.hasPrefix("{"), !memo.hasPrefix("[") else {
            return p.incoming ? String(localized: "Received over Lightning")
                              : String(localized: "Paid over Lightning")
        }
        return String(memo.prefix(80))
    }

    static func sentence(_ failure: NostrWalletConnect.Failure) -> String {
        switch failure {
        case .unreachable:
            return String(localized: "Couldn't reach your wallet's relay — check your connection.")
        case .unreadable:
            return String(localized: "Your wallet answered in a way that couldn't be read.")
        case .wallet(let code, let message):
            if code == "RESTRICTED" {
                return String(localized: "Your wallet didn't allow that. Give the connection Read balance and Read transactions.")
            }
            return message.isEmpty ? String(localized: "Your wallet said no (\(code)).")
                                   : String(localized: "Your wallet said: \(message)")
        }
    }
}

enum LightningWatch {
    @MainActor
    static func registerBridge(store: BridgeStore) {
        guard LightningAuth.configured else {
            store.remove(TokenBridge.lightning.bridgeID)
            return
        }
        store.registerConnected(id: TokenBridge.lightning.bridgeID, name: LightningIngest.source,
                                proof: String(localized: "Connected"))
    }
}
