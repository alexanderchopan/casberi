import SwiftUI

/// What a room's scope control needs of a scope (prd §483, 2026-08-26).
///
/// Deliberately tiny, and deliberately NOT tied to any one room's enum: Wallet
/// and Vibenet arrived at the same control within a day of each other with
/// completely different vocabularies — `Activity · Holdings · Positions · NFTs
/// · Risk · Permissions` against `Holdings · Recent · Accounts · Keys` — which
/// is the shape that says the control is generic and the words are not.
///
/// Conform in the room's own layer, never on the model type itself: both scope
/// enums are Foundation-only so their rules can be compiled WHOLE by a
/// `swiftc` harness, and a SwiftUI protocol on the declaration would end that.
/// A bare `extension X: DSSectionScope {}` beside the call site costs nothing
/// and keeps the harness door open.
protocol DSSectionScope: Identifiable, Hashable {
    /// The chip's word. Short nouns — a scope strip that scrolls because its
    /// labels are sentences is a strip nobody reads (user ruling, 2026-08-26:
    /// *"we can't really have the sections we what you hold etc b/c they are
    /// too long"*).
    var label: String { get }
    /// What the scope holds, for the accessibility label and the tooltip.
    /// Short nouns are learnable but not self-explaining, and one of Wallet's
    /// ("Permissions") must not read as an app-settings screen when what sits
    /// behind it is ranked by the dollars somebody can take right now (§292).
    var summary: String { get }
}

extension DSSectionScope {
    /// A room with nothing more to say than the word itself. Defaulted so a
    /// room adopting this control is never forced to invent a second string
    /// per scope just to satisfy the protocol — an invented one would be worse
    /// than the label repeated.
    var summary: String { label }
}

/// A room's SCOPE control — which of its readings is on screen.
///
/// **A TEXT sibling of `CategoryVenueSwitcher`, not an extension of it.** That
/// control draws `BridgeIcon` and nothing else: every seat it scopes is a brand
/// with a bundled mark, so it is icon-only by construction and structurally
/// cannot render "Positions". These scopes have no marks and never will — they
/// are readings of one subject, not products — so the choice was a text sibling
/// or a room-shaped `if` inside a control two rooms share. This is the sibling;
/// `CategoryVenueSwitcher` is untouched.
///
/// Everything else is deliberately identical, because two switchers a few
/// points apart on the same screen that behave differently read as a bug: the
/// glass capsule, the horizontal scroll **clipped to that capsule** (§357's own
/// 2026-08-11 fix — `dsGlass` paints a capsule but does not bound its content,
/// so a half-scrolled chip draws past the glass onto the page), the
/// `matchedGeometryEffect` travel on the selected fill with its Reduce Motion
/// branch (§360 — swapping in `glassEffectID` silently deletes the travel it
/// replaces, since the decoration is inert on a shape carrying no
/// `glassEffect`, and the still frames look correct either way), the re-centre
/// on change, and the edge-ease scroll transition.
///
/// **The one thing it adds is the dot**, and it is what makes a conditional
/// scope safe to put at the END of a strip: `Risk` and `Permissions` are absent
/// on most wallets, so they sit last — a conditional scope in the middle shifts
/// every scope after it the day it appears — and position is therefore not how
/// you find an alarm. The dot is, and it is visible from every other scope.
/// That is the job the briefly-considered "Needs you" scope was invented to do
/// and did worse, since it could only ever say that SOMETHING wanted you.
struct DSSectionSwitcher<Scope: DSSectionScope>: View {

    let sections: [Scope]
    let active: Scope
    /// Scopes with something that wants answering. A set rather than a single
    /// optional so the caller is never forced to decide which one "the" alarm
    /// belongs to — several can want you at once, and each says so for itself.
    var attention: Set<Scope> = []
    // **`embedded` IS DELETED (prd §747, 2026-09-15).** It was §547's flag for
    // drawing this switcher as the lower deck of `DSRoomRailSlab` — no glass of
    // its own, no outer padding, no rest fill, and a concentric rounded-rect
    // pick instead of a capsule — so that a pill inside a pill did not double.
    // The slab is gone and no caller set it, which made every one of those
    // branches unreachable. The five screens that still draw this switcher all
    // drew it un-embedded, so what survives is exactly what they were already
    // getting.
    //
    // **§553's edge fade is NOT deleted with it.** It was reported on the
    // embedded strip and lived in that branch, but the ruling is about any
    // overflowing strip — a cut word reads as a layout fault rather than as
    // more content — so it moves onto the surviving branch rather than going
    // out with the mode it happened to be written in.
    let onPick: (Scope) -> Void

    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The shape a pick fills, and the shape a tap is caught by — one value, so
    /// the target can never drift from the thing that looks tappable.
    private var pickShape: AnyShape { AnyShape(Capsule(style: .continuous)) }

    /// **A CUT WORD IS NOT AN AFFORDANCE (prd §553 amendment, 2026-09-01).**
    ///
    /// Reported on vibenet, whose five scopes do not fit 390pt: the strip
    /// scrolls and always has, and it centres the active scope on appear — so
    /// nothing was broken. What was broken is that it LOOKED broken.
    /// "Permissions" was sliced mid-letter against a hard edge, which reads as
    /// a layout fault rather than as more content, and a person who reads it
    /// that way never tries the gesture that would have shown them the rest.
    ///
    /// So the trailing edge fades — the iOS convention for exactly this, and
    /// the smallest possible change: no chrome, no arrow, no hairline (§8
    /// forbids the last of those outright), and no re-sizing of a component
    /// seven other rooms share.
    ///
    /// **Only when it actually overflows.** A permanent fade would dim the last
    /// scope of every SHORT strip — a two-scope room would wear a gradient
    /// telling it there is more when there is not, which is the same lie
    /// pointing the other way.
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private var overflows: Bool { contentWidth > viewportWidth + 1 }

    private var edgeFade: LinearGradient {
        // Wide enough to READ as a gradient. The first cut faded over the last
        // 8% (~28pt) and measured on screen as barely distinguishable from the
        // hard cut it was meant to replace — which would have been the worst
        // outcome: the change made, the problem still there.
        LinearGradient(stops: [.init(color: .black, location: 0),
                               .init(color: .black, location: 0.82),
                               .init(color: .black.opacity(0.15), location: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                DSGlassContainer(spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(sections) { section in
                            chip(section)
                        }
                    }
                }
                .padding(4)
                .background(GeometryReader { g in
                    Color.clear.onAppear { contentWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in contentWidth = w }
                })
            }
            .background(GeometryReader { g in
                Color.clear.onAppear { viewportWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in viewportWidth = w }
            })
            .scrollBounceBehavior(.basedOnSize)
            // §553's fade, INSIDE the clip: it fades the chips, and the glass
            // capsule painted behind them by `dsGlass` stays whole. Only when
            // the strip actually overflows — a permanent fade would dim the
            // last scope of every short strip, which is the same lie pointing
            // the other way.
            .mask(overflows ? AnyView(edgeFade) : AnyView(Color.black))
            .clipShape(Capsule(style: .continuous))
            .dsGlass(cornerRadius: 999)
            .onAppear { proxy.scrollTo(active.id, anchor: .center) }
            .onChange(of: active) { _, now in
                withAnimation(DS.Motion.standard) { proxy.scrollTo(now.id, anchor: .center) }
            }
        }
        // Sizes to its content up to the width available, so a room with only
        // two scopes draws a short capsule rather than a full-width bar with
        // four empty inches in it — `CategoryVenueSwitcher`'s own rule.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ section: Scope) -> some View {
        let isOn = section == active
        let wants = attention.contains(section)
        return Button {
            guard !isOn else { return }
            DSHaptic.selection()
            onPick(section)
        } label: {
            HStack(spacing: DS.Space.s1 + 2) {
                if wants {
                    Circle()
                        .fill(DS.attention)
                        .frame(width: 6, height: 6)
                }
                Text(section.label)
                    .dsText(.label12)
                    .fontWeight(isOn ? .semibold : .medium)
                    .foregroundStyle(isOn ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
                    // **A CHIP'S WORD NEVER ACCEPTS A NARROWER WIDTH (prd §724,
                    // 2026-09-13).** This strip sits in a `List` row, and a
                    // horizontal scroll inside a List row keeps the content
                    // width it first measured. Two things grow a chip AFTER
                    // that measure: the pick (`.semibold` is 1pt wider than
                    // `.medium`, measured 2026-08-11) and the dot, which
                    // arrives once the room resolves what needs you. Squeezed
                    // by that difference the label truncated to "Revi…" on the
                    // 0xBow room — an ellipsis where a scope's whole name is
                    // the affordance. Fixed horizontally, the strip scrolls
                    // instead; `DSChip` carries the same modifier for the
                    // same reason.
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background {
                ZStack {
                    Capsule(style: .continuous).fill(DS.fillFaint)
                    if isOn {
                        // `DS.tintDim` — the token whose documented job is exactly this
                        // ("tint at rest-chip opacity"), rather than a second
                        // hand-spelled 0.18 that drifts from it.
                        let fill = pickShape.fill(DS.tintDim)
                        if reduceMotion {
                            fill
                        } else {
                            fill.matchedGeometryEffect(id: "dsSectionActiveFill", in: ns)
                        }
                    }
                }
            }
            .contentShape(pickShape)
        }
        .buttonStyle(.plain)
        .dsHover()
        .id(section.id)
        // The dot is visual and carries real information, so the label says it
        // too — and names what the scope HOLDS, since these nouns are learnable
        // but not self-explaining.
        .accessibilityLabel(wants
                            ? String(localized: "\(section.label), \(section.summary), needs you")
                            : String(localized: "\(section.label), \(section.summary)"))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .dsTooltip(section.summary)
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.9)
                .opacity(phase.isIdentity ? 1 : 0.6)
        }
    }
}
