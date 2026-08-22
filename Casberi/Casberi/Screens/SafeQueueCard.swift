import SwiftUI

/// A Safe multisig thing's live queue card (2026-07-20, rebuilt 2026-07-30) —
/// the same shape as `ApprovalPrepareCard`: a read-only recheck, rendered only
/// once it's answered (no spinner theater).
///
/// The 2026-07-30 rebuild is about ONE idea: a Safe is the only object in this
/// app where other people act on your behalf and you wait on them. Every other
/// bridge is solo. So the queue is drawn as the PEOPLE it's waiting on — each
/// owner's own `WalletFace`, lit when they've signed and dim when they
/// haven't, yours marked — instead of the bare fraction "2 of 3", which says
/// nothing about who to go ask. Names come from `WalletIngest.knownLabel`'s
/// existing chain (address-book name → Farcaster handle → short hex), so a
/// person who has named their co-signers sees people, not hex.
///
/// Two facts the old card couldn't state, both cheap and both the kind almost
/// no interface surfaces: a same-nonce CONFLICT (a Safe executes exactly one
/// transaction per nonce, so signing this one may be wasted), and the door out
/// to the person's own Safe app — the one action this app deliberately can't
/// do, and until now had no way to hand off.
struct SafeQueueCard: View {
    let check: SafeBridge.Check
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            switch check.status {
            case .pending(let have, let required):
                pendingHead(have: have, required: required)
                if !check.roster.isEmpty { roster }
                if check.conflicts > 0 { conflictNote }
            case .executed:
                statusLine(icon: "checkmark.circle", tone: DS.confirm,
                           text: "Executed — the transaction went through.")
                if !check.roster.isEmpty { roster }
            case .replaced:
                statusLine(icon: "arrow.triangle.2.circlepath", tone: DS.textTertiary,
                           text: "Replaced — a different transaction executed at this position instead.")
            }
            if let door = check.doorURL, let url = URL(string: door) {
                doorRow(icon: "arrow.up.right", label: "Open in Safe") { openURL(url) }
            }
            Text("Signatures happen in your Safe app — never here.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    // MARK: - Head

    /// The disc carries the count so the sentence doesn't have to, and the
    /// sentence spends its words on the thing a fraction can't say: who is
    /// left, or that nobody is.
    private func pendingHead(have: Int, required: Int) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            SafeSignatureDisc(have: have, required: required)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: headline(have: have, required: required))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = subline(have: have, required: required) {
                    Text(verbatim: sub)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func headline(have: Int, required: Int) -> String {
        if check.readyToExecute {
            return String(localized: "Fully signed — ready to execute")
        }
        let waiting = check.waitingOn
        // "Your signature is the one missing" is the whole feature in a
        // sentence, and it's only sayable when we know which seat is yours.
        if waiting.count == 1, waiting[0].isYou {
            return String(localized: "Yours is the last signature needed")
        }
        if waiting.contains(where: \.isYou) {
            return String(localized: "Waiting on you and \(waiting.count - 1) other")
        }
        guard !waiting.isEmpty else {
            return required > 0
                ? String(localized: "\(have) of \(required) signatures collected")
                : String(localized: "\(have) signatures collected")
        }
        if waiting.count == 1 {
            return String(localized: "Waiting on \(waiting[0].displayName)")
        }
        return String(localized: "Waiting on \(waiting[0].displayName) and \(waiting.count - 1) other")
    }

    private func subline(have: Int, required: Int) -> String? {
        guard required > 0 else { return nil }
        if check.readyToExecute {
            return String(localized: "\(have) of \(required) — anyone can execute it now")
        }
        let short = required - have
        return String(localized: "\(have) of \(required) · \(short) more to go")
    }

    // MARK: - The people

    private var roster: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(check.roster) { signer in
                HStack(spacing: DS.Space.s2) {
                    WalletFace(address: signer.address, size: DS.Face.row, circular: true)
                        .opacity(signer.signed ? 1 : 0.38)
                        .overlay(alignment: .bottomTrailing) {
                            if signer.signed {
                                Image(systemName: "checkmark.circle.fill")
                                    .dsGlyph(10, weight: .bold)
                                    .foregroundStyle(DS.confirm)
                                    .background(Circle().fill(DS.page).padding(1))
                                    .offset(x: 2, y: 2)
                            }
                        }
                    Text(verbatim: signer.isYou
                         ? String(localized: "\(signer.displayName) (you)")
                         : signer.displayName)
                        .dsText(.subhead13)
                        .foregroundStyle(signer.signed ? DS.textPrimary : DS.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: signer.signed
                         ? signedLabel(signer)
                         : String(localized: "waiting"))
                        .dsText(.label12)
                        .foregroundStyle(signer.signed ? DS.textTertiary : DS.textSecondary)
                }
            }
        }
    }

    /// When they signed, relative — "2h ago". A confirmation with an
    /// unparseable stamp still counts as signed (the signature is the fact);
    /// it just doesn't claim a time it doesn't have.
    private func signedLabel(_ signer: SafeBridge.Signer) -> String {
        guard let at = signer.signedAt, at != .distantPast else {
            return String(localized: "signed")
        }
        return at.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }

    // MARK: - Conflict

    /// A Safe executes exactly one transaction per nonce. Two live at the
    /// same one means only one can ever land — so a signature spent on the
    /// loser is spent for nothing. Stated plainly, not as an alarm: it's a
    /// fact about how Safes work, not a sign anything is wrong.
    private var conflictNote: some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            Image(systemName: "arrow.triangle.branch")
                .dsGlyph(13, weight: .regular)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 18)
            Text(check.conflicts == 1
                 ? "Another transaction is queued at the same position — only one of the two can execute."
                 : "\(check.conflicts) other transactions are queued at the same position — only one of them can execute.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Bits

    private func statusLine(icon: String, tone: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: icon)
                .dsGlyph(15, weight: .regular)
                .foregroundStyle(tone)
            Text(text)
                .dsText(.callout15).foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func doorRow(icon: String, label: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: icon)
                    .dsGlyph(13, weight: .regular)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
    }
}

/// The signature ring — `MetricDisc`'s doctrine applied to a multisig: a
/// generic glyph names nothing, so this one is segmented by the Safe's OWN
/// owner count and fills per signature collected. A 2-of-3 and a 4-of-7 draw
/// visibly different marks because they ARE different, and the count sits in
/// the middle so the disc states the whole fact alone.
struct SafeSignatureDisc: View {
    let have: Int
    let required: Int
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// **The signatures land one at a time** (2026-08-04, prd §298), in the
    /// order they were collected. The disc's whole claim is that this is a
    /// COUNT toward a threshold, so counting them in is the claim drawn; a
    /// ring that faded in whole would state the same fraction and none of the
    /// accumulation. Segments that are still missing appear immediately —
    /// they're the track, not the reading.
    @State private var landed = false

    private var met: Bool { required > 0 && have >= required }

    var body: some View {
        ZStack {
            Circle().fill(DS.fillFaint)
            // One segment per required signature, with a hairline gap — the
            // ring counts, it doesn't just fill. Drawn as trims rather than a
            // dashed stroke so the gaps stay even at any `required`.
            if required > 0 {
                ForEach(0..<required, id: \.self) { i in
                    let span = 1.0 / Double(required)
                    let gap = min(0.02, span * 0.18)
                    Circle()
                        .trim(from: Double(i) * span + gap / 2,
                              to: Double(i + 1) * span - gap / 2)
                        .stroke(i < have ? (met ? DS.confirm : DS.tint) : DS.textTertiary.opacity(0.28),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        // A collected signature counts itself in; an empty
                        // segment is the track and is simply there.
                        .opacity(i < have && !landed ? 0 : 1)
                        .animation(reduceMotion ? nil
                                   : ChartEntrance.arrive(index: i), value: landed)
                }
            }
            Text(verbatim: required > 0 ? "\(have)/\(required)" : "\(have)")
                .dsText(.label12)
                .monospacedDigit()
                .foregroundStyle(met ? DS.confirm : DS.textPrimary)
        }
        .frame(width: size, height: size)
        // Still animates when a signature actually LANDS later — what this
        // modifier was here for.
        .animation(DS.Motion.standard, value: have)
        .onAppear { landed = true }
        .accessibilityElement()
        .accessibilityLabel(required > 0
                            ? Text("\(have) of \(required) signatures collected")
                            : Text("\(have) signatures collected"))
        // Tooltip but no hover, deliberately: the ring is a readout, not a
        // control, and a pointer lift on something a click can't act on is the
        // dead affordance the honesty rule bans. Naming a wordless mark is
        // exactly what `dsTooltip` is for — same sentence VoiceOver reads.
        .dsTooltip(required > 0
                   ? String(localized: "\(have) of \(required) signatures collected")
                   : String(localized: "\(have) signatures collected"))
    }
}

// MARK: - Signing, when this phone is an owner (prd §425)

/// The ask (`docs/signer-spec.md` §9), drawn under the queue card it belongs
/// to rather than as a screen of its own — the pending transaction is already
/// on screen as a money receipt with a flat bottom edge (`MoneyReceipt` has
/// meant "still in the machine" by that edge since §363), and the one thing
/// missing was a way to say yes.
///
/// **It draws nothing at all until the chain has answered**, and that is the
/// design rather than a loading state: every refusal in `SafeSigner` is read
/// from the chain, so a Sign button rendered optimistically would be a button
/// that might turn out to be a lie. `ApprovalPrepareCard`'s rule — no spinner
/// theater, render once it is answered.
///
/// **A refusal is a sentence, never a hidden button.** A co-signer that
/// silently declines is indistinguishable from one that is broken, and the
/// person's next move differs for every case: a threshold of 1 needs an
/// on-chain change, "not an owner" needs the address pasted into their other
/// wallet, and a hash mismatch needs them to not sign anywhere.
struct SafeSignBlock: View {
    /// `wallet:safe:<seg>:<safeTxHash>` — the thing's own ref.
    let sourceRef: String
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome

    @State private var phase: Phase = .checking
    @State private var signing = false

    private enum Phase {
        case checking
        case ready(SafeSigner.Ready)
        case refused(SafeSigner.Refusal)
        case keyDestroyed
        case done
    }

    private var parts: (seg: String, hash: String)? {
        let bits = sourceRef.split(separator: ":", maxSplits: 3).map(String.init)
        guard bits.count == 4, bits[0] == "wallet", bits[1] == "safe" else { return nil }
        return (bits[2], bits[3])
    }

    var body: some View {
        Group {
            switch phase {
            case .checking:
                EmptyView()
            case .ready(let ready):
                readyBody(ready)
            case .refused(let refusal):
                // Only the refusals that are ABOUT this phone are worth a
                // sentence. "No key" and "nothing to do" are the ordinary
                // states of almost every Safe row in the corpus, and a
                // paragraph explaining them on each one is noise.
                if let sentence = sentence(for: refusal) {
                    Text(verbatim: sentence)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .keyDestroyed:
                Text("This phone's signing key is gone — Face ID was re-enrolled, which erases it by design. Make a new one in the Safe screen and have another owner swap the old address out.")
                    .dsText(.subhead13).foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            case .done:
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "checkmark.circle.fill").dsGlyph(15)
                        .foregroundStyle(DS.confirm)
                    Text("Signed from this phone.")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                }
                .settleIn()
            }
        }
        .task {
            guard let parts else { return }
            // The key can be GONE rather than merely locked — `.biometryCurrentSet`
            // destroys the item when the enrolled set changes. Said here as well
            // as on the setup screen, because this is where somebody is standing
            // when they find out.
            if SignerKey.presence() == .destroyed { phase = .keyDestroyed; return }
            guard SignerKey.exists else { return }
            switch await SafeSigner.prepare(seg: parts.seg, safeTxHash: parts.hash) {
            case .success(let ready): phase = .ready(ready)
            case .failure(let refusal): phase = .refused(refusal)
            }
        }
    }

    @ViewBuilder private func readyBody(_ ready: SafeSigner.Ready) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: reading(ready))
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            // An N-of-N Safe is stated, never REFUSED over (prd §426
            // amendment). Declining to sign here would be the lock itself: in
            // a 2-of-2 that names this phone, our refusal is what stops the
            // Safe reaching its threshold. So the honest move is to say what
            // is true and keep signing — and to say the opposite when the
            // transaction in front of us is the repair.
            if ready.standing.hasNoSpareOwner {
                Text(verbatim: ready.addsASpareOwner
                     ? String(localized: "This is the fix: it gives the Safe an owner to spare, so losing one key stops being final.")
                     : String(localized: "This Safe needs every owner it has. If this phone goes, it can't be signed for again — or repaired, since that needs a signature too."))
                    .dsText(.subhead13)
                    .foregroundStyle(ready.addsASpareOwner ? DS.confirm : DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                DSHaptic.tap()
                Task { await sign(ready) }
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "faceid").dsGlyph(15)
                    Text(signing ? "Signing…" : "Sign")
                        .dsText(.callout15).fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(signing ? DS.gray100 : DS.tint, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(PressSpring())
            .disabled(signing)
            Text("Casberi signs; it can't execute. Another owner sends it.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    /// What the calldata SAYS, or an honest refusal to say (§8.5). A fluent
    /// wrong summary is the one failure here that costs real money, so an
    /// unrecognised selector shows the four bytes and the hash instead of a
    /// guess.
    ///
    /// **Amounts stay in base units, and that is deliberate on this one
    /// screen.** Everywhere else in this app a figure is divided by its
    /// decimals and rounded for reading — `SafeBridge.describe` does exactly
    /// that for the feed row. Here the number is what somebody is about to
    /// authorize, an ERC-20's decimals are a property of a contract we have
    /// not read, and `Double` loses precision above 2^53 (which a wei figure
    /// crosses at 0.009 ETH). Precise and awkward beats pretty and slightly
    /// wrong; the money receipt above this block carries the readable
    /// version, and the unit is named in words so the two cannot be confused.
    ///
    /// It composes only from what `SafeCalldata` READ out of the bytes — never
    /// from the title or from the service's `dataDecoded`.
    private func reading(_ ready: SafeSigner.Ready) -> String {
        switch ready.reading {
        case .send:
            return String(localized: "Sends \(ready.tx.value) wei to \(WalletStore.shortAddress(ready.tx.to)).")
        case .rejection:
            return String(localized: "Cancels whatever else is proposed at this position. Moves nothing.")
        case .erc20Transfer(let recipient, let amount):
            return String(localized: "Transfers \(amount) base units of \(WalletStore.shortAddress(ready.tx.to)) to \(WalletStore.shortAddress(recipient)).")
        case .erc20Approve(let spender, let amount):
            return String(localized: "Lets \(WalletStore.shortAddress(spender)) spend up to \(amount) base units of \(WalletStore.shortAddress(ready.tx.to)).")
        case .erc20TransferFrom(let from, let recipient, _):
            return String(localized: "Moves tokens from \(WalletStore.shortAddress(from)) to \(WalletStore.shortAddress(recipient)).")
        case .addOwner(let owner, let threshold):
            return String(localized: "Adds \(WalletStore.shortAddress(owner)) as an owner and sets the threshold to \(threshold).")
        case .removeOwner(let owner):
            return String(localized: "Removes \(WalletStore.shortAddress(owner)) as an owner.")
        case .swapOwner(let old, let new):
            return String(localized: "Replaces owner \(WalletStore.shortAddress(old)) with \(WalletStore.shortAddress(new)).")
        case .changeThreshold(let threshold):
            return String(localized: "Changes how many signatures this Safe needs to \(threshold).")
        case .enableModule(let module):
            return String(localized: "Lets \(WalletStore.shortAddress(module)) move funds without any signature at all.")
        case .setGuard(let guardAddress):
            return String(localized: "Puts \(WalletStore.shortAddress(guardAddress)) in front of every transaction.")
        case .batch:
            return String(localized: "A batch of several calls. Casberi won't summarise a batch — read it in your Safe app before signing.")
        case .undecoded(let selector):
            return String(localized: "Casberi can't read what this does. It calls \(selector) on \(WalletStore.shortAddress(ready.tx.to)). Hash \(ready.safeTxHash).")
        }
    }

    private func sentence(for refusal: SafeSigner.Refusal) -> String? {
        switch refusal {
        case .noKey, .nothingToDo:
            return nil
        case .chainUnsupported:
            return String(localized: "Casberi can't sign on this chain — it can't re-check the hash against the Safe there, and it won't sign one it worked out alone.")
        case .thresholdTooLow(let threshold):
            return String(localized: "This Safe executes on \(threshold) signature, so signing here would let one key spend on its own. Raise the threshold to 2 first.")
        case .notAnOwner:
            return String(localized: "This phone isn't an owner of this Safe yet. Add its address from your other wallet.")
        case .chainUnreadable:
            return String(localized: "Couldn't reach the chain to re-check this transaction, so Casberi won't sign it. Try again in a moment.")
        case .proposalUnreadable:
            return String(localized: "Couldn't read this proposal well enough to sign it.")
        case .hashMismatch, .serviceHashMismatch:
            return String(localized: "The Safe's own hash for this transaction doesn't match what Casberi worked out. Don't sign this anywhere until you know why.")
        }
    }

    private func sign(_ ready: SafeSigner.Ready) async {
        signing = true
        defer { signing = false }
        guard let parts else { return }
        switch await SafeSigner.sign(seg: parts.seg, safeTxHash: parts.hash) {
        case .posted:
            phase = .done
            SafeSigner.land(context: modelContext, ready: ready, posted: true)
            chrome.flash(String(localized: "Signed"), tone: .success)
        case .signedNotPosted(let signature, _):
            // The signature EXISTS — a service outage must never throw away a
            // Face ID the person already gave, so it goes to the clipboard for
            // tier 0 (paste it into the Safe app) and lands as a thing.
            phase = .done
            SafeSigner.land(context: modelContext, ready: ready, posted: false)
            DSPasteboard.copySensitive(signature)
            chrome.flash(String(localized: "Signed, but Safe's service didn't take it — the signature is on your clipboard"),
                         tone: .failure)
        case .refused(let refusal):
            phase = .refused(refusal)
        case .keyRefused(let failure):
            phase = .refused(.noKey)
            chrome.flash(keySentence(failure), tone: .failure)
        }
    }

    private func keySentence(_ failure: SignerKey.Failure) -> String {
        switch failure {
        case .locked:
            // The likeliest case by far is a cancelled prompt; the other is an
            // item invalidated because the biometric enrollment changed, which
            // the setup copy warned about. Neither is recoverable here.
            return String(localized: "Face ID didn't unlock the key.")
        case .missing:
            return String(localized: "This phone has no signing key.")
        case .selfCheck:
            return String(localized: "The signature didn't come back as this phone's address, so Casberi threw it away.")
        default:
            return String(localized: "Couldn't sign on this device.")
        }
    }
}
