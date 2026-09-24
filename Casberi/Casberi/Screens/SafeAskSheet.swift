import SwiftUI
import SwiftData

/// THE LIVE ASK (prd §913) — a paired app rang while you hold the phone, or
/// you pasted a request, and here is what it wants signed. One sheet for
/// the three shapes this phone signs; each shape's block is the same block
/// its landed row draws, so a request over the relay and a row in the feed
/// cannot describe one thing two ways.
///
/// **Everything on it is derived from what would be signed.** The
/// transaction block reads the ten fields, the statement block reads the
/// words behind the hash, the recovery block reads the owner set off the
/// chain — and each draws nothing until the chain has answered every
/// refusal (`ApprovalPrepareCard`'s rule: no spinner theater).
///
/// **The verb is the block's.** This sheet adds only the head (who asks, for
/// which address) and, for a paired ask, the way to say no. A pasted ask
/// has no one to say no to; closing the sheet is the no.
struct SafeAskSheet: View {
    let ask: SafePeer.PendingAsk
    /// True when a paired app is waiting on the relay for the answer; false
    /// for a paste, where the answer goes to the clipboard.
    let paired: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        DSTray(title: title, height: 620, ink: true, detents: [.height(620), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    head
                    block
                    if paired {
                        DSDoorRow(icon: "xmark", label: "Decline", role: .destructive) {
                            Task {
                                await SafePeer.decline(ask)
                                dismiss()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var title: String {
        switch ask.ask {
        case .safeTx: return String(localized: "Sign a Safe transaction")
        case .safeMessage: return String(localized: "Sign a statement")
        case .recovery: return String(localized: "Approve a recovery")
        }
    }

    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSProse.text(paired
                         ? "\(ask.app) asks this phone to sign, as \(WalletStore.shortAddress(ask.address))."
                         : "A pasted request for \(WalletStore.shortAddress(ask.address)).")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var block: some View {
        switch ask.ask {
        case .safeTx(let chainId, let safe, let tx, let requesterHash):
            SafeSignBlock(inHand: chainId, safe: safe, tx: tx, requesterHash: requesterHash,
                          onSigned: paired ? deliver : nil)
        case .safeMessage(let chainId, let safe, let innerHash, let requesterHash):
            SafeStatementBlock(source: .inHand(chainId: chainId, safe: safe, innerHash: innerHash,
                                               requesterHash: requesterHash),
                               onSigned: paired ? deliver : nil)
        case .recovery(let request, let requesterHash):
            SafeRecoveryBlock(request: request, requesterHash: requesterHash,
                              onSigned: paired ? deliver : nil)
        }
    }

    private func deliver(_ signature: String) {
        Task {
            let delivered = await SafePeer.deliver(ask, signature: signature)
            chrome.flash(delivered
                         ? String(localized: "Signed — sent back to \(ask.app)")
                         : String(localized: "Signed, but the relay didn't take the answer — the signature is on your clipboard"),
                         tone: delivered ? .success : .failure)
            if !delivered { DSPasteboard.copySensitive(signature) }
            dismiss()
        }
    }
}

// MARK: - A statement

/// What a Safe is being asked to SAY, and the one Sign for it (prd §913).
/// Drawn under a landed `wallet:safemsg:` row and on the live ask alike.
struct SafeStatementBlock: View {
    enum Source: Equatable {
        /// `wallet:safemsg:<seg>:<safeMessageHash>` — the row's ref, and the
        /// Safe it was landed for; the words are fetched by that hash.
        case landed(ref: String, safe: String)
        case inHand(chainId: Int, safe: String, innerHash: [UInt8], requesterHash: [UInt8]?)
    }
    let source: Source
    var onSigned: ((String) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome

    @State private var phase: Phase = .checking
    @State private var signing = false
    @State private var attempt = 0
    /// Tier 0's second half: when the service does not know the words, the
    /// person pastes the statement itself and the hash must match.
    @State private var pastedWords = ""

    private enum Phase {
        case checking
        case ready(SafeStatementSigner.Ready)
        case refused(SafeStatementSigner.Refusal)
        case done
    }

    var body: some View {
        Group {
            switch phase {
            case .checking:
                EmptyView()
            case .ready(let ready):
                readyBody(ready)
            case .refused(let refusal):
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(verbatim: sentence(for: refusal))
                        .dsText(.subhead12).foregroundStyle(refusalTone(refusal))
                        .fixedSize(horizontal: false, vertical: true)
                    if case .messageUnknown = refusal, case .inHand = source {
                        pasteField
                    }
                    if case .chainUnreadable = refusal {
                        DSSlabDoor(title: String(localized: "Try again"), systemImage: "arrow.clockwise") {
                            phase = .checking
                            attempt += 1
                        }
                    }
                }
            case .done:
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "checkmark.circle.fill").dsGlyph(.subhead)
                        .foregroundStyle(DS.confirm)
                    Text("Signed from this phone.")
                        .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                }
                .settleIn()
            }
        }
        .task(id: attempt) {
            guard SafeSigner.hasAnyKey else { return }
            switch await prepare() {
            case .success(let ready): phase = .ready(ready)
            case .failure(let refusal): phase = .refused(refusal)
            case nil: break
            }
        }
    }

    /// The pasted statement as the signer takes it — typed data when it
    /// parses as JSON, else the text verbatim.
    private var pastedMessage: Any? {
        let trimmed = pastedWords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        return trimmed
    }

    private func prepare() async -> Result<SafeStatementSigner.Ready, SafeStatementSigner.Refusal>? {
        switch source {
        case .landed(let ref, let safe):
            return await SafeStatementSigner.prepare(landedRef: ref, safe: safe)
        case .inHand(let chainId, let safe, let innerHash, let requesterHash):
            return await SafeStatementSigner.prepare(chainId: chainId, safe: safe, innerHash: innerHash,
                                                     requesterHash: requesterHash, pasted: pastedMessage)
        }
    }

    @ViewBuilder private var pasteField: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            TextField(String(localized: "Paste the statement itself"), text: $pastedWords, axis: .vertical)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .tint(DS.tint)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...8)
                .padding(.horizontal, DS.Space.s3)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsWell(cornerRadius: DS.Radius.control, recessed: true)
            DSSlabDoor(title: String(localized: "Read it"), systemImage: "text.magnifyingglass") {
                phase = .checking
                attempt += 1
            }
        }
    }

    @ViewBuilder private func readyBody(_ ready: SafeStatementSigner.Ready) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            statementLines(ready.statement)
            if ready.required > 0 {
                line(String(localized: "Signatures"), String(localized: "\(ready.have) of \(ready.required)"))
            }
            DSActVerb(title: signing ? String(localized: "Signing…") : String(localized: "Sign"),
                      glyph: "faceid", busy: signing) {
                Task { await sign(ready) }
            }
            DSFootnote("A statement, not a transaction — nothing moves. Casberi signs only what it can name.")
        }
    }

    /// The statement in its own words. Only the two vocabularies this app
    /// names ever reach here; an unreadable one is a refusal above.
    @ViewBuilder private func statementLines(_ statement: SafeStatement) -> some View {
        switch statement {
        case .signIn(let siwe):
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                DSProse.text("Sign in to \(siwe.domain) as your Safe.")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let statement = siwe.statement {
                    Text(verbatim: statement)
                        .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                line(String(localized: "Site"), siwe.uri)
                line(String(localized: "Chain"), String(siwe.chainId))
                if let expires = siwe.expirationTime { line(String(localized: "Expires"), expires) }
            }
        case .snapshotVote(let vote):
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                DSProse.text("Vote in \(vote.space) as your Safe.")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                line(String(localized: "Proposal"), vote.proposal)
                line(String(localized: "Choice"), vote.choice)
                if let reason = vote.reason { line(String(localized: "Reason"), reason) }
            }
        case .unreadable(let why):
            Text(verbatim: why)
                .dsText(.subhead12).foregroundStyle(DS.attention)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: label).dsText(.subhead12).foregroundStyle(DS.textTertiary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: value).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3).truncationMode(.middle)
        }
    }

    private func refusalTone(_ refusal: SafeStatementSigner.Refusal) -> Color {
        switch refusal {
        case .hashMismatch, .requesterHashMismatch, .messageMismatch, .signatureNotAccepted: return DS.destructive
        case .unreadable: return DS.attention
        default: return DS.textTertiary
        }
    }

    private func sentence(for refusal: SafeStatementSigner.Refusal) -> String {
        switch refusal {
        case .noKey:
            return String(localized: "This phone has no signing key.")
        case .chainUnsupported:
            return String(localized: "Casberi can't sign on this chain — it can't re-check the hash against the Safe there.")
        case .chainUnreadable:
            return String(localized: "Couldn't reach the chain to re-check this statement, so Casberi won't sign it. Try again in a moment.")
        case .thresholdTooLow(let threshold):
            return String(localized: "This Safe executes on \(threshold) signature, so signing here would let one key speak for it alone. Raise the threshold to 2 first.")
        case .notAnOwner:
            return String(localized: "This phone isn't an owner of this Safe yet.")
        case .hashMismatch, .requesterHashMismatch:
            return String(localized: "The Safe's own hash for this statement doesn't match what Casberi worked out. Don't sign this anywhere until you know why.")
        case .messageUnknown:
            return String(localized: "Casberi can't see the words behind this hash: Safe's service has no record of it yet. Paste the statement itself, or have it proposed from your Safe app first.")
        case .messageMismatch:
            return String(localized: "The words Casberi found don't hash to what this request names, so it won't sign them.")
        case .unreadable(let why):
            return why + " " + String(localized: "Casberi signs only what it can name.")
        case .serviceThrottled:
            return String(localized: "Safe paused reads right now, so Casberi couldn't fetch the statement.")
        case .nothingToDo:
            return String(localized: "This phone already signed this one.")
        case .signerNotDeployed:
            return String(localized: "This Safe names this phone's vault-chip key, but its signer contract isn't deployed yet.")
        case .signatureNotAccepted:
            return String(localized: "Safe's passkey factory didn't accept the signature this phone made, so Casberi threw it away.")
        }
    }

    private func sign(_ ready: SafeStatementSigner.Ready) async {
        signing = true
        defer { signing = false }
        let post = onSigned == nil
        let (outcome, signed) = await SafeStatementSigner.sign(
            chainId: ready.chainId, safe: ready.safeAddress,
            innerHash: SafeABI.hexBytes(ready.innerHash) ?? [],
            requesterHash: nil, pasted: ready.message,
            post: post)
        switch outcome {
        case .posted:
            phase = .done
            if let signed { SafeStatementSigner.land(context: modelContext, ready: signed, posted: true) }
            chrome.flash(String(localized: "Signed"), tone: .success)
        case .signedNotPosted(let signature, let status):
            phase = .done
            if let signed { SafeStatementSigner.land(context: modelContext, ready: signed, posted: status != 0) }
            if let onSigned { onSigned(signature); return }
            DSPasteboard.copySensitive(signature)
            chrome.flash(String(localized: "Signed — the signature is on your clipboard"),
                         tone: status == 0 ? .success : .failure)
        case .refused(let refusal):
            phase = .refused(refusal)
        case .keyRefused(let failure):
            phase = .refused(.noKey)
            if case .locked = failure {
                chrome.flash(String(localized: "Face ID didn't unlock the key."), tone: .failure)
            } else {
                chrome.flash(String(localized: "Couldn't sign on this device."), tone: .failure)
            }
        case .enclaveRefused:
            phase = .refused(.noKey)
            chrome.flash(String(localized: "Face ID didn't unlock the vault-chip key."), tone: .failure)
        }
    }
}

// MARK: - A recovery

/// What a guardian is being asked to APPROVE, read off the chain, and the
/// one Sign for it (prd §913).
struct SafeRecoveryBlock: View {
    let request: SafeRecovery.Request
    let requesterHash: [UInt8]?
    var onSigned: ((String) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome

    @State private var phase: Phase = .checking
    @State private var signing = false
    @State private var attempt = 0

    private enum Phase {
        case checking
        case ready(SafeRecoverySigner.Ready)
        case refused(SafeRecoverySigner.Refusal)
        case done
    }

    var body: some View {
        Group {
            switch phase {
            case .checking:
                EmptyView()
            case .ready(let ready):
                readyBody(ready)
            case .refused(let refusal):
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(verbatim: sentence(for: refusal))
                        .dsText(.subhead12).foregroundStyle(refusalTone(refusal))
                        .fixedSize(horizontal: false, vertical: true)
                    if case .chainUnreadable = refusal {
                        DSSlabDoor(title: String(localized: "Try again"), systemImage: "arrow.clockwise") {
                            phase = .checking
                            attempt += 1
                        }
                    }
                }
            case .done:
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "checkmark.circle.fill").dsGlyph(.subhead)
                        .foregroundStyle(DS.confirm)
                    Text("Approved from this phone.")
                        .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                }
                .settleIn()
            }
        }
        .task(id: attempt) {
            guard SafeSigner.hasAnyKey else { return }
            switch await SafeRecoverySigner.prepare(request, requesterHash: requesterHash) {
            case .success(let ready): phase = .ready(ready)
            case .failure(let refusal): phase = .refused(refusal)
            }
        }
    }

    @ViewBuilder private func readyBody(_ ready: SafeRecoverySigner.Ready) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSProse.text("Replace the owners of \(WalletStore.shortAddress(request.wallet)).")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !ready.currentOwners.isEmpty {
                ownerList(String(localized: "Now"), ready.currentOwners, threshold: ready.currentThreshold)
            }
            ownerList(String(localized: "After"), request.newOwners, threshold: request.newThreshold)
            factLine(String(localized: "Guardians"),
                     String(localized: "\(ready.guardianThreshold) of \(ready.guardianCount) needed, this phone one of them"))
            if let pending = ready.pending {
                Text(verbatim: String(localized: "A recovery is already scheduled with \(pending.approvals) approvals, executable \(Date(timeIntervalSince1970: TimeInterval(pending.executableAt)).formatted(.relative(presentation: .named)))."))
                    .dsText(.subhead12).foregroundStyle(DS.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DSActVerb(title: signing ? String(localized: "Signing…") : String(localized: "Approve"),
                      glyph: "faceid", busy: signing) {
                Task { await sign(ready) }
            }
            DSFootnote("An approval, not a transaction. The module waits out its delay, and the current owners can cancel until then.")
        }
    }

    private func ownerList(_ label: String, _ owners: [String], threshold: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: "\(label) · \(threshold) of \(owners.count)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            ForEach(owners, id: \.self) { owner in
                HStack(spacing: DS.Space.s2) {
                    WalletFace(address: owner, size: DS.Face.row, circular: true)
                    Text(verbatim: WalletIngest.knownLabel(for: owner) ?? WalletStore.shortAddress(owner))
                        .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                }
            }
        }
    }

    private func factLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: label).dsText(.subhead12).foregroundStyle(DS.textTertiary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: value).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func refusalTone(_ refusal: SafeRecoverySigner.Refusal) -> Color {
        switch refusal {
        case .hashMismatch, .requesterHashMismatch, .notARecoveryModule, .moduleNotEnabled: return DS.destructive
        default: return DS.textTertiary
        }
    }

    private func sentence(for refusal: SafeRecoverySigner.Refusal) -> String {
        switch refusal {
        case .noKey:
            return String(localized: "This phone has no signing key.")
        case .chainUnsupported:
            return String(localized: "Casberi can't sign on this chain — it can't re-check the hash against the module there.")
        case .chainUnreadable:
            return String(localized: "Couldn't reach the chain to re-check this recovery, so Casberi won't sign it. Try again in a moment.")
        case .notARecoveryModule:
            return String(localized: "The contract this request names doesn't call itself a recovery module. Don't sign this anywhere.")
        case .versionMismatch(let module):
            return String(localized: "The module says it is version \(module), not the version this request was written for.")
        case .moduleNotEnabled:
            return String(localized: "The wallet doesn't list this module as enabled, so an approval would change nothing — and a request naming a module the wallet never enabled is not one to sign.")
        case .notAGuardian:
            return String(localized: "The module doesn't list this phone as a guardian of this wallet.")
        case .guardianThresholdTooLow(let threshold):
            return String(localized: "This wallet's recovery needs \(threshold) guardian, so this phone alone could replace its owners. Casberi won't be a lone guardian — ask the owner to set the guardian threshold to 2.")
        case .staleNonce(let module):
            return String(localized: "This request is for an earlier round (the module is at nonce \(module)), so the module would reject it.")
        case .hashMismatch, .requesterHashMismatch:
            return String(localized: "The module's own hash for this recovery doesn't match what Casberi worked out. Don't sign this anywhere until you know why.")
        case .unreadable:
            return String(localized: "Couldn't read this recovery request well enough to sign it.")
        }
    }

    private func sign(_ ready: SafeRecoverySigner.Ready) async {
        signing = true
        defer { signing = false }
        let (outcome, signed) = await SafeRecoverySigner.sign(request, requesterHash: requesterHash)
        switch outcome {
        case .signed(let signature, let guardian):
            phase = .done
            if let signed { SafeRecoverySigner.land(context: modelContext, ready: signed) }
            if let onSigned { onSigned(signature); return }
            // Tier 0: whoever submits `multiConfirmRecovery` needs the bytes
            // AND the guardian address they belong to.
            DSPasteboard.copySensitive("\(guardian) \(signature)")
            chrome.flash(String(localized: "Approved — your guardian address and signature are on your clipboard"),
                         tone: .success)
        case .refused(let refusal):
            phase = .refused(refusal)
        case .keyRefused:
            phase = .refused(.noKey)
            chrome.flash(String(localized: "Face ID didn't unlock the key."), tone: .failure)
        case .enclaveRefused:
            phase = .refused(.noKey)
            chrome.flash(String(localized: "Face ID didn't unlock the vault-chip key."), tone: .failure)
        }
    }
}
