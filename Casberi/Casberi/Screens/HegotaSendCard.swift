import SwiftUI
import SwiftData

/// **HEGOTÁ'S HOME IS TWO VERBS (prd §553, 2026-09-01).**
///
/// §544 put a payment console here and §552/§552a spent a session failing to
/// fit it under the room's chrome. `DevnetSendConsole`'s header carries that
/// whole argument; what it comes to is that Home should not hold a form at all.
/// It holds the two things you can do, and the form lives on a sheet with the
/// screen to itself.
///
/// **BOTH VERBS ARE REAL HERE, and that is not true of the sibling room.**
/// `HegotaSend.claimFaucet` has existed since §525 and **no screen has ever
/// called it** — the app has carried a working faucet nobody could reach.
/// vibenet has no equivalent: its faucet is a PAYER that sponsors gas, not
/// something an address can claim from, so that room draws the Send half alone
/// rather than a button that cannot act (§83).
///
/// **THE CARD PRESENTS NOTHING.** Send hands upward to `FeedScreen`'s single
/// `.sheet` — a `.sheet` attached to a view inside a `List` row resolves to the
/// same presenting controller as the screen's own and half-opens then closes,
/// paid for three times already. Top up needs no sheet: it acts in place and
/// reports on itself, which is the whole of its design.
struct HegotaSendCard: View {
    /// Raise the send sheet. Owned by the screen, for the reason above.
    var onSend: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome

    @State private var creating = false
    @State private var createError: String?
    @State private var topUpBusy = false
    @State private var topUpNote: String?

    // The app's own accent, not `HegotaModeStyle.room` (user: "that cyan
    // color blue or whatever it is... we don't use that anywhere else") —
    // this is an ordinary send flow, not a frame/vault reading.
    private static let mark = DS.tint

    var body: some View {
        if sender == nil {
            create
        } else {
            DevnetSendPanel(
                tint: Self.mark,
                topUp: .init(busy: topUpBusy, note: topUpNote, action: topUp),
                onSend: onSend)
        }
    }

    // MARK: - Before there is a key

    /// **ONE TAP MAKES IT, and there is no screen in between** (user,
    /// 2026-09-01: *"we won't show a 'ready' screen, once created it will just
    /// do confetti rain pour and then land on the top up and send screen"*).
    ///
    /// §552d routed this to the key SHEET, which asked the same question the
    /// button had just asked and offered the same button to answer it. Face ID
    /// rises inside `HegotaKey.create()` and that is a real confirmation from
    /// the system — ours would have been ceremony.
    ///
    /// The copy makes no claim about the ROOM (user: *"not necessarily true b/c
    /// user may be following account"*). You can be watching plenty of
    /// addresses here; the only thing missing is a key on THIS phone.
    private var create: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DevnetCreatePanel(tint: Self.mark,
                              title: String(localized: "Create\naccount"),
                              busy: creating,
                              onCreate: makeKey)
            if let createError {
                Text(createError)
                    .dsText(.label12)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func makeKey() {
        // Nothing is minted in a tour — a real key would raise Face ID and put
        // an item in this phone's Keychain, from a screen whose own banner says
        // none of this is yours.
        guard !DemoMode.isActive else {
            createError = String(localized: "No key is made in the demo — this is where your own would be.")
            return
        }
        creating = true
        createError = nil
        Task { @MainActor in
            defer { creating = false }
            do {
                _ = try HegotaKey.create()
                DSHaptic.success()
                pour()
            } catch {
                createError = String(localized: "Couldn't make a key on this phone.")
            }
        }
    }

    // MARK: - Top up

    /// **THREE ENDINGS, AND ONLY ONE IS A FAULT (prd §553).**
    ///
    /// The faucet allows one claim per source IP per hour, MEASURED, and §525
    /// rules that refusal expected rather than a failure. It and the
    /// unreachable case read the same way here on purpose: no red, no alarm
    /// mark, a plain sentence in the tile's own empty top — because whichever
    /// it is, the next step is identical and it is to tap again.
    private func topUp() {
        guard !DemoMode.isActive else {
            topUpNote = String(localized: "The faucet isn't reached in the demo.")
            return
        }
        guard let address = HegotaKey.address() else { return }
        topUpBusy = true
        topUpNote = nil
        Task { @MainActor in
            defer { topUpBusy = false }
            do {
                let claimed = try await HegotaSend.claimFaucet(for: address)
                HegotaSend.landReceipt(txHash: claimed.transactionHash, kind: .claimed,
                                       in: modelContext)
                DSHaptic.success()
                pour()
                // The crown is the proof, so it has to be re-read rather than
                // left saying what it said before the money arrived.
                await HegotaLiveState.shared.refresh()
            } catch let f as HegotaSend.Failure {
                if case .faucet(let verdict) = f {
                    topUpNote = Self.faucetNote(verdict)
                } else {
                    topUpNote = String(localized: "The faucet didn't answer. Tap to try again.")
                }
            } catch {
                topUpNote = String(localized: "The faucet didn't answer. Tap to try again.")
            }
        }
    }

    private static func faucetNote(_ verdict: HegotaFaucetVerdict) -> String {
        switch verdict {
        case .sent:
            return String(localized: "Claimed.")
        case .rateLimited:
            return String(localized: "Once an hour. Try again a little later.")
        case .refused(let why):
            return String(localized: "The faucet said no: \(why)")
        case .unreachable:
            return String(localized: "The faucet didn't answer. Tap to try again.")
        }
    }

    /// The pour IS the confirmation (prd §553) — `BerryRain` is mounted once in
    /// `MainSurface` and driven by this counter, so a success here costs a
    /// bump rather than a view of its own.
    private func pour() {
        chrome.refreshHue = Self.mark
        chrome.refreshPulse &+= 1
    }

    // MARK: - Who it spends from

    /// **THE ADDRESS THIS CARD SPENDS FROM, and it answers in the demo (prd
    /// §552b).** The gate was `HegotaKey.address() != nil`, which a tour can
    /// never satisfy, so the room's DEFAULT scope drew nothing in the demo from
    /// the day §539 made the console its content.
    ///
    /// **No fake credential is written.** The demo does not plant an address in
    /// `HegotaKey`'s own defaults, which would make every other path on this
    /// phone believe it holds a key and hand `HegotaSign` one that is not in
    /// the Keychain. It borrows the fixture's own account for display, and
    /// every write above refuses before it reaches a signature.
    private var sender: String? {
        HegotaKey.address() ?? (DemoMode.isActive ? HegotaLiveState.demoOwnerAddress : nil)
    }
}
