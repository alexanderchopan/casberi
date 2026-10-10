import SwiftData
import SwiftUI

/// A CHAIN AND A WALLET AS CHECKUPS, IN THE ROOM'S FRAME (prd §1187, the
/// design canvas "People, apps and checks, the Apple pass"): the title is the
/// name, the box is the reading — L2BEAT's stage as a three-step ladder lit
/// where the chain stands, Walletbeat's verdicts as a ring with the count
/// inside — then the tiles, then what falls short before what passes.
///
/// **The grouping amends §428 and §419, and nothing else.** The rows keep
/// their reviewer's own order inside each group, and every reading is the
/// reviewer's own words; the box counts what passes and names nothing the
/// reviewer did not say.

// MARK: - A chain (L2BEAT)

struct L2beatChainSheet<Tiles: View>: View {
    let chainID: String
    /// The sheet's tiles, handed the fourth: Watch while you don't.
    @ViewBuilder let tiles: (VerbDial.Keep?) -> Tiles

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome

    @State private var project: L2beatProject?
    @State private var live = false
    /// Starts true, so a Watch tile never flashes for a chain you watch.
    @State private var watching = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSRoomTitleRow(title: project?.name ?? chainID)
                .padding(.horizontal, DSRoomChassis.inset)
                .settleIn(delay: 0.04)
            box
                .dsRoomBox()
                .padding(.top, DS.Space.s3)
                .settleIn(delay: 0.06)
            tiles(keep)
                .padding(.top, DSRoomChassis.leadGap)
                .settleIn(delay: 0.08)
            if let project { list(project).settleIn(delay: 0.12) }
        }
        .task(id: chainID) { load() }
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(verbatim: "L2BEAT")
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
            CheckLadder(lit: project?.stage?.rung)
            Text(verbatim: project?.stage?.meaning ?? L2beatStage.notApplicable.meaning)
                .dsText(.heading20)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let project, !project.risks.isEmpty {
                let pass = project.risks.filter { $0.worstSentiment == .good }.count
                CheckTally(pass: pass, of: project.risks.count,
                           words: String(localized: "\(pass) of \(project.risks.count) checks pass"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private var spoken: String {
        guard let project else { return project?.name ?? chainID }
        let short = project.orderedRisks.filter { Self.fallsShort($0) }
            .map { "\($0.axis.label) \($0.value)" }
        var line = "\(project.name), \(project.stage?.label ?? L2beatStage.notApplicable.label). \(project.stage?.meaning ?? "")"
        if !short.isEmpty { line += " " + String(localized: "Falls short: \(short.joined(separator: ", "))") }
        return line
    }

    static func fallsShort(_ risk: L2beatRisk) -> Bool {
        risk.worstSentiment == .warning || risk.worstSentiment == .bad
    }

    @ViewBuilder
    private func list(_ project: L2beatProject) -> some View {
        let short = project.orderedRisks.filter(Self.fallsShort)
        let passes = project.orderedRisks.filter { $0.worstSentiment == .good }
        let unjudged = project.orderedRisks.filter {
            !Self.fallsShort($0) && $0.worstSentiment != .good
        }
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if !short.isEmpty {
                CheckSection(title: String(localized: "Falls short")) {
                    ForEach(short) { risk in
                        CheckReadingRow(name: risk.axis.label, reading: risk.value,
                                        ink: risk.worstSentiment == .bad ? DS.destructiveInk : DS.attentionInk,
                                        explanation: risk.explanation)
                    }
                }
            }
            if !passes.isEmpty {
                CheckSection(title: String(localized: "Passes")) {
                    ForEach(passes) { risk in
                        CheckReadingRow(name: risk.axis.label, reading: risk.value,
                                        ink: DS.textSecondary, explanation: nil)
                    }
                }
            }
            if !unjudged.isEmpty {
                CheckSection(title: String(localized: "Not judged")) {
                    ForEach(unjudged) { risk in
                        CheckReadingRow(name: risk.axis.label, reading: risk.value,
                                        ink: DS.textSecondary, explanation: nil)
                    }
                }
            }
            Text(verbatim: freshness)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.top, DS.Space.s6)
    }

    /// Which copy of L2BEAT's reading this is (§83: a bundled reading and a
    /// fresh one look the same).
    private var freshness: String {
        let attribution = L2beatCopy.attribution + "."
        return live
            ? "\(attribution) \(String(localized: "Read on this device."))"
            : "\(attribution) \(String(localized: "Bundled with the app as of \(L2beatDirectory.generated)."))"
    }

    private var keep: VerbDial.Keep? {
        guard !watching, let project else { return nil }
        return VerbDial.Keep(label: String(localized: "Follow"), glyph: ScopeTileGlyph.watch) {
            DSHaptic.tap()
            L2beatWatch.add(project, context: modelContext)
            L2beatWatch.registerBridge(store: store, context: modelContext)
            withAnimation(DS.Motion.standard) { watching = true }
            chrome.flash(String(localized: "Following \(project.name)"), tone: .success)
        }
    }

    private func load() {
        watching = L2beatWatch.watchedIDs(context: modelContext).contains(chainID)
        if let stored = L2beatState.project(chainID) {
            project = stored
            live = true
        } else {
            project = L2beatDirectory.project(chainID)
        }
    }
}

// MARK: - A wallet (Walletbeat)

struct WalletbeatWalletSheet<Tiles: View>: View {
    let walletID: String
    @ViewBuilder let tiles: (VerbDial.Keep?) -> Tiles

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome

    @State private var card: WalletbeatCard?
    @State private var watching = true

    private var entry: WalletbeatEntry? {
        WalletbeatDirectory.wallets.first { $0.id == walletID }
    }
    private var name: String { card?.name ?? entry?.name ?? walletID }
    private var counts: WalletbeatCounts { card?.overall ?? entry?.overall ?? .zero }

    /// Fails first, then partly, each in Walletbeat's own order (§419).
    private var shortfalls: [WalletbeatAttribute] {
        guard let card else { return [] }
        return card.attributes.filter { $0.verdict == .fail }
            + card.attributes.filter { $0.verdict == .partial }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSRoomTitleRow(title: name)
                .padding(.horizontal, DSRoomChassis.inset)
                .settleIn(delay: 0.04)
            box
                .dsRoomBox()
                .padding(.top, DS.Space.s3)
                .settleIn(delay: 0.06)
            tiles(keep)
                .padding(.top, DSRoomChassis.leadGap)
                .settleIn(delay: 0.08)
            if let card { list(card).settleIn(delay: 0.12) }
        }
        .task(id: walletID) { await load() }
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(verbatim: "Walletbeat")
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
            HStack(spacing: DS.Space.s4) {
                CheckRing(counts: counts)
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    ForEach(shortfalls.prefix(2)) { attribute in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                            CheckVerdictGlyph(verdict: attribute.verdict)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: attribute.name)
                                    .dsText(.body17)
                                    .foregroundStyle(DS.textPrimary)
                                    .lineLimit(2)
                                Text(verbatim: WalletbeatCopy.label(attribute.verdict))
                                    .dsText(.subhead12)
                                    .foregroundStyle(DS.textSecondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
            // What the ring cannot say on its own: how much is rated at all.
            if counts.judged < counts.applicable {
                Text(verbatim: WalletbeatCopy.coverage(counts))
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private var spoken: String {
        var line = "\(name), " + String(localized: "\(counts.pass) of \(counts.judged) checks pass")
            + ". " + WalletbeatCopy.barReadout(counts)
        let named = shortfalls.prefix(2).map { "\($0.name) \(WalletbeatCopy.label($0.verdict))" }
        if !named.isEmpty { line += ". " + named.joined(separator: ", ") }
        return line
    }

    @ViewBuilder
    private func list(_ card: WalletbeatCard) -> some View {
        let passes = card.attributes.filter { $0.verdict == .pass }
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if !shortfalls.isEmpty {
                CheckSection(title: String(localized: "Falls short")) {
                    ForEach(shortfalls) { attribute in
                        CheckReadingRow(name: attribute.name,
                                        reading: WalletbeatCopy.label(attribute.verdict),
                                        ink: attribute.verdict == .fail ? DS.destructiveInk : DS.attentionInk,
                                        explanation: attribute.explanation)
                    }
                }
            }
            if !passes.isEmpty {
                CheckSection(title: String(localized: "Passes")) {
                    ForEach(passes) { attribute in
                        HStack(spacing: DS.Space.s2) {
                            CheckVerdictGlyph(verdict: .pass)
                            Text(verbatim: attribute.name)
                                .dsText(.body17)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 36)
                    }
                }
            }
            Text(verbatim: WalletbeatCopy.attribution + ".")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.top, DS.Space.s6)
    }

    private var keep: VerbDial.Keep? {
        guard !watching, let entry else { return nil }
        return VerbDial.Keep(label: String(localized: "Follow"), glyph: ScopeTileGlyph.watch) {
            DSHaptic.tap()
            WalletbeatWatch.add(entry, context: modelContext)
            WalletbeatWatch.registerBridge(store: store, context: modelContext)
            withAnimation(DS.Motion.standard) { watching = true }
            chrome.flash(String(localized: "Following \(entry.name)"), tone: .success)
        }
    }

    private func load() async {
        watching = WalletbeatWatch.watchedIDs(context: modelContext).contains(walletID)
        if let stored = WalletbeatState.card(walletID) { card = stored }
        if let fresh = await WalletbeatFetch.card(walletID: walletID) {
            card = fresh
            WalletbeatState.set(fresh)
        }
    }
}

// MARK: - The parts the two share

/// Three rungs, the chain's lit (the way Health shows a level). A chain
/// L2BEAT does not stage lights none.
struct CheckLadder: View {
    let lit: Int?

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(0..<3, id: \.self) { rung in
                Text(verbatim: L2beatStage.allCases[rung].label)
                    .dsText(.label12)
                    .fontWeight(.semibold)
                    .foregroundStyle(rung == lit ? DS.inkGround : DS.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(rung == lit ? DS.tint : DS.fillFaint))
            }
        }
        .accessibilityHidden(true)
    }
}

/// "4 of 5 checks pass", with a glyph that says the same in shape.
struct CheckTally: View {
    let pass: Int
    let of: Int
    let words: String

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: pass == of ? "checkmark.circle" : "exclamationmark.triangle")
                .dsGlyph(.caption, weight: .semibold)
                .foregroundStyle(pass == of ? DS.confirm : DS.attention)
            Text(verbatim: words)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
        }
    }
}

/// Walletbeat's judged verdicts as one ring — passes, partly, fails — with
/// the count inside. Exempt and unrated are not in it.
struct CheckRing: View {
    let counts: WalletbeatCounts
    private static let size: CGFloat = 120
    private static let line: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The ring draws round once on open (§299); Reduce Motion shows it whole.
    @State private var drawn: CGFloat = 0

    var body: some View {
        // Over every check that applies, so what Walletbeat has not rated
        // yet stands in the ring as the faint track, never as a pass.
        let whole = CGFloat(max(counts.applicable, 1))
        let pass = CGFloat(counts.pass) / whole
        let partial = CGFloat(counts.partial) / whole
        let fail = CGFloat(counts.fail) / whole
        ZStack {
            Circle().stroke(DS.fillFaint, lineWidth: Self.line)
            arc(from: 0, to: pass, DS.confirm)
            arc(from: pass, to: pass + partial, DS.attention)
            arc(from: pass + partial, to: pass + partial + fail, DS.destructive)
            VStack(spacing: 0) {
                Text(verbatim: counts.judged == 0 ? WalletbeatCopy.label(.unrated)
                     : String(localized: "\(counts.pass) of \(counts.judged)"))
                    .dsText(.heading24)
                    .monospacedDigit()
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(counts.judged == 0 ? "" : String(localized: "pass"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, Self.line + 4)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
        .onAppear {
            guard drawn == 0 else { return }
            if reduceMotion { drawn = 1 } else {
                withAnimation(DS.Motion.standard.delay(0.15)) { drawn = 1 }
            }
        }
    }

    @ViewBuilder
    private func arc(from start: CGFloat, to end: CGFloat, _ color: Color) -> some View {
        if end > start {
            Circle()
                .trim(from: start * drawn, to: end * drawn)
                .stroke(color, style: StrokeStyle(lineWidth: Self.line, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A verdict in shape as well as hue: a check, a half, a cross.
struct CheckVerdictGlyph: View {
    let verdict: WalletbeatVerdict

    var body: some View {
        Image(systemName: Self.symbol(verdict))
            .dsGlyph(.caption, weight: .semibold)
            .foregroundStyle(Self.hue(verdict))
            .accessibilityHidden(true)
    }

    static func symbol(_ verdict: WalletbeatVerdict) -> String {
        switch verdict {
        case .pass: return "checkmark.circle"
        case .partial: return "circle.lefthalf.filled"
        case .fail: return "xmark.circle"
        case .unrated, .exempt: return "circle.dashed"
        }
    }

    static func hue(_ verdict: WalletbeatVerdict) -> Color {
        switch verdict {
        case .pass: return DS.confirm
        case .partial: return DS.attention
        case .fail: return DS.destructive
        case .unrated, .exempt: return DS.textTertiary
        }
    }
}

/// A list's pink name over its rows, as every list under a sheet's tiles.
struct CheckSection<Rows: View>: View {
    let title: String
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: title)
                .dsText(.heading20)
                .foregroundStyle(DS.brandInk)
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One check: its name, the reviewer's reading trailing in its ink, and the
/// reviewer's sentence under it when it falls short.
struct CheckReadingRow: View {
    let name: String
    let reading: String
    let ink: Color
    let explanation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                Text(verbatim: name)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: reading)
                    .dsText(.subhead12)
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            if let explanation, !explanation.isEmpty {
                Text(verbatim: explanation)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DS.Space.s1)
        .accessibilityElement(children: .combine)
    }
}
