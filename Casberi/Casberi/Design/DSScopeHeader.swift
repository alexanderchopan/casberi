import SwiftUI

/// THE SCOPE HEADER — where you are inside a room, and the way to the rest
/// (prd §747, 2026-09-15).
///
/// Once the scopes are door rows on Home (`DSScopeRows`), reaching one is a
/// PUSH. This is what a pushed scope wears: its own name at the room's title
/// rung, the scopes after it trailing off beside it, and a back chevron to
/// Home.
///
/// **It scrolls; it is never swiped, and that is a ruling rather than a
/// detail** (user, 2026-09-15: *"inside can't be swipe bc swipe is for rooms
/// but can be a scroll header"*). A horizontal swipe on room content already
/// means one thing in this app — walk the rooms in dock order (§648/§663) —
/// and a second horizontal swipe that walks scopes instead would make the
/// gesture mean two things depending on how deep you happen to be. So travel
/// here is the strip's own scroll and the pick is a TAP, which is also what
/// `DSSectionSwitcher` has always done: the words are bigger and the container
/// is gone, but nothing about the interaction is new to learn.
///
/// **The trailing edge fades only when it overflows** — §553's amendment,
/// inherited wholesale: a cut word reads as a layout fault rather than as more
/// content, and a permanent fade on a short strip is the same lie pointing the
/// other way.
///
/// Home is deliberately NOT in the strip. It is the back chevron, because
/// leaving is a different act from moving sideways, and a room that offers two
/// ways to reach Home has to explain why one of them is a word.
struct DSScopeHeader<Scope: DSSectionScope, Account: View>: View {

    /// Every scope BUT home, in the room's own order — the same list the rows
    /// draw, so the two agree by construction.
    let sections: [Scope]
    let active: Scope
    var attention: Set<Scope> = []
    let onBack: () -> Void
    let onPick: (Scope) -> Void
    /// The one line under the title saying which account this reading is of.
    /// A builder rather than a string: it carries faces, and a room with a
    /// single account has nothing to say here and passes `EmptyView`.
    @ViewBuilder let account: () -> Account

    // No `matchedGeometryEffect` here and so no namespace: the switcher's
    // travelling fill named a position among chips of one size, and this
    // strip says "picked" with weight and ink instead. Reduce Motion needs no
    // branch for the same reason — the only motion is the scroll's own.

    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private var overflows: Bool { contentWidth > viewportWidth + 1 }

    private var edgeFade: LinearGradient {
        LinearGradient(stops: [.init(color: .black, location: 0),
                               .init(color: .black, location: 0.82),
                               .init(color: .black.opacity(0.15), location: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s1) {
                back
                strip
            }
            account()
                .padding(.leading, DSRoomChassis.inset)
        }
    }

    private var back: some View {
        Button {
            DSHaptic.selection()
            onBack()
        } label: {
            Image(systemName: "chevron.left")
                .dsGlyph(DS.Space.s6 - 2, weight: .semibold)
                .foregroundStyle(DS.textPrimary)
                .frame(width: DS.Hit.min, height: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .accessibilityLabel(Text("Back to the room"))
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: DS.Space.s4) {
                    ForEach(sections) { section in
                        word(section)
                    }
                }
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { contentWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in contentWidth = w }
                })
            }
            .scrollIndicators(.hidden)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { viewportWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in viewportWidth = w }
            })
            .mask(overflows ? AnyView(edgeFade) : AnyView(Color.black))
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { proxy.scrollTo(active.id, anchor: .leading) }
            .onChange(of: active) { _, now in
                // `glide`, not `standard`: this names a position (§667), and a
                // title that overshoots its own place and settles back reads
                // as a miss.
                withAnimation(DS.Motion.glide) { proxy.scrollTo(now.id, anchor: .leading) }
            }
        }
    }

    @ViewBuilder
    private func word(_ section: Scope) -> some View {
        let isOn = section == active
        let wants = attention.contains(section)
        Button {
            guard !isOn else { return }
            DSHaptic.selection()
            onPick(section)
        } label: {
            HStack(spacing: DS.Space.s1 + 2) {
                if wants {
                    Circle()
                        .fill(DS.attention)
                        .frame(width: DS.Space.s2 - 4, height: DS.Space.s2 - 4)
                }
                Text(section.label)
                    .dsText(.heading22)
                    .foregroundStyle(isOn ? DS.textPrimary : DS.textTertiary)
                    .lineLimit(1)
                    // §724's rule, for §724's reason: the pick is a shade
                    // heavier than the rest, and a strip squeezed by that
                    // difference truncates the one word that is the whole
                    // affordance.
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .id(section.id)
        .accessibilityLabel(wants
                            ? Text("\(section.label), \(section.summary), needs you")
                            : Text("\(section.label), \(section.summary)"))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .dsTooltip(section.summary)
    }
}

extension DSScopeHeader where Account == EmptyView {
    /// A room with one account, or none worth naming.
    init(sections: [Scope], active: Scope, attention: Set<Scope> = [],
         onBack: @escaping () -> Void, onPick: @escaping (Scope) -> Void) {
        self.init(sections: sections, active: active, attention: attention,
                  onBack: onBack, onPick: onPick) { EmptyView() }
    }
}
