import SwiftUI

/// What is left of the agent's instrument panel (prd §334/§336/§337).
///
/// The bento grid itself was deleted with the panel (prd §386p) and sat here
/// with no call site until prd §717's sweep removed it, along with its corner
/// badge and its tile entrance. The chip peek went in §836, and every figure
/// only it drew went with it. What survives is what the answer still draws:
/// the room hue below and the dial (`GenDial`, through `FigureView`). The
/// semantic map (`ScatterFigure`) went with the Today brief (2026-10-01). An
/// enum, not a view — nothing here is a screen any more.
enum AgentPanelGrid {
    /// The room's hue, made safe to FILL with against a near-black well.
    ///
    /// `signalColor` solves the inverse problem — a near-black brand mark
    /// needs a lighter glyph — and it hands back a near-WHITE colour for the
    /// brands whose mark is white (ChatGPT, Claude, X). White is fine on an
    /// 18pt glyph and glaring as the fill of a whole figure: ChatGPT's old pulse
    /// grid rendered as a wall of white cells on the sim, brighter than every real
    /// signal on the screen. Above the luminance bar the tint stands in, which
    /// keeps the figure readable and costs only that one room its hue.
    static func panelHue(for source: String) -> Color {
        let brand = BridgeGlyph.signalColor(for: source)
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(brand).getRed(&r, green: &g, blue: &b, alpha: &a) {
            // Rec. 601 luma — the same weighting the contrast pass used.
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            if luma > 0.78 { return DS.tint }
        }
        #endif
        return brand
    }
}

// MARK: - The figures

/// Draws one `AgentPanel.Figure` — the dial is the one left (prd §836).
///
/// Kept as the dial's ONE renderer so its floor, hues and entrance live in one
/// place; `GenDial` delegates here rather than drawing a second copy.
/// Appear-triggered, collapsing to the settled state under Reduce Motion, and
/// it never loops: `repeatForever` is what the motion audit flagged on
/// `GenTagMap`, so the figure settles and goes still.
struct FigureView: View {
    let figure: AgentPanel.Figure
    let reduceMotion: Bool

    /// The figure's ONE clock, 0 → 1 over the whole entrance (prd §342).
    ///
    /// A monotonic Double driven once from `onAppear` — deliberately NOT
    /// `PhaseAnimator`/`KeyframeAnimator`, which re-run on state-identity
    /// changes and both replay on view recycling inside `List`/`LazyVGrid`.
    /// That replay is what got the row sparkline's draw-on reverted (see
    /// `Sparkline`'s own doc); a value that only ever counts up cannot replay.
    @State private var paint: Double = 0

    /// Maps the master clock onto a sub-interval, clamped 0…1.
    ///
    /// The phase grammar — STRUCTURE (0…0.25), DATA (0.15…0.80), MEANING
    /// (0.70…1.0) — because that is the order a hand draws a chart: the axis,
    /// then the data, then the words.
    private func phase(_ from: Double, _ to: Double) -> Double {
        min(1, max(0, (paint - from) / max(0.001, to - from)))
    }

    var body: some View {
        Group {
            switch figure {
            case .dial(let marks):
                DialFigure(marks: marks, ring: phase(0, 0.25),
                           sweep: phase(0.2, 0.85), reduceMotion: reduceMotion)
            }
        }
        .onAppear {
            // `paint` is monotonic because a replayed entrance is the one
            // failure this design cannot show.
            guard paint == 0 else { return }
            guard !reduceMotion else { paint = 1; return }
            withAnimation(.easeOut(duration: 1.1)) { paint = 1 }
        }
    }
}

// MARK: - The day dial

/// A week of things on a 24-hour clock (prd §337): radially symmetric, no
/// labels to clip, hue carrying identity, and the shape itself is the reading.
private struct DialFigure: View {
    let marks: [AgentPanel.DialMark]
    /// STRUCTURE — the hour anchors fading in before the marks.
    let ring: Double
    /// DATA — the radar sweep gating each mark by its own hour.
    let sweep: Double
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cx = geo.size.width / 2, cy = geo.size.height / 2
            let rMax = side / 2 - 14
            let rMin = rMax * 0.34
            ZStack {
                // NO RING (§8: nothing draws a line). The hour anchors and
                // the marks themselves are the clock face.
                // Six-hour anchors only — 24 ticks is a dotted ring that
                // reads as texture, not as a clock.
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    let a = Self.angle(Double(h))
                    Text(Self.hourLabel(h))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                        .opacity(ring)
                        .position(x: cx + cos(a) * (rMax + 10),
                                  y: cy + sin(a) * (rMax + 10))
                }
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                    let a = Self.angle(mark.hour)
                    let r = rMin + (rMax - rMin) * pow(mark.recency, 0.8)
                    Circle()
                        .fill(AgentPanelGrid.panelHue(for: mark.source))
                        .frame(width: 3.4, height: 3.4)
                        // The radar sweep: a mark appears once the hand has
                        // passed its hour, so the figure fills clockwise — and
                        // it FADES rather than pops, which is the difference
                        // between a sweep and a stutter.
                        .opacity(sweep >= mark.hour / 24 ? 0.42 + mark.recency * 0.5 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15),
                                   value: sweep >= mark.hour / 24)
                        .position(x: cx + cos(a) * r, y: cy + sin(a) * r)
                }
            }
        }
    }

    /// Midnight at the top, clockwise — a clock face, which is the mental model
    /// the figure is borrowing.
    private static func angle(_ hour: Double) -> Double {
        (hour / 24) * 2 * .pi - .pi / 2
    }

    private static func hourLabel(_ h: Int) -> String {
        switch h {
        case 0:  return "12a"
        case 6:  return "6a"
        case 12: return "12p"
        default: return "6p"
        }
    }
}

