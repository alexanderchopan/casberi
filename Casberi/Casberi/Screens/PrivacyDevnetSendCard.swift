import SwiftUI

/// **ETHREX PRIVACY'S HOME SCOPE — the acts, at last (prd §593d).**
///
/// The panel, the sheet and the keypad are all `DevnetSendConsole`'s, shared
/// with Hegotá, Frames and vibenet. What is new is that this seat has any acts
/// at all: it shipped watch-only because §593a could not reproduce the
/// type-`0x6` envelope, `PrivacyDevnetSend` and `PrivacyDevnetKey` were written
/// when §593c settled it — and then **nothing in the app ever called either
/// one**. A room that can read a chain and not touch it, next to three siblings
/// that can, on the one chain in the family whose defining capability is
/// something you have to DO.
///
/// **TWO ACTS, so the split panel keeps its crown rung.** §559: *"Two verbs is
/// the ceiling, and the second is the ink half. Three is a menu."* Create and
/// Authorize are vibenet's acts, not this chain's — there is no account
/// abstraction here to authorize a key against, so a third tile would be the
/// dead control §83 bans.
///
/// **The acts are HERE and not on the connect screen**, which is §594's line:
/// an act that WRITES to the chain moves to Home, an act that changes what you
/// are LOOKING AT stays with the view.
struct PrivacyDevnetSendCard: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var store

    let onSend: () -> Void

    @State private var keyAddress: String? = PrivacyDevnetKey.address()
    @State private var creating = false
    @State private var createError: String?
    @State private var topUpBusy = false
    @State private var topUpNote: String?

    /// The seat's own brand hue where it has one, `DS.tint` otherwise — the
    /// console is chrome around the room's own colour, never a new one.
    private static let mark = DS.brandHue(for: PrivacyDevnetIdentity.source) ?? DS.tint

    var body: some View {
        if keyAddress == nil {
            create
        } else {
            DevnetSendPanel(
                tint: Self.mark,
                // `POST /api/claim`, byte-identical to Hegotá's — so the tile
                // acts in place rather than opening a page.
                topUp: .init(busy: topUpBusy, note: topUpNote, action: topUp),
                onSend: onSend)
        }
    }

    // MARK: - Before there is a key

    /// **ONE TAP MAKES IT, and there is no screen in between** — §553's ruling,
    /// carried unchanged: a confirmation screen would ask the question the
    /// button just asked. The key is a plain scalar rather than an Enclave one
    /// on this chain (every signature measured here is scheme `0x1`), so the
    /// tap IS the act and nothing rises.
    @ViewBuilder private var create: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
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
        guard !creating else { return }
        creating = true
        defer { creating = false }
        do {
            let made = try PrivacyDevnetKey.create()
            keyAddress = made
            createError = nil
            // **THE KEY'S OWN ACCOUNT IS WATCHED (prd §602).** Creating a key
            // did not watch its address, so after Create and Top up the
            // balance you had just claimed appeared NOWHERE in the room unless
            // you thought to paste your own address into the field on the
            // connect screen — on the one seat where the app itself made the
            // account. Every other reading this room has is per watched
            // address, so an unwatched key has no face, no row, no rail seat
            // and no tally.
            //
            // Watching is a READ (§593's own word for it), so this adds no
            // capability the tap did not already grant; it makes the account
            // the tap just created visible to the room that made it. It also
            // makes the first-settle nonce read free, since the sweep is now
            // reading this address anyway.
            if PrivacyDevnetWatch.shared.add(made) {
                PrivacyDevnetBridge.registerBridge(store: store)
            }
            PrivacyDevnetLiveState.shared.setMine(made)
            Task { await PrivacyDevnetLiveState.shared.refresh() }
            chrome.refreshPulse &+= 1
        } catch {
            // The keychain's own answer, never a bare "it failed" (§531): a
            // code with no remedy is a dead end.
            createError = String(localized: "Couldn't make a key: \(String(describing: error))")
        }
    }

    // MARK: - Top up

    private func topUp() {
        guard !topUpBusy, let address = keyAddress else { return }
        topUpBusy = true
        topUpNote = nil
        Task { @MainActor in
            defer { topUpBusy = false }
            do {
                _ = try await PrivacyDevnetSend.claim(address: address)
                topUpNote = nil
                await PrivacyDevnetLiveState.shared.refresh()
                chrome.refreshPulse &+= 1
            } catch let failure as PrivacyDevnetSend.Failure {
                if case .faucet(let verdict) = failure {
                    // **The rate limit and a real failure read the SAME way**
                    // (§525): the refusal is expected rather than a fault, and
                    // either way the next step is identical — tap it again.
                    topUpNote = verdict.sentence ?? String(localized: "The faucet didn't answer.")
                } else {
                    topUpNote = String(localized: "The faucet didn't answer.")
                }
            } catch {
                topUpNote = String(localized: "The faucet didn't answer.")
            }
        }
    }
}

// MARK: - What a send on this chain becomes

/// The steps the sheet draws between the figure and the keypad.
///
/// **Built from `PrivacyDevnetSend.transfer`, which is the object that gets
/// signed** — not a description of it. A preview drawn from a parallel
/// description is how a screen ends up promising two frames and sending three;
/// here they are the same `Fields`, so they cannot disagree.
///
/// Empty until there is a real recipient and a real amount, so the strip
/// appears when there is something true to say rather than sitting there as a
/// diagram of nothing.
enum PrivacyDevnetSendPlanSteps {
    @MainActor
    static func steps(destination: String, amount: String) -> [DevnetSendStep] {
        guard PrivacyDevnetKey.address() != nil,
              DevnetSendParse.isValidAddress(destination),
              let wei = DevnetSendParse.weiData(from: amount)
        else { return [] }
        let weiHex = "0x" + (wei.isEmpty ? "0" : RLP.hex(wei))
        guard let fields = try? PrivacyDevnetSend.transfer(
            to: destination, weiHex: weiHex,
            nonce: PrivacyDevnetLiveState.shared.accounts.first?.nonce ?? 0,
            gasPrice: 0)
        else { return [] }
        return fields.frames.map { DevnetSendStep(name: name(for: $0), detail: detail(for: $0)) }
    }

    /// The chain's own words — `PrivacyDevnetSection.label`'s ruling: the chip
    /// is where the vocabulary gets learned, and this chain names its steps
    /// frames.
    private static func name(for frame: PrivacyDevnetTransaction.Frame) -> String {
        switch frame.mode {
        case 1: String(localized: "Verify")
        // **MODE 2 IS SENDER, and mode 0 is not** — measured, and the node
        // refuses a non-zero value in any other mode. Naming 0 "Sender" here
        // would be a screen agreeing with a mistake the encoder already made
        // once.
        case 2: String(localized: "Sender")
        case 0: String(localized: "Default")
        default: String(localized: "Mode \(String(frame.mode))")
        }
    }

    /// **THE PERMISSION, said out loud.** A VERIFY frame's flags ARE the
    /// authorisation on this chain — there is no standing grant anywhere — and
    /// without an APPROVE the transaction has no payer and is invalid, so
    /// "approves both" is load-bearing rather than a detail.
    private static func detail(for frame: PrivacyDevnetTransaction.Frame) -> String {
        if frame.mode == 1 {
            let execution = frame.flags & 0x1 != 0
            let payment = frame.flags & 0x2 != 0
            if execution && payment { return String(localized: "approves both") }
            if payment { return String(localized: "approves payment") }
            if execution { return String(localized: "approves running") }
            return String(localized: "approves nothing")
        }
        return frame.value.isEmpty ? String(localized: "no value")
                                   : String(localized: "moves the value")
    }
}
