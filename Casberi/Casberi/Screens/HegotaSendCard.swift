import SwiftUI
import SwiftData

/// SENDING TEST ETH ON HEGOTÁ, ON THE ROOM ITSELF (prd §539, 2026-08-31).
///
/// `VibenetSendCard`'s ruling (§538) carried to the other devnet, at the
/// user's own instruction — *"apply this way of thinking and design to
/// Hegota. it also has a home screen with a list that can be replaced with
/// send etc like we did here"*.
///
/// **The fault here was worse than vibenet's, in two ways that compound.**
///
/// 1. **Home drew the first four of Activity's own rows.** `HegotaRoomList`
///    was `case .home: movesList(Array(moves.prefix(4)))` against
///    `case .activity: movesList(moves)` — the same list, truncated, one chip
///    away from the whole of itself. That is §533's "Latest 3" duplication
///    verbatim, and the answer is the same: Home is where you DO the thing,
///    Activity is the stream.
///
/// 2. **Sending was TWO SHEETS DEEP.** The only door to `HegotaSendSheet` was
///    a button inside `HegotaKeySheet`, which is itself a presented sheet
///    reached from the room — so the one thing a key is for sat behind a tap,
///    a sheet, a scroll and another tap. That key sheet had already been
///    reported clipped ("you can't see the bottom of thi tray where it says
///    send eth so someone seeing it wont know it's there") and answered three
///    times by guessing a taller number: 560, 560, 820. The comment that
///    landed with 820 diagnoses it exactly — *"a ScrollView makes that content
///    REACHABLE, never DISCOVERABLE"* — and then keeps the arrangement that
///    made discoverability the problem. Putting the form on the room retires
///    the question: there is nothing to discover, because there is nothing in
///    front of it.
///
/// **What differs from `VibenetSendCard`, deliberately, and why.**
///
/// - **No account parameter.** A Hegotá key IS its address (a plain EOA), so
///   there is no separate account object to be handed one; this gates on
///   `HegotaKey.address()` and shows nothing when this phone has no key.
/// - **NO "Max" CHIP, and that is the interesting divergence.** Hegotá sends
///   are unsponsored by construction — the sheet's own sentence says "the
///   sender pays its own gas" — so an amount equal to the whole balance
///   cannot pay for itself and is a GUARANTEED failure, which is the dead
///   control §83 bans wearing a convenience's clothing. On vibenet Max is
///   honest because gas is the faucet's when it sponsors, and when it does
///   not, no send of any size goes through, so Max is never the thing that
///   broke. Here it always would be. The balance is still SHOWN — knowing
///   what you hold is information, filling it in is a claim.
struct HegotaSendCard: View {
    @Environment(\.modelContext) private var modelContext

    @State private var destination = ""
    @State private var amount = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var sentHash: String?
    @State private var sentSummary: String?

    // The app's own accent, not `HegotaModeStyle.room` (user: "that cyan
    // color blue or whatever it is... we don't use that anywhere else") —
    // this is an ordinary send flow, not a frame/vault reading.
    private static let mark = DS.tint

    /// **NOTHING WITHOUT A KEY, never a form that cannot submit (§83).** This
    /// phone makes its Hegotá key in `HegotaKeySheet`, and until it has one
    /// there is no address to send from — a To field and an armed Send button
    /// over that state would be a control that provably does nothing. The room
    /// keeps its own "this phone's account" row, which is the door to making
    /// one, so a keyless room is not a dead end.
    var body: some View {
        if HegotaKey.address() != nil {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                head
                if sentHash == nil { form } else { done }
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsWidgetSurface()
            .animation(DS.Motion.standard, value: sentHash)
        }
    }

    // MARK: - Head

    /// A title and the address it spends from — NOT a `DSSheetHead`. That
    /// component exists so a PRESENTED surface reads as an object; this is not
    /// presented, and a head here would be the duplicate-title fault §538 took
    /// out of three sheets in this feature.
    private var head: some View {
        HStack(spacing: DS.Space.s3) {
            ZStack {
                Circle().fill(Self.mark.opacity(0.18))
                    .frame(width: DS.Face.rowCircle, height: DS.Face.rowCircle)
                Image(systemName: sentHash == nil ? "arrow.up.right" : "checkmark")
                    .accessibilityHidden(true)
                    .dsGlyph(13, weight: .semibold)
                    .foregroundStyle(Self.mark)
            }
            Text(sentHash == nil ? String(localized: "Send") : String(localized: "Sent"))
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            if sentHash != nil {
                DSStamp(word: String(localized: "Broadcast"), weight: .good)
            } else if let from = HegotaKey.address() {
                // The room's own resolution, so this card can never name an
                // address differently from the roster above it.
                Text(HegotaWatch.shared.name(for: from) ?? WalletStore.shortAddress(from))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Form

    private var canSend: Bool {
        !busy && Self.isValidAddress(destination) && Self.weiData(from: amount) != nil
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "To"))
                well {
                    HStack(spacing: DS.Space.s2) {
                        TextField(String(localized: "0x\u{2026}"), text: $destination)
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .tint(DS.tint)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        // Deciding WITHOUT reading: `hasStrings` asks the
                        // system whether the pasteboard holds text and brings
                        // none of it into this process, so it raises no paste
                        // banner. A chip that pastes nothing is a dead control.
                        if destination.isEmpty, UIPasteboard.general.hasStrings {
                            miniChip(String(localized: "Paste")) {
                                destination = (UIPasteboard.general.string ?? "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                }
                if !destination.isEmpty, !Self.isValidAddress(destination) {
                    Text(String(localized: "That doesn't look like an address."))
                        .dsText(.label11)
                        .foregroundStyle(DS.destructive)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "Amount"))
                well {
                    HStack(spacing: DS.Space.s2) {
                        TextField("0.0", text: $amount)
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .tint(DS.tint)
                            .keyboardType(.decimalPad)
                        Text(String(localized: "ETH"))
                            .dsText(.body17)
                            .foregroundStyle(DS.textTertiary)
                        // No Max here — see the type's own doc. Gas is the
                        // sender's on this chain, so the whole balance is the
                        // one amount that provably cannot be sent.
                    }
                }
                if !amount.isEmpty, Self.weiData(from: amount) == nil {
                    Text(String(localized: "Enter an amount up to 18 decimal places."))
                        .dsText(.label11)
                        .foregroundStyle(DS.destructive)
                } else if let held {
                    // WHAT IS THERE TO SEND — this address's own balance, off
                    // the last sweep. `HegotaFormat.eth` is the room's own
                    // rendering, so the figure reads the same here as it does
                    // in the crown above.
                    Text(String(localized: "Holds \(HegotaFormat.eth(held))"))
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                }
            }

            Button {
                DSHaptic.tap()
                send()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right").dsGlyph(13, weight: .semibold)
                    Text(sendLabel)
                    if busy { ProgressView().controlSize(.mini) }
                }
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(canSend ? .white : DS.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s3)
                .background(canSend ? AnyShapeStyle(Self.mark) : AnyShapeStyle(DS.gray200),
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .buttonStyle(PressSpring())
            .disabled(!canSend)
            .armedPop(canSend)
            .animation(DS.Motion.standard, value: canSend)
            .dsHover()

            if let errorText {
                Text(errorText)
                    .dsText(.label11)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(String(localized: "Signed by this phone's key, unsponsored \u{2014} the sender pays its own gas, exactly as measured on this chain."))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The button NAMES THE AMOUNT once there is one — the figure it is about
    /// can be off screen in a scrolling room, and "Send" alone on a control
    /// that moves money is the weakest thing it could say at the moment it is
    /// tapped.
    private var sendLabel: String {
        guard canSend, Self.weiData(from: amount) != nil else {
            return String(localized: "Send")
        }
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(localized: "Send \(trimmed) ETH")
    }

    /// This address's own balance, off the last sweep — never a live read, so
    /// a keystroke never spends a request. Nil when the sweep could not reach
    /// the chain, which `HegotaAccount.reached` keeps honest: a failed read
    /// and a real zero must not look alike (§83), so the line is simply absent
    /// rather than claiming nothing is held.
    private var held: Decimal? {
        guard let mine = HegotaKey.address() else { return nil }
        return HegotaLiveState.shared.accounts.first {
            $0.address.caseInsensitiveCompare(mine) == .orderedSame
        }?.balanceWei
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
        Text(text)
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
    }

    /// The in-well affordance. `label12` on `fillFaint` — a quiet chip, never
    /// the mark: it fills a field in, it does not move money, and wearing the
    /// send button's colour would say it did.
    private func miniChip(_ title: String, act: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.selection()
            act()
        } label: {
            Text(title)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.tint)
                .padding(.horizontal, DS.Space.s2)
                .padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(DS.fillFaint))
                .fixedSize()
        }
        .buttonStyle(PressSpring())
        .dsHover()
    }

    // MARK: - Done

    /// **THE CARD SETTLES, IT DOES NOT DISMISS.** A sheet could close and leave
    /// the room looking exactly as it did before the send; here the block that
    /// took the instruction is the block that reports it, in the same place.
    private var done: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let sentSummary {
                Text(sentSummary)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let sentHash {
                Text(sentHash)
                    .dsText(.mono12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: DS.Space.s4) {
                Button {
                    DSHaptic.tap()
                    destination = ""
                    amount = ""
                    sentHash = nil
                    sentSummary = nil
                    errorText = nil
                } label: {
                    Text(String(localized: "Send another"))
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(Self.mark)
                }
                .buttonStyle(PressSpring())
                .dsHover()

                if let sentHash,
                   let url = URL(string: HegotaIdentity.explorer + "/tx/" + sentHash) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text(String(localized: "View it"))
                            Image(systemName: "arrow.up.right")
                        }
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize()
                    }
                }
            }
        }
    }

    // MARK: - Act

    private func send() {
        guard let target = RLP.data(fromHex: destination),
              let valueWei = Self.weiData(from: amount),
              let address = HegotaKey.address() else { return }
        let spending = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = destination
        let shortTo = HegotaWatch.shared.name(for: to) ?? WalletStore.shortAddress(to)
        errorText = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                guard let sequence = await HegotaSend.currentNonceSequence(for: address) else {
                    errorText = String(localized: "Couldn't reach the chain to read this account's sequence.")
                    return
                }
                let hash = try await HegotaSend.sendValue(to: target, valueWei: valueWei,
                                                          nonceSequence: sequence)
                DSHaptic.success()
                HegotaSend.landReceipt(txHash: hash, kind: .sent(to: to), in: modelContext)
                sentSummary = String(localized: "\(spending) ETH to \(shortTo) is on its way to the chain.")
                sentHash = hash
            } catch let f as HegotaSend.Failure {
                switch f {
                case .broadcastRefused(let why):
                    errorText = String(localized: "The chain refused it: \(why)")
                case .signingRefused:
                    errorText = String(localized: "Signing was cancelled or refused.")
                case .noKey:
                    errorText = String(localized: "No key on this phone.")
                case .chainUnreachable:
                    errorText = String(localized: "Couldn't reach the chain, so nothing was sent.")
                default:
                    errorText = String(localized: "Couldn't send.")
                }
            } catch {
                errorText = String(localized: "Couldn't send.")
            }
        }
    }

    // MARK: - Parsing

    private static func isValidAddress(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 42, s.hasPrefix("0x") else { return false }
        return s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// A typed decimal ETH amount to minimal big-endian wei bytes — string
    /// arithmetic throughout, never `Double`: this devnet's own faucet
    /// balances run into the billions of ETH, well past `Double`'s
    /// exact-integer range.
    private static func weiData(from text: String) -> Data? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let whole = parts[0].isEmpty ? "0" : String(parts[0])
        let frac = parts.count == 2 ? String(parts[1]) : ""
        guard whole.allSatisfy(\.isNumber), frac.allSatisfy(\.isNumber), frac.count <= 18
        else { return nil }
        let combined = whole + frac + String(repeating: "0", count: 18 - frac.count)
        guard let word = SafeABI.word(uint256: combined) else { return nil }
        let trimmed = word.drop(while: { $0 == 0 })
        guard !trimmed.isEmpty else { return nil }
        return Data(trimmed)
    }
}
