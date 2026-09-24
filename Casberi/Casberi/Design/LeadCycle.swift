import SwiftUI

/// ONE CYCLE, NOT A SWITCH (prd §901, 2026-09-23 — user: "i like the idea if
/// it could change and change back like one cycle not a switch" … "it should
/// always be the category not a state b/c then we'd be making up new icons or
/// glyphs for a user to learn").
///
/// A feed row's 26pt lead is the source's mark. When the row LANDS while you
/// are looking, or its fact MOVES in place (a package delivered, a Safe
/// transaction executed), the mark turns over to the glyph of its dock
/// category — the one the category chip already wears, read from
/// `CategoryFold.glyph(for:)` and nowhere else — holds, and turns back. It
/// ends where it began, so the source is never lost; the WORDS carry what
/// happened, the glyph only says "this one moved", in a word the dock already
/// taught. No state glyphs (a tick, a clock): those would be a second
/// vocabulary to learn, and the category is a fact the row already has.
///
/// Two moments, ONE rule, one clock: out at `out`, back at `back`, once.
///
/// - **Landing while looking** — `capturedAt` is later than the wave the page
///   is standing on (`FeedWaveAt`: stamped at the page's landing and every
///   pull, `FeedScreen.shapeWaveAt`) AND within `freshWindow` of now. The
///   first bound keeps the corpus you open the app to at rest (the cascade
///   carries it, §661); the second keeps a row you SCROLL to at rest even if
///   it landed after the wave — never on a row met by scrolling.
/// - **A fact moved** — `fact` (the title) changed while the row was mounted.
///   Mounted is the bound: a `List` only holds the visible window, so a heal
///   that rewrites 200 rows cycles the few on screen. The wallet ledger's rows
///   opt out (`cyclesOnChange: false`): a counterparty rename there is §171's
///   ripple, already a motion, and this would be the second on one moment.
///
/// A source with no category has no second glyph and does not cycle. Reduce
/// Motion: the words change, the disc stays. The glyph is resolved when the
/// cycle FIRES, never per body pass (§626: nothing per row per render).
///
/// The turn is a Y-axis flip with the faces' visibility derived from the
/// animated angle (`Face`, an `Animatable` modifier), so one transaction turns
/// it out and one turns it back — not four with a swap at the edge. The disc
/// on the back is `DSGlyphLead`, the row lead the Readings rows already wear
/// (§763), so the flipped face is a shape the feed already draws.
struct LeadCycle: ViewModifier {
    /// The thing's source; the category glyph is resolved from it on fire.
    let source: String
    /// When the thing landed, against the page's wave.
    let capturedAt: Date
    /// The fact whose in-place change is the row's "moved" — the title.
    let fact: String
    /// The row's cascade index, for the stagger that follows `RowEntrance`'s.
    var index: Int = 0
    /// Whether a changed fact cycles. False on the wallet ledger's rows, whose
    /// retitle already ripples (§171).
    var cyclesOnChange: Bool = true

    /// The clock, shared by both moments. `out` sits after the row's own
    /// entrance spring (`DS.Motion.duration`), so the cycle FOLLOWS the
    /// cascade rather than competing with it (§661: one animation per moment).
    static let out: TimeInterval = 0.3
    static let back: TimeInterval = 1.2
    /// A landing is one that appeared within this of being captured.
    static let freshWindow: TimeInterval = 20
    /// Per-row stagger, `RowEntrance`'s own step, capped like its cascade.
    static let stagger: TimeInterval = 0.045

    @Environment(\.feedWaveAt) private var waveAt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Degrees turned: 0 at rest (the mark), 180 held (the glyph), 360 landed
    /// and reset to 0 with no animation — visually identical, so the next
    /// cycle starts from the same place.
    @State private var angle: Double = 0
    @State private var glyph: String?
    @State private var cycling = false

    func body(content: Content) -> some View {
        ZStack {
            content
                .modifier(Face(angle: angle, back: false))
            if let glyph {
                DSGlyphLead(glyph: glyph)
                    .accessibilityHidden(true)
                    .modifier(Face(angle: angle, back: true))
            }
        }
        .onAppear { if landedWhileLooking { fire() } }
        .onChange(of: fact) { if cyclesOnChange { fire() } }
    }

    /// Captured after the wave the page stands on, and just now.
    private var landedWhileLooking: Bool {
        guard let waveAt else { return false }
        let captured = capturedAt.timeIntervalSinceReferenceDate
        let now = Date.timeIntervalSinceReferenceDate
        return captured > waveAt && now - captured < Self.freshWindow
    }

    private func fire() {
        guard !reduceMotion, !cycling else { return }
        // The dock's own table, and nothing else: a category added there is a
        // glyph here the same day, and no glyph exists here that a chip does
        // not wear (`lead-cycle-audit.py`).
        guard let category = BridgeCatalog.category(forSource: source) else { return }
        glyph = CategoryFold.glyph(for: category)
        cycling = true
        let delay = Double(min(index, 12)) * Self.stagger
        withAnimation(DS.Motion.standard.delay(delay + Self.out)) { angle = 180 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((delay + Self.back) * 1000)))
            withAnimation(DS.Motion.standard) { angle = 360 }
            try? await Task.sleep(for: .milliseconds(Int(DS.Motion.duration * 1000) + 150))
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                angle = 0
                cycling = false
            }
        }
    }

    /// One face of the turning disc. The angle is the animated value, so each
    /// frame decides which face shows from where the turn actually is, and a
    /// single transaction carries the swap at the edge.
    private struct Face: ViewModifier, Animatable {
        var angle: Double
        let back: Bool
        var animatableData: Double {
            get { angle }
            set { angle = newValue }
        }

        func body(content: Content) -> some View {
            let turned = angle.truncatingRemainder(dividingBy: 360)
            let frontShows = turned < 90 || turned > 270
            content
                .rotation3DEffect(.degrees(angle + (back ? 180 : 0)),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .opacity(back ? (frontShows ? 0 : 1) : (frontShows ? 1 : 0))
        }
    }
}

/// The wave the feed page stands on (`FeedScreen.shapeWaveAt`, seconds since
/// the reference date), set once on the room's list so every row lead can tell
/// a thing that landed after it from the corpus that was there. Nil outside a
/// feed page — a lead there never cycles on appear.
private struct FeedWaveAtKey: EnvironmentKey {
    static let defaultValue: TimeInterval? = nil
}

extension EnvironmentValues {
    var feedWaveAt: TimeInterval? {
        get { self[FeedWaveAtKey.self] }
        set { self[FeedWaveAtKey.self] = newValue }
    }
}

extension View {
    /// The one cycle on a row lead — see `LeadCycle`.
    func leadCycle(source: String, capturedAt: Date, fact: String,
                   index: Int = 0, cyclesOnChange: Bool = true) -> some View {
        modifier(LeadCycle(source: source, capturedAt: capturedAt, fact: fact,
                           index: index, cyclesOnChange: cyclesOnChange))
    }
}
