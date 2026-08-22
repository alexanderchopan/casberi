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
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    // The id, not a prettied label: the id is what actually
                    // goes on the wire, and it is what a provider's own
                    // pricing page is keyed by.
                    Text(provider.model(for: task))
                        .dsText(.callout15).monospaced()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if AgentModelStore.chosen(provider, task: task) == nil {
                    Text(task == .librarian
                         ? String(localized: "Same model as your questions. Naming a screenshot is small work — a cheaper, faster model usually does it just as well for a fraction of the cost.")
                         : String(localized: "The default for \(provider.agent). Providers retire model names — if answers start failing, pick a current one."))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loading {
                    HStack(spacing: DS.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Asking \(provider.company) what it offers…")
                            .dsText(.callout15).foregroundStyle(DS.textTertiary)
                    }
                } else if readable == false {
                    Text("Couldn't read \(provider.company)'s model list — keeping \(provider.defaultModel).")
                        .dsText(.subhead13).foregroundStyle(DS.attention)
                        .fixedSize(horizontal: false, vertical: true)
                } else if models.isEmpty {
                    Button {
                        DSHaptic.tap()
                        load()
                    } label: {
                        Chip(text: "Choose a model", style: .neutral, glyph: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                } else {
                    // A Menu rather than a list of rows: OpenRouter answers
                    // with several hundred, and any layout that draws them all
                    // turns a settings card into a directory.
                    Menu {
                        Button {
                            AgentModelStore.set(nil, for: provider, task: task)
                            tick += 1
                        } label: {
                            Text(task == .librarian
                                 ? String(localized: "Same as questions")
                                 : String(localized: "Default (\(provider.defaultModel))"))
                        }
                        ForEach(models) { model in
                            Button {
                                DSHaptic.selection()
                                AgentModelStore.set(model.id, for: provider, task: task)
                                tick += 1
                            } label: {
                                if model.id == provider.model(for: task) {
                                    Label(model.label, systemImage: "checkmark")
                                } else {
                                    Text(model.label)
                                }
                            }
                        }
                    } label: {
                        Chip(text: "\(models.count) available", style: .tint,
                             glyph: "slider.horizontal.3")
                    }
                }
            }
            // `tick` is never read — mutating it is enough to invalidate the
            // view, which re-evaluates the static, non-observable
            // `AgentModelStore.chosen` fresh (`AgentActiveStatusRow`'s trick,
            // same reason).
            .dsListCardRow()
        }
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
                    Text(requestLine(entry))
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                }
                if let tokens = entry.tokenLine {
                    Text(tokens)
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    // Only when there is a hit to report. A "0 served from
                    // cache" would read as a thing that went wrong, when for a
                    // short exchange it just means the prompt never reached the
                    // model's minimum cacheable length.
                    if let cache = entry.cacheLine {
                        Text(cache)
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    // The honest blank. A "0 in · 0 out" here would claim the
                    // requests were free.
                    Text("\(provider.company) doesn't report token counts to us.")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let usd = entry.reportedUSD {
                    Text("\(provider.company) reports \(String(format: "$%.2f", usd)) used on this key.")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // `DS.device`, not "this iPhone" — this line is a claim about
                // where the counting happens, and on Mac the literal was
                // false. The sibling line 44 rows down already said
                // "there's no on-device model here" correctly, so one file
                // held both the fixed and the unfixed spelling.
                Text("Counted on \(DS.device). Your bill is \(provider.company)'s — see \(provider.console).")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .dsListCardRow()
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
struct AgentLibrarianRow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var enabled = AgentLibrarian.isEnabled
    @State private var working = false
    @State private var result: String?
    /// Never read — mutating it re-evaluates this view so the non-observable
    /// `AgentBudget` reads fresh after the cap changes (`AgentModelRow`'s own
    /// trick, same reason).
    @State private var tick = 0

    var body: some View {
        if AgentKey.isConfigured, AgentKey.active != .bankr, !AgentLibrarian.deviceCanDoIt {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let your key organize too")
                            .dsText(.callout15).foregroundStyle(DS.textPrimary)
                        Text("Names your screenshots from what they say, and reads long imported chats so they can be found. There's no on-device model here to do it free.")
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
                    Text("Only words your own things already contain. A chat summary is used to find it again and is never shown.")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    AgentBudgetControl(tick: $tick)
                    if working {
                        HStack(spacing: DS.Space.s2) {
                            ProgressView().controlSize(.small)
                            Text("Working through the backlog…")
                                .dsText(.callout15).foregroundStyle(DS.textTertiary)
                        }
                    } else {
                        Button {
                            DSHaptic.tap()
                            catchUp()
                        } label: {
                            Chip(text: "Catch up now", style: .tint, glyph: "wand.and.stars")
                        }
                        .buttonStyle(.plain)
                    }
                    if let result {
                        Text(result)
                            .dsText(.callout15).foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .settleIn()
                    }
                    // The organizing model, offered only where organizing is
                    // actually turned on. It is the same picker the ask uses,
                    // pointed at a different task — one list read, one shape,
                    // and the two choices can never drift apart in how they
                    // resolve.
                    if let provider = AgentKey.active {
                        AgentModelRow(provider: provider, task: .librarian)
                    }
                }
            }
            .dsListCardRow()
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
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
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
                        Chip(text: AgentBudget.monthlyCap.map { AgentBudget.usd($0) + " a month" }
                                ?? String(localized: "No limit"),
                             style: AgentBudget.monthlyCap == nil ? .neutral : .tint,
                             glyph: "gauge.with.dots.needle.33percent")
                    }
                }
                if let line = AgentBudget.line(for: AgentBudget.measurableProvider) {
                    Text(line)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Said out loud because it is the one thing somebody would
                // otherwise assume wrongly, in the expensive direction: a cap
                // stops the app spending on its own, and never stops YOU.
                Text("Counted from what OpenRouter reports this key has used. Your own questions are never blocked.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let provider = AgentKey.active {
            Text("\(provider.company) doesn't report what a key has spent, so there's no limit to set here — the counts above are what we can measure.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
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
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let agents on this Mac read your things")
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    Text("A door on this computer only — 127.0.0.1, never the network. An agent needs the key below, and anything it offers to save waits for your approval.")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onChange(of: enabled) { _, on in
                MCPServer.isEnabled = on
                if on { MCPServer.shared.start() } else { MCPServer.shared.stop() }
                running = MCPServer.shared.running
                error = MCPServer.shared.lastError
            }
            if enabled {
                // Measured 2026-08-08 (prd §340): the standard MCP inspector
                // connects to this over HTTP and both lists and calls the
                // tools. What is NOT claimed is any particular product — the
                // sentence says which client was checked rather than implying
                // all of them, and keeps the invitation to report a failure,
                // because that is still how a specific one gets found.
                Text("Checked with the standard MCP tools on this Mac. If your client can't connect, tell us.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: running ? "checkmark.circle.fill" : "circle.dotted")
                        .dsSymbolSwap(running)
                        .foregroundStyle(running ? DS.confirm : DS.textTertiary)
                        .accessibilityHidden(true)
                    Text(running ? MCPServer.endpoint : String(localized: "Not listening"))
                        .dsText(.callout15).monospaced()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let error {
                    Text(error)
                        .dsText(.subhead13).foregroundStyle(DS.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if running {
                    Button {
                        DSHaptic.tap()
                        // Sensitive: this IS the credential. Short clipboard
                        // life, local only — `DSPasteboard`'s own split.
                        DSPasteboard.copySensitive(MCPPairing.token())
                        copied = true
                    } label: {
                        Chip(text: copied ? "Key copied" : "Copy the key",
                             style: .tint, glyph: "key.fill")
                    }
                    .buttonStyle(.plain)
                    Text("Paste it as `Authorization: Bearer …`. Deleting access in Privacy mints a new one and disconnects anything paired.")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .dsListCardRow()
        .onAppear {
            running = MCPServer.shared.running
            error = MCPServer.shared.lastError
        }
    }
}
#endif
