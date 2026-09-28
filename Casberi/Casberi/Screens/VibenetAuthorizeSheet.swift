import SwiftUI
import SwiftData

/// AUTHORIZING (OR RE-AUTHORIZING) A KEY ON A VIBENET ACCOUNT, AS A SHEET
/// (prd §534, 2026-08-31).
///
/// One flow for both Modify Owners and Spending Account, because the chain
/// treats them as the same act with a different actor identity — and one
/// flow for both "add a new key" and "change an existing key's scope",
/// because `AuthorizeActor` is an upsert (`VibenetSend.authorizeActor`'s own
/// doc has the source citation). Paste either shape and this sheet tells
/// them apart by LENGTH, never by asking which kind it is:
///
///   * 64 raw bytes (128 hex chars) — a P-256 public key (`x || y`). Another
///     phone's own key, the Modify Owners case. actorId is
///     `keccak256(x || y)` and the authenticator is the live
///     `P256Authenticator` — `VibenetP256Auth`'s already-measured join.
///   * 20 bytes (40 hex chars) — an account address. The Spending Account
///     case: that account becomes a delegate, actorId is
///     `ActorId.fromAddress` (the address right-aligned into a word,
///     `ActorId.sol`, source-read not guessed) and the authenticator is the
///     live `DelegateAuthenticator`.
///
/// **Deliberately NOT offered here: the Policy scope.** A gated key needs a
/// manager and a commitment this sheet does not compose — Subscriptions'
/// own build, not a checkbox bolted onto this one.
struct VibenetAuthorizeSheet: View {
    let account: Data
    let localEpoch: UInt32
    let localSequence: UInt32
    /// nil for a brand-new key; the actor being RE-authorized otherwise —
    /// prefills the paste field with its id (read-only, so scope alone
    /// changes) and the sheet's own words say "Editing", not "Authorize".
    var editing: VibenetActor?
    /// With `editing`: a NEW key takes `editing`'s place in one transaction
    /// (`VibenetSend.replaceActor`), where without it the same key's scope
    /// changes. The paste field opens for the new key and the switches start
    /// at the old key's scope.
    var replacing: Bool = false

    @Environment(\.modelContext) private var modelContext

    @State private var pasted = ""
    /// THE SCOPE AS SWITCHES (user: "scope as switches"). Admin is its own
    /// switch because it is not a sum of the others (`VibenetScope.isAdmin`);
    /// a new key starts at "Send anywhere", never at full control.
    @State private var admin = false
    @State private var bits: UInt16 = VibenetScope.sender
    /// Bits an edited key holds that no switch shows (POLICY, reserved ones),
    /// signed back unchanged — `VibenetScopeEdit`.
    @State private var kept: UInt16 = 0
    /// Read once on appear off the saved room: the account's admin keys other
    /// than the one being changed, for the last-admin refusal.
    @State private var otherAdmins = 0
    @State private var isThisPhoneKey = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var sentHash: String?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    private enum Phase: Equatable { case form, done }
    private var phase: Phase { sentHash == nil ? .form : .done }

    var body: some View {
        // **THE ACTION IS PINNED, THE FORM SCROLLS UNDER IT (prd §538,
        // 2026-08-31)** — `VibenetCreateSheet`'s fix, in the sheet that needed
        // it most: at 680 this is the tallest tray in the feature, and every
        // point of that number is a guess about how tall a two-field form, a
        // menu, a validation line and a button turn out to be in the reader's
        // type size. When the guess is short the button — the only thing this
        // sheet is for — is the part that goes under the screen edge.
        DSTray(title: editing == nil ? String(localized: "Authorize a key")
                                      : replacing ? String(localized: "Replace this key")
                                      : String(localized: "Edit permissions"),
               height: trayHeight, ink: true, detents: [.height(trayHeight), .large]) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        DSSheetHead(disc: { headDisc },
                                    stamp: headStamp,
                                    stampWeight: headStampWeight,
                                    // **NOT THE TRAY'S OWN TITLE AGAIN (§538).**
                                    // This passed the byte-identical expression
                                    // the tray title is built from twenty lines
                                    // up, so the sheet opened on "Authorize a
                                    // key" in `heading40` with "Authorize a key"
                                    // in `heading24` directly beneath it — the
                                    // fault §538 took out of the key sheet and
                                    // the create sheet, third instance.
                                    //
                                    // The head names WHICH ACCOUNT the new key
                                    // will be able to act for. That is the fact
                                    // this sheet was not stating anywhere in
                                    // words, and it is the one worth being sure
                                    // of before granting somebody a key.
                                    title: headTitle,
                                    // The form's title IS the account, so it
                                    // is not said again under itself.
                                    secondary: phase == .done ? accountName : nil,
                                    sentence: headSentence)
                        switch phase {
                        case .form: formBody
                        case .done: doneBody
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, DS.Space.s4)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
                pinnedAction
            }
        }
        .onAppear {
            if let editing {
                if !replacing { pasted = editing.actorId }
                admin = editing.scope.isAdmin
                bits = VibenetScopeEdit.bits(from: editing.scope)
                kept = VibenetScopeEdit.kept(from: editing.scope)
                let hex = "0x" + VibenetTransaction.hex(account)
                let actors = VibenetRoomSource.card()?.items
                    .first { $0.address.caseInsensitiveCompare(hex) == .orderedSame }?.actors ?? []
                otherAdmins = actors.filter {
                    $0.scope.isAdmin && $0.actorId.lowercased() != editing.actorId.lowercased()
                }.count
                isThisPhoneKey = VibenetThisPhone.isKey(editing.actorId, ours: VibenetThisPhone.actorID())
            }
        }
    }

    /// **RE-MEASURED against what the SCROLL now holds (§538.)** 680 counted
    /// the button, and the button is no longer in it; these numbers describe
    /// the scrolling content alone, so a wrong one costs a scroll rather than
    /// a clipped control. Still a floor rather than a fit — `.large` is one
    /// drag away, and slack is a tray while a deficit hides something.
    private var trayHeight: CGFloat {
        switch phase {
        case .form: 700
        case .done: 340
        }
    }

    // MARK: - Head

    private var headDisc: some View {
        ZStack {
            Circle().fill(Self.mark.opacity(0.18)).frame(width: DS.Face.list, height: DS.Face.list)
            Image(systemName: phase == .done ? "checkmark" : "key.fill")
                .dsGlyph(.subhead, weight: .semibold)
                .foregroundStyle(Self.mark)
        }
        .accessibilityHidden(true)
    }

    /// WHOSE ACCOUNT this key will act for — never the tray's own words again
    /// (§538). `.done` keeps a state word, which is a different sentence
    /// rather than the same one: the tray still says what you came to do, the
    /// head says it happened.
    private var headTitle: String {
        switch phase {
        case .done: String(localized: "Authorized")
        case .form: accountName
        }
    }

    /// The account in the room's own words — a watched name where there is
    /// one, its short address otherwise. Same resolution every other vibenet
    /// surface makes, so this sheet can never name an account differently
    /// from the room that opened it, and never as 42 raw hex characters
    /// (which is what the head's `secondary` carried until §538).
    private var accountName: String {
        let hex = "0x" + VibenetTransaction.hex(account)
        return VibenetWatch.shared.name(for: hex) ?? VibenetRoom.shortAddress(hex)
    }

    private var headStamp: String? { phase == .done ? String(localized: "Broadcast") : nil }
    private var headStampWeight: DSStamp.Weight { .good }

    private var headSentence: String? {
        switch phase {
        case .form:
            String(localized: "This costs two Face ID prompts — one approving the change itself, one authorizing the transaction that carries it.")
        case .done:
            String(localized: "The transaction is on its way to the chain.")
        }
    }

    // MARK: - Form

    private var parsedActor: (actorID: Data, authenticator: Data, isDelegate: Bool)? {
        // EDITING THE SAME KEY re-authorizes it with its own actorId and the
        // authenticator the chain already holds for it. The field shows that
        // 32-byte id, which the paste reading below (a 64-byte key or a
        // 20-byte address) never accepts — so until this branch, "Save" on
        // Edit permissions could not arm at all.
        if let editing, !replacing {
            guard let id = VibenetTransaction.data(fromHex: editing.actorId), id.count == 32,
                  let authenticator = VibenetTransaction.data(fromHex: editing.authenticator),
                  authenticator.count == 20
            else { return nil }
            return (id, authenticator, editing.kind == .delegate)
        }
        let hex = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: [.anchored])
        guard let contracts = VibenetConfig.cached() else { return nil }
        switch hex.count {
        case 128:
            guard let xy = VibenetTransaction.data(fromHex: hex), xy.count == 64,
                  let actorID = VibenetP256Auth.actorID(publicKeyXY: xy),
                  // Nil where the deployment publishes no authenticator
                  // (2026-09-04) — this function's existing "can't read that"
                  // answer, which the sheet already renders as a refusal to
                  // arm rather than as an error.
                  let authenticator = contracts.p256Authenticator
                      .flatMap(VibenetTransaction.data(fromHex:))
            else { return nil }
            return (actorID, authenticator, false)
        case 40:
            guard let addr = VibenetTransaction.data(fromHex: hex), addr.count == 20,
                  let authenticator = contracts.delegateAuthenticator
                      .flatMap(VibenetTransaction.data(fromHex:))
            else { return nil }
            return (VibenetABIEncode.word(addr), authenticator, true)
        default:
            return nil
        }
    }

    private var act: VibenetScopeEdit.Act {
        guard let editing else { return .add }
        return replacing ? .replace(before: editing.scope.raw) : .edit(before: editing.scope.raw)
    }

    /// The scope the switches describe; nil when they describe none.
    private var composed: UInt16? { VibenetScopeEdit.compose(admin: admin, bits: bits, kept: kept) }

    private var refusal: VibenetScopeEdit.Refusal? {
        VibenetScopeEdit.refusal(act, after: composed, otherAdmins: otherAdmins)
    }

    /// A replacement must be a DIFFERENT key: the same actorId would be
    /// authorized and then revoked by the one transaction.
    private var replacesWithItself: Bool {
        guard replacing, let editing, let parsedActor else { return false }
        return ("0x" + VibenetTransaction.hex(parsedActor.actorID)).lowercased()
            == editing.actorId.lowercased()
    }

    private var canSubmit: Bool {
        !busy && parsedActor != nil && refusal == nil && !replacesWithItself
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(replacing ? String(localized: "The new key")
                                  : String(localized: "Public key or address"))
                TextField(String(localized: "Paste a P-256 key or an account address"),
                          text: $pasted, axis: .vertical)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .tint(DS.tint)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...3)
                    .disabled(editing != nil && !replacing)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsWell(cornerRadius: DS.Radius.control, recessed: true)
                if let parsedActor {
                    DSFootnote(prose: parsedActor.isDelegate
                         ? String(localized: "Reads as an account address — that account becomes a delegate.")
                         : String(localized: "Reads as a P-256 public key — another phone's own key."))
                } else if !pasted.isEmpty {
                    Text(String(localized: "That's neither a 64-byte public key nor a 20-byte address."))
                        .dsText(.label12)
                        .foregroundStyle(DS.destructive)
                }
                if replacesWithItself {
                    Text(String(localized: "That's the key being replaced."))
                        .dsText(.label12)
                        .foregroundStyle(DS.destructive)
                }
            }

            scopeEditor

            changePreview

            // The button LEFT this stack for the tray's own bottom edge — see
            // `pinnedAction`. The failure it can no longer state stays here,
            // beside the fields it is about.
            if let errorText {
                Text(errorText)
                    .dsText(.label12)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// WHAT IT MAY DO, AS SWITCHES. Base's six presets stay as shortcuts that
    /// set the switches (a preset lights when the switches match it); Admin
    /// is a switch of its own and hides the rest, because full control is not
    /// the four switches on — it also holds every bit this build can't name.
    private var scopeEditor: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            caption(String(localized: "What it may do"))
            ScrollView(.horizontal) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(Array(VibenetScope.presets.enumerated()), id: \.offset) { _, preset in
                        Button {
                            DSHaptic.tap()
                            withAnimation(DS.Motion.standard) {
                                admin = preset.raw == 0
                                if preset.raw != 0 { bits = preset.raw & VibenetScopeEdit.switchable }
                            }
                        } label: {
                            Chip(text: preset.name, selected: composed == (preset.raw | (preset.raw == 0 ? 0 : kept)))
                        }
                        .buttonStyle(PressSpring())
                    }
                }
            }
            .scrollIndicators(.hidden)
            DSToggleRow(title: Text(String(localized: "Admin")),
                        detail: Text(String(localized: "Every permission, including changing this account's keys.")),
                        isOn: $admin.animation(DS.Motion.standard),
                        tint: Self.mark)
            if !admin {
                ForEach(Array(Self.switches.enumerated()), id: \.offset) { _, entry in
                    DSToggleRow(title: Text(entry.name), isOn: bitBinding(entry.bit), tint: Self.mark)
                }
                if composed == nil {
                    Text(String(localized: "Turn on at least one, or choose Admin."))
                        .dsText(.label12)
                        .foregroundStyle(DS.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The switchable bits with their plain names, in the contract's order.
    private static var switches: [(bit: UInt16, name: String)] {
        VibenetScope.orderedPlainBits
            .filter { VibenetScopeEdit.switchable & $0.0 != 0 }
            .map { (bit: $0.0, name: $0.1) }
    }

    private func bitBinding(_ bit: UInt16) -> Binding<Bool> {
        Binding(get: { bits & bit != 0 },
                set: { on in bits = on ? bits | bit : bits & ~bit })
    }

    /// THE CHANGE, BEFORE IT IS SIGNED (user: "show change before signing").
    /// One line in the permissions' own words — what the key could do, an
    /// arrow, what it will — then the refusal or the warnings that apply.
    @ViewBuilder
    private var changePreview: some View {
        if let after = composed {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "The change"))
                Text(changeLine(after: after))
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let refusal, let sentence = refusalSentence(refusal) {
                    Text(sentence)
                        .dsText(.label12)
                        .foregroundStyle(DS.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(VibenetScopeEdit.warnings(act, after: after, isThisPhone: isThisPhoneKey),
                        id: \.self) { warning in
                    Text(warningSentence(warning))
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func changeLine(after: UInt16) -> String {
        let now = VibenetScopeEdit.words(after)
        switch act {
        case .add:
            return String(localized: "New key: \(now)")
        case .edit(let before):
            return "\(VibenetScopeEdit.words(before)) → \(now)"
        case .replace(let before):
            let old = editing.map { VibenetKeyIdentity.short($0.actorId) } ?? ""
            return String(localized: "\(old) (\(VibenetScopeEdit.words(before))) → new key (\(now))")
        }
    }

    private func refusalSentence(_ refusal: VibenetScopeEdit.Refusal) -> String? {
        switch refusal {
        // Said under the switches already.
        case .noScope: nil
        case .unchanged: String(localized: "Nothing changes yet.")
        case .lastAdmin: String(localized: "This is the account's only Admin key. Without one, nobody could change this account again — make another key Admin first.")
        case .policyGate: String(localized: "This key is limited to one contract, and this sheet can't carry that limit over. Change it on Base's console.")
        }
    }

    private func warningSentence(_ warning: VibenetScopeEdit.Warning) -> String {
        switch warning {
        case .thisPhoneLosesAdmin:
            String(localized: "This phone won't be able to change this account's keys afterwards.")
        case .grantsAdmin:
            String(localized: "Admin can do anything with this account, including removing this phone's key.")
        }
    }

    /// THE ONE THING THIS SHEET IS ASKING FOR, outside the scroll (§538).
    ///
    /// `.done` has no action: the transaction is on its way and the only thing
    /// left is to read the hash or leave, which the done body already offers.
    /// A control there would be one that cannot change anything.
    @ViewBuilder
    private var pinnedAction: some View {
        if phase == .form {
            Button {
                DSHaptic.tap()
                authorize()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").dsGlyph(.caption, weight: .semibold)
                    Text(editing == nil ? String(localized: "Authorize")
                         : replacing ? String(localized: "Replace") : String(localized: "Save"))
                    if busy { DSSpinner(size: .mini) }
                }
                .dsText(.body17)
                .foregroundStyle(canSubmit ? .white : DS.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s3)
                .background(canSubmit ? AnyShapeStyle(Self.mark) : AnyShapeStyle(DS.gray200),
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .buttonStyle(PressSpring())
            .disabled(!canSubmit)
            .armedPop(canSubmit)
            .animation(DS.Motion.standard, value: canSubmit)
            .dsHover()
            .padding(.top, DS.Space.s3)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).dsText(.label12).foregroundStyle(DS.textTertiary)
    }

    // MARK: - Done

    private var doneBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let sentHash {
                Text(VibenetExplorer.tx(sentHash))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Act

    private func authorize() {
        guard let (actorID, authenticator, _) = parsedActor, let scope = composed, refusal == nil
        else { return }
        let replaced = replacing ? editing.flatMap { VibenetTransaction.data(fromHex: $0.actorId) } : nil
        if replacing, replaced == nil { return }
        errorText = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                let sent: VibenetSend.Sent
                if let replaced {
                    sent = try await VibenetSend.replaceActor(
                        on: account, oldActorID: replaced, newActorID: actorID,
                        newAuthenticator: authenticator, scope: scope,
                        localEpoch: localEpoch, localSequence: localSequence)
                } else {
                    sent = try await VibenetSend.authorizeActor(
                        on: account, newActorID: actorID, newAuthenticator: authenticator,
                        scope: scope, localEpoch: localEpoch, localSequence: localSequence)
                }
                DSHaptic.success()
                VibenetSend.landAuthorizeReceipt(
                    sent, newActorHex: "0x" + VibenetTransaction.hex(actorID), in: modelContext)
                sentHash = sent.transactionHash
            } catch let f as VibenetSend.Failure {
                switch f {
                case .noSponsor:
                    errorText = String(localized: "Nobody is sponsoring right now, and this account has nothing to pay with. Try again later.")
                case .sponsorUnreadable:
                    errorText = String(localized: "Couldn't reach the sponsor to ask who pays, so nothing was signed.")
                case .broadcastRefused(let why):
                    errorText = String(localized: "The network refused it: \(why)")
                case .payerRefused(let why):
                    errorText = String(localized: "The sponsor refused: \(why)")
                case .signingRefused:
                    errorText = String(localized: "Face ID didn't confirm, so nothing was signed.")
                case .chainUnreachable:
                    errorText = String(localized: "Couldn't reach the network, so nothing was sent.")
                case .noKey:
                    errorText = String(localized: "This phone has no key yet.")
                case .cannotCompose:
                    errorText = String(localized: "Couldn't put the transaction together.")
                // Spelled once on the type: it must agree with the room's own
                // empty note about the same fact (§530, and `emptyRoomNote`).
                case .noAccountStack:
                    errorText = VibenetSend.Failure.noAccountStackSentence
                case .advancedRefused(let why):
                    errorText = why
                }
            } catch {
                errorText = String(localized: "Couldn't authorize.")
            }
        }
    }
}
