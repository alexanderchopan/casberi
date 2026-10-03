import SwiftUI

/// THE FRAMES ROOM'S THREE VERBS — Create, Send, Top up — as the last three
/// TILES (prd §1039, 2026-10-01; the user approved three verb tiles in this
/// one room). They were rows in Home's Actions block (`FramesSendCard`, §750,
/// §774), which the merge deleted with the Overview rows under it.
///
/// **Each tile does exactly what its row did.** Send selects the page's account
/// and raises the room's one send sheet; Top up copies the address and opens
/// the faucet's page in the in-app Safari sheet (prd §962 — the faucet is
/// proof-of-work plus a captcha, so it is a door, never an in-place claim);
/// Create makes a key (the first) or another account (prd §774). What a row
/// said as its fact or under its title — "The faucet isn't reached in the
/// demo.", a keychain refusal — is a flash now, since a tile has no line.
///
/// **Which verbs a page offers is §774's rule, unchanged** (`verbs(for:)`):
/// All acts for this phone's current account, one of your own accounts acts
/// for itself, a stranger's page keeps Create alone, and a phone with no key
/// yet offers Create alone on All.
///
/// Nothing here presents: Send hands upward to the screen's single `.sheet`,
/// for the reason that has been paid for three times (a `.sheet` on a view in
/// a `List` row half-opens then closes).
@MainActor
enum FramesActs {

    /// The verb tiles for the page showing (prd §774). `account` is nil on the
    /// All page. Defaults reads only (`FramesKey`, the passkey address) — the
    /// Keychain is never asked from a body, the build-525 class.
    static func verbs(for account: String?) -> [FramesSection] {
        let mine = account == nil || FramesKey.holds(account)
            || FramesPasskey.accountAddress()
                .map { $0.caseInsensitiveCompare(account ?? "") == .orderedSame } == true
        guard mine else { return [.create] }
        // No key on this phone and the All page: Create is the one act; Send
        // and Top up would act for nobody.
        if account == nil, FramesKey.address() == nil { return [.create] }
        return FramesSection.verbs
    }

    /// Send: this page's account becomes the one the send sheet signs as. A
    /// passkey account is not a `FramesKey` item, so `select` declines it and
    /// the room's scope says who sends (§728d).
    static func send(account: String?, open: () -> Void) {
        FramesKey.select(account)
        open()
    }

    /// Top up: the CURRENT account, read at the tap (prd §774), copied so the
    /// faucet's address field is one paste. Not in a demo: the tour's account
    /// is nobody's, and a live faucet page for it is the gap
    /// `devnet-console-audit.py` check 8 names.
    static func topUp(account: String?, chrome: ShellChrome, openPage: (URL) -> Void) {
        guard !DemoMode.isActive else {
            chrome.flash(String(localized: "The faucet isn't reached in the demo."))
            return
        }
        guard let address = account ?? FramesKey.address(),
              let url = URL(string: FramesNetwork.current.faucetPage) else { return }
        UIPasteboard.general.string = address
        chrome.flash(String(localized: "Address copied"))
        openPage(url)
        watchForDeposit(address: address, chrome: chrome)
    }

    // MARK: - The top up's return trip (prd §1089)

    private static var depositWatch: Task<Void, Never>?

    /// **THE FAUCET IS A PAGE, SO THE ROOM WAITS FOR WHAT IT SENDS (prd
    /// §1089).** Top up handed you to a captcha and proof of work and then
    /// said nothing; whether it had paid was a pull-to-refresh you had to
    /// think of. This reads the one balance every few seconds for ten
    /// minutes — `eth_getBalance` on the host `NetworkReach` already declares
    /// — and says what arrived the moment it does, then reads the room.
    ///
    /// **An increase, never a change**: a send from this account in the
    /// window lowers the balance and must not read as a deposit. A balance
    /// that does not read is skipped, never a zero (§515a). A second tap
    /// replaces the watch rather than stacking two.
    static func watchForDeposit(address: String, chrome: ShellChrome) {
        depositWatch?.cancel()
        depositWatch = Task { @MainActor in
            guard let before = await balance(address) else { return }
            let until = Date().addingTimeInterval(depositWindow)
            while !Task.isCancelled, Date() < until {
                try? await Task.sleep(for: .seconds(depositPoll))
                guard !Task.isCancelled, let now = await balance(address), now > before else { continue }
                let arrived = NSDecimalNumber(decimal: (now - before) / FramesMoney.weiPerETH).doubleValue
                DSHaptic.success()
                chrome.flash(String(localized: "\(FramesMoney.eth(arrived)) test ETH arrived"), tone: .success)
                chrome.rain(sources: [FramesIdentity.source])
                await FramesLiveState.shared.refresh()
                return
            }
        }
    }

    static let depositWindow: TimeInterval = 10 * 60
    static let depositPoll: Double = 8

    private static func balance(_ address: String) async -> Decimal? {
        guard let hex = await FramesRPC.call(method: "eth_getBalance", params: [address, "latest"]) as? String
        else { return nil }
        return FramesMoney.decimal(fromHex: hex)
    }

    /// Create: **ONE TAP MAKES IT, and there is no screen in between** (§553).
    /// The first key on this phone (`FramesKey.create`), or a further account
    /// (prd §774, "even if user has one they may want another"), which is
    /// watched so it has a face, scoped so the room turns to it, and current
    /// so Send and Top up act for it. The copy makes no claim about the room
    /// that follows: a new account with no test ETH can send nothing yet.
    static func create(store: BridgeStore, chrome: ShellChrome) {
        guard !DemoMode.isActive else {
            chrome.flash(String(localized: "No key is made in the demo — this is where your own would be."))
            return
        }
        let first = FramesKey.addresses().isEmpty
        do {
            let made = first ? try FramesKey.create() : try FramesKey.createAnother()
            // A later account is watched so it has a face on the rail; the
            // first is read unwatched, as this phone's own key always was.
            if !first { _ = FramesWatch.shared.add(made) }
            // Registered, or a room reached straight from the catalog has no
            // seat: the account would be missing from the rooms tray.
            FramesBridge.registerBridge(store: store)
            // Read it now and turn the room to it — the room reads this
            // phone's key, but nothing asked it to until the next sweep, so
            // the new account stood under whatever the crown last drew.
            chrome.framesScope = made
            Task { await FramesLiveState.shared.refresh() }
            // The arrival is worth a moment — it is the only thing this seat
            // makes rather than reads. The seat's own tile falls (prd §655).
            chrome.rain(sources: [FramesIdentity.source])
        } catch {
            // The keychain's own answer, never a bare "it failed" (§531): a
            // code with no remedy is a dead end.
            chrome.flash(String(localized: "Couldn't make a key: \(String(describing: error))"),
                         tone: .failure)
        }
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
        case 2: String(localized: "Send")
        case 0: String(localized: "Call")
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
