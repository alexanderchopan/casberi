import SwiftUI
import SwiftData

/// Your own model, connected — by address (2026-10-23, prd §1478). The person's
/// own OpenAI-compatible server (Ollama, LM Studio, llama.cpp, vLLM, Open
/// WebUI) as an agent in the composer, the same way OpenRouter and NEAR AI are.
///
/// One entry well, three fields: **Address** (required; `localhost:11434` on
/// the Mac, `192.168.1.20:11434` on the phone), **Key** (optional — Ollama on
/// a home network wants none), **Model** (filled from the server's own list
/// once the address answers, typed by hand when the server has no list).
/// Connect checks the address (`AgentAnswer.checkOwnModel`) and saves; on
/// success the seat becomes the active agent.
///
/// Three things on this page say what they do rather than let it be found:
///
/// - **Under an `http` address, one line**: "Not encrypted. Anyone on your
///   Wi-Fi could read what's sent." The address rule (`OwnModel.parse`) allows
///   `http` only to a local host; a public `http://` is refused at the field
///   with the reason, before Apple's ATS would refuse it with none.
/// - **Never "stays on your device."** The server is somebody's computer, so
///   every line says "the address you gave" (prd §83).
/// - **Configured is an address, not a key.** `AgentKey.configured` reads
///   `OwnModel.address` for this seat, so `keyed:` here follows whether a key
///   was in fact saved — a "Your key · in the Keychain" row over no key would
///   be the fake status §83 forbids.
///
/// `lands: true` for the reason every keyed seat has it since §839: a
/// conversation in the composer lands as a chat thing that grows as you talk.
struct OwnModelSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @State private var addressDraft = OwnModel.address ?? ""
    @State private var keyDraft = ""
    @State private var modelDraft = AgentModelStore.chosen(.ownModel) ?? ""
    /// The server's own list, read as soon as the typed address parses.
    @State private var models: [String] = []
    @State private var checking = false
    @State private var result: BridgeProof?
    @State private var configured = AgentKey.isConfigured(.ownModel)
    @State private var hasKey = TokenVault.get(AgentProvider.ownModel.vaultKey) != nil
    @State private var tick = 0

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    private static let setupCard = "setup"

    var body: some View {
        // The seat spelled out, as every account page does: the catalog-mode
        // audit reads these literals to agree the page's mode with the offer.
        AccountPage(
            name: "Your own model", seatID: "ownmodel", source: "Your own model",
            state: AccountPageState.of(name: "Your own model", seatID: "ownmodel",
                                       connected: configured, store: store),
            // "No sign-in" — true: an address, a key only if the server asks.
            mode: .noAccount,
            keyed: hasKey,
            lands: true,
            cardPushes: { _ in true },
            cardSheet: { _ in
                AnyView(AccountKeySheet(name: OwnModel.name,
                                        title: String(localized: "Your server")) { setupBlock })
            },
            teardown: {
                AgentKey.clear(.ownModel)
                configured = false
                hasKey = false
                addressDraft = ""
                modelDraft = ""
                models = []
            },
            sheet: $sheet,
            act: {
                if configured {
                    connectedBlock
                } else {
                    setupBlock
                }
            },
            more: { EmptyView() },
            keySheet: { setupBlock }
        )
    }

    // MARK: - The form

    private var address: OwnModel.Address { OwnModel.parse(addressDraft) }

    private var armed: Bool {
        !checking && address.url != nil
    }

    @ViewBuilder private var setupBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: OwnModel.placeholder(isMac: DS.isMac),
                        text: $addressDraft, actionLabel: "",
                        keyboard: .URL,
                        paste: { addressDraft = $0 },
                        action: connect)
            if let refusal = address.refusal {
                // The field's own refusal, said before anything is sent.
                DSProse.text(resolving: refusal)
                    .dsText(.subhead12).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let url = address.url, OwnModel.isPlainHTTP(url) {
                // The one explaining sentence this page gets (prd §748): a
                // local http address is plain text on the Wi-Fi, which the
                // controls cannot say and the person cannot otherwise know.
                DSFootnote(prose: OwnModel.httpLine)
            }
            DSSlabField(placeholder: AgentProvider.ownModel.placeholder, text: $keyDraft,
                        actionLabel: "", secure: true, action: connect)
                // The page's one ask (§1302) is the ADDRESS — the field a
                // person fills first. Sibling `onAppear` order is not
                // guaranteed, so the other two fields leave the ask alone.
                .environment(\.dsAskFocus, nil)
            if !models.isEmpty {
                // The server's own list, the moment the address answers. A
                // Menu, as every agent's picker is: an Ollama with forty pulls
                // would otherwise turn the form into a directory.
                Menu {
                    ForEach(models, id: \.self) { id in
                        Button {
                            DSHaptic.selection()
                            modelDraft = id
                        } label: {
                            if id == modelDraft {
                                Label(id, systemImage: "checkmark")
                            } else {
                                Text(id)
                            }
                        }
                    }
                } label: {
                    DSDoorRowLabel(icon: "slider.horizontal.3",
                                   title: Text(modelDraft.isEmpty
                                               ? String(localized: "Choose a model")
                                               : modelDraft))
                        .dsTapTarget()
                }
                .buttonStyle(RowPress())
                .dsHover()
            }
            DSSlabField(placeholder: models.isEmpty
                            ? String(localized: "Model, like llama3.1")
                            : String(localized: "Or type a model"),
                        text: $modelDraft,
                        actionLabel: checking ? "Checking…" : (configured ? "Update" : "Connect"),
                        isArmed: armed,
                        action: connect)
                .environment(\.dsAskFocus, nil)
            BridgeSyncStatusRows(proof: result)
        }
        // Read the list as soon as the typed address parses, so the picker
        // fills before Connect is pressed. Silent: a failure here says nothing
        // — Connect will, with the sentence for it.
        .task(id: address.url) {
            guard let url = address.url else { models = []; return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            let key = keyDraft.isEmpty ? TokenVault.get(AgentProvider.ownModel.vaultKey) : keyDraft
            if case .connected(let list) = await AgentAnswer.checkOwnModel(base: url, key: key,
                                                                             typedModel: modelDraft) {
                models = list
                // A server with exactly one model has chosen it.
                if modelDraft.isEmpty, list.count == 1 { modelDraft = list[0] }
            }
        }
    }

    /// Connects only after the server answers at the address.
    private func connect() {
        let typed = addressDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = address.url else {
            if let refusal = address.refusal { result = .failed(refusal) }
            return
        }
        let newKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = newKey.isEmpty ? TokenVault.get(AgentProvider.ownModel.vaultKey) : newKey
        checking = true
        result = nil
        Task { @MainActor in
            let outcome = await AgentAnswer.checkOwnModel(base: url, key: key,
                                                          typedModel: modelDraft)
            checking = false
            switch outcome {
            case .connected(let list):
                if !list.isEmpty { models = list }
                var model = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if model.isEmpty, list.count == 1 { model = list[0] }
                guard !model.isEmpty else {
                    // The address answers; the picker is filled. The one thing
                    // left is theirs to choose — a request with no model never
                    // goes out.
                    result = .says(String(localized: "That server answers. Choose a model to finish."))
                    return
                }
                // What changed forgets the tool memory (prd §1478): a refusal
                // remembered for one model at one address says nothing about
                // another.
                let previous = OwnModel.address
                if previous != typed || model != AgentModelStore.chosen(.ownModel) {
                    OwnModel.forgetToolless()
                }
                OwnModel.setAddress(typed)
                if !newKey.isEmpty {
                    AgentKey.set(newKey, for: .ownModel)
                } else {
                    AgentKey.activate(.ownModel)
                }
                AgentModelStore.set(model, for: .ownModel)
                modelDraft = model
                configured = true
                hasKey = TokenVault.get(AgentProvider.ownModel.vaultKey) != nil
                keyDraft = ""
                tick += 1
                DSHaptic.success()
                result = .connected(String(localized: "answers now offer \"Try with your key\" on \(model)."))
                store.registerConnected(id: OwnModel.seatID, name: OwnModel.name,
                                        proof: String(localized: "At \(OwnModel.hostLine(url))"),
                                        can: ["Answers on your own server — only when you tap.",
                                              OwnModel.privacyLine,
                                              "Remembers a chat's earlier answers; screenshots and web search stay off."])
            case .unreachable:
                result = .failed(OwnModel.Check.unreachableLine(host: OwnModel.hostLine(url)))
            case .needsModel, .noModels, .wantsKey, .keyRefused, .webPage, .other:
                result = .failed(outcome.line ?? "")
            }
        }
    }

    // MARK: - Connected

    /// The live facts about a server that is already answering: which agent
    /// answers, at what address, with which model. The address and model rows
    /// open the same form the seat was connected with.
    @ViewBuilder private var connectedBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            AgentActiveStatusRow(provider: .ownModel)
            AccountFactRow(glyph: "server.rack",
                           title: String(localized: "Address"),
                           fact: OwnModel.base.map(OwnModel.hostLine) ?? (OwnModel.address ?? ""),
                           opens: true,
                           action: { sheet = .card(id: Self.setupCard) })
            AccountFactRow(glyph: "cpu",
                           title: String(localized: "Model"),
                           fact: AgentProvider.ownModel.model.isEmpty
                               ? String(localized: "Choose one") : AgentProvider.ownModel.model,
                           opens: true,
                           action: { sheet = .card(id: Self.setupCard) })
            // The librarian's switch draws only on the ACTIVE agent's page,
            // so it cannot read as a per-seat setting (prd §871). No spend
            // row: there is no bill.
            AgentLibrarianRow(provider: .ownModel)
        }
        .id(tick)
    }
}
