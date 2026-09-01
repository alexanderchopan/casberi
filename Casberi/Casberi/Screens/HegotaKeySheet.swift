import SwiftUI
import SwiftData

/// THIS PHONE'S KEY ON HEGOTÁ, AS A SHEET (prd §525, 2026-08-29).
///
/// `VibenetCreateSheet`'s anatomy, one chain over: `DSSheetHead` — a disc, a
/// stamp, a title, one sentence saying what it means now — then a captioned
/// body, then one full-width control for whichever act the phase calls for.
/// No text-link verbs; the one thing a phase asks for gets the weight the
/// ready state's button gets.
///
/// **What is different from vibenet's sheet, stated rather than hidden.**
/// This key is `HegotaKey` — a plain secp256k1 scalar in the Keychain, not a
/// Secure Enclave key — on the user's own ruling that a devnet with worthless
/// money does not need hardware-backed non-export. The head says so in its own
/// sentence, because the difference from vibenet's promise is exactly the
/// kind of thing that must not be silently implied to be the same.
struct HegotaKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome

    // `onOpenSend` was HERE and is deleted (prd §539, 2026-08-31). It opened
    // `HegotaSendSheet` — a sheet raised from inside this sheet — and sending
    // is the room's own Home scope now (`HegotaSendCard`), so the closure had
    // no destination and its one call site had nothing to pass.

    @State private var presence: HegotaKey.Presence = .none
    @State private var busy = false
    @State private var keyFailure: String?
    @State private var faucetResult: String?
    /// Whether `faucetResult` is a REFUSAL. A refusal set in the same tertiary
    /// grey as a success reads as a footnote rather than as an answer — the
    /// §83 rule that a screen must not state a failure in the voice it uses
    /// for fine print.
    @State private var faucetFailed = false
    @State private var faucetBusy = false
    /// What the sheet's content actually measures — `trayHeight`'s whole
    /// input. 0 until the first layout pass.
    @State private var contentHeight: CGFloat = 0

    // The app's own accent, not `HegotaModeStyle.room` — this sheet is an
    // ordinary account/key screen, not a frame/vault reading, so it gets the
    // same blue every other primary action in the app uses (user: "that
    // cyan color blue or whatever it is... we don't use that anywhere else").
    private static let mark = DS.tint

    private enum Phase: Equatable { case noKey, ready, working }

    private var phase: Phase {
        switch presence {
        case .none, .destroyed: .noKey
        case .present:          busy ? .working : .ready
        }
    }

    var body: some View {
        // SCROLLABLE, AND DRAG-PAST (the `HegotaSendSheet`/`VibenetKeySheet`
        // fix for the same class of bug, §480/§526): this sheet was a bare
        // `VStack` with no `ScrollView`, so the ready phase's four stacked
        // sections (head, faucet, Send, Actions) clipped dead against the
        // fixed 560 the moment real device text metrics ran a line longer
        // than guessed — the Send/Actions rows sat below the tray's own
        // bottom edge with no way to reach them (user report: "the tray is
        // clipped at the bottom on create account"). A `ScrollView` plus
        // `detents: [.height(trayHeight), .large]` makes every reachable
        // state reachable regardless of how the numbers are guessed.
        DSTray(title: String(localized: "This phone's account"), height: trayHeight, ink: true,
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    DSSheetHead(disc: { headDisc },
                                stamp: headStamp,
                                stampWeight: headStampWeight,
                                title: headTitle,
                                secondary: headSecondary,
                                sentence: headSentence)
                    switch phase {
                    case .noKey:
                        noKeyBody
                    case .ready, .working:
                        readyBody
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.s4)
                // THE MEASUREMENT `trayHeight` rests on — see its doc.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    contentHeight = $0
                }
            }
            .scrollIndicators(.hidden)
        }
        .task { refresh() }
    }

    /// **MEASURED, NOT GUESSED — the fourth number in this slot, and the first
    /// that cannot be wrong (prd §542, 2026-08-31).** The history is 560 →
    /// 560 → 820 → 520, each a hand-sum of line counts that real device text
    /// metrics outran (the last one within a day: "the this phones account
    /// sheet doesn't fully show, has stuff hidden below and user needs to
    /// scroll. shouldn't be that way — all content should be able to be
    /// seen"). A hand-sum breaks every time a sentence gains a line, a result
    /// row appears, or Dynamic Type steps up — so the content now reports its
    /// own height and the tray fits it.
    ///
    /// The chrome constant is `DSTray`'s own documented model — top pad,
    /// `heading34` title (line 40), gap, content, bottom pad — the same
    /// arithmetic `SourcesTray.chromeHeight` spells. The cap keeps a tall
    /// phase a TRAY rather than a takeover; past it the `.large` detent is
    /// the escape, and the guessed fallbacks last only until the first layout
    /// pass reports in.
    private var trayHeight: CGFloat {
        guard contentHeight > 0 else {
            return phase == .noKey ? 380 : 560
        }
        let chrome = DS.Space.s6 + 40 + DS.Space.s4 + DS.Space.s6
        return min(contentHeight + chrome, 700)
    }

    // MARK: - Head

    private var headDisc: some View {
        ZStack {
            Circle()
                .fill(presence == .destroyed ? DS.destructive.opacity(0.16) : Self.mark.opacity(0.18))
                .frame(width: DS.Face.list, height: DS.Face.list)
            Image(systemName: presence == .destroyed ? "exclamationmark.triangle.fill" : "key.fill")
                .dsGlyph(presence == .destroyed ? 14 : 16, weight: .semibold)
                .foregroundStyle(presence == .destroyed ? DS.destructive : Self.mark)
        }
        .accessibilityHidden(true)
    }

    /// **THE HEAD DOES NOT RESTATE THE TRAY (prd §539, 2026-08-31).** The tray
    /// is titled "This phone's account" and this said "Your account on this
    /// phone" — the same sentence with its words reordered, in `heading22`
    /// directly under the `heading34` it was echoing. It is the mildest form
    /// of the fault §538 took out of three vibenet sheets, and the mildest
    /// form is the one that survives longest, because nothing about it reads
    /// as a bug.
    ///
    /// `.present` names WHICH account — the address, by its watched name where
    /// it has one, the resolution the room's own roster uses. The other two
    /// phases keep their words: those are STATES, not the tray's noun said
    /// twice, and each is the answer to "why is there nothing here".
    private var headTitle: String {
        switch presence {
        case .present:
            if let address = HegotaKey.address() {
                return HegotaWatch.shared.name(for: address)
                    ?? WalletStore.shortAddress(address)
            }
            // A key that is present while its address will not derive is a
            // STATE, and it gets a state's words like the two cases below —
            // not a paraphrase of the tray's own title, which is what stood
            // here and is the fault this whole ruling is about. It also says
            // more: "we have your key and cannot read its address" is a real
            // condition somebody can act on, where "Your account on this
            // phone" over a tray reading "This phone's account" said nothing
            // at all, twice.
            return String(localized: "Address unreadable")
        case .destroyed: return String(localized: "This phone's key is gone")
        case .none:      return String(localized: "No account yet")
        }
    }

    /// The chain, always — the address moved UP to the title, so this slot
    /// says where that address lives rather than repeating it. Same string in
    /// every phase now, which is correct: it is a fact about the seat, not
    /// about the key's state.
    private var headSecondary: String? {
        String(localized: "Hegotá \u{00B7} frame-transaction devnet")
    }

    private var headSentence: String? {
        switch presence {
        case .present:
            String(localized: "A plain secp256k1 key on this device, not the Secure Enclave \u{2014} there is nothing of value here to protect.")
        case .destroyed:
            String(localized: "It was removed from this phone's keychain. Making a new one is safe \u{2014} nothing on a devnet is lost by it.")
        case .none:
            String(localized: "This becomes an account on Hegot\u{00E1} that only this phone can sign for \u{2014} it sits beside the accounts you watch, but unlike those, you'll actually control this one: send test ETH from it, not just see what's in it.")
        }
    }

    private var headStamp: String? {
        switch presence {
        case .present:   String(localized: "Ready")
        case .destroyed: String(localized: "Gone")
        case .none:      nil
        }
    }

    private var headStampWeight: DSStamp.Weight {
        switch presence {
        case .present:   .good
        case .destroyed: .urgent
        case .none:      .quiet
        }
    }

    // MARK: - No key

    private var noKeyBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Button {
                DSHaptic.tap()
                makeKey()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").dsGlyph(13, weight: .semibold)
                    Text(String(localized: "Make an account on this phone"))
                }
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s3)
                .background(Self.mark, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .buttonStyle(PressSpring())
            .dsHover()
            if let keyFailure {
                Text(keyFailure)
                    .dsText(.label11)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Ready

    private var readyBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            // **THE ADDRESS, IN FULL AND COPYABLE (prd §539, 2026-08-31).**
            //
            // It was the head's `secondary` — displayed, never selectable —
            // and moving the short form up to the title (see `headTitle`)
            // would otherwise have left the full value nowhere on the sheet.
            // That is a loss worth catching: this is the screen you open to
            // RECEIVE test ETH, and an address you can read but not copy is
            // one you have to transcribe forty-two characters of by hand.
            //
            // So it comes back as a row rather than as a line — the same
            // wrapping, monospaced treatment every other full id in this app
            // gets — with the copy this sheet never had. `copySensitive`
            // rather than `copy`, the vault's own verb: an address is not a
            // secret, but the pasteboard it lands on is shared with every app
            // on the device and a devnet address is still an identifier
            // somebody chose to hold.
            if let address = HegotaKey.address() {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    caption(String(localized: "Address"))
                    Button {
                        DSHaptic.tap()
                        DSPasteboard.copySensitive(address)
                        chrome.flash(String(localized: "Address copied"))
                    } label: {
                        HStack(alignment: .top, spacing: DS.Space.s2) {
                            Text(address)
                                .dsText(.mono12)
                                .foregroundStyle(DS.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "doc.on.doc")
                                .accessibilityHidden(true)
                                .dsGlyph(12, weight: .semibold)
                                .foregroundStyle(Self.mark)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressSpring())
                    .dsHover()
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "Test ETH"))
                Button {
                    DSHaptic.tap()
                    claimFaucet()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill").dsGlyph(13, weight: .semibold)
                        Text(String(localized: "Claim from the faucet"))
                        if faucetBusy { ProgressView().controlSize(.mini) }
                    }
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s3)
                    .background(Self.mark, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressSpring())
                .disabled(faucetBusy)
                .dsHover()
                if let faucetResult {
                    Text(faucetResult)
                        .dsText(.label11)
                        .foregroundStyle(faucetFailed ? DS.destructive : DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Rate-limited to one claim per source IP per hour — measured,
                // not guessed (§525) — so the copy says why a second tap may
                // fail rather than leaving it to read as broken.
                Text(String(localized: "One claim per hour."))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
            }

            // **THE SEND BLOCK IS GONE (prd §539, 2026-08-31).** It was a door
            // to `HegotaSendSheet` — a sheet, opened from inside this sheet,
            // to reach the one thing a key is for. Sending is the room's own
            // Home scope now (`HegotaSendCard`), in front of everything rather
            // than two presentations behind it, so this button would open
            // nothing and its absence is what makes the form findable.
            //
            // This is also what retires the height problem this sheet was
            // reported for three times (560 → 560 → 820, "you can't see the
            // bottom of thi tray where it says send eth so someone seeing it
            // wont know it's there"). The content that kept falling past the
            // bottom edge was largely this block; the answer was never a
            // taller guess.

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "Actions"))
                Button {
                    DSHaptic.tap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").dsGlyph(12, weight: .semibold)
                        Text(String(localized: "Remove this key"))
                    }
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.destructive)
                }
                .buttonStyle(PressSpring())
                .dsHover()
                .simultaneousGesture(TapGesture().onEnded { removeKey() })
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
    }

    // MARK: - Acts

    private func refresh() {
        presence = HegotaKey.presence()
    }

    private func makeKey() {
        keyFailure = nil
        do {
            _ = try HegotaKey.create()
            DSHaptic.success()
            refresh()
            // The room BEHIND this sheet (user, 2026-08-30: "doesn't show a
            // new account was created"). `refresh()` updates this sheet's own
            // `presence`, which is all a person sees while the tray is open —
            // but `HegotaRoomList.thisPhoneRow`, in the room underneath,
            // isn't bound to that state at all. `FeedScreen.headIdentity`'s
            // own doc already names the reason Hegotá's room needs this:
            // it lands no row for anything, ever, so its corpus revision is
            // permanently frozen and `chrome.refreshPulse` is the ONLY
            // thing that moves its memoised head — the same fact that made
            // the room a permanent black box once before this key existed.
            // Making a key changes nothing `HegotaRoomSource.identity`
            // reads either, so without this the room kept showing "Create
            // an account" after one had just been made.
            chrome.refreshPulse += 1
        } catch {
            keyFailure = Self.keySentence(for: error)
        }
    }

    private func removeKey() {
        HegotaKey.delete()
        refresh()
        chrome.flash(String(localized: "Key removed"))
    }

    private func claimFaucet() {
        guard let address = HegotaKey.address() else { return }
        faucetBusy = true
        faucetResult = nil
        faucetFailed = false
        Task {
            defer { faucetBusy = false }
            do {
                let claim = try await HegotaSend.claimFaucet(for: address)
                DSHaptic.success()
                HegotaSend.landReceipt(txHash: claim.transactionHash, kind: .claimed, in: modelContext)
                faucetFailed = false
                faucetResult = String(localized: "Sent \u{2014} \(claim.transactionHash.prefix(10))\u{2026}")
                // The small grey line under the button is easy to miss below
                // the fold in a scrollable tray (user: "there is no toast
                // when faucet is claimed") — a real toast is the confirmation
                // that survives however far the sheet is scrolled.
                chrome.flash(String(localized: "Test ETH sent to this account"), tone: .success)
            } catch let f as HegotaSend.Failure {
                // THE VERDICT SAYS IT, not this screen (prd §531). The old
                // branch here grepped the failure TEXT for "429" — which
                // `postJSON` had already thrown away, so the friendly
                // rate-limit sentence could never once have been reached over
                // the one refusal this faucet is known to make.
                if case .faucet(let verdict) = f {
                    faucetResult = verdict.sentence
                    faucetFailed = true
                } else {
                    faucetResult = String(localized: "Couldn't reach the faucet.")
                    faucetFailed = true
                }
            } catch {
                faucetResult = String(localized: "Couldn't reach the faucet.")
                faucetFailed = true
            }
        }
    }

    private static func keySentence(for error: Error) -> String {
        guard let f = error as? HegotaKey.Failure else {
            return String(localized: "Couldn't make a key.")
        }
        switch f {
        case .alreadyExists:
            return String(localized: "There's already a key on this phone.")
        case .missing:
            return String(localized: "No key was found.")
        case .curve:
            return String(localized: "The key could not be generated.")
        case .selfCheck:
            return String(localized: "The new key didn't check out \u{2014} nothing was saved.")
        case .locked(let status):
            // Distinct from a refused WRITE (prd §531): this is the keychain
            // declining to be READ, which `create()` now reaches when there is
            // an item it cannot open — and the remedy is a locked device, not
            // a broken app. Never worded as a fault we can fix from here.
            return String(localized: "The keychain wouldn't open (code \(String(Int(status)))). Unlock this device and try again.")
        case .keychainRefused(let status):
            return String(localized: "The keychain refused (code \(String(Int(status)))).")
        }
    }
}
