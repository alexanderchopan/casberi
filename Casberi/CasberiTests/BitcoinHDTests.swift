import Foundation
import Testing
@testable import Casberi

/// **A wallet's addresses, derived from its public key** (prd §1097).
///
/// Every vector below is published in the BIP that defines its script, for the
/// same seed ("abandon" ×11, "about"). A derivation that is wrong in any step
/// — the HMAC, the point tweak, HASH160, the bech32m checksum, the Taproot
/// tweak — produces a valid-LOOKING address that belongs to nobody, and the
/// watch then reads an empty wallet with total confidence. Only a vector says
/// otherwise.
struct BitcoinHDTests {

    static let zpub84 = "zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs"
    static let xpub86 = "xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ"
    static let ypub49 = "ypub6Ww3ibxVfGzLrAH1PNcjyAWenMTbbAosGNB6VvmSEgytSER9azLDWCxoJwW7Ke7icmizBMXrzBx9979FfaHxHcrArf3zbeJJJUZPf663zsP"
    static let xpub44 = "xpub6BosfCnifzxcFwrSzQiqu2DBVTshkCXacvNsWGYJVVhhawA7d4R5WSWGFNbi8Aw6ZRc1brxMyWMzG3DSSSSoekkudhUd9yLb6qx39T9nMdj"

    /// The same key under another version prefix — how a descriptor's `xpub`
    /// and a private-key paste are built here without a second vector.
    static func reversioned(_ key: String, _ version: [UInt8]) -> String {
        let payload = BitcoinAddress.base58CheckDecode(key)!
        return BitcoinAddress.base58Check(version + payload.dropFirst(4))
    }

    @Test func ripemd160MatchesItsPublishedVectors() {
        func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
        #expect(hex(RIPEMD160.hash([])) == "9c1185a5c5e9fc54612808977ee8f548b2258d31")
        #expect(hex(RIPEMD160.hash(Array("abc".utf8))) == "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc")
        #expect(hex(RIPEMD160.hash(Array("message digest".utf8))) == "5d0689ef49d2fae572b881b123a85ffa21595f36")
        // 56 bytes: the padding crosses into a second block.
        #expect(hex(RIPEMD160.hash(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)))
                == "12a053384a9c0c88e405a06c27dcf49ada62eb2b")
    }

    @Test func zpubDerivesBIP84() throws {
        let w = try #require(BitcoinHD.parse(Self.zpub84))
        #expect(w.scripts == [.wpkh])
        #expect(w.branches == [[0], [1]])
        #expect(BitcoinHD.address(w, script: .wpkh, branch: [0], index: 0) == "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
        #expect(BitcoinHD.address(w, script: .wpkh, branch: [0], index: 1) == "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g")
        #expect(BitcoinHD.address(w, script: .wpkh, branch: [1], index: 0) == "bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el")
    }

    @Test func taprootDerivesBIP86() throws {
        let w = try #require(BitcoinHD.parse("tr(\(Self.xpub86)/<0;1>/*)"))
        #expect(w.scripts == [.tr])
        #expect(BitcoinHD.address(w, script: .tr, branch: [0], index: 0) == "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr")
        #expect(BitcoinHD.address(w, script: .tr, branch: [0], index: 1) == "bc1p4qhjn9zdvkux4e44uhx8tc55attvtyu358kutcqkudyccelu0was9fqzwh")
        #expect(BitcoinHD.address(w, script: .tr, branch: [1], index: 0) == "bc1p3qkhfews2uk44qtvauqyr2ttdsw7svhkl9nkm9s9c3x4ax5h60wqwruhk7")
    }

    @Test func ypubAndLegacyDeriveBIP49AndBIP44() throws {
        let y = try #require(BitcoinHD.parse(Self.ypub49))
        #expect(y.scripts == [.shWpkh])
        #expect(BitcoinHD.address(y, script: .shWpkh, branch: [0], index: 0) == "37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf")
        let x = try #require(BitcoinHD.parse(Self.xpub44))
        #expect(x.scripts == BitcoinHD.Script.allCases, "a bare xpub names no script")
        #expect(BitcoinHD.address(x, script: .pkh, branch: [0], index: 0) == "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA")
    }

    @Test func derivedAddressesPassTheirOwnChecksum() throws {
        let x = try #require(BitcoinHD.parse(Self.xpub44))
        for script in BitcoinHD.Script.allCases {
            let a = try #require(BitcoinHD.address(x, script: script, branch: [0], index: 7))
            #expect(BitcoinAddress.isAddress(a), "\(script) produced \(a)")
            #expect(BitcoinAddress.scriptKind(a) == script.kind)
        }
    }

    @Test func descriptorsNameTheirScriptAndBranches() throws {
        let xpub = Self.reversioned(Self.zpub84, [0x04, 0x88, 0xB2, 0x1E])
        let both = try #require(BitcoinHD.parse("wpkh([73c5da0a/84h/0h/0h]\(xpub)/<0;1>/*)#8zl0zxma"))
        #expect(both.scripts == [.wpkh])
        #expect(both.branches == [[0], [1]])
        #expect(BitcoinHD.address(both, script: .wpkh, branch: [0], index: 0) == "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
        let receive = try #require(BitcoinHD.parse("wpkh(\(xpub)/0/*)"))
        #expect(receive.branches == [[0]])
        // A ypub inside wpkh() contradicts itself; one address is not a wallet;
        // a hardened step cannot be derived from a public key.
        #expect(BitcoinHD.parse("wpkh(\(Self.ypub49)/0/*)") == nil)
        #expect(BitcoinHD.parse("wpkh(\(xpub)/0/5)") == nil)
        #expect(BitcoinHD.parse("wpkh(\(xpub)/0h/*)") == nil)
        #expect(BitcoinHD.parse("\(xpub)/0/*") == nil)
    }

    @Test func aPrivateKeyIsRefusedWithASentence() {
        // The zpub's own payload under xprv's version, with a private-key
        // byte layout (0x00 ‖ 32 bytes) — a real-shaped xprv, built here.
        var payload = BitcoinAddress.base58CheckDecode(Self.zpub84)!
        payload.replaceSubrange(0..<4, with: [0x04, 0x88, 0xAD, 0xE4])
        payload.replaceSubrange(45..<78, with: [0x00] + [UInt8](repeating: 7, count: 32))
        let xprv = BitcoinAddress.base58Check(payload)
        #expect(xprv.hasPrefix("xprv"))
        #expect(BitcoinHD.parse(xprv) == nil)
        #expect(BitcoinHD.refusal(xprv)?.contains("private key") == true)
        #expect(BitcoinHD.refusal("wpkh([73c5da0a/84h/0h/0h]\(xprv)/0/*)")?.contains("private key") == true)
        #expect(BitcoinHD.refusal(Self.zpub84) == nil)
        #expect(BitcoinHD.refusal("bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu") == nil)
    }

    @Test func multisigAndTestnetAreRefusedNotSwallowed() {
        let xpub = Self.reversioned(Self.zpub84, [0x04, 0x88, 0xB2, 0x1E])
        #expect(BitcoinHD.refusal("wsh(sortedmulti(2,\(xpub)/0/*,\(xpub)/1/*))")?.contains("Multisig") == true)
        let tpub = Self.reversioned(Self.zpub84, [0x04, 0x35, 0x87, 0xCF])
        #expect(tpub.hasPrefix("tpub"))
        #expect(BitcoinHD.parse(tpub) == nil)
        #expect(BitcoinHD.refusal(tpub)?.contains("testnet") == true)
    }

    @Test func aWalletIsNotMistakenForAnotherFamily() {
        #expect(!BitcoinAddress.isAddress(Self.zpub84))
        #expect(!SNS.isAddress(Self.zpub84))
        #expect(!ENS.isHexAddress(Self.zpub84))
        #expect(BitcoinAddress.isWatchable(Self.zpub84))
        #expect(BitcoinAddress.isWatchable("bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"))
        #expect(BitcoinHD.fingerprint(Self.zpub84) == BitcoinHD.fingerprint(" \(Self.zpub84)\n"))
        #expect(!BitcoinHD.fingerprint(Self.zpub84).contains("zpub"))
    }
}

/// **A wallet's own change is not a payment** (prd §1097) — the failure §226's
/// one-address read shipped: 0.01 BTC sent out of a 0.5 BTC piece read as
/// "Sent 0.5 BTC", and the change address was named as the recipient.
struct BitcoinUnitAccountingTests {

    static let spender = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
    static let change = "bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el"
    static let payee = "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g"

    static func tx(ins: [(String, Int)], outs: [(String?, Int)]) -> [String: Any] {
        [
            "txid": "ab",
            "vin": ins.map { ["prevout": ["scriptpubkey_address": $0.0, "value": $0.1]] },
            "vout": outs.map { out -> [String: Any] in
                guard let a = out.0 else { return ["scriptpubkey_type": "op_return", "value": out.1] }
                return ["scriptpubkey_address": a, "value": out.1]
            },
        ]
    }

    /// 0.5 BTC in; 0.01 BTC to the payee, the rest back as change, a 10k fee.
    static let spend = tx(ins: [(spender, 50_000_000)],
                          outs: [(payee, 1_000_000), (change, 48_990_000)])

    @Test func oneAddressReadsTheWholeCoinAsSpent() {
        let owned: Set<String> = [Self.spender]
        #expect(BitcoinBridge.netSats(tx: Self.spend, owned: owned) == -50_000_000)
        #expect(BitcoinBridge.counterparty(tx: Self.spend, owned: owned, received: false) == Self.change,
                "the old read names the change as the recipient — the bug a wallet fixes")
    }

    @Test func theWalletReadsWhatActuallyLeft() {
        let owned: Set<String> = [Self.spender, Self.change]
        #expect(BitcoinBridge.netSats(tx: Self.spend, owned: owned) == -1_010_000)
        #expect(BitcoinBridge.counterparty(tx: Self.spend, owned: owned, received: false) == Self.payee)
        #expect(!BitcoinBridge.isInternal(Self.spend, owned: owned))
    }

    @Test func aMoveBetweenYourOwnAddressesPaysNobody() {
        let move = Self.tx(ins: [(Self.spender, 20_000)], outs: [(Self.change, 19_000), (nil, 0)])
        #expect(BitcoinBridge.isInternal(move, owned: [Self.spender, Self.change]))
        #expect(!BitcoinBridge.isInternal(move, owned: [Self.spender]))
    }

    @Test func caseFoldsForBech32Only() {
        #expect(BitcoinBridge.norm("BC1QCR8TE4KR609GCAWUTMRZA0J4XV80JY8Z306FYU") == Self.spender)
        #expect(BitcoinBridge.norm("1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA") == "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA")
        // Keys an address wrote before wallets existed are unchanged.
        #expect(BitcoinBridge.unitKey("BC1QCR8TE4KR609GCAWUTMRZA0J4XV80JY8Z306FYU") == Self.spender)
        #expect(BitcoinBridge.unitKey(BitcoinHDTests.zpub84).hasPrefix("hd-"))
    }

    @Test func aWaitingSendSaysBothNumbersAndWhichWayTheyFall() {
        #expect(BitcoinBridge.waitingTitle(paid: 3, need: 12)
                == "Your send is waiting — it paid 3 sat/vB, and the next hour needs 12")
        #expect(BitcoinBridge.waitingTitle(paid: 2.5, need: 2).contains("enough for the next hour"))
    }

    @Test func aKeysKindIsReadOffItsSpelling() {
        #expect(BitcoinHD.kindWord(BitcoinHDTests.zpub84) == "Bitcoin wallet · Native SegWit")
        #expect(BitcoinHD.kindWord("tr(\(BitcoinHDTests.xpub86)/<0;1>/*)") == "Bitcoin wallet · Taproot")
        #expect(BitcoinHD.kindWord(BitcoinHDTests.xpub44) == "Bitcoin wallet")
        #expect(BitcoinHD.kindWord(Self.spender) == nil)
    }
}
