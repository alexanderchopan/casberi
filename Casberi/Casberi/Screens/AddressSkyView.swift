import SwiftUI

/// THE SKY, drawn (prd §435, 2026-08-21). The layout — every position, every
/// link, every constellation — is `AddressSky`'s and is computed before this
/// view exists; nothing here decides where anything goes.
///
/// ## What it replaces
///
/// Three sections of the wallet manager: the roster shelf, the connections
/// card and the group headers' face decks. They were three drawings of one
/// graph, and the screen read as a settings page because of it.
///
/// ## What it keeps, exactly
///
/// §295's factual-only ruling, which governs everything drawn here: **every
/// link is the same width and the same colour** — a connection exists or it
/// doesn't — and nothing is ranked. A watched wallet's body is bigger because
/// you chose it, never because of what it holds; **no figure appears anywhere
/// in this view** (user ruling 2026-08-21: the manager shows no balances, the
/// feed's crown owns that reading).
///
/// ## The motion, and its one rule
///
/// Links draw themselves (`trim`, the §297 grammar — "every visualization
/// draws itself"), bodies land in a stagger, and a connection that is NEW
/// since the last look draws LAST and dashed, so the map is seen growing
/// rather than arriving already grown. Under Reduce Motion everything is
/// final on the first frame — including the new links, which stay dashed,
/// because the dash is information rather than decoration.
struct AddressSkyView: View {
    let sky: AddressSky.Sky
    /// A body was tapped — a wallet or a connected address. The open slot
    /// reports `nil`, since it stands for no address at all.
    var onPick: (AddressSky.Body) -> Void
    var onPickSlot: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var newDrawn: CGFloat = 0

    /// The caption under a body needs room below it, and a body at the top of
    /// the ring needs room above. Insetting the DRAWING rather than padding the
    /// container keeps the normalized 0…1 space honest: `AddressSky` places a
    /// body at 0.17 and it must land at 0.17 of the field it was laid out for.
    private let inset: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let field = CGSize(width: geo.size.width - inset * 2,
                               height: geo.size.height - inset * 2)
            ZStack {
                // Constellation labels sit UNDER the bodies: a group name is
                // the region's word, and a face landing on top of it is the
                // correct occlusion — the members are the subject, the label
                // is the sky behind them.
                ForEach(sky.constellations) { constellation in
                    constellationLabel(constellation, in: field)
                }
                linkLayer(settled: false, in: field)
                linkLayer(settled: true, in: field)
                ForEach(Array(sky.bodies.enumerated()), id: \.element.id) { index, body in
                    bodyView(body, index: index)
                        .position(point(body.at, in: field))
                }
            }
            .frame(width: field.width, height: field.height)
            .padding(inset)
            .onAppear(perform: start)
        }
    }

    // MARK: - Links

    /// One `Path` per link, trimmed on appear.
    ///
    /// Drawn in TWO passes rather than one loop: settled links share a single
    /// trim and new ones share a later, slower trim, so the sky finishes
    /// assembling itself and only then reaches out to whatever arrived since
    /// you last looked. A per-link stagger would say the same thing about every
    /// link, which is exactly what this does not want to say.
    @ViewBuilder
    private func linkLayer(settled: Bool, in field: CGSize) -> some View {
        let links = sky.links.filter { $0.isNew != settled }
        if !links.isEmpty {
            Path { path in
                for link in links {
                    let from = point(link.from, in: field)
                    let to = point(link.to, in: field)
                    path.move(to: from)
                    // A gentle bow toward the centre, so two links between the
                    // same pair of neighbours stay distinguishable and the sky
                    // reads as orbits rather than as a wire diagram. The bow is
                    // geometry, not weight: every link bows the same amount.
                    path.addQuadCurve(to: to, control: bow(from: from, to: to, in: field))
                }
            }
            .trim(from: 0, to: settled ? drawn : newDrawn)
            .stroke(settled ? DS.textTertiary.opacity(0.32) : DS.tint.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                       dash: settled ? [] : [3, 4]))
            .allowsHitTesting(false)
        }
    }

    /// Pulls the control point a little toward the middle of the drawing.
    private func bow(from: CGPoint, to: CGPoint, in field: CGSize) -> CGPoint {
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let centre = CGPoint(x: field.width / 2, y: field.height / 2)
        return CGPoint(x: mid.x + (centre.x - mid.x) * 0.18,
                       y: mid.y + (centre.y - mid.y) * 0.18)
    }

    // MARK: - Bodies

    @ViewBuilder
    private func bodyView(_ body: AddressSky.Body, index: Int) -> some View {
        // The ramp rung, spelled INLINE rather than behind a helper: the face
        // ramp audit resolves a named size only when the constant's own
        // declaration reads a `DS.Face` tier, and a helper hides that. Which is
        // the right call — `WalletFace(size: someFunction())` is exactly how a
        // raw number gets back onto a face.
        //
        // A watched body draws at `shelf` because it IS the tap target and is
        // the subject of the drawing; a connected body and the invitation both
        // draw at `list`, one rung down, which is the second thing after
        // position that says "yours" apart from "somebody you deal with".
        let size: CGFloat = body.kind == .watched ? DS.Face.shelf : DS.Face.list
        VStack(spacing: 5) {
            switch body.kind {
            case .openSlot:
                Circle()
                    .strokeBorder(DS.textTertiary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "plus")
                            .dsGlyph(14)
                            .foregroundStyle(DS.textTertiary)
                    }
            case .watched, .connected:
                WalletFace(address: body.address, size: size, circular: true)
                    // Its own hue, held close — the identicon already carries
                    // the colour, so this is the same light spilling off it.
                    // A CONNECTED body doesn't glow: the glow is what says
                    // "you watch this one", and it is the only size-independent
                    // difference between the two kinds.
                    .shadow(color: body.kind == .watched
                            ? WalletFace.tint(for: body.address).opacity(0.42) : .clear,
                            radius: body.kind == .watched ? 16 : 0)
            }
            captionView(body)
        }
        .frame(width: max(size, 78))
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.selection()
            if body.kind == .openSlot { onPickSlot() } else { onPick(body) }
        }
        .dsTapCard()
        .accessibilityLabel(Text(body.kind == .openSlot
                                 ? String(localized: "Watch another address")
                                 : body.name))
        .chartArrival(index: index, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private func captionView(_ body: AddressSky.Body) -> some View {
        switch body.kind {
        case .openSlot:
            Text("Watch").dsText(.label12).foregroundStyle(DS.textTertiary)
        case .watched:
            Text(body.name)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
        case .connected:
            // One step quieter than a wallet's, which is the second thing (after
            // size) that separates "yours" from "someone you deal with". No
            // count, no total — the line beside a face on a map is a name.
            Text(body.name)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
    }

    private func constellationLabel(_ constellation: AddressSky.Constellation,
                                    in field: CGSize) -> some View {
        Text(constellation.name)
            .dsText(.label12).fontWeight(.bold)
            .foregroundStyle(DS.textTertiary.opacity(0.75))
            .position(point(constellation.at, in: field))
            .allowsHitTesting(false)
            .chartArrival(index: 0, delay: ChartEntrance.lead + 0.5,
                          reduceMotion: reduceMotion)
    }

    // MARK: - Space

    private func point(_ at: AddressSky.Point, in field: CGSize) -> CGPoint {
        CGPoint(x: at.x * field.width, y: at.y * field.height)
    }

    private func start() {
        guard drawn == 0 else { return }
        guard !reduceMotion else { drawn = 1; newDrawn = 1; return }
        withAnimation(.easeOut(duration: ChartEntrance.wipe).delay(ChartEntrance.lead)) {
            drawn = 1
        }
        // A new link waits for the settled sky to finish, then reaches out on
        // its own beat — the growth, seen.
        withAnimation(.easeOut(duration: 0.7)
            .delay(ChartEntrance.lead + ChartEntrance.wipe + 0.25)) {
            newDrawn = 1
        }
    }
}
