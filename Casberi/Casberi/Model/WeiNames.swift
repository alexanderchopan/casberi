import Foundation

/// The Wei and Gwei name services (prd §597, 2026-09-04) — `ENS`'s and `SNS`'s
/// third and fourth sibling, and the first two this app reads STRAIGHT OFF A
/// CONTRACT rather than through somebody's resolver API.
///
/// `.wei` is the Wei Name Service (WNS, Feb 2026); `.gwei` is the Gwei Name
/// Service (GNS), an ownerless fork of it. Both are single immutable ERC-721
/// registries on Ethereum mainnet with a byte-identical read surface, so one
/// set of encoders serves both and a third registry of the same shape is a
/// `Registry` case and nothing else.
///
/// **This file is Foundation-only BY DESIGN** (`Keccak256` aside, which is
/// itself pure) so `scripts/wei-names-selftest.sh` compiles it WHOLE and
/// unmodified. Every read lives in `WeiNamesSource`. That split is not
/// tidiness: nothing on this host can register a name, so the harness is the
/// only proof these encodings are right, and it can only be that proof if it
/// compiles the bytes the app actually runs.
///
/// **MEASURED 2026-09-04** against both contracts on four public mainnet
/// hosts, and re-measure before changing any of it:
///
///   • `vitalik.wei` → `0xd8dA…6045`, `z0r0z.wei` → `0x1c0a…5a20`,
///     `donnoh.gwei` → `0xc046…f1a3`, `alice.gwei` → `0xdc10…f86a`;
///   • `reverseResolve` answers `ross.wei` for `0x1c0a…5a20` and
///     `donnoh.gwei` for `0xc046…f1a3`, and both round-trip;
///   • **an unregistered name has a perfectly good token id.** `alice.wei`
///     and `a.wei` both compute a large non-zero id and then resolve to the
///     ZERO ADDRESS. The reference client's own comment says GNS answers id
///     `0` for names it has never seen; measured, it does not —
///     `zzqqxxnobodyhasthis.gwei` computes a real id too. So the zero address
///     is the ONLY unregistered test on either registry, which is what
///     `address(from:)` refuses on and why it refuses rather than returning a
///     string the caller might believe;
///   • the contracts normalise case themselves (`vitalik.wei`, `Vitalik.wei`
///     and `VITALIK.WEI` compute one id), so `canonical`'s lowercasing is
///     OURS, for cache keying — never rely on it for correctness;
///   • neither contract is `ERC721Enumerable`: `tokenOfOwnerByIndex` and
///     `totalSupply` both revert, while `balanceOf` answers (79 `.wei` names
///     for `0x1c0a…5a20`). So the names an address HOLDS cannot be listed
///     on-chain — only the one it chose to be called. See `WeiNamesSource`.
enum WeiNames {

    /// One registry. Adding a third of the same shape is a case here and
    /// nothing else — the encoders below name no registry at all.
    enum Registry: String, CaseIterable, Sendable {
        case wns
        case gns

        /// The suffix this registry claims, WITH its dot. The dot is the whole
        /// of the rule: `alice.gwei` ends in `wei`, and a registry matched on
        /// the bare word would take every GNS name for a WNS one, resolve it
        /// against the wrong contract, and answer with a confident nothing.
        var suffix: String {
            switch self {
            case .wns: return ".wei"
            case .gns: return ".gwei"
            }
        }

        /// Ethereum mainnet, immutable. GNS carries the same address on
        /// Sepolia; this app only ever asks mainnet.
        var contract: String {
            switch self {
            case .wns: return "0x0000000000696760E15f265e828DB644A0c242EB"
            case .gns: return "0x9D51D507BC7264d4fE8Ad1cf7Fe191933A0a81d6"
            }
        }

        /// The label a reach row wears above the name. Deliberately the SHORT
        /// form — the card's rows say "Wei" the way they say "Bluesky", and
        /// the row beneath carries the name itself, which already ends in the
        /// suffix that spells it out.
        var label: String {
            switch self {
            case .wns: return String(localized: "Wei")
            case .gns: return String(localized: "Gwei")
            }
        }

        /// The service's own name, for copy that has room to be explicit.
        var serviceName: String {
            switch self {
            case .wns: return String(localized: "Wei Name Service")
            case .gns: return String(localized: "Gwei Name Service")
            }
        }
    }

    /// The registry claiming this name, or nil when none does.
    ///
    /// UNORDERED, and that is a claim about the suffixes rather than laziness:
    /// `suffixesAreUnambiguous` below is what makes at most one case match, and
    /// the harness asserts it. A first cut sorted longest-first as a belt, and
    /// the mutation pass proved the belt untestable — with the leading dot
    /// required, `.gwei` cannot be confused for `.wei` under ANY order, so the
    /// sort was code no fixture could ever exercise. The precondition it was
    /// standing in for is checkable, so it is checked instead.
    static func registry(claiming name: String) -> Registry? {
        let value = canonical(name)
        return Registry.allCases
            .first { value.hasSuffix($0.suffix) && value.count > $0.suffix.count }
    }

    /// No registry's suffix may END WITH another's — the precondition that
    /// makes `registry(claiming:)` order-independent.
    ///
    /// `.wei` and `.gwei` satisfy it because of the dot: `.gwei` does not end
    /// in `.wei`. A registry added later with a SUBNAME-shaped suffix
    /// (`.x.wei` beside `.wei`) would break it, and would then need the match
    /// ordered longest-first — so this is asserted rather than assumed.
    /// Taken as a LIST rather than read off `Registry` directly so a test can
    /// hand it a bad pair. Asserting only over the real cases proves the
    /// registries shipped today are fine and says nothing about whether the
    /// check works — it returns true either way, which the mutation pass
    /// caught: a fixture only tests the rule it names if it FAILS that rule.
    static func suffixesAreUnambiguous(_ suffixes: [String]) -> Bool {
        for (i, a) in suffixes.enumerated() {
            for (j, b) in suffixes.enumerated() where i != j {
                if a.hasSuffix(b) { return false }
            }
        }
        return true
    }

    static var suffixesAreUnambiguous: Bool {
        suffixesAreUnambiguous(Registry.allCases.map(\.suffix))
    }

    /// True when either registry claims this string.
    ///
    /// The `count > suffix.count` guard in `registry(claiming:)` is what keeps
    /// a bare `.wei` — no label at all — out: it computes a real id, resolves
    /// to nothing, and would otherwise present as a name we merely failed to
    /// find rather than one that cannot exist.
    static func looksLikeName(_ s: String) -> Bool { registry(claiming: s) != nil }

    /// Trimmed and lowercased. The registries normalise case themselves
    /// (measured — see the header), so this is for OUR keying: two spellings
    /// of one name must be one cache entry and one request, not two.
    static func canonical(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Calldata

    /// A function selector computed off `Keccak256` at call time rather than
    /// hardcoded from memory — `AerodromeDeFi`'s rule, and the one place a
    /// typo would produce a revert that reads exactly like a dead contract.
    ///
    /// Bare hex, no `0x` — it is a fragment, and only the finished calldata
    /// below wears the prefix, so a fragment can never be handed to `eth_call`
    /// by mistake.
    static func selector(_ signature: String) -> String {
        Keccak256.hexString(Array(Keccak256.hash(Array(signature.utf8)).prefix(4)))
    }

    /// `computeId(string fullName)` — pure on both registries, so the answer
    /// is stable forever and may be cached without an expiry.
    static func computeIdCalldata(_ name: String) -> String {
        "0x" + selector("computeId(string)") + encodeString(canonical(name))
    }

    /// `resolve(uint256 tokenId)`.
    ///
    /// The id is carried as its 64-character WORD and never as an `Int`. A
    /// token id here is a keccak hash — `vitalik.wei`'s is
    /// `0x4c2c7a51…d263`, a full 256 bits — so parsing one through the app's
    /// `hexToInt` overflows and hands back nil, which would present as a name
    /// that does not resolve. The word is what came off the wire and the word
    /// is what goes back.
    static func resolveCalldata(idWord: String) -> String? {
        guard let word = normalizedWord(idWord) else { return nil }
        return "0x" + selector("resolve(uint256)") + word
    }

    /// `reverseResolve(address addr)` — the primary name an address chose,
    /// which is at most one per registry and usually none.
    static func reverseCalldata(address: String) -> String? {
        guard let word = addressWord(address) else { return nil }
        return "0x" + selector("reverseResolve(address)") + word
    }

    // MARK: - ABI

    /// A dynamic `string` argument in the tail-offset form: head offset, then
    /// length, then the bytes right-padded to a 32-byte boundary.
    static func encodeString(_ s: String) -> String {
        let bytes = Array(s.utf8)
        let padding = (32 - bytes.count % 32) % 32
        return pad(String(32, radix: 16))
            + pad(String(bytes.count, radix: 16))
            + Keccak256.hexString(bytes + Array(repeating: 0, count: padding))
    }

    /// A left-padded 32-byte word for a hex address, or nil when the input is
    /// not one. Lowercased: EIP-55 case is a checksum, never identity.
    static func addressWord(_ address: String) -> String? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.hasPrefix("0x"), value.count == 42,
              value.dropFirst(2).allSatisfy(\.isHexDigit) else { return nil }
        return pad(String(value.dropFirst(2)))
    }

    /// The nth 32-byte word of an `eth_call` return, without `0x`, lowercased
    /// — nil when the response is short or malformed, which is how a reverted
    /// call and a real answer are told apart here.
    static func word(_ hex: String, _ n: Int) -> String? {
        let s = (hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex).lowercased()
        guard s.allSatisfy(\.isHexDigit) else { return nil }
        let start = n * 64
        guard s.count >= start + 64 else { return nil }
        let i0 = s.index(s.startIndex, offsetBy: start)
        let i1 = s.index(s.startIndex, offsetBy: start + 64)
        return String(s[i0..<i1])
    }

    /// The token id word from a `computeId` return, or nil.
    static func tokenIdWord(from hex: String) -> String? { word(hex, 0) }

    /// The address a `resolve` return names — **nil for the zero address**,
    /// which on both registries is the answer for a name nobody has taken.
    ///
    /// This is the single most load-bearing line in the file. `alice.wei`
    /// computes a real id and resolves to zero (measured), so a reader that
    /// trusts the id and skips this check watches `0x0000…0000` — an address
    /// holding burned funds and an enormous transfer history, which renders
    /// as a perfectly healthy wallet and is nobody's.
    static func address(from hex: String) -> String? {
        guard let word = word(hex, 0),
              word.hasPrefix(String(repeating: "0", count: 24)) else { return nil }
        let body = String(word.dropFirst(24))
        guard body.contains(where: { $0 != "0" }) else { return nil }
        return "0x" + body
    }

    /// The `string` a `reverseResolve` return carries — nil when empty, which
    /// is what an address that set no primary name answers.
    static func string(from hex: String) -> String? {
        let s = (hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex).lowercased()
        guard let offsetWord = word(s, 0),
              let offset = Int(offsetWord.drop(while: { $0 == "0" }).isEmpty
                               ? "0" : String(offsetWord.drop(while: { $0 == "0" })), radix: 16),
              offset % 32 == 0
        else { return nil }
        let lengthStart = offset * 2
        guard s.count >= lengthStart + 64,
              let lengthWord = word(s, offset / 32),
              let length = Int(lengthWord.drop(while: { $0 == "0" }).isEmpty
                               ? "0" : String(lengthWord.drop(while: { $0 == "0" })), radix: 16),
              // No `length > 0` beside this: the empty case is already caught
              // by the `!text.isEmpty` guard below, and the mutation pass
              // showed a second test of it could never fail — two conditions
              // guarding one thing, where only one can be shown to work.
              s.count >= lengthStart + 64 + length * 2
        else { return nil }
        let start = s.index(s.startIndex, offsetBy: lengthStart + 64)
        let end = s.index(start, offsetBy: length * 2)
        var bytes: [UInt8] = []
        var i = start
        while i < end {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        guard let text = String(bytes: bytes, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    /// Left-pads a hex string to one 32-byte word. nil-safe by construction:
    /// anything longer than a word is returned as-is and will simply fail to
    /// resolve rather than silently addressing a different token.
    private static func pad(_ hex: String) -> String {
        String(repeating: "0", count: max(0, 64 - hex.count)) + hex
    }

    /// A 64-character word, however it arrived (`0x`-prefixed or not), or nil.
    private static func normalizedWord(_ raw: String) -> String? {
        let s = (raw.hasPrefix("0x") ? String(raw.dropFirst(2)) : raw).lowercased()
        guard s.count == 64, s.allSatisfy(\.isHexDigit) else { return nil }
        return s
    }
}
