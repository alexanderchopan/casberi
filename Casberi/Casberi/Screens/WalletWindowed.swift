import SwiftUI

/// **THE WINDOW LIVES WITH THE CONTROL THAT PICKS IT (prd §1716; two windows,
/// 7d and 30d, since prd §1717; user,
/// 2026-11-06: "on wallet home the period pickers are inactive"; 2026-11-08,
/// of the crown's 7d · Followed pills: "these are inactive").**
///
/// The Wallet's crown kept its window on `FeedScreen` (`balanceRange`) and
/// read it back down the body → `DSRoomScopeChrome` → list-row path — the
/// path §1403 measured as NOT rebuilding the box: the row is keyed on its
/// total alone, so a pick landed in state and the line kept the window it
/// mounted with. Reading the state in the body (the 11-06 fix) made the body
/// run and changed nothing the box drew. The pills answered the finger
/// (`PressSpring`'s dip, the haptic) and nothing followed, which is §83's dead
/// control with a pulse.
///
/// Here the window is `@State` on the view that draws the chips, so a pick
/// re-runs exactly this body, whatever the row above decides. `RoomHomeCrown`
/// had this shape already (its own `@State range`) and comes through it now,
/// so the Wallet and the devnets keep one rule instead of one each.
///
/// Everything handed down is DERIVED, never stored: the windows the record
/// can honestly answer (`WalletRange.offered` — a chip can never name a span
/// the samples do not cover), the active one (the pick while it is still
/// offered, else the remembered one), and the samples inside it. A remount —
/// the box re-keys on its total (§1403, §1535) — resets the state, and
/// `WalletRange.remembered` restores the pick from what `remember()` wrote.
struct WalletWindowed<Content: View>: View {
    /// The record, oldest first.
    let samples: [WalletStore.ValueSample]
    let content: (Window) -> Content

    /// Written out, not synthesized: the memberwise initializer a
    /// `@ViewBuilder let` gets does not let the toolchain infer `Content`
    /// from a multi-statement trailing closure (both callers failed to
    /// compile with "generic parameter 'Content' could not be inferred").
    init(samples: [WalletStore.ValueSample], @ViewBuilder content: @escaping (Window) -> Content) {
        self.samples = samples
        self.content = content
    }

    /// One window over the record: what the crown needs to draw it and the
    /// one act that changes it.
    struct Window {
        /// The windows this record can answer; fewer than two draws no chips.
        let offered: [WalletRange]
        let active: WalletRange
        /// The samples inside `active`.
        let samples: [WalletStore.ValueSample]
        let pick: (WalletRange) -> Void

        /// The line for this window — nil until two samples fall inside it.
        var chart: TokenChart? { TokenChart.from(samples: samples) }
        /// The window as words on the change line (prd §920).
        var word: String { active.windowWord(since: samples.first?.at) }
    }

    /// `.week` is a placeholder: the body never draws it unless it is the
    /// remembered answer, because `active` is re-derived on every pass.
    @State private var range: WalletRange = .week

    var body: some View {
        let offered = WalletRange.offered(for: samples)
        let active = offered.contains(range) ? range : WalletRange.remembered(offered: offered)
        content(Window(offered: offered, active: active, samples: active.clip(samples),
                       pick: { picked in
                           range = picked
                           picked.remember()
                       }))
    }
}
