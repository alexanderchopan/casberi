import Foundation
import Observation

/// MONEY THAT REALLY ARRIVED (2026-08-27, prd §501).
///
/// Stripe has celebrated money landing since §250 — its arrivals rain, and its
/// challenged money deliberately does not — and the wallet, the room whose
/// whole subject is money moving, never has. This is that moment, with the
/// fences the wallet needs and Stripe did not.
///
/// **It publishes a pulse, never a view.** The rain already exists
/// (`BerryRain`, driven off `ShellChrome.refreshPulse`), so nothing new is
/// drawn: the room bumps the pulse it already bumps for a pull-to-refresh, in
/// the receiving wallet's own rail stop. That is also why this type holds an
/// address rather than a colour — `Model` does not know about hues, and the
/// stop is `WalletFace`'s to decide.
///
/// ## The four fences, and why each one is not optional
///
/// **1. A row an insert really inserted.** `WalletIngest` re-reads a window on
/// every pass and dedupes on `sourceRef`, so "the pass saw a transfer" and "a
/// transfer arrived" are different facts, and only the second is news. This is
/// Stripe's own rule (`insert` really inserted, never a re-read window).
///
/// **2. Received, and priced above the floor.** An outbound transfer is not an
/// arrival, and dust is not money — `WalletIngest.holdingFloor` is the same
/// bar the holdings read uses to decide a token is worth drawing.
///
/// **3. Nothing flagged, and nothing unpriced.** §481's rule is that a spam
/// mint is one you didn't sign, and its whole point is that a stranger can put
/// anything in your wallet. If a duster could make your phone celebrate, the
/// celebration is theirs to trigger, not yours to earn — so a flagged transfer
/// never rains, and neither does one whose price could not be read. That
/// second half is the conservative direction on purpose: silence when we
/// cannot tell is cheap, and a fabricated party over a fake token is not.
///
/// **4. A sync you are present for.** Nothing here decides that — the ROOM
/// does, by observing `pulse` on change alone and never on appear. A pulse
/// raised while the room was closed reaches nobody and is not replayed, which
/// is the honest behaviour: the rain is a moment, and a moment you missed is
/// missed. It also makes the fence impossible to get wrong from this side.
@Observable
final class WalletArrival {
    static let shared = WalletArrival()
    private init() {}

    /// Bumped once per pass that landed at least one qualifying arrival —
    /// never once per transfer. Four USDC transfers in one sync are one
    /// arrival to look at, and four showers stacked on each other is the
    /// "one gesture, one shower" rule `BerryRain` already earned.
    private(set) var pulse = 0

    /// The wallet the money reached, for the rain's hue. The FIRST qualifying
    /// arrival of the pass: with several, any pick is arbitrary, and the first
    /// is the one whose row is highest in the feed the shower falls over.
    private(set) var address: String?

    @MainActor
    func announce(address: String) {
        self.address = address
        pulse += 1
    }
}
