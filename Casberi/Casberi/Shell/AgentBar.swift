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
struct AgentBar: View {
    var hasUnseenSignal: Bool
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
    }
}
