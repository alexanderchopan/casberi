import SwiftUI
import SwiftData

/// Which model a key answers with, read from the provider (2026-08-06,
/// `AgentModels`) — shown on the settings key card and on each key-backed
/// agent screen, beside `AgentActiveStatusRow`.
///
/// Renders nothing until the provider is configured: there is no model choice
/// to offer for a key that doesn't exist, and the list read needs that key.
/// Bankr renders nothing either, and that is a real answer rather than a gap —
/// it picks its own model per job, so there is genuinely nothing to choose
/// (`AgentModels.list` returns an empty list for it, which is deliberately
/// distinct from the nil it returns when a read FAILED).
///
/// The list is fetched on demand, never on appear. It is a free read on every
/// provider here, but it is still somebody's network and somebody's rate
/// limit, and a settings screen that fires requests for being looked at is the
/// shape this codebase keeps deciding against.
struct AgentModelRow: View {
    let provider: AgentProvider
    /// Which job this picker chooses for (2026-08-20, `AgentTask`). The ask is
    /// the default so every existing call site keeps its meaning; the librarian
    /// row passes `.librarian` and is drawn only where that work is actually
    /// happening (`AgentLibrarianRow`).
    var task: AgentTask = .ask

    @State private var models: [AgentModelInfo] = []
    @State private var loading = false
    /// nil until a read has been attempted; false means it failed, which is a
    /// different sentence from "this provider offers nothing".
    @State private var readable: Bool?
    @State private var tick = 0

    var body: some View {
        if AgentKey.isConfigured(provider), provider != .bankr {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    Text(task == .librarian ? "Model for organizing" : "Model")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    // The id, not a prettied label: the id is what actually
                    // goes on the wire, and it is what a provider's own
                    // pricing page is keyed by.
                    Text(provider.model(for: task))
                        .dsText(.body17).monospaced()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                }
                // No caption under the model (prd §748): the menu's own first
                // row already says "Default (…)" / "Same as questions".
                if loading {
                    HStack(spacing: DS.Space.s2) {
                        DSSpinner()
                        Text("Asking \(provider.company) what it offers…")
                            .dsText(.body17).foregroundStyle(DS.textTertiary)
                    }
                } else if readable == false {
                    Text("Couldn't read \(provider.company)'s model list — keeping \(provider.defaultModel).")
                        .dsText(.subhead12).foregroundStyle(DS.attention)
                        .fixedSize(horizontal: false, vertical: true)
                } else if models.isEmpty {
                    // A verb, so a row (prd §746).
                    DSDoorRow(icon: "slider.horizontal.3", label: "Choose a model") {
                        DSHaptic.tap()
                        load()
                    }
                } else {
                    // A Menu rather than a list of rows: OpenRouter answers
                    // with several hundred, and any layout that draws them all
                    // turns a settings card into a directory.
                    Menu {
                        Button {
                            AgentModelStore.set(nil, for: provider, task: task)
                            AgentModelFacts.forget(provider, task: task)
                            tick += 1
                        } label: {
                            Text(task == .librarian && AskSurface.enabled
                                 ? String(localized: "Same as questions")
                                 : String(localized: "Default (\(provider.defaultModel))"))
                        }
                        ForEach(models) { model in
                            Button {
                                DSHaptic.selection()
                                AgentModelStore.set(model.id, for: provider, task: task)
                                // What the listing said about it, kept beside
                                // the choice (2026-08-23, prd §459). THIS is
                                // the only moment both are in hand — re-reading
                                // the list later to learn it would be a settings
                                // screen firing requests for being looked at.
                                // A model the provider said nothing about
                                // forgets rather than keeping the last one's
                                // facts, or a pin swap would silently inherit
                                // somebody else's capabilities.
                                if let facts = model.facts {
                                    AgentModelFacts.remember(facts, for: provider, task: task)
                                } else {
                                    AgentModelFacts.forget(provider, task: task)
                                }
                                tick += 1
                            } label: {
                                // The price and the free mark ride the menu row
                                // rather than a separate screen: choosing among
                                // four hundred names is the exact moment cost
                                // matters, and it is the one place this app can
                                // state a price it did not compute.
                                if model.id == provider.model(for: task) {
                                    Label(menuLabel(model), systemImage: "checkmark")
                                } else {
                                    Text(menuLabel(model))
                                }
                            }
                        }
                    } label: {
                        // A CHOICE — the picker's current answer (prd §746).
                        Chip(text: String(localized: "\(models.count) available"),
                             glyph: "slider.horizontal.3",
                             selected: AgentModelStore.chosen(provider, task: task) != nil)
                    }
                }
            }
            // `tick` is never read — mutating it is enough to invalidate the
            // view, which re-evaluates the static, non-observable
            // `AgentModelStore.chosen` fresh (`AgentActiveStatusRow`'s trick,
            // same reason).
            .dsListRow()
        }
    }

    /// "Claude Sonnet 4.5 · $3.00/M in" — the model's own name, plus what its
    /// listing prices it at (2026-08-23, prd §459).
    ///
    /// **Only the INPUT rate, and that is a legibility decision rather than a
    /// rounding one.** Both halves would double the width of every one of four
    /// hundred rows, and for the work this app does — a prompt carrying sixteen
    /// candidates and up to six screenshots, answered in a few sentences —
    /// input is the half that decides the bill. The full pair is on the
    /// provider's own pricing page, which is where somebody comparing seriously
    /// is going anyway.
    ///
    /// "Free" replaces the rate rather than printing "$0.00/M in", which reads
    /// as a rounding artifact on a screen full of tiny numbers.
    private func menuLabel(_ model: AgentModelInfo) -> String {
        guard let facts = model.facts else { return model.label }
        if facts.free { return String(localized: "\(model.label) · Free") }
        guard let rate = facts.promptUSDPerMillion, rate > 0 else { return model.label }
        return String(localized: "\(model.label) · \(String(format: "$%.2f", rate))/M in")
    }

    private func load() {
        guard let key = TokenVault.get(provider.vaultKey) else { return }
        loading = true
        Task {
            let found = await AgentModels.list(provider: provider, key: key)
            await MainActor.run {
                loading = false
                readable = found != nil
                models = found ?? []
            }
        }
    }
}

/// What this key has actually been spent on (2026-08-06, `AgentSpend`) — the
/// receipt for the sentence settings has always carried, "They bill you
/// directly."
///
/// Deliberately does NOT show a dollar figure it computed. A rate table is the
/// artifact this codebase keeps learning not to ship: it renders perfectly
/// whatever is in it and goes stale the day a provider re-prices, and a wrong
/// number on a spending screen is believed. Tokens are measured; the one
/// dollar figure that appears is one the provider itself reported.
struct AgentSpendRow: View {
    let provider: AgentProvider
    /// Bumped by the caller to force a re-read of the non-observable ledger.
    var tick = 0

    var body: some View {
        if let entry = AgentSpend.shared.entry(for: provider), entry.requests > 0 {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .foregroundStyle(DS.textSecondary)
                        .accessibilityHidden(true)
                    Text(AskSurface.enabled ? requestLine(entry)
                         // With the ask off every request is the librarian's,
                         // so none of them is "an ask" (prd §718).
                         : entry.requests == 1 ? String(localized: "1 request")
                         : String(localized: "\(entry.requests) requests"))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                }
                if let tokens = entry.tokenLine {
                    Text(tokens)
                        .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    // Only when there is a hit to report. A "0 served from
                    // cache" would read as a thing that went wrong, when for a
                    // short exchange it just means the prompt never reached the
                    // model's minimum cacheable length.
                    if let cache = entry.cacheLine {
                        Text(cache)
                            .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    // The honest blank. A "0 in · 0 out" here would claim the
                    // requests were free.
                    DSFootnote("\(provider.company) doesn't report token counts to us.")
                }
                // What THIS APP spent, above what the key has spent — the
                // narrower and more useful of the two, so it leads (2026-08-23,
                // prd §459). They are deliberately two lines and never one
                // total: the app's figure covers only generations it started,
                // the key's covers everything the key has ever done, and adding
                // them would double-count while subtracting them would invent a
                // number for other apps.
                if let line = entry.appCostLine {
                    Text(line)
                        .dsText(.subhead12).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let usd = entry.reportedUSD {
                    Text("\(provider.company) reports \(String(format: "$%.2f", usd)) used on this key, across everything it's used for.")
                        .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // `DS.device`, not "this iPhone" — this line is a claim about
                // where the counting happens, and on Mac the literal was
                // false. The sibling line 44 rows down already said
                // "there's no on-device model here" correctly, so one file
                // held both the fixed and the unfixed spelling.
                DSFootnote("Counted on \(DS.device). Your bill is \(provider.company)'s — see \(provider.console).")
            }
            .dsListRow()
        }
    }

    /// "12 asks" when nothing went looking, "12 asks · 19 calls" when the tool
    /// loop spent extra rounds — the two numbers differ only when it did, so
    /// the second appears only then.
    private func requestLine(_ entry: AgentSpend.Entry) -> String {
        let asks = entry.requests - entry.toolRounds
        if entry.toolRounds == 0 {
            return asks == 1 ? String(localized: "1 ask")
                             : String(localized: "\(asks) asks")
        }
        return String(localized: "\(asks) asks · \(entry.requests) calls, \(entry.toolRounds) of them searching your things")
    }
}

/// The two things only a ROUTER can be asked for (2026-08-23, prd §459) —
/// drawn for OpenRouter and nowhere else, because nowhere else is there a
/// choice of who serves a request.
///
/// Every other agent seat is one company answering with its own models: there
/// is no second backend to prefer and no plugin to enable, so a control here
/// would be the dead switch the honesty rule bans. This renders only when the
/// provider it is handed is OpenRouter and that key exists.
///
/// **The two defaults deliberately disagree, and the asymmetry is the point.**
/// Private routing is ON: it only ever narrows what happens to a question
/// already being sent, and it is the app's own promise made enforceable by
/// somebody else's routing table. Web search is OFF: it sends the question
/// somewhere new AND bills per result, and a tap that quietly costs more than
/// expected is the one surprise a receipt cannot undo.
struct OpenRouterRoutingRow: View {
    let provider: AgentProvider
    @State private var privateRouting = AgentOpenRouter.privateRouting
    @State private var webSearch = AgentOpenRouter.webSearch

    var body: some View {
        if provider == .openrouter, AgentKey.isConfigured(.openrouter) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // The cost is stated on the control that causes it, not in
                // fine print elsewhere — this is the one setting here that
                // can make a question fail to answer.
                DSToggleRow(title: AskSurface.enabled
                                ? Text("Only providers that don't keep your question")
                                : Text("Only providers that don't keep what you send"),
                            detail: Text("Some models won't be served that way — you'll be told which."),
                            isOn: $privateRouting)
                .onChange(of: privateRouting) { _, on in AgentOpenRouter.privateRouting = on }
                // Web search only ever runs inside an ask (prd §718).
                if AskSurface.enabled {
                    DSToggleRow(title: Text("Let it search the web"),
                                detail: Text("Only when your own things fall short. Charged per result."),
                                isOn: $webSearch)
                    .onChange(of: webSearch) { _, on in AgentOpenRouter.webSearch = on }
                }
            }
            .dsListRow()
        }
    }
}

/// "Let your key organize too" (2026-08-06, `AgentLibrarian`) — the one place
/// this app offers to spend somebody's money on its own schedule, so it is the
/// one place that asks first.
///
/// It renders ONLY where it would change something: a key is configured, and
/// this device has no on-device model to do the work for free. On an Apple
/// Intelligence device the local model already names screenshots and digests
/// threads at no cost, and offering to pay for the same work would be a
/// control that makes the app worse when used — which the honesty rule treats
/// the same as a dead one.
///
/// **IT LIVES ON A SEAT NOW, NOT IN SETTINGS (prd §871).** It used to have one
/// caller, the Settings key card, and that card is gone: every key is
/// connected on its own account page, so the switch that spends a key belongs
/// on the page for the key it would spend. `provider` is what makes that safe
/// — the switch is ONE app-wide flag, so it may be drawn on ONE page, and the
/// guard names which: the seat whose key is active. Drawn on every keyed page
/// it would read as a per-seat setting and three of them would contradict
/// each other.
struct AgentLibrarianRow: View {
    /// The seat drawing it. The row appears only when this is the provider
    /// `AgentKey.active` names — see the note above.
    let provider: AgentProvider
    @Environment(\.modelContext) private var modelContext
    @State private var enabled = AgentLibrarian.isEnabled
    @State private var working = false
    @State private var result: String?
    /// Never read — mutating it re-evaluates this view so the non-observable
    /// `AgentBudget` reads fresh after the cap changes (`AgentModelRow`'s own
    /// trick, same reason).
    @State private var tick = 0

    var body: some View {
        if AgentKey.active == provider, provider != .bankr, !AgentLibrarian.deviceCanDoIt {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSToggleRow(title: AskSurface.enabled
                                ? Text("Let your key organize too")
                                : Text("Let your key organize"),
                            detail: Text("Names screenshots and reads long chats so they can be found. No free on-device model here."),
                            isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    AgentLibrarian.isEnabled = on
                    result = nil
                }
                if enabled {
                    // The words the model writes are never displayed — a title
                    // it proposes must be built from words the screenshot
                    // itself shows, and a digest goes into a retrieval-only
                    // field. Said plainly, because "an AI renamed my things"
                    // is a fair thing to be wary of.
                    DSFootnote("Only words your things already contain — a chat summary is never shown.")
                    AgentBudgetControl(tick: $tick)
                    if working {
                        HStack(spacing: DS.Space.s2) {
                            DSSpinner()
                            Text("Working through the backlog…")
                                .dsText(.body17).foregroundStyle(DS.textTertiary)
                        }
                    } else {
                        DSDoorRow(icon: "wand.and.stars", label: "Catch up now") {
                            DSHaptic.tap()
                            catchUp()
                        }
                    }
                    if let result {
                        Text(result)
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .settleIn()
                    }
                    // The organizing model, offered only where organizing is
                    // actually turned on. It is the same picker the ask uses,
                    // pointed at a different task — one list read, one shape,
                    // and the two choices can never drift apart in how they
                    // resolve.
                    // `provider` IS `AgentKey.active` — the guard above says
                    // so — which is why this no longer re-reads it.
                    AgentModelRow(provider: provider, task: .librarian)
                }
            }
            .dsListRow()
        }
    }

    private func catchUp() {
        working = true
        result = nil
        Task { @MainActor in
            let caught = await AgentLibrarian.catchUp(context: modelContext)
            working = false
            result = caught.line
        }
    }
}

/// A ceiling on what organizing may cost in a month (2026-08-20,
/// `AgentBudget`).
///
/// **It renders for OpenRouter and nobody else, and that is the honest shape
/// rather than a gap.** A dollar cap can only be enforced where the provider
/// states dollars, and OpenRouter's free key read is the only place in this
/// catalog that does. Drawing this control for Anthropic would be a switch that
/// governs nothing — the dead control the honesty rule bans — so the other
/// providers get one plain sentence saying why there is no cap to offer,
/// which is a truer answer than a slider that quietly does nothing.
///
/// The amounts are a short menu rather than a text field: a keyboard here
/// invites "5" and "0.5" and "five", and a free-typed ceiling that fails to
/// parse is a ceiling somebody believes they set.
struct AgentBudgetControl: View {
    @Binding var tick: Int

    private static let choices: [Double] = [1, 3, 5, 10, 25]

    var body: some View {
        if AgentKey.active == AgentBudget.measurableProvider {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(spacing: DS.Space.s2) {
                    Text("Monthly limit")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    Menu {
                        Button {
                            AgentBudget.monthlyCap = nil
                            tick += 1
                        } label: { Text("No limit") }
                        ForEach(Self.choices, id: \.self) { amount in
                            Button {
                                DSHaptic.selection()
                                AgentBudget.monthlyCap = amount
                                tick += 1
                            } label: {
                                if AgentBudget.monthlyCap == amount {
                                    Label(AgentBudget.usd(amount), systemImage: "checkmark")
                                } else {
                                    Text(AgentBudget.usd(amount))
                                }
                            }
                        }
                    } label: {
                        // A CHOICE — the menu's current answer (prd §746).
                        Chip(text: AgentBudget.monthlyCap.map { AgentBudget.usd($0) + " a month" }
                                ?? String(localized: "No limit"),
                             glyph: "gauge.with.dots.needle.33percent",
                             selected: AgentBudget.monthlyCap != nil)
                    }
                }
                if let line = AgentBudget.line(for: AgentBudget.measurableProvider) {
                    Text(line)
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Said out loud because it is the one thing somebody would
                // otherwise assume wrongly, in the expensive direction: a cap
                // stops the app spending on its own, and never stops YOU.
                if AskSurface.enabled {
                    DSFootnote("Your own questions are never blocked.")
                }
                // Only where it is true. A ceiling governs spend, and a free
                // model spends nothing — so it keeps working past the cap, and
                // saying so is what stops that reading as the cap being broken.
                if AgentModelFacts.isFree(AgentBudget.measurableProvider, task: .librarian) {
                    DSFootnote("Your organizing model is free, so it keeps going.")
                }
            }
        } else if let provider = AgentKey.active {
            DSFootnote("\(provider.company) doesn't report spend, so there's no limit to set here.")
        }
    }
}

#if targetEnvironment(macCatalyst)
/// The local MCP listener's switch (2026-08-06, `MCPServer`) — Mac only,
/// because it is the only build that is a real desktop process sitting on the
/// same machine as the agent that wants to read the corpus.
///
/// It states its own unproven status rather than implying a working feature.
/// `MCPPairing.transportReady` is still false and no pairing UI has appeared;
/// this is the honest interim — a switch that says what it does, what it
/// can't promise, and exactly what to paste into a client.
struct MCPServerRow: View {
    @State private var enabled = MCPServer.isEnabled
    @State private var running = MCPServer.shared.running
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSToggleRow(title: Text("Let agents on this Mac read your things"),
                        detail: Text("127.0.0.1 only, never the network. Anything it offers to save waits for your approval."),
                        isOn: $enabled)
            .onChange(of: enabled) { _, on in
                MCPServer.isEnabled = on
                if on { MCPServer.shared.start() } else { MCPServer.shared.stop() }
                running = MCPServer.shared.running
                error = MCPServer.shared.lastError
            }
            if enabled {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: running ? "checkmark.circle.fill" : "circle.dotted")
                        .dsSymbolSwap(running)
                        .foregroundStyle(running ? DS.confirm : DS.textTertiary)
                        .accessibilityHidden(true)
                    Text(running ? MCPServer.endpoint : String(localized: "Not listening"))
                        .dsText(.body17).monospaced()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let error {
                    Text(error)
                        .dsText(.subhead12).foregroundStyle(DS.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if running {
                    // A verb, so a row (prd §746).
                    DSDoorRow(icon: copied ? "checkmark" : "key.fill",
                              label: copied ? "Key copied" : "Copy the key") {
                        DSHaptic.tap()
                        // Sensitive: this IS the credential. Short clipboard
                        // life, local only — `DSPasteboard`'s own split.
                        DSPasteboard.copySensitive(MCPPairing.token())
                        copied = true
                    }
                    // ONE sentence for the row (prd §748), where there were
                    // two. Measured 2026-08-08 (prd §340): the standard MCP
                    // inspector connects over HTTP and both lists and calls
                    // the tools — the sentence names what was checked rather
                    // than implying every client. Drawn only while listening:
                    // the claim is about a server that is running.
                    DSFootnote("Paste it as `Authorization: Bearer …` — checked with the standard MCP tools.")
                }
            }
        }
        .dsListRow()
        .onAppear {
            running = MCPServer.shared.running
            error = MCPServer.shared.lastError
        }
    }
}
#endif
