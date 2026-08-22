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
                // THE RINGS THEMSELVES (prd §438). The drawing claimed
                // everything sat on two rings and never drew either one, so
                // with two wallets and a handful of connected addresses there
                // was nothing circular on the screen at all — the report was
                // "my addresses are NOT in a circle", and it was right.
                // The empty state has drawn its ring since the day it shipped;
                // the real sky now draws both of its own. Ellipses, not
                // Circles, because positions scale x and y by the field's own
                // sides and the strokes must pass through the faces they hold.
                // The inner ring only once somebody is on it — an empty orbit
                // is decoration.
                ringStroke(radius: AddressSky.ringRadius, in: field)
                if !sky.connectedBodies.isEmpty {
                    ringStroke(radius: AddressSky.connectedRadius, in: field)
                }
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

    private func ringStroke(radius: Double, in field: CGSize) -> some View {
        Ellipse()
            .strokeBorder(DS.fillLine, lineWidth: 1.5)
            .frame(width: radius * 2 * field.width, height: radius * 2 * field.height)
            .position(x: field.width / 2, y: field.height / 2)
            .allowsHitTesting(false)
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
                    // STRAIGHT (prd §437, 2026-08-22). It bowed toward the
                    // centre, on the reasoning that the sky should read as
                    // orbits rather than as a wire diagram — and paired with
                    // bodies that were themselves pulled toward the centre,
                    // that made every connection a short arc hugging the
                    // interior. The drawing read as rings inside rings, which
                    // is a picture of nothing: the one thing it has to say is
                    // that THIS address reached THOSE wallets. A straight line
                    // from a body on the inner ring to a wallet on the outer
                    // one crosses the drawing when the two wallets are far
                    // apart and stays short when they are neighbours, so the
                    // geometry itself says how far a connection reaches.
                    path.addLine(to: to)
                }
            }
            .trim(from: 0, to: settled ? drawn : newDrawn)
            .stroke(settled ? DS.textTertiary.opacity(0.32) : DS.tint.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                       dash: settled ? [] : [3, 4]))
            .allowsHitTesting(false)
        }
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

/// THE SKY BEFORE THERE IS ONE (prd §437, 2026-08-22).
///
/// `AddressSky.layout` returns nil under two watched wallets, and the manager
/// fell through to the roster shelf for both of those states. For ONE watched
/// wallet that is right — a face and four empty slots is an honest picture of
/// a shelf part-filled. For ZERO it is not: a row of five identical dashed
/// circles is a picture of the CAP, offered to somebody who has not yet met
/// the feature and has no use for its ceiling. It also throws away the one
/// thing this screen now knows how to say, which is what the drawing is FOR.
///
/// So an empty manager gets the same ring, with one invitation on it where the
/// first wallet will sit and the seats its world will draw into left quiet.
/// Nothing here is a control except the invitation itself, and nothing claims
/// a number: the cap is a sentence on the caption line below, exactly as it is
/// once the sky is real.
///
/// It draws no `WalletFace`, because there is no address to draw one of — an
/// identicon over an address nobody has entered is the invented identity §83
/// bans, on the screen where trust is being established.
struct AddressSkyEmptyView: View {
    var onPickSlot: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The same inset the real sky uses, for the same reason — the caption
    /// hangs below its body and the top body needs room above it.
    private let inset: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let field = CGSize(width: geo.size.width - inset * 2,
                               height: geo.size.height - inset * 2)
            ZStack {
                // The ring the wallets will sit on, at the radius they will sit
                // at — so the invitation is not floating in space, it is
                // standing in the first seat of something.
                Circle()
                    .strokeBorder(DS.fillLine, lineWidth: 1.5)
                    .frame(width: AddressSky.ringRadius * 2 * field.width,
                           height: AddressSky.ringRadius * 2 * field.height)
                    .allowsHitTesting(false)
                // Where the people you deal with will draw. Quiet dots rather
                // than dashed faces: a dashed circle is an invitation and these
                // are not — nothing about them is tappable, and three more
                // invitations would read as three more things to do.
                ForEach(seats, id: \.self) { angle in
                    Circle()
                        .fill(DS.fillStrong)
                        .frame(width: 8, height: 8)
                        .position(point(angle: angle,
                                        radius: AddressSky.connectedRadius,
                                        in: field))
                        .allowsHitTesting(false)
                }
                invitation
                    .position(point(angle: -.pi / 2,
                                    radius: AddressSky.ringRadius, in: field))
                Text("Who it reaches draws here")
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .position(x: field.width / 2, y: field.height / 2)
                    .allowsHitTesting(false)
                    .chartArrival(index: 0, delay: ChartEntrance.lead + 0.35,
                                  reduceMotion: reduceMotion)
            }
            .frame(width: field.width, height: field.height)
            .padding(inset)
        }
    }

    /// Three seats, evenly spaced on the connected ring and deliberately NOT
    /// at the top — the top is the invitation's, and a seat under it would
    /// read as its caption.
    private var seats: [Double] {
        (0..<3).map { -Double.pi / 2 + Double.pi / 2 + 2 * Double.pi * Double($0) / 3 }
    }

    private var invitation: some View {
        VStack(spacing: 5) {
            Circle()
                .strokeBorder(DS.tint.opacity(0.7),
                              style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                 dash: [5, 6]))
                .frame(width: DS.Face.shelf, height: DS.Face.shelf)
                .overlay {
                    Image(systemName: "plus")
                        .dsGlyph(18)
                        .foregroundStyle(DS.textSecondary)
                }
            Text("Your first wallet")
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
        .frame(width: max(DS.Face.shelf, 96))
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.selection()
            onPickSlot()
        }
        .dsTapCard()
        .accessibilityLabel(Text("Watch your first address"))
        .chartArrival(index: 0, reduceMotion: reduceMotion)
    }

    private func point(angle: Double, radius: Double, in field: CGSize) -> CGPoint {
        CGPoint(x: (0.5 + radius * cos(angle)) * field.width,
                y: (0.5 + radius * sin(angle)) * field.height)
    }
}
