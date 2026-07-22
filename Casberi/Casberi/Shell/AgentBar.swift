import SwiftUI

/// The agent's bar (docs/agent-brief.md, ruling 6) — replaces the FAB.
/// Floating-layer glass, rides every screen (hosted in `RootShell`'s own
/// ZStack, not `MainSurface`'s, so pushed rooms — Apps, Settings, a bridge
/// setup form — never slide over it the way they used to slide over the
/// FAB). Tap raises the agent full screen.
///
/// The berry mark breathes (the same idiom `Composer.swift`'s in-flight
/// "Thinking…" state already uses) while some kept ask changed and the agent
/// hasn't been raised yet this launch — ruling 6: no number badges, ever.
///
/// Morphs into the risen surface (2026-07-20) — `morphNS` is the SAME
/// namespace `RootShell` gives `Composer`'s `glassNamespace`, and `"agentMorph"`
/// the same id both sides key on, so the bar's own frame is what the risen
/// sheet visibly grows out of (`matchedGeometryEffect`, not `glassEffectID` —
/// the risen surface is plain ink, never glass, per design law §8 "Liquid
/// Glass on the floating layer only... never on content panels"; only the
/// SHAPE morphs, the glass itself stays the bar's alone and fades out as the
/// sheet's opaque background fades in). `RootShell` hides this view entirely
/// once risen (`if !composerOpen`) so exactly one side of the pair exists at
/// a time — matchedGeometryEffect needs that alternation to interpolate.
struct AgentBar: View {
    var hasUnseenSignal: Bool
    var morphNS: Namespace.ID?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                Text("Ask your things…")
                    .dsText(.body17)
                    .foregroundStyle(DS.textTertiary)
                Spacer(minLength: 0)
                if hasUnseenSignal {
                    CasberiMark(size: 20).breathing()
                } else {
                    CasberiMark(size: 20)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dsGlass(cornerRadius: DS.Radius.pill)
        .modifier(MorphMatch(ns: morphNS))
    }
}

/// The whisper (ruling 6's flag-gated sketch, ruled real 2026-07-22 — prd
/// §165): one glass card above the bar on the first open of a day, carrying
/// the day brief. Floating layer, so glass is lawful here. Tap opens the
/// Today brief itself (prd §166). It dies for the day the moment the agent
/// rises by any path — its one job is done — and never shows with nothing to
/// say (`DayBrief.whisper` composes nil).
///
/// **It names itself** (user ruling 2026-07-22). The first cut was a pill: a
/// tint dot beside one line of facts. That is notification grammar — a dot
/// plus a sentence reads as "a transaction happened", and nobody could tell
/// it was a daily synthesis. Three changes fix the read, and each is doing a
/// job: the day is NAMED on its own line ("Your Wednesday brief") so the
/// artifact is legible before the facts are; the unread dot becomes the
/// agent's own mark, which says who this is from instead of merely that it's
/// new; and a chevron says it opens something rather than just sitting there.
/// It is also INSET from the bar below it (2026-07-22): two full-width glass
/// slabs stacked read as one confusing double-bar. A step narrower on each
/// side gives the floating layer a hierarchy — the bar is furniture, the
/// whisper is today's delivery sitting on top of it.
struct WhisperCapsule: View {
    var title: String
    var lead: String
    var walletPct: Double?
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var detail: Text {
        let base = Text(lead).foregroundStyle(DS.textSecondary)
        guard let walletPct else { return base }
        // The figure wears its own direction (§83's accent rule), which is
        // the whole reason `walletPct` travels separately from the lead.
        return base
            + Text(String(localized: ", wallet ")).foregroundStyle(DS.textSecondary)
            + Text(String(format: "%+.1f%%", walletPct))
                .foregroundStyle(TokenChartStyle.accent(change: walletPct / 100, scheme: scheme))
                .fontWeight(.semibold)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                CasberiMark(size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    detail
                        .dsText(.subhead13)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .dsGlass(cornerRadius: DS.Radius.control)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(lead)"
                            + (walletPct.map { String(format: ", wallet %+.1f percent", $0) } ?? ""))
        .accessibilityHint("Opens your day")
    }
}

/// Applies `matchedGeometryEffect` only when a real namespace was given —
/// `RootShell` always supplies one, but keeps this optional so a future
/// preview/embedding of `AgentBar` without a namespace doesn't crash on a
/// force-unwrap. Shared with `Composer` (not file-private) — both sides of
/// the morph key the exact same id/namespace pairing, so one modifier
/// keeps them from drifting apart.
struct MorphMatch: ViewModifier {
    let ns: Namespace.ID?
    func body(content: Content) -> some View {
        if let ns {
            content.matchedGeometryEffect(id: "agentMorph", in: ns)
        } else {
            content
        }
    }
}
