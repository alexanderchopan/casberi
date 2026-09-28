import Foundation

/// WHICH FRAMES DEVNET THIS SEAT IS ON (prd §962, 2026-09-27) — one value, so
/// the next relaunch is one edit rather than a hunt through six files.
///
/// The seat moved off chain 81410 (`*.frames.ethrex.xyz`, one client, run by
/// the ethrex team) onto ethpandaops' `frames-devnet-0`: the EIP-8141 devnet
/// every client team tests against — geth, nethermind, reth and ethrex behind
/// lighthouse — pinned to EIPs `b75cbe61`. ethpandaops numbers its devnets and
/// relaunches them as `-1`, `-2`, each with a new chain id and new hosts, so
/// everything that names the chain reads it from here.
///
/// **The envelope did NOT move.** Measured 2026-09-27: `FramesTransaction`
/// re-encodes 4 of 4 distinct transaction shapes mined on this chain (two to
/// five frames, an atomic batch) to the node's own hash with no change. What
/// moved is only what this value holds, plus two measured facts the readers
/// carry (`FramesRead.servesFrames`, and the faucet).
///
/// Foundation-only BY DESIGN: `FramesTransaction.chainID` reads it, and
/// `scripts/frames-tx-selftest.sh` compiles both whole.
struct FramesNetwork: Equatable {
    /// ethpandaops' own name for it, as its pages print it.
    let name: String
    /// The id the encoder signs over. A transaction hashed for another id is a
    /// well-formed signature over a different digest — never a loud failure.
    let chainID: UInt64
    /// Every host is tried in order. ethpandaops publishes ONE public endpoint,
    /// load-balanced across every client's node (eRPC); the per-node hosts
    /// behind it answer 401.
    let rpcHosts: [String]
    /// Dora. Serves `/tx/<hash>` and `/address/<0x…>` (measured 200 on both).
    let explorer: String
    /// **A PAGE, never an endpoint.** This faucet is proof-of-work plus
    /// hCaptcha (`/api/getFaucetConfig`, measured): a person mines in a
    /// browser and solves the captcha, so the app can only open it.
    let faucetPage: String

    static let current = devnet0

    static let devnet0 = FramesNetwork(
        name: "frames-devnet-0",
        // `0x1a3453829`, from the node and from the published genesis.json.
        chainID: 7_034_189_865,
        rpcHosts: ["https://rpc.frames-devnet-0.ethpandaops.io"],
        explorer: "https://dora.frames-devnet-0.ethpandaops.io",
        faucetPage: "https://faucet.frames-devnet-0.ethpandaops.io")
}
