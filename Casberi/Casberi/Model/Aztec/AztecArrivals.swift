import Foundation

/// **A DEPOSIT ARRIVES ON ITS OWN (prd §1700ac, user, 2026-11-10: "how will i
/// know when it arrives?").** A move into Aztec waits for Aztec to carry its
/// message (minutes), then has to be claimed, proved on this iPhone. The claim
/// ran only while Move's Aztec sentence stood, so a deposit you walked away
/// from sat unclaimed until you came back to that sentence, and nothing said
/// it was on its way. Now:
///   - Holdings › Private draws one grey row per deposit Aztec has not handed
///     over (`AztecAccountStore.arriving`): a state, nobody waiting on you, so
///     never amber and never in Needs you (§1713 item 5's rule for Railgun's
///     unlisted money; Needs you keeps what ends in a step of yours, as an
///     exit's Finish does);
///   - the claim runs wherever the account is looked at — the Wallet's open
///     (`AztecAccountStore.warm`), that row, Move's sentence — through
///     `settle()` here, one pass at a time whoever asks;
///   - a claimed deposit lands one Activity row (`ShieldBridge.settle`).
@MainActor
enum AztecArrivals {
    /// A claim proves for seconds: a second asker joins nothing and leaves.
    private static var settling = false

    /// Whether anything this phone sent into Aztec is still unclaimed.
    static var waiting: Bool {
        let s = AztecAccountStore.shared.snapshot
        return (s.gas ?? []).contains { !$0.claimed } || (s.shield ?? []).contains { !$0.claimed }
    }

    /// Claims what Aztec has carried, gas first (a claim pays from gas).
    /// Only where there is a prover, never in the demo.
    static func settle() async {
        guard AztecProver.isAvailable, !DemoMode.isActive, waiting, !settling else { return }
        settling = true
        defer { settling = false }
        await AztecGas.settle()
        await ShieldBridge.settle()
    }
}
