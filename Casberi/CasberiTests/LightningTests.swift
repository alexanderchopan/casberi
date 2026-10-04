import Foundation
import Testing
@testable import Casberi

/// **A Lightning wallet over Nostr Wallet Connect** (prd §1098).
///
/// The wire format was checked end to end against an independent wallet and
/// relay (Python, coincurve + cryptography) that verified every event id and
/// signature this client produced and answered in NIP-04. These pin the parts
/// that can drift without a relay: the parse, the refusal set, which payments
/// count, and the title.
struct LightningTests {

    static let pubkey = String(repeating: "ab", count: 32)
    static let secret = String(repeating: "07", count: 32)

    @Test func aConnectionStringParses() throws {
        let raw = "nostr+walletconnect://\(Self.pubkey)?relay=wss%3A%2F%2Frelay.getalby.com%2Fv1&relay=wss://nos.lol&secret=\(Self.secret)&lud16=me%40getalby.com"
        let c = try #require(NostrWalletConnect.parse(raw))
        #expect(c.walletPubkey == Self.pubkey)
        #expect(c.relays == ["wss://relay.getalby.com/v1", "wss://nos.lol"])
        #expect(c.relayHosts == ["relay.getalby.com", "nos.lol"])
        #expect(c.secret == Self.secret)
        #expect(c.lud16 == "me@getalby.com")
    }

    @Test func anIncompleteStringIsNotAConnection() {
        #expect(NostrWalletConnect.parse("nostr+walletconnect://\(Self.pubkey)?secret=\(Self.secret)") == nil, "no relay")
        #expect(NostrWalletConnect.parse("nostr+walletconnect://\(Self.pubkey)?relay=wss://nos.lol") == nil, "no secret")
        #expect(NostrWalletConnect.parse("nostr+walletconnect://abc?relay=wss://nos.lol&secret=\(Self.secret)") == nil)
        #expect(NostrWalletConnect.parse("https://example.com") == nil)
        #expect(NostrWalletConnect.looksLikeConnection(" nostr+walletconnect://x"))
    }

    @Test func everyMethodThatPaysIsRefused() {
        #expect(NostrWalletConnect.spendingMethods
                == ["pay_invoice", "multi_pay_invoice", "pay_keysend", "multi_pay_keysend"])
        #expect(!NostrWalletConnect.spendingMethods.contains("make_invoice"),
                "an invoice asks to be paid; it cannot spend")
    }

    @Test func nip04RoundTripsAndSharesOneSecret() throws {
        let a = NostrWalletConnect.hexBytes(String(repeating: "11", count: 32))
        let b = NostrWalletConnect.hexBytes(String(repeating: "22", count: 32))
        let aPub = try #require(try? P256KTestKey.xonly(a))
        let bPub = try #require(try? P256KTestKey.xonly(b))
        let ab = try #require(NostrWalletConnect.sharedSecret(secret: a, peer: bPub))
        let ba = try #require(NostrWalletConnect.sharedSecret(secret: b, peer: aPub))
        #expect(ab == ba, "ECDH agrees from both sides")
        let sealed = try #require(NostrWalletConnect.nip04Encrypt(#"{"method":"get_balance"}"#, key: ab))
        #expect(sealed.contains("?iv="))
        #expect(NostrWalletConnect.nip04Decrypt(sealed, key: ba) == #"{"method":"get_balance"}"#)
    }

    @Test func anEventIDKeepsItsSlashes() throws {
        let id = try #require(NostrWalletConnect.eventID(pubkey: Self.pubkey, created: 1, kind: 23194,
                                                         tags: [["p", Self.pubkey]], content: "a/b+c=?iv=d/e"))
        // SHA-256 of the NIP-01 serialisation with the slashes left alone.
        let expected = #"[0,"\#(Self.pubkey)",1,23194,[["p","\#(Self.pubkey)"]],"a/b+c=?iv=d/e"]"#
        #expect(id == Array(SHA256Digest.of(expected)))
    }

    @Test func onlySettledPaymentsLand() {
        func t(_ state: String?, settled: Date?) -> NostrWalletConnect.Transaction {
            .init(incoming: true, amountMsats: 1000, feesMsats: 0, description: nil,
                  paymentHash: "x", createdAt: .now, settledAt: settled, state: state)
        }
        #expect(LightningIngest.isSettled(t("settled", settled: .now)))
        #expect(!LightningIngest.isSettled(t("pending", settled: nil)))
        #expect(!LightningIngest.isSettled(t("failed", settled: nil)))
        #expect(!LightningIngest.isSettled(t("expired", settled: nil)))
        #expect(LightningIngest.isSettled(t(nil, settled: .now)), "a wallet older than `state`")
        #expect(!LightningIngest.isSettled(t(nil, settled: nil)))
    }

    @Test func aPaymentIsTitledByItsMemo() {
        func t(_ incoming: Bool, _ msats: Int, _ memo: String?) -> NostrWalletConnect.Transaction {
            .init(incoming: incoming, amountMsats: msats, feesMsats: 0, description: memo,
                  paymentHash: "x", createdAt: .now, settledAt: .now, state: "settled")
        }
        #expect(LightningIngest.title(t(true, 21_000_000, "Coffee for Ana")) == "Coffee for Ana")
        #expect(LightningIngest.title(t(false, 2_100_000_000, "")) == "Paid over Lightning")
        #expect(LightningIngest.title(t(true, 5_000, #"[["text/plain","zap"]]"#)) == "Received over Lightning",
                "LNURL metadata is not a memo")
    }
}

import CryptoKit
import P256K

private enum P256KTestKey {
    static func xonly(_ secret: [UInt8]) throws -> String {
        NostrWalletConnect.hex(try P256K.Schnorr.PrivateKey(dataRepresentation: secret).xonly.bytes)
    }
}

private enum SHA256Digest {
    static func of(_ s: String) -> [UInt8] { Array(SHA256.hash(data: Data(s.utf8))) }
}
