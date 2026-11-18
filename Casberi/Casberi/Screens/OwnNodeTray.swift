import SwiftUI

/// **NODES IN A TRAY (prd §1803, user: "a sheet like Round-ups, its row under
/// Connection"; no switch since §1833).** A row per network under its mark,
/// saying "Public" or your node's host; a tap opens that network's field, a
/// paste checks it in place. The one sentence says what Tor no longer covers.
struct OwnNodeTray: View {
    @Bindable var model = OwnNodeModel.shared
    @State private var editing: Int?
    /// A row opened is a field focused: the keyboard comes with it.
    @FocusState private var focused: Int?

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
                    ForEach(lines) { line in
                        row(line)
                        if editing == line.id { field(line) }
                    }
                    DSFootnote("Your own node sees your address, even over Tor.")
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
            focused = editing
        } label: {
            HStack(spacing: DS.Space.s2) {
                if let mark = line.mark { MoveRowMark(network: mark) }
                Text(verbatim: line.name).dsText(.body17).foregroundStyle(DS.textSecondary)
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: address.map(Self.host) ?? OwnNode.publicWord)
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
            TextField(OwnNode.fieldPrompt,
                      text: Binding(get: { model.typed[line.id] ?? "" },
                                    set: { model.type($0, key: line.id, check: line.check) }))
                .dsText(.mono17)
                .foregroundStyle(DS.textPrimary)
                .tint(DS.pickInk)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused, equals: line.id)
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
            if !(model.typed[line.id] ?? "").isEmpty || model.settings.nodes[String(line.id)] != nil {
                HStack(spacing: DS.Space.s6) {
                    Button { Task { await line.check() } } label: {
                        Text("Check").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                    Button { line.useList(); withAnimation(DS.Motion.standard) { editing = nil } } label: {
                        Text(OwnNode.usePublic).dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                }
            }
        }
        .padding(.bottom, DS.Space.s2)
        .transition(.opacity)
    }

    /// A typed address shortened to its host and port, no scheme or path.
    static func host(_ address: String) -> String {
        guard let url = URL(string: address), let host = url.host else { return address }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}
