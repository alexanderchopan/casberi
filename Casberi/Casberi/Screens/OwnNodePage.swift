import SwiftUI

/// **NODES, UNDER YOUR ACCOUNT (prd §1509 item 5, §1517, canvas figure 14).**
/// A switch, "Your own node"; on, each network takes an address or keeps
/// Casberi's list, and an address is checked against the network's chain id
/// before it is used. One sentence says what Tor no longer covers.
@MainActor @Observable
final class OwnNodeModel {
    static let shared = OwnNodeModel()
    var settings = OwnNodeStore.settings
    /// What is typed per network, and what its check said.
    var typed: [Int: String] = [:]
    var verdicts: [Int: OwnNode.Verdict] = [:]
    var checking: Set<Int> = []

    private var demo: Bool { YourAccountDemo.isOn }

    func load() {
        if demo {
            settings = YourAccountDemo.ownNode
            verdicts = YourAccountDemo.ownNodeVerdicts
        } else {
            settings = OwnNodeStore.settings
        }
        for (id, address) in settings.nodes { typed[Int(id) ?? 0] = typed[Int(id) ?? 0] ?? address }
    }

    func setOn(_ on: Bool) {
        settings.on = on
        if !demo { OwnNodeStore.save(settings) }
    }

    /// Check the typed address; kept only when it answers for this network.
    func check(_ net: YourAccountOp.Network) async {
        let text = typed[net.chainId] ?? ""
        guard !checking.contains(net.chainId) else { return }
        if demo {
            verdicts[net.chainId] = OwnNode.normalized(text) == nil ? .notAnAddress
                : .answers(chainId: net.chainId, block: 31_882_104)
            return
        }
        checking.insert(net.chainId)
        defer { checking.remove(net.chainId) }
        let (verdict, url) = await OwnNodeStore.check(text, chainId: net.chainId)
        verdicts[net.chainId] = verdict
        if case .answers = verdict, let url {
            settings.nodes[String(net.chainId)] = url
            OwnNodeStore.save(settings)
        }
        #if DEBUG
        NSLog("ownNode| %@ %@ → %@", net.name, url ?? text, OwnNode.words(verdict, network: net.name, expected: net.chainId).text)
        #endif
    }

    /// Back to Casberi's list for this network.
    func useList(_ net: YourAccountOp.Network) {
        settings.nodes[String(net.chainId)] = nil
        typed[net.chainId] = nil
        verdicts[net.chainId] = nil
        if !demo { OwnNodeStore.save(settings) }
    }
}

/// The page's box: how many networks read from your node.
struct OwnNodeFigure: View {
    let model = OwnNodeModel.shared

    var body: some View {
        let n = model.settings.on ? model.settings.nodes.count : 0
        DSFigureReading(number: "\(n)",
                        caption: n == 0 ? String(localized: "networks read from Casberi's list")
                                        : n == 1 ? String(localized: "network reads from your node")
                                                 : String(localized: "networks read from your node"))
            .task { model.load() }
    }
}

/// The switch, a block per network, and the one sentence.
struct OwnNodeRows: View {
    @Bindable var model = OwnNodeModel.shared

    var body: some View {
        Section {
            DSToggleRow(title: Text("Your own node"),
                        isOn: Binding(get: { model.settings.on }, set: { model.setOn($0) }))
                .walletRowPitch()
                .walletListRow()
            if model.settings.on {
                ForEach(YourAccountOp.networks) { net in
                    network(net).walletListRow()
                }
            }
            DSFootnote("Your node sees your address. Tor doesn't hide it from your own node.")
                .walletListRow()
        }
    }

    @ViewBuilder private func network(_ net: YourAccountOp.Network) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: net.name).dsText(.body17).foregroundStyle(DS.textPrimary)
            TextField(String(localized: "Casberi's list"),
                      text: Binding(get: { model.typed[net.chainId] ?? "" }, set: { model.typed[net.chainId] = $0 }))
                .dsText(.mono17)
                .foregroundStyle(DS.textPrimary)
                .tint(DS.pickInk)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { Task { await model.check(net) } }
                .frame(minHeight: 44)
            if model.checking.contains(net.chainId) {
                HStack(spacing: DS.Space.s2) {
                    DSSpinner()
                    Text("Asking it").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
            } else if let v = model.verdicts[net.chainId] {
                let said = OwnNode.words(v, network: net.name, expected: net.chainId)
                HStack(alignment: .firstTextBaseline) {
                    Text(said.ok ? "Answers" : "Not used").dsText(.body17).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: said.text).dsText(.body17).foregroundStyle(said.ok ? DS.confirmInk : DS.destructiveInk)
                        .multilineTextAlignment(.trailing)
                }
            }
            if !(model.typed[net.chainId] ?? "").isEmpty {
                HStack(spacing: DS.Space.s6) {
                    Button { Task { await model.check(net) } } label: {
                        Text("Check").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                    Button { model.useList(net) } label: {
                        Text("Use Casberi's list").dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                }
            }
        }
        .padding(.vertical, DS.Space.s2)
    }
}
