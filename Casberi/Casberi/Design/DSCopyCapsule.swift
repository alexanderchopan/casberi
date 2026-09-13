import SwiftUI

/// **Copy, and say it was copied (prd §715, 2026-09-13).** A bare tap-to-copy
/// went unnoticed (user, 2026-07-15), so three device-code screens each drew
/// this capsule and its two-second state by hand, byte-identically. The value
/// is copied SENSITIVE (local-only, expiring) because every caller so far
/// copies a sign-in code; pass `sensitive: false` for anything public.
struct DSCopyCapsule: View {
    let value: String
    var sensitive = true
    @State private var copied = false

    var body: some View {
        Button {
            if sensitive { DSPasteboard.copySensitive(value) } else { DSPasteboard.copy(value) }
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) { copied = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation(DS.Motion.standard) { copied = false }
            }
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .dsSymbolSwap(copied)
                    .dsGlyph(13)
                Text(copied ? "Copied" : "Copy")
                    .dsText(.subhead13).fontWeight(.semibold)
            }
            .foregroundStyle(copied ? DS.confirm : DS.tint)
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: 34)
            .background(DS.gray100, in: Capsule(style: .continuous))
            .dsTapTarget(Capsule(style: .continuous))
        }
        .buttonStyle(PressSpring())
        .dsHover()
    }
}
