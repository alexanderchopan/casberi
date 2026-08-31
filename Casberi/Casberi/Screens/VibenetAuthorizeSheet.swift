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

    @Environment(\.modelContext) private var modelContext

    @State private var pasted = ""
    @State private var scopeIndex = 0
    @State private var busy = false
    @State private var errorText: String?
    @State private var sentHash: String?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    private enum Phase: Equatable { case form, done }
    private var phase: Phase { sentHash == nil ? .form : .done }

    var body: some View {
        DSTray(title: editing == nil ? String(localized: "Authorize a key")
                                      : String(localized: "Edit permissions"),
               height: trayHeight, ink: true, detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    DSSheetHead(disc: { headDisc },
                                stamp: headStamp,
                                stampWeight: headStampWeight,
                                title: headTitle,
                                secondary: "0x" + VibenetTransaction.hex(account),
                                sentence: headSentence,
                                inkCard: true)
                    switch phase {
                    case .form: formBody
                    case .done: doneBody
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            if let editing {
                pasted = editing.actorId
                if let match = VibenetScope.presets.firstIndex(where: { $0.raw == editing.scope.raw }) {
                    scopeIndex = match
                }
            }
        }
    }

    private var trayHeight: CGFloat {
        switch phase {
        case .form: 680
        case .done: 360
        }
    }

    // MARK: - Head

    private var headDisc: some View {
        ZStack {
            Circle().fill(Self.mark.opacity(0.18)).frame(width: DS.Face.list, height: DS.Face.list)
            Image(systemName: phase == .done ? "checkmark" : "key.fill")
                .dsGlyph(16, weight: .semibold)
                .foregroundStyle(Self.mark)
        }
        .accessibilityHidden(true)
    }

    private var headTitle: String {
        switch phase {
        case .done: String(localized: "Authorized")
        case .form: editing == nil ? String(localized: "Authorize a key")
                                    : String(localized: "Edit permissions")
        }
    }

    private var headStamp: String? { phase == .done ? String(localized: "Broadcast") : nil }
    private var headStampWeight: DSStamp.Weight { .good }

    private var headSentence: String? {
        switch phase {
        case .form:
            String(localized: "This costs TWO Face ID prompts — one approving the change itself, one authorizing the transaction that carries it.")
        case .done:
            String(localized: "The transaction is on its way to the chain.")
        }
    }

    // MARK: - Form

    private var parsedActor: (actorID: Data, authenticator: Data, isDelegate: Bool)? {
        let hex = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: [.anchored])
        guard let contracts = VibenetConfig.cached() else { return nil }
        switch hex.count {
        case 128:
            guard let xy = VibenetTransaction.data(fromHex: hex), xy.count == 64,
                  let actorID = VibenetP256Auth.actorID(publicKeyXY: xy),
                  let authenticator = VibenetTransaction.data(fromHex: contracts.p256Authenticator)
            else { return nil }
            return (actorID, authenticator, false)
        case 40:
            guard let addr = VibenetTransaction.data(fromHex: hex), addr.count == 20,
                  let authenticator = VibenetTransaction.data(fromHex: contracts.delegateAuthenticator)
            else { return nil }
            return (VibenetABIEncode.word(addr), authenticator, true)
        default:
            return nil
        }
    }

    private var canSubmit: Bool { !busy && parsedActor != nil }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "Public key or address"))
                well {
                    TextField(String(localized: "Paste a P-256 key or an account address"),
                              text: $pasted, axis: .vertical)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .tint(DS.tint)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...3)
                        .disabled(editing != nil)
                }
                if let parsedActor {
                    Text(parsedActor.isDelegate
                         ? String(localized: "Reads as an account address — that account becomes a delegate.")
                         : String(localized: "Reads as a P-256 public key — another phone's own key."))
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                } else if !pasted.isEmpty {
                    Text(String(localized: "That's neither a 64-byte public key nor a 20-byte address."))
                        .dsText(.label11)
                        .foregroundStyle(DS.destructive)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "What it may do"))
                Menu {
                    ForEach(Array(VibenetScope.presets.enumerated()), id: \.offset) { index, preset in
                        Button {
                            DSHaptic.tap()
                            scopeIndex = index
                        } label: {
                            if index == scopeIndex {
                                Label(preset.name, systemImage: "checkmark")
                            } else {
                                Text(preset.name)
                            }
                        }
                    }
                } label: {
                    well {
                        HStack {
                            Text(VibenetScope.presets[scopeIndex].name)
                                .dsText(.body17)
                                .foregroundStyle(DS.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .dsGlyph(12)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                }
                .dsHover()
            }

            Button {
                DSHaptic.tap()
                authorize()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").dsGlyph(13, weight: .semibold)
                    Text(editing == nil ? String(localized: "Authorize") : String(localized: "Save"))
                    if busy { ProgressView().controlSize(.mini) }
                }
                .dsText(.callout15).fontWeight(.semibold)
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

            if let errorText {
                Text(errorText)
                    .dsText(.label11)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func well<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surfaceWell,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
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
        guard let (actorID, authenticator, _) = parsedActor else { return }
        errorText = nil
        busy = true
        let scope = VibenetScope.presets[scopeIndex].raw
        Task {
            defer { busy = false }
            do {
                let sent = try await VibenetSend.authorizeActor(
                    on: account, newActorID: actorID, newAuthenticator: authenticator,
                    scope: UInt16(scope), localEpoch: localEpoch, localSequence: localSequence)
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
                }
            } catch {
                errorText = String(localized: "Couldn't authorize.")
            }
        }
    }
}
