import SwiftUI

/// **SEND PRIVATELY ON AZTEC (prd §1700e).** Picked from Send's recipients
/// when the address typed is an Aztec account (`0x` and 64 hex characters,
/// longer than Ethereum's); its own sentence, as gas's is. Shield's USDC or
/// WETH moves from your Aztec account to theirs, privately: who, what and how
/// much stay hidden, and no one's permission is asked (measured, §1700d item
/// 6). Face ID, then about 20 seconds to prove it on this iPhone.
struct MoveAztecSendSentence<Head: View>: View {
    let to: String
    var inTray = false
    var leave: () -> Void = {}
    @ViewBuilder let head: () -> Head

    enum Stage: Equatable { case ready, working(String), sent, failed(String) }

    @State private var symbol = "USDC"
    @State private var amount = ""
    @State private var stage: Stage = .ready
    @FocusState private var typing: Bool
    private var store: AztecAccountStore { .shared }

    /// What the account holds of a token on Aztec, privately (from the last reading).
    private func held(_ symbol: String) -> AztecAccountStore.Holding? {
        store.shown.holdings.first { $0.name == symbol && $0.kind == .token }
    }

    /// The amount in base units, or nil when it is not a number this token can hold.
    private var units: String? {
        let decimals = held(symbol)?.decimals ?? (symbol == "USDC" ? 6 : 18)
        guard let value = Decimal(string: amount), value > 0 else { return nil }
        let scaled = value * pow(10, decimals)
        var rounded = Decimal(); var s = scaled
        NSDecimalRound(&rounded, &s, 0, .down)
        guard rounded == scaled else { return nil } // more places than the token has
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private var enough: Bool {
        guard let units, let have = held(symbol)?.privateUnits, let h = Decimal(string: have), let u = Decimal(string: units) else { return false }
        return u <= h
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                MoveFlow {
                    head()
                    MovePhrase(amount.isEmpty ? String(localized: "an amount") : "\(amount) \(symbol)", ink: DS.pickInk)
                    MovePhrase(String(localized: "on Aztec"), glue: String(localized: "on"))
                    MovePhrase("\(AddressTail.short(to)) \(String(localized: "privately."))", glue: String(localized: "to"))
                }
                HStack(spacing: DS.Space.s2) {
                    ForEach(["USDC", "WETH"], id: \.self) { s in
                        Button { withAnimation(DS.Motion.standard) { symbol = s } } label: {
                            Chip(text: s, selected: s == symbol)
                        }
                        .buttonStyle(PressSpring())
                        .disabled(stage != .ready)
                    }
                }
                .padding(.top, DS.Space.s4)
                TextField(String(localized: "Amount"), text: $amount)
                    .keyboardType(.decimalPad)
                    .focused($typing)
                    .dsText(.heading24)
                    .padding(.top, DS.Space.s3)
                    .disabled(stage != .ready)
                Text(line)
                    .dsText(.subhead12)
                    .foregroundStyle(lineInk)
                    .padding(.top, DS.Space.s2)
                HStack(spacing: DS.Space.s1) {
                    ProtocolInlineMark(mark: "aztec")
                    Text("Powered by Aztec").dsText(.subhead12).foregroundStyle(DS.textSecondary)
                }
                .padding(.top, DS.Space.s2)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .task { if AztecProver.isAvailable, !DemoMode.isActive { await store.refresh() } }
    }

    private var line: String {
        switch stage {
        case .ready:
            if let h = held(symbol), let decimals = h.decimals, let p = h.privateUnits {
                return String(localized: "You have \(PrivateMoney.figure(p, decimals: decimals, symbol: symbol)) privately on Aztec.")
            }
            return String(localized: "Who, what and how much stay private. About 20 seconds to prove on this iPhone.")
        case .working(let words): return words
        case .sent: return String(localized: "Sent privately.")
        case .failed(let why): return why
        }
    }

    private var lineInk: Color {
        if case .failed = stage { return DS.destructiveInk }
        return DS.textSecondary
    }

    private var foot: some View {
        HStack(alignment: .firstTextBaseline) {
            Button { leave() } label: {
                Text("Back").dsText(.heading24).foregroundStyle(DS.textSecondary).frame(minHeight: 48)
            }
            .buttonStyle(RowPress())
            Spacer(minLength: DS.Space.s3)
            Button { Task { await send() } } label: {
                Text(footWord).dsText(.heading34)
                    .foregroundStyle(canSend ? DS.pickInk : DS.textSecondary)
                    .frame(minHeight: 48, alignment: .trailing)
            }
            .buttonStyle(RowPress())
            .disabled(!canSend)
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.vertical, DS.Space.s2)
    }

    private var canSend: Bool { stage == .ready && units != nil && enough && !DemoMode.isActive && AztecProver.isAvailable }

    private var footWord: LocalizedStringKey {
        switch stage {
        case .ready:
            if DemoMode.isActive { return "Not in the demo" }
            if units != nil, !enough { return "Not enough" }
            return "Send"
        case .working: return "Sending…"
        case .sent: return "Sent"
        case .failed: return "Try again"
        }
    }

    @MainActor
    private func send() async {
        guard let units else { return }
        typing = false
        do {
            try await PrivateRootKey.unlock(reason: String(localized: "Send privately on Aztec"))
        } catch { return }
        stage = .working(String(localized: "Proving on this iPhone…"))
        do {
            _ = try await AztecEngine.shared.call("sendPrivately", [symbol, to, units])
            AztecAccountStore.shared.markUsed(address: (try? await AztecEngine.shared.accountAddress()) ?? "")
            stage = .sent
            DSHaptic.success()
            await AztecAccountStore.shared.refresh()
        } catch {
            stage = .failed(AztecEngine.words(error))
            try? await Task.sleep(for: .seconds(3))
            if case .failed = stage { stage = .ready }
        }
    }
}

enum AztecAddressText {
    /// An Aztec account's address: `0x` and 64 hex characters.
    static func isAztec(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        return t.hasPrefix("0x") && t.count == 66 && t.dropFirst(2).allSatisfy(\.isHexDigit)
    }
}
