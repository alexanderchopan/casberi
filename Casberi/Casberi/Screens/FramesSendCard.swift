import SwiftUI

/// THE FRAMES DEVNET'S HOME SCOPE — two tiles, not a form (prd §548, mirroring
/// §553).
///
/// The panel, the sheet and the keypad are all `DevnetSendConsole`'s, shared
/// with Hegotá and vibenet. What is this room's own is the one thing neither
/// neighbour can say: **a send here is not one act.** It becomes a VERIFY
/// frame that authorises execution and payment, then a SENDER frame that moves
/// the value — and without the first the transaction has no payer and is
/// invalid. `plan` hands those to the sheet as `DevnetSendStep`s.
///
/// **Top up OPENS the faucet here (prd §962).** On chain 81410 it claimed in
/// place through `POST /api/claim`. `frames-devnet-0`'s faucet is
/// proof-of-work plus hCaptcha, which only a person in a browser can do, so
/// the row is a door: it wears the push row's trailing mark and its fact says
/// where it goes, so it never looks like it acts in place and then leaves
/// (§553b's promise). The address is copied first, because the page asks for
/// it.
struct FramesSendCard: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL

    /// **WHOSE HOME THIS IS (prd §774, user: "send and top up … on each
    /// account's home page … they may do it from home but may also from the
    /// account, but make it consistent").** nil is the room's All page, which
    /// acts for this phone's CURRENT account; an address is one account's own
    /// page, which acts for that account and makes it current the moment you
    /// send. `stranger` is an account this phone holds no key for: its page
    /// keeps the room's own verb, Create account, and nothing that would
    /// spend — a Send there could only ever send from somebody else.
    var account: String? = nil
    var stranger = false
    let onSend: () -> Void
    /// The faucet page, in the in-app Safari sheet (prd §653). It left for
    /// Safari, so after the captcha you had to find your way back.
    var onOpenPage: ((URL) -> Void)? = nil

    @State private var keyAddress: String? = FramesKey.address()
    @State private var creating = false
    @State private var createError: String?

    /// `DS.tint` rather than an invented hue — the seat's own icon is the
    /// brand and the console is chrome around it.
    private static let mark = DS.tint

    /// The Send row's fact when this phone holds more than one account here
    /// (prd §774): nil with one. Read on appear, never in the body — the
    /// build-525 rule — and set directly by `makeAnother`.
    @State private var from: String?
    /// The Top up row's fact when the tap did not open the page (the demo).
    @State private var topUpNote: String?

    var body: some View {
        if stranger {
            createOnly
        } else if keyAddress == nil && account == nil {
            create
        } else {
            VStack(alignment: .leading, spacing: 0) {
                DevnetSendPanel(
                    tint: Self.mark,
                    // A door, not an act: the faucet is a page a person
                    // mines and solves a captcha on (prd §962).
                    topUp: .init(note: topUpNote ?? String(localized: "Opens the faucet"),
                                 opens: true, action: topUp),
                    onSend: {
                        // This page's account becomes the one the send sheet
                        // signs as. A passkey account is not a `FramesKey`
                        // item, so `select` declines it and the room's scope
                        // says who sends (§728d).
                        FramesKey.select(account)
                        onSend()
                    },
                    // **CREATE STAYS ONCE THERE IS AN ACCOUNT (user, prd §774):**
                    // "even if user has one they may want another". It was
                    // drawn INSTEAD of this panel, so the first account closed
                    // the door behind it — vibenet's own fix, one chain over.
                    extras: [
                        .init(id: "create", title: String(localized: "Create\naccount"),
                              glyph: "plus.rectangle.on.rectangle", act: makeAnother),
                    ],
                    from: from)
                if let createError {
                    Text(createError)
                        .dsText(.label12)
                        .foregroundStyle(DS.destructiveInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DSRoomChassis.inset)
                        .padding(.bottom, DS.Space.s3)
                }
            }
            .task(id: account ?? "") { refreshFrom() }
        }
    }

    /// The account page of an address this phone holds no key for.
    private var createOnly: some View {
        VStack(alignment: .leading, spacing: 0) {
            DevnetVerbRow(title: String(localized: "Create account"),
                          glyph: "plus.rectangle.on.rectangle", tint: Self.mark,
                          busy: creating, act: makeAnother)
            if let createError {
                Text(createError)
                    .dsText(.label12)
                    .foregroundStyle(DS.destructiveInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DSRoomChassis.inset)
                    .padding(.bottom, DS.Space.s3)
            }
        }
    }

    /// Only the All page names the sender: an account's own page IS the name.
    private func refreshFrom() {
        let held = FramesKey.addresses()
        from = account == nil && held.count > 1
            ? FramesKey.address().map(WalletStore.shortAddress) : nil
    }

    /// A further account on this phone (prd §774). It is watched so it has a
    /// face on the rail, scoped so the room turns to it, and current so Send
    /// and Top up act for it — `FramesKey.createAnother` set that last part.
    private func makeAnother() {
        guard !creating else { return }
        guard !DemoMode.isActive else {
            createError = String(localized: "No key is made in the demo — this is where your own would be.")
            return
        }
        creating = true
        defer { creating = false }
        do {
            let made = try FramesKey.createAnother()
            createError = nil
            keyAddress = made
            _ = FramesWatch.shared.add(made)
            FramesBridge.registerBridge(store: store)
            chrome.framesScope = made
            refreshFrom()
            Task { await FramesLiveState.shared.refresh() }
            chrome.rain(sources: [FramesIdentity.source])
        } catch {
            createError = String(localized: "Couldn't make a key: \(String(describing: error))")
        }
    }

    // MARK: - Before there is a key

    /// **ONE TAP MAKES IT, and there is no screen in between** — §553's ruling
    /// for Hegotá, and the reasoning carries unchanged: a confirmation screen
    /// would ask the question the button just asked. Nothing rises here at all
    /// on this chain, since the key is a plain scalar rather than an Enclave
    /// one, so the tap IS the act.
    ///
    /// The copy makes no claim about the room that follows: making a key does
    /// not make the chain answer, and an account with no test ETH can send
    /// nothing yet.
    @ViewBuilder private var create: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DevnetCreatePanel(tint: Self.mark,
                              title: String(localized: "Create\naccount"),
                              busy: creating,
                              onCreate: makeKey)
            if let createError {
                Text(createError)
                    .dsText(.label12)
                    .foregroundStyle(DS.destructiveInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DSRoomChassis.inset)
                    .padding(.bottom, DS.Space.s3)
            }
        }
    }

    private func makeKey() {
        guard !creating else { return }
        creating = true
        defer { creating = false }
        do {
            let made = try FramesKey.create()
            keyAddress = made
            // Registered, or a room reached straight from the catalog has no
            // seat: the account would be missing from the rooms tray.
            FramesBridge.registerBridge(store: store)
            createError = nil
            // Read it now and turn the room to it, as `makeAnother` does. The
            // room reads this phone's key unwatched, but nothing asked it to
            // until the next sweep, so the new account stood under whatever
            // the crown last drew (measured: a demo fixture's 17.99 test ETH).
            chrome.framesScope = made
            refreshFrom()
            Task { await FramesLiveState.shared.refresh() }
            // The arrival is worth a moment — it is the only thing this seat
            // makes rather than reads. The seat's own tile falls (prd §655);
            // a bare bump rained the last pull's roster.
            chrome.rain(sources: [FramesIdentity.source])
        } catch {
            // The keychain's own answer, never a bare "it failed" (§531): a
            // code with no remedy is a dead end.
            createError = String(localized: "Couldn't make a key: \(String(describing: error))")
        }
    }

    // MARK: - Top up

    /// The CURRENT account, read at the tap: a face picked on the rail can
    /// have changed it since this card's state was set (prd §774). Copied, so
    /// the faucet's address field is one paste. Not in a demo: the tour's
    /// account is nobody's, and a live faucet page for it is the gap
    /// `devnet-console-audit.py` check 8 names.
    private func topUp() {
        guard !DemoMode.isActive else {
            topUpNote = String(localized: "The faucet isn't reached in the demo.")
            return
        }
        guard let address = account ?? FramesKey.address(),
              let url = URL(string: FramesNetwork.current.faucetPage) else { return }
        UIPasteboard.general.string = address
        chrome.flash(String(localized: "Address copied"))
        if let onOpenPage { onOpenPage(url) } else { openURL(url) }
    }
}

// MARK: - What a Frames send becomes

/// The steps the sheet draws between the figure and the keypad.
///
/// **Built from `FramesSend.plan(…)`, which is the object that gets signed** —
/// not a description of it. A preview drawn from a parallel description is how
/// a screen ends up promising two frames and sending three; here they are the
/// same `Fields`, so they cannot disagree.
///
/// Empty until there is a real recipient and a real amount, so the strip
/// appears when there is something true to say rather than sitting there as a
/// diagram of nothing.
enum FramesSendPlanSteps {
    @MainActor
    static func steps(destination: String, amount: String,
                      asset: DevnetSendAsset? = nil) -> [DevnetSendStep] {
        guard let sender = FramesKey.address().flatMap({ RLP.data(fromHex: $0) }),
              DevnetSendParse.isValidAddress(destination),
              let target = RLP.data(fromHex: destination)
        else { return [] }
        // The SENDER's nonce, not the first account read: with more than one
        // account here the first is often somebody else (prd §774).
        let nonce = FramesLiveState.shared.accounts.first(where: {
            $0.address.caseInsensitiveCompare(FramesKey.address() ?? "") == .orderedSame
        })?.nonce ?? 0
        // The same deadline rule the send signs with (prd §728b), so the
        // preview shows the deadline frame the transaction will really lead with.
        let deadline = FramesSend.deadline()

        let fields: FramesTransaction.Fields
        if let asset, !asset.id.isEmpty {
            guard let contract = RLP.data(fromHex: asset.id),
                  let units = DevnetSendParse.unitsData(from: amount, decimals: asset.decimals),
                  let leg = FramesTransaction.tokenLeg(contract: contract, to: target, amount: units)
            else { return [] }
            fields = FramesSend.planToken(sender: sender, leg: leg, nonce: nonce, deadline: deadline)
        } else {
            guard let wei = DevnetSendParse.weiData(from: amount) else { return [] }
            fields = FramesSend.plan(sender: sender, to: target, valueWei: wei,
                                     nonce: nonce, deadline: deadline)
        }
        return fields.frames.map { frame in
            DevnetSendStep(name: name(for: frame), detail: detail(for: frame))
        }
    }

    /// The chain's own words — `FramesSection.label`'s ruling: the chip is
    /// where the vocabulary gets learned, and this chain is named for frames.
    private static func name(for frame: FramesTransaction.Frame) -> String {
        if frame.mode == 1, frame.target == FramesTransaction.expiryVerifier {
            return String(localized: "Expiry")
        }
        if frame.mode == 0, frame.target == FramesPasskeyAccount.deployer {
            return String(localized: "Deploy")
        }
        return switch frame.mode {
        case 1: String(localized: "Verify")
        case 2: String(localized: "Sender")
        case 0: String(localized: "Default")
        default: String(localized: "Mode \(String(frame.mode))")
        }
    }

    /// **THE PERMISSION, said out loud.** A VERIFY frame's flags ARE the
    /// authorisation on this chain — there is no standing grant anywhere, so
    /// this is the only place it can be read (`FramesSection`'s Permissions
    /// ruling). Without an APPROVE the transaction has no payer and is
    /// invalid, so "approves both" is load-bearing rather than a detail.
    private static func detail(for frame: FramesTransaction.Frame) -> String {
        if frame.mode == 1, frame.target == FramesTransaction.expiryVerifier {
            let minutes = Int(FramesSend.deadlineWindow / 60)
            return String(localized: "lands within \(String(minutes)) min or never")
        }
        if frame.mode == 0, frame.target == FramesPasskeyAccount.deployer {
            return String(localized: "installs the account's code")
        }
        if frame.data.starts(with: FramesTransaction.erc20TransferSelector) {
            return String(localized: "sends the token")
        }
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
