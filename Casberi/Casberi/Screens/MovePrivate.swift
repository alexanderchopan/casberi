import SwiftUI

/// **MOVE TO PRIVATE IS A MOVE SENTENCE (prd §1553).** Move is the one place
/// money moves, so the private deposit is one more of its sentences, drawn in
/// its anatomy: the verbs on their own line (`head`, Move's own), then
///
///     Move 0.001 ETH
///     to private
///     on Sepolia.
///
/// at the sentence's one size (`MoveFlow`), the amount a pink word whose
/// choices open in the glass box under it, one grey line under that, and the
/// act at the foot's trailing edge, a word that says each stage as Move's
/// does ("Confirm with Face ID", "Waiting for Sepolia…"). Done, the sentence
/// turns past tense in place and waits for 0xBow's approval, asking again
/// while it stands; Holdings shows the same note moving in.
///
/// Sepolia only, DEBUG builds only: the sender is the DEBUG testnet sender
/// (`PrivacyTestnetSender`) until your account sends. Short of Sepolia ETH,
/// the sentence names the address to fund ("Fund …DeBb on Sepolia first."),
/// tail only, and the foot copies the whole of it.
struct MovePrivateSentence<Head: View>: View {
    /// Held by whoever draws the sentence, so Move's verbs can wait on it.
    let move: PrivateMove
    var inTray = false
    @ViewBuilder let head: () -> Head

    @State private var choosing = false
    @State private var copied = false
    @Environment(\.openURL) private var openURL

    private var store: PrivateMoneyStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                head()
                    .padding(.bottom, DS.Space.s4)
                MoveFlow { sentence }
                    .animation(DS.Motion.standard, value: move.stage)
                    .animation(DS.Motion.standard, value: move.amount)
                Group {
                    if choosing, move.stage == .ready {
                        choices
                            .transition(.asymmetric(insertion: .offset(y: 24).combined(with: .opacity), removal: .opacity))
                    } else {
                        line.transition(.opacity)
                    }
                }
                .padding(.top, choosing ? DS.Space.s4 : DS.Space.s6)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { if !choosing { foot.transition(.opacity) } }
        .task {
            await move.read()
            #if DEBUG
            if let amount = UserDefaults.standard.string(forKey: "movePrivateAmount"), move.choices.contains(amount) {
                move.amount = amount
            }
            NSLog("[Casberi] movePrivate: %@", String(describing: move.stage))
            if UserDefaults.standard.bool(forKey: "movePrivateGo"), move.stage == .ready {
                await move.run()
            }
            #endif
        }
        // Done, the ASP is asked again while the sentence stands, so the
        // approval lands here as well as in Holdings.
        .task(id: doneHash) {
            guard doneHash != nil else { return }
            for _ in 0..<30 where note?.status == .waiting {
                try? await Task.sleep(for: .seconds(20))
                await store.refresh(force: true)
            }
        }
    }

    private var doneHash: String? {
        if case .done(let hash) = move.stage { return hash }
        return nil
    }

    /// The note this sentence made, once it has.
    private var note: PrivateMoney.Note? {
        guard let doneHash else { return nil }
        return store.notes.first { $0.tx == doneHash }
    }

    private var figure: String {
        PrivateMoney.figure(PrivateMoney.baseUnits(move.amount, decimals: 18) ?? "0", decimals: 18, symbol: "ETH")
    }

    // MARK: - The sentence

    @ViewBuilder private var sentence: some View {
        switch move.stage {
        case .reading:
            MovePhrase(String(localized: "Reading Sepolia…"), ink: DS.textSecondary)
        case .needsFunds(let address):
            MoveClause(glue: String(localized: "Fund")) {
                Button { copy(address) } label: { MoveWord(YourAccount.short(address), ink: DS.pickInk) }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text("This build's test account, \(address)"))
                    .accessibilityHint(Text("Copies the address"))
            }
            MovePhrase(String(localized: "Sepolia"), glue: String(localized: "on"))
            MovePhrase(String(localized: "first."))
        case .done:
            MoveClause(glue: String(localized: "Moved")) { MoveWord(figure) }
            MovePhrase(String(localized: "private"), glue: String(localized: "to"))
            MovePhrase(String(localized: "Sepolia."), glue: String(localized: "on"))
        default:
            // Ready, working or refused: the sentence stands as written, and
            // the foot (or the line) says the rest.
            MoveClause(glue: String(localized: "Move")) {
                Button {
                    guard move.stage == .ready else { return }
                    withAnimation(DS.Motion.standard) { choosing.toggle() }
                    DSHaptic.selection()
                } label: {
                    MoveWord(figure, ink: move.stage == .ready ? (choosing ? DS.pickInk.opacity(0.6) : DS.pickInk) : DS.textPrimary)
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Amount, \(figure)"))
                .accessibilityHint(Text("Picks how much"))
            }
            MovePhrase(String(localized: "private"), glue: String(localized: "to"))
            MovePhrase(String(localized: "Sepolia."), glue: String(localized: "on"))
        }
    }

    /// The one grey line under the sentence: what the test account holds,
    /// what went wrong, or where the move stands.
    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready, .opening, .preparing, .registering, .proving, .sending:
            if let held = move.held {
                Text("\(held) test ETH in this build's account")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
            }
        case .failed(let words):
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        case .done(let hash):
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(verbatim: approval)
                    .dsText(.body17)
                    .foregroundStyle(note?.status == .approved ? DS.confirmInk
                                     : note?.status == .rejected ? DS.destructiveInk : DS.attentionInk)
                if let link = URL(string: "https://sepolia.etherscan.io/tx/" + hash) {
                    let explorer = "Etherscan"
                    Button { openURL(link) } label: {
                        Text("View on \(explorer)").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                }
            }
        default:
            EmptyView()
        }
    }

    private var approval: String {
        switch note?.status {
        case .approved: String(localized: "Approved, private now")
        case .rejected: String(localized: "Not approved")
        default: String(localized: "Waiting for approval")
        }
    }

    /// The amounts this account can move and still pay the gas, in the
    /// glass box Move opens a blank's choices in.
    private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(move.choices, id: \.self) { step in
                let shown = PrivateMoney.figure(PrivateMoney.baseUnits(step, decimals: 18) ?? "0", decimals: 18, symbol: "ETH")
                Button {
                    withAnimation(DS.Motion.standard) {
                        move.amount = step
                        choosing = false
                    }
                    DSHaptic.selection()
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        AssetMark(name: "ETH", size: DS.Face.list)
                        Text(verbatim: shown)
                            .dsText(.body17)
                            .foregroundStyle(step == move.amount ? DS.textSecondary : DS.textPrimary)
                            .monospacedDigit()
                        Spacer(minLength: DS.Space.s2)
                    }
                    .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityAddTraits(step == move.amount ? [.isSelected] : [])
            }
        }
        .padding(.vertical, DS.Space.s2)
        .padding(.horizontal, DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(cornerRadius: RoomsTray.radius)
    }

    // MARK: - The foot

    /// The act at the trailing edge, Move's rung; a quiet word beside it
    /// where there is a second thing to do.
    private var foot: some View {
        HStack(alignment: .firstTextBaseline) {
            switch move.stage {
            case .needsFunds(let address):
                Button {
                    Task { await move.read() }
                    DSHaptic.selection()
                } label: {
                    Text("Check again").dsText(.heading24).foregroundStyle(DS.textPrimary).frame(minHeight: 48)
                }
                .buttonStyle(RowPress())
                Spacer(minLength: DS.Space.s3)
                footButton(copied ? String(localized: "Copied") : String(localized: "Copy address"), on: true) { copy(address) }
            case .done:
                Spacer(minLength: 0)
            case .failed:
                Spacer(minLength: 0)
                footButton(String(localized: "Try again"), on: true) { Task { await move.read() } }
            default:
                Spacer(minLength: 0)
                footButton(footVerb, on: move.stage == .ready) {
                    choosing = false
                    Task { await move.run() }
                }
                .disabled(move.stage != .ready)
            }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    /// Each stage in the foot's own words, as Move's verb says its own.
    private var footVerb: String {
        switch move.stage {
        case .reading: String(localized: "Move to private")
        case .opening: String(localized: "Confirm with Face ID")
        case .preparing: String(localized: "Preparing…")
        case .registering(let n): String(localized: "Setting up, \(n) of 2…")
        case .proving: String(localized: "Proving…")
        case .sending: String(localized: "Waiting for Sepolia…")
        default: String(localized: "Move to private")
        }
    }

    private func footButton(_ word: String, on: Bool, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(verbatim: word)
                .dsText(.heading34)
                .foregroundStyle(on ? DS.pickInk : DS.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minHeight: 48, alignment: .trailing)
        }
        .buttonStyle(RowPress())
    }

    private func copy(_ address: String) {
        DSPasteboard.copy(address)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
    }
}
