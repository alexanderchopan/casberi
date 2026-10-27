import CryptoKit
import Foundation

/// THE CIRCUIT FILES THE PRIVACY POOLS ENGINE RUNS, AND THE RULE THAT NONE IS
/// UNPINNED (prd §1540, 2026-10-26).
///
/// Every proof is computed from three files per circuit: the witness
/// generator (`wasm`), the Groth16 proving key (`zkey`) and its verification
/// key (`vkey`). A wrong proving key would make proofs the pool refuses; a
/// hostile witness generator runs code in the engine's page. So no byte
/// reaches the engine unless it hashes to the pin for its network
/// (`PrivacyArtifactPins.swift`, generated from 0xBow's published manifest by
/// `tools/privacy-pools-engine/pins.mjs`).
///
/// **Downloaded on first use, never bundled.** One operation's circuit is
/// 3 MB (deposit) to 66 MB (`transact_5x5`), 27 circuits in all; a
/// transfer's or withdrawal's is about 20 MB. They come by IPFS CID from the
/// gateways below, in order, and are kept in Application Support under their
/// hash, so a file is fetched once and re-checked whenever it is read.
///
/// Pure (Foundation + CryptoKit): `privacy-engine-selftest.sh` compiles it.
enum PrivacyArtifacts {

    struct File: Equatable {
        let cid: String
        let sha256: String
    }

    struct Circuit: Equatable {
        let wasm: File
        let zkey: File
        let vkey: File

        func file(_ kind: Kind) -> File {
            switch kind {
            case .wasm: wasm
            case .zkey: zkey
            case .vkey: vkey
            }
        }
    }

    enum Kind: String, CaseIterable {
        case wasm, zkey, vkey
    }

    /// The largest file any circuit has (transact_5x5's zkey is 66 MB):
    /// a download that runs past it is not a circuit file.
    static let maxBytes = 96 * 1_048_576

    /// IPFS gateways, tried in order. ipfs.io (the SDK's default) answered
    /// some CIDs with a service-worker page or a 429 on 2026-10-26, which the
    /// hash check refuses; Pinata's served every one. A CID names its bytes,
    /// so any gateway will do: the pin, not the host, is the trust.
    static let gateways = ["https://gateway.pinata.cloud/ipfs/", "https://ipfs.io/ipfs/"]

    /// The pins for a chain, or nil: a network with no pins runs no proof.
    /// Sepolia's verifiers hold 1.0.0's dev keys; Ethereum's the ceremony
    /// keys (prd §1563): a proof made with the other set reverts there
    /// (`mainnet-sim.mjs --mutate devkeys`).
    static func pins(chainId: Int) -> [String: Circuit]? {
        switch chainId {
        case PrivacyNetwork.sepolia.chainId: sepoliaPins
        case PrivacyNetwork.ethereum.chainId: ceremonyPins
        default: nil
        }
    }

    /// `artifact/<circuit>/<kind>`, the path the engine asks for; anything
    /// else — another shape, a circuit with no pin, a name that could walk a
    /// path — is nil.
    static func request(path: String, pins: [String: Circuit]) -> (name: String, kind: Kind, file: File)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "artifact",
              parts[1].range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil,
              let kind = Kind(rawValue: parts[2]),
              let circuit = pins[parts[1]] else { return nil }
        return (parts[1], kind, circuit.file(kind))
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The one gate: these bytes are this file.
    static func verify(_ data: Data, against file: File) -> Bool {
        guard !data.isEmpty, data.count <= maxBytes, file.sha256.count == 64 else { return false }
        return sha256Hex(data) == file.sha256.lowercased()
    }

    static func urls(for file: File) -> [URL] {
        gateways.compactMap { URL(string: $0 + file.cid) }
    }

    /// Where a verified file is kept: named by its hash, so two networks that
    /// share a file share it, and a changed pin can never read a stale file.
    static func cacheURL(for file: File, in directory: URL) -> URL {
        directory.appendingPathComponent(file.sha256.lowercased())
    }
}
