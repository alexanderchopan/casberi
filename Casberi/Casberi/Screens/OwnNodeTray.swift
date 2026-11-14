import SwiftUI

/// **NODES IN A TRAY (prd §1803, user: "a sheet like Round-ups, its row under
/// Connection").** The switch; on, a row per network under its mark, saying
/// your node's address or "Casberi's list"; a tap opens that network's field
/// and its check in place. The one sentence says what Tor no longer covers.
struct OwnNodeTray: View {
    @Bindable var model = OwnNodeModel.shared
    @State private var editing: Int?

    private struct Line: Identifiable {
        let id: Int
        let name: String
        let mark: String?
        let check: () async -> Void
        let useList: () -> Void
    }

    private var lines: [Line] {
        var all: [Line] = []
        // Your Aztec account reads Aztec (prd §1700f item 3).
        if AztecAccountStore.shared.isShown {
            all.append(Line(id: OwnNodeStore.aztecKey, name: String(localized: "Aztec"), mark: "brand-aztec",
                            check: { await model.checkAztec() }, useList: { model.useList(key: OwnNodeStore.aztecKey) }))
        }
        for net in YourAccountOp.networks {
            all.append(Line(id: net.chainId, name: net.name, mark: MoveSentence.networkMark(net),
                            check: { await model.check(net) }, useList: { model.useList(net) }))
        }
        return all
    }

    var body: some View {
        DSTray(title: String(localized: "Nodes"), height: 560) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSToggleRow(title: Text("Your own node"),
                                isOn: Binding(get: { model.settings.on },
                                              set: { on in withAnimation(DS.Motion.standard) { model.setOn(on) } }))
                        .frame(minHeight: 52)
                    if model.settings.on {
                        ForEach(lines) { line in
                            row(line)
                            if editing == line.id { field(line) }
                        }
                    }
                    DSFootnote("Your node sees your address. Tor doesn't hide it from your own node.")
                        .padding(.top, DS.Space.s4)
                }
                .padding(.vertical, DS.Space.s4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            // The switch's knob reaches the tray's edge (seen clipped).
            .scrollClipDisabled()
        }
        .task { model.load() }
    }

    private func row(_ line: Line) -> some View {
        let address = model.settings.nodes[String(line.id)]
        return Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { editing = editing == line.id ? nil : line.id }
        } label: {
            HStack(spacing: DS.Space.s2) {
                if let mark = line.mark { MoveRowMark(network: mark) }
                Text(verbatim: line.name).dsText(.body17).foregroundStyle(DS.textSecondary)
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: address.map(Self.host) ?? String(localized: "Casberi's list"))
                    .dsText(.heading20)
                    .foregroundStyle(address == nil ? DS.textSecondary : DS.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .dsGlyph(.tick, weight: .semibold)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityHint(Text("Changes it"))
    }

    /// One network's field and what its check said, under its row.
    @ViewBuilder private func field(_ line: Line) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            TextField(String(localized: "Casberi's list"),
                      text: Binding(get: { model.typed[line.id] ?? "" }, set: { model.typed[line.id] = $0 }))
                .dsText(.mono17)
                .foregroundStyle(DS.textPrimary)
                .tint(DS.pickInk)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { Task { await line.check() } }
                .frame(minHeight: 44)
            if model.checking.contains(line.id) {
                HStack(spacing: DS.Space.s2) {
                    DSSpinner()
                    Text("Asking it").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
            } else if let v = model.verdicts[line.id] {
                let said = OwnNode.words(v, network: line.name, expected: line.id)
                Text(verbatim: said.text).dsText(.body17)
                    .foregroundStyle(said.ok ? DS.confirmInk : DS.destructiveInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !(model.typed[line.id] ?? "").isEmpty {
                HStack(spacing: DS.Space.s6) {
                    Button { Task { await line.check() } } label: {
                        Text("Check").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                    Button { line.useList(); withAnimation(DS.Motion.standard) { editing = nil } } label: {
                        Text("Use Casberi's list").dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                }
            }
        }
        .padding(.bottom, DS.Space.s2)
        .transition(.opacity)
    }

    /// "https://my-node.local:8080/rpc" → "my-node.local:8080".
    static func host(_ address: String) -> String {
        guard let url = URL(string: address), let host = url.host else { return address }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}
