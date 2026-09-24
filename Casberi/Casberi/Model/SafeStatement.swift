import Foundation

/// A Safe MESSAGE — what a Safe "says" off-chain, and whether this app can
/// read it (prd §913). Foundation-only and pure; `scripts/safe-signer-selftest.sh`
/// compiles it whole and pins the fixtures `safe-signer-vectors.py` derives.
///
/// **What a Safe message is.** A Safe cannot `personal_sign`; it validates a
/// signature through ERC-1271, and the thing its owners sign is
/// `SafeMessage(bytes message)` under the Safe's own EIP-712 domain, where
/// `message` is the 32-byte hash of the INNER thing — an EIP-191 hash of a
/// text, or the EIP-712 digest of typed data. Owners sign the outer hash;
/// the Safe's fallback handler checks the threshold of them.
///
/// **Why this file reads the inner message at all.** The outer hash tells
/// the signer nothing. §425's fourth refusal — "no free-form typed data" —
/// exists because a CoW order and a Permit ride this exact envelope and
/// move money. So a statement is signed only when the inner message can be
/// READ AND NAMED: a sign-in (EIP-4361, parsed field by field, whose address
/// must be the Safe) or a Snapshot vote (typed data in Snapshot's own
/// domain). Anything else is `.unreadable` and the signer declines with the
/// hash on screen — the §8.5 rule, applied to words instead of calldata.
///
/// Nothing here reaches the network; the message body comes in by paste,
/// or `SafeStatementSigner` fetches it from Safe's own service.
enum SafeMessageEncoder {

    static let typeString = "SafeMessage(bytes message)"
    static var typeHash: [UInt8] { Keccak256.hash(Array(typeString.utf8)) }

    /// `getMessageHashForSafe(safe, message)`, as `CompatibilityFallbackHandler`
    /// computes it: `keccak256(0x1901 ‖ safe.domainSeparator() ‖ keccak256(TYPEHASH ‖ keccak256(message)))`.
    /// `message` is the 32-byte inner hash, so the struct hashes it once more
    /// — the same double hash the contract performs, and the reason the local
    /// figure is checked against `getMessageHash` on the Safe before signing.
    static func safeMessageHash(chainId: Int, safe: String, message: [UInt8]) -> [UInt8]? {
        guard message.count == 32,
              let domain = SafeTxEncoder.domainSeparator(chainId: chainId, safe: safe)
        else { return nil }
        let structHash = Keccak256.hash(typeHash + Keccak256.hash(message))
        return Keccak256.hash([0x19, 0x01] + domain + structHash)
    }

    static var getMessageHashSelector: String { SafeCalldata.selector("getMessageHash(bytes)") }

    /// `getMessageHash(bytes)` calldata over the 32-byte inner hash — the
    /// rail's `eth_call`, made to the Safe itself (its fallback handler
    /// answers).
    static func getMessageHashCalldata(message: [UInt8]) -> String? {
        guard message.count == 32,
              let selector = SafeABI.hexBytes(getMessageHashSelector),
              let offset = SafeABI.word(uint: 32),
              let length = SafeABI.word(uint: 32)
        else { return nil }
        return SafeABI.hex(selector + offset + length + message)
    }
}

/// EIP-191 personal messages, the `\x19Ethereum Signed Message:\n` prefix.
enum EIP191 {
    static func preimage(text: String) -> [UInt8] {
        let body = Array(text.utf8)
        return Array("\u{19}Ethereum Signed Message:\n\(body.count)".utf8) + body
    }

    static func hash(text: String) -> [UInt8] { Keccak256.hash(preimage(text: text)) }
}

/// A Sign-In with Ethereum message (EIP-4361), parsed by its ABNF rather
/// than matched by its first line. Every required field must be present or
/// the parse is nil — a message with a missing nonce is not "a sign-in with
/// no nonce", it is text this app cannot vouch for.
struct SIWEMessage: Equatable {
    let scheme: String?
    let domain: String
    let address: String
    let statement: String?
    let uri: String
    let version: String
    let chainId: Int
    let nonce: String
    let issuedAt: String
    let expirationTime: String?
    let notBefore: String?
    let requestId: String?
    let resources: [String]

    static func parse(_ text: String) -> SIWEMessage? {
        // A paste ends with the newline the clipboard kept, and a browser
        // spells its line ends `\r\n`; neither is part of the message.
        var body = text.replacingOccurrences(of: "\r\n", with: "\n")
        while body.hasSuffix("\n") { body.removeLast() }
        let lines = body.components(separatedBy: "\n")
        guard lines.count >= 6 else { return nil }
        // Line 1: `[scheme://]domain wants you to sign in with your Ethereum account:`
        let suffix = " wants you to sign in with your Ethereum account:"
        guard lines[0].hasSuffix(suffix) else { return nil }
        var authority = String(lines[0].dropLast(suffix.count))
        var scheme: String?
        if let range = authority.range(of: "://") {
            scheme = String(authority[authority.startIndex..<range.lowerBound])
            authority = String(authority[range.upperBound...])
        }
        guard !authority.isEmpty, !authority.contains(" ") else { return nil }
        // Line 2: the address, which must be a hex address.
        let address = lines[1]
        guard SafeABI.word(address: address) != nil, address.hasPrefix("0x") else { return nil }
        // Line 3 is blank. Then an optional statement, then a blank, then fields.
        guard lines[2].isEmpty else { return nil }
        var index = 3
        var statement: String?
        if index < lines.count, !lines[index].isEmpty, !isFieldLine(lines[index]) {
            statement = lines[index]
            index += 1
            guard index < lines.count, lines[index].isEmpty else { return nil }
            index += 1
        } else if index < lines.count, lines[index].isEmpty {
            // A blank where the statement would be: the ABNF allows an empty
            // statement line followed by its blank.
            index += 1
        }
        var fields: [String: String] = [:]
        var resources: [String] = []
        var inResources = false
        while index < lines.count {
            let line = lines[index]
            index += 1
            if inResources {
                guard line.hasPrefix("- ") else { return nil }
                resources.append(String(line.dropFirst(2)))
                continue
            }
            if line == "Resources:" { inResources = true; continue }
            guard let colon = line.range(of: ": ") else { return nil }
            let key = String(line[line.startIndex..<colon.lowerBound])
            let value = String(line[colon.upperBound...])
            guard fields[key] == nil else { return nil }
            fields[key] = value
        }
        guard let uri = fields["URI"], let version = fields["Version"],
              let chainText = fields["Chain ID"], let chainId = Int(chainText),
              let nonce = fields["Nonce"], nonce.count >= 8,
              let issuedAt = fields["Issued At"]
        else { return nil }
        let known: Set<String> = ["URI", "Version", "Chain ID", "Nonce", "Issued At",
                                  "Expiration Time", "Not Before", "Request ID"]
        guard fields.keys.allSatisfy({ known.contains($0) }) else { return nil }
        return SIWEMessage(scheme: scheme, domain: authority, address: address, statement: statement,
                           uri: uri, version: version, chainId: chainId, nonce: nonce,
                           issuedAt: issuedAt, expirationTime: fields["Expiration Time"],
                           notBefore: fields["Not Before"], requestId: fields["Request ID"],
                           resources: resources)
    }

    private static func isFieldLine(_ line: String) -> Bool {
        for key in ["URI: ", "Version: ", "Chain ID: ", "Nonce: ", "Issued At: ",
                    "Expiration Time: ", "Not Before: ", "Request ID: ", "Resources:"]
            where line.hasPrefix(key) { return true }
        return false
    }
}

/// What a Safe message SAYS, in the only two vocabularies this app will sign.
enum SafeStatement: Equatable {
    /// A sign-in, EIP-4361. `siwe.address` has already been checked against
    /// the Safe by `read(message:safe:)`.
    case signIn(SIWEMessage)
    /// A Snapshot vote — typed data in Snapshot's own domain (`name:
    /// "snapshot"`), primary type `Vote`.
    case snapshotVote(SnapshotVote)
    /// Anything else. The signer declines and shows the hash; `why` is the
    /// sentence, never a summary of the message.
    case unreadable(why: String)

    struct SnapshotVote: Equatable {
        let space: String
        let proposal: String
        let choice: String
        let reason: String?
        let from: String
        let timestamp: Int?
    }

    var isNamed: Bool {
        if case .unreadable = self { return false }
        return true
    }

    /// The inner hash and the reading, from the message as Safe's service
    /// or a paste carries it: a `String` (EIP-191) or typed data (EIP-712).
    /// The hash is computed for EVERY message — the unreadable ones too —
    /// because the outer `SafeMessage` hash is what the request carries, and
    /// matching it is how the phone knows the words it was shown are the
    /// words it is being asked about.
    static func read(message: Any, safe: String) -> (statement: SafeStatement, hash: [UInt8])? {
        if let text = message as? String {
            let hash = EIP191.hash(text: text)
            guard let siwe = SIWEMessage.parse(text) else {
                return (.unreadable(why: "This is free-form text, which Casberi won't sign for a Safe."), hash)
            }
            guard siwe.address.lowercased() == safe.lowercased() else {
                return (.unreadable(why: "This sign-in names a different account than the Safe."), hash)
            }
            return (.signIn(siwe), hash)
        }
        guard let typed = EIP712.parse(message), let hash = EIP712.digest(typed) else { return nil }
        guard typed.domainName == "snapshot" else {
            return (.unreadable(why: "This is typed data in a domain Casberi can't name (\(typed.domainName ?? typed.primaryType))."), hash)
        }
        guard typed.primaryType == "Vote",
              let space = typed.message["space"]?.string,
              let from = typed.message["from"]?.string,
              let proposal = typed.message["proposal"].flatMap(describe),
              let choice = typed.message["choice"].flatMap(describe)
        else {
            return (.unreadable(why: "This is a Snapshot \(typed.primaryType), which Casberi doesn't read."), hash)
        }
        guard from.lowercased() == safe.lowercased() else {
            return (.unreadable(why: "This vote is cast from a different account than the Safe."), hash)
        }
        let reason = typed.message["reason"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        let timestamp = typed.message["timestamp"].flatMap(EIP712.int)
        return (.snapshotVote(SnapshotVote(space: space, proposal: proposal, choice: choice,
                                           reason: reason, from: from, timestamp: timestamp)), hash)
    }

    /// A Snapshot field as a person reads it — a choice index, a list of
    /// them, or a string; a proposal id verbatim.
    private static func describe(_ value: EIP712.Value) -> String? {
        switch value {
        case .string(let s): return s
        case .number, .bool: return EIP712.numberText(value)
        case .array(let items):
            let parts = items.compactMap(describe)
            return parts.count == items.count ? parts.joined(separator: ", ") : nil
        case .object(let o):
            // A weighted choice: `{"1": 3, "2": 1}`.
            let parts = o.keys.sorted().compactMap { k in o[k].flatMap(describe).map { "\(k): \($0)" } }
            return parts.count == o.count ? parts.joined(separator: ", ") : nil
        case .null: return nil
        }
    }
}
