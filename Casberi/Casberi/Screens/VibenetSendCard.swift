import SwiftUI
import SwiftData

/// SENDING ETH FROM A VIBENET ACCOUNT, ON THE ROOM ITSELF (prd §538,
/// 2026-08-31).
///
/// **The history, because it is one afternoon long.** §533 replaced Home's
/// "Latest 3" preview — a duplicate of Activity's own stream — with the room's
/// one write action, and made that action a ROW that opened a sheet
/// (`VibenetSendSheet`, deleted with this file's arrival). Reported the same
/// day: *"it's in an inline menu now and should be on the screen, it is really
/// bad right now"*, then *"it shouldn't have a door"*, then *"it should be part
/// of the screen"*.
///
/// The complaint is right and it is not about the sheet's contents, which were
/// fine. **Home is a scope with one job**, and a scope whose entire content is
/// a single row saying "Send ›" has not answered the question it was given: it
/// has restated it as a menu item. The tap, the presentation, the head that
/// re-announced the word "Send", the dismissal back to a room that looks
/// exactly as it did — all of that is ceremony around two fields.
///
/// So the fields ARE the scope. The crown, the face rail and the section strip
/// are untouched and in place above (`VibenetRoomCard.stackedRoom` emits them
/// and this draws under them); this is what Home's content is now.
///
/// **What is different from the sheet it replaces, stated rather than hidden.**
/// - **No head.** `DSSheetHead` exists so a PRESENTED surface reads as an
///   object; this is not presented, and a head here would be the same
///   duplicate-title fault §538 took out of the key and create sheets, one
///   surface further along.
/// - **The done state settles IN PLACE.** A sheet could dismiss and leave the
///   room looking untouched; a card cannot, so it says what happened where the
///   form was and offers the way back to a form.
/// - **`Paste` and `Max`**, which the sheet did not have and this earns: an
///   inline form sits under a crown that is already showing the balance, so
///   `Max` is filling in a number that is on screen rather than claiming one,
///   and nobody types 42 hex characters into a phone by hand.
///
/// **The mechanic, unchanged and worth restating.** `VibenetTransaction.Call`
/// carries no value by design (confirmed against the reference
/// `DefaultAccount.sol`, not assumed) — a send is the account calling ITSELF,
/// invoking `execute(recipient, valueWei, "")`, which is where the real
/// value-carrying EVM `CALL` happens. See `VibenetExecute`'s own doc.
///
/// **One account, one key, today.** This app has never authorized more than one
/// signer per account (`VibenetCreate.plan` hardcodes a single initial actor),
/// so there is no "which key" question yet and none is asked here.
struct VibenetSendCard: View {
    let account: Data

    @Environment(\.modelContext) private var modelContext

    @State private var destination = ""
    @State private var amount = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var sentHash: String?
    @State private var sentSummary: String?
    /// The recipient picker — one sheet, raised from the To row.
    @State private var picking = false

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            head
            if sentHash == nil { form } else { done }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .animation(DS.Motion.standard, value: sentHash)
    }

    // MARK: - Head

    /// A title and the account it spends from — NOT a `DSSheetHead`, and not
    /// the word "Send" twice. The room's strip already says Home; this says
    /// which of the two questions on Home this block is.
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
            } else if let name = accountName {
                Text(name)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// The sending account in the room's own words, so this block names it the
    /// way the rail and the roster above already do.
    private var accountName: String? {
        let hex = "0x" + VibenetTransaction.hex(account)
        return VibenetWatch.shared.name(for: hex) ?? VibenetRoom.shortAddress(hex)
    }

    // MARK: - Form

    private var canSend: Bool {
        !busy && Self.isValidAddress(destination) && Self.weiData(from: amount) != nil
    }

    /// **THE CONSOLE (prd §544).** Two labelled wells and a button became a
    /// recipient row, a centred figure and a keypad — see `DevnetSendConsole`
    /// for the reasoning; what is specific to vibenet is here.
    private var form: some View {
        VStack(spacing: DS.Space.s4) {
            DevnetSendToRow(address: destination.isEmpty ? nil : destination,
                            name: destination.isEmpty ? nil : recipientName,
                            preview: knownAddresses,
                            onTap: { picking = true })

            DevnetSendFigure(amount: amount, dim: amount.isEmpty) {
                HStack(spacing: DS.Space.s2) {
                    // THE UNIT IS A WORD HERE, and the asset CHOICE is not yet
                    // built (§544's stated gap): this seat has only ever moved
                    // native ETH — `VibenetSend.sendValue` takes a `valueWei`
                    // and nothing else — so a chip opening a one-item menu
                    // would be the dead control §83 bans. It becomes a control
                    // the day the bridge can move a token, and not before.
                    Text(String(localized: "ETH"))
                        .dsText(.callout15)
                        .fontWeight(.semibold)
                        .foregroundStyle(amount.isEmpty ? DS.textTertiary : DS.textSecondary)
                    if let held {
                        Text(String(localized: "\(VibenetBalanceFormat.line(held)) available"))
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                        if held > 0 {
                            miniChip(String(localized: "Max")) {
                                amount = VibenetBalanceFormat.line(held)
                            }
                        }
                    }
                }
            }

            DevnetSendKeypad(amount: $amount, tint: Self.mark)

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
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !destination.isEmpty, !Self.isValidAddress(destination) {
                Text(String(localized: "That doesn't look like an address."))
                    .dsText(.label11)
                    .foregroundStyle(DS.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(String(localized: "Signed by this phone's key. Whether the sender or the devnet's faucet pays is checked when you tap Send."))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $picking) {
            DevnetSendPicker(title: String(localized: "Send to"),
                             candidates: pickerCandidates,
                             onPick: { destination = $0 })
        }
    }

    /// The room's own resolution for the chosen address, so this card can never
    /// name somebody differently from the roster above it.
    private var recipientName: String? {
        VibenetWatch.shared.name(for: destination)
    }

    /// The addresses this devnet already knows, MINUS the one sending — an
    /// account cannot usefully send to itself, and offering it is a cell that
    /// leads to a refused transaction.
    private var knownAddresses: [String] {
        let me = "0x" + VibenetTransaction.hex(account)
        return VibenetWatch.shared.addresses.filter {
            $0.caseInsensitiveCompare(me) != .orderedSame
        }
    }

    private var pickerCandidates: [(address: String, name: String?)] {
        knownAddresses.map { ($0, VibenetWatch.shared.name(for: $0)) }
    }

    /// The button NAMES THE AMOUNT once there is one. A sheet's button sat a
    /// few points under the field it was about; this one sits at the bottom of
    /// a card in a scrolling room, so the figure it is about can be off screen
    /// — and "Send" alone, on a control that moves money, is the weakest thing
    /// it could say at the moment it is tapped.
    private var sendLabel: String {
        guard canSend, Self.weiData(from: amount) != nil else {
            return String(localized: "Send")
        }
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(localized: "Send \(trimmed) ETH")
    }

    /// This account's own native balance, off the last saved read — never a
    /// live one, the `VibenetRoomSource.card()` rule every synchronous draw in
    /// this room follows, so a keystroke never spends a request.
    private var held: Double? {
        let hex = VibenetTransaction.hex(account)
        return VibenetState.saved?.items.first {
            $0.address.caseInsensitiveCompare("0x" + hex) == .orderedSame
                || $0.address.caseInsensitiveCompare(hex) == .orderedSame
        }?.nativeBalance
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

    /// The in-well affordances. `label12` on `fillFaint` — the room's own quiet
    /// chip, never the mark: these fill a field in, they do not move money, and
    /// wearing the send button's colour would say they did.
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

                if let sentHash, let url = URL(string: VibenetExplorer.tx(sentHash)) {
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
        guard let target = VibenetTransaction.data(fromHex: destination), target.count == 20,
              let valueWei = Self.weiData(from: amount) else { return }
        let spending = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = VibenetRoom.shortAddress("0x" + VibenetTransaction.hex(target))
        errorText = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                let sent = try await VibenetSend.sendValue(from: account, to: target, valueWei: valueWei)
                DSHaptic.success()
                VibenetSend.landSendReceipt(sent, to: target, valueWei: valueWei, in: modelContext)
                sentSummary = String(localized: "\(spending) ETH to \(to) is on its way to the chain.")
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

    /// A typed decimal ETH amount to minimal big-endian wei bytes —
    /// `HegotaSendSheet.weiData`'s own reasoning, string arithmetic
    /// throughout, never `Double`: this devnet's own faucet balances run
    /// into the billions of ETH, well past `Double`'s exact-integer range.
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
