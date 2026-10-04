import Foundation
import Testing
@testable import Casberi

/// **Solana's activity read, past §86** (prd §1096): SPL delegates read as
/// grants, the venue table, and the base58 rules the name reads keep. Every
/// wrong answer here is a confident row: a grant nobody made, a delegate
/// dropped, a swap "on Orca" that ran on Raydium.
@MainActor
struct SolanaActivityTests {

    private static let owner = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
    private static let delegate = "4aR1CeodjCPyyuVDbhP1yd2xPX6H6A2fZ7bApXyVmCrY"
    private static let tokenAccount = "AySmhNYLeRMLyv7i3bCGhUq2hydGyv8otaMTuGNCfwUh"
    private static let usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    private static let pda = "81aCXrx1HhTu7CBZXXvG9SGeNfV38L2sf64LTBphrSDL"

    /// A jsonParsed `getTransaction` result in the shape the RPC returns for
    /// legacy, v0 and v1 alike: the owner at index 0 (the fee payer), the
    /// token account at index 1, its balances recorded either side.
    private static func tx(signedBy signer: String = owner,
                           top: [[String: Any]] = [], inner: [[String: Any]] = [],
                           balances: Bool = true) -> [String: Any] {
        let keys: [[String: Any]] = [
            ["pubkey": signer, "signer": true, "writable": true],
            ["pubkey": tokenAccount, "signer": false, "writable": true],
        ]
        let balance: [String: Any] = [
            "accountIndex": 1, "mint": usdc, "owner": owner,
            "uiTokenAmount": ["amount": "5000000", "decimals": 6, "uiAmount": 5.0],
        ]
        return [
            "meta": [
                "fee": 5000.0,
                "preBalances": [1_000_000_000.0, 2_039_280.0],
                "postBalances": [999_995_000.0, 2_039_280.0],
                "preTokenBalances": balances ? [balance] : [],
                "postTokenBalances": balances ? [balance] : [],
                "innerInstructions": inner.isEmpty ? [] : [["index": 0, "instructions": inner]],
            ] as [String: Any],
            "transaction": ["message": ["accountKeys": keys, "instructions": top]],
        ]
    }

    private static func approve(owner: String = owner, amount: String = "250000000",
                                checked: Bool = false) -> [String: Any] {
        var info: [String: Any] = ["delegate": delegate, "owner": owner, "source": tokenAccount]
        if checked {
            info["mint"] = usdc
            info["tokenAmount"] = ["amount": amount, "decimals": 6]
        } else {
            info["amount"] = amount
        }
        return ["program": "spl-token", "programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
                "parsed": ["type": checked ? "approveChecked" : "approve", "info": info]]
    }

    private static func revoke() -> [String: Any] {
        ["program": "spl-token", "programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
         "parsed": ["type": "revoke", "info": ["owner": owner, "source": tokenAccount]]]
    }

    private static func move(_ tx: [String: Any]) -> SolanaActivity.Move? {
        SolanaActivity.derive(tx: tx, signature: "sig", address: owner, when: .now)
    }

    // MARK: - Grants

    @Test func aSignedApproveIsAGrant() throws {
        let m = try #require(Self.move(Self.tx(top: [Self.approve(checked: true)])))
        let g = try #require(m.grants.first)
        #expect(m.grants.count == 1)
        #expect(g.tokenAccount == Self.tokenAccount && g.delegate == Self.delegate)
        #expect(g.mint == Self.usdc && g.decimals == 6 && g.amountRaw == 250_000_000)
        #expect(!g.unlimited)
    }

    /// Plain `approve` names no mint; the balances recorded for the same
    /// token account do.
    @Test func aPlainApproveTakesItsMintFromTheBalances() throws {
        let g = try #require(Self.move(Self.tx(top: [Self.approve()]))?.grants.first)
        #expect(g.mint == Self.usdc && g.decimals == 6)
    }

    @Test func u64MaxIsUnlimited() throws {
        let g = try #require(Self.move(Self.tx(top: [Self.approve(amount: "18446744073709551615")]))?.grants.first)
        #expect(g.unlimited)
    }

    /// A delegate set for one hop and cleared before the transaction ends
    /// leaves nothing standing.
    @Test func aRevokeInTheSameTransactionCancels() throws {
        let m = try #require(Self.move(Self.tx(top: [Self.approve()], inner: [Self.revoke()])))
        #expect(m.grants.isEmpty)
    }

    /// The inner instructions count: a program can approve on the owner's
    /// signature through a CPI.
    @Test func anInnerApproveCounts() throws {
        let m = try #require(Self.move(Self.tx(inner: [Self.approve(checked: true)])))
        #expect(m.grants.count == 1)
    }

    /// A program approving on its OWN token account (measured: every inner
    /// approve in 60 recent blocks had a PDA owner) is not this wallet's grant.
    @Test func someoneElsesApproveIsNotAGrant() throws {
        let m = try #require(Self.move(Self.tx(top: [Self.approve(owner: Self.pda)])))
        #expect(m.grants.isEmpty)
    }

    /// A transaction the wallet did not sign cannot have granted for it.
    @Test func anUnsignedTransactionGrantsNothing() throws {
        let m = try #require(Self.move(Self.tx(signedBy: Self.pda, top: [Self.approve()])))
        #expect(!m.signed && m.grants.isEmpty)
    }

    @Test func aZeroApproveIsNotAGrant() throws {
        let m = try #require(Self.move(Self.tx(top: [Self.approve(amount: "0")])))
        #expect(m.grants.isEmpty)
    }

    /// The EVM sentence, word for word, so one catalog key serves both chains.
    @Test func aGrantReadsLikeAnApproval() throws {
        let g = try #require(Self.move(Self.tx(top: [Self.approve(amount: "18446744073709551615")]))?.grants.first)
        #expect(SolanaActivity.grantTitle(g, symbols: [Self.usdc: "USDC"])
                == "Approved …mCrY to spend unlimited USDC")
        let capped = try #require(Self.move(Self.tx(top: [Self.approve(checked: true)]))?.grants.first)
        #expect(SolanaActivity.grantTitle(capped, symbols: [Self.usdc: "USDC"])
                == "Approved …mCrY to spend 250.00 USDC")
    }

    /// A grant lands even when its token cannot be named.
    @Test func anUnnamedTokenStillTitlesTheGrant() throws {
        let g = try #require(Self.move(Self.tx(top: [Self.approve()]))?.grants.first)
        #expect(SolanaActivity.grantTitle(g, symbols: [:]).hasSuffix("…Dt1v"))
    }

    @Test func aSolanaGrantWearsTheGrantMark() {
        #expect(WalletActionMark.isApprovalRef("wallet:sol-approval:sig:\(Self.tokenAccount)"))
        #expect(!WalletPrepare.applies(to: Thing(kind: .transaction, title: "t", content: "",
                                                 source: "Wallet", capturedAt: .now,
                                                 sourceRef: "wallet:sol-approval:sig:acct")))
    }

    // MARK: - Venues

    /// `CAMMCzo5…` is Raydium's concentrated pools; the table had it as Orca.
    @Test func raydiumClmmIsRaydium() throws {
        let swap: [String: Any] = ["programId": "CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK"]
        let m = try #require(Self.move(Self.tx(top: [swap])))
        #expect(m.venue == "Raydium")
    }

    /// The aggregator is named over the pool it routed through: top level first.
    @Test func theTopLevelProgramNamesTheVenue() throws {
        let jupiter: [String: Any] = ["programId": "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4"]
        let orca: [String: Any] = ["programId": "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc"]
        let m = try #require(Self.move(Self.tx(top: [jupiter], inner: [orca])))
        #expect(m.venue == "Jupiter")
    }

    // MARK: - Names

    /// Base58's case is the address: a record for a case-twin is someone else.
    @Test func base58OwnershipKeepsCase() {
        let record = Web3Bio.Record(platform: .sns, identity: "toly.sol",
                                    address: Self.owner, displayName: nil, avatar: nil)
        #expect(Web3Bio.names([record], ownedBy: Self.owner).count == 1)
        #expect(Web3Bio.names([record], ownedBy: Self.owner.lowercased()).isEmpty)
    }

    @Test func theCacheKeepsABase58AddressAsSpelled() {
        #expect(Web3Bio.cacheKey(Self.owner) == Self.owner)
        #expect(Web3Bio.cacheKey("Toly.SOL") == "toly.sol")
        #expect(Web3Bio.cacheKey("0xABC0000000000000000000000000000000000001")
                == "0xabc0000000000000000000000000000000000001")
    }
}
