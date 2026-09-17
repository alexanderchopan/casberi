import SwiftUI

/// The avatar door — the ACCOUNTS entry (prd §796, 2026-09-17). It was the
/// Settings entry from the day it lived alone in the top-right toolbar corner
/// through 2026-07-20, when it joined the catalogue door as a second FIXED
/// leading chip in `SourceChips` (Stories-style: your own face leads the
/// strip), and on into the dock's fixed seat (§700). The user re-read it: the
/// face is about YOU, and what is yours in this app is your accounts — so the
/// face opens the Accounts screen, and Settings is a door in that screen's
/// switcher (`Manage | Connect | Settings`, one section of it). Kept as its own
/// small view (not folded directly into `SourceChips`) so
/// `AvatarDoor`/`DoorSpin`/`DoorBounce` stay one shared definition regardless
/// of where the door lives.
struct AvatarChip: View {
    /// Opens (and, pressed again, closes — §705) the Accounts screen.
    var onAccounts: () -> Void
    /// Bumped by pull-to-refresh — the avatar does one full spin while the
    /// refresh runs: it's the person's own face doing the work.
    var refreshSpin: Int = 0
    /// Live overscroll points while a pull is in progress
    /// (`ShellChrome.pullTension`) — the door winds up with the finger
    /// before the release spin, so the gesture has tension instead of a
    /// silent threshold (2026-08-04). Zero at rest and under Reduce Motion
    /// (the writer gates).
    var pullTension: CGFloat = 0
    /// The glass union this door joins — `SourceChips.doorsUnion`, which
    /// paired it with the catalogue door beside it from 2026-08-06 until §798
    /// deleted that door. The door wears glass either way; the union is what
    /// made the two of them ONE shape, and is kept as a union of one so the
    /// material has a single definition. nil is the phone's own dock seat
    /// (`DockDoors`), which stands on `RootShell`'s layer with nothing beside
    /// it to merge with — and a preview.
    var doorUnion: DSGlassUnion? = nil
    /// The mark's drawn size. 46 everywhere it floats; the dock's leading
    /// seat folds it 46→40 with the chips beside it (prd §697), which a fixed
    /// frame could not do — a door standing at 46 in a row of 40s reads as a
    /// slightly grown one, the near-miss `DSDock.agentSize` exists to prevent.
    var size: CGFloat = 46
    /// Set on a pushed screen, and the seat becomes the BACK door (prd §767).
    /// §752 put every back control in the content or the bottom band, and the
    /// system's chevron still stood at the top of every pushed screen. This
    /// seat already survives into every one of them and already meant "put it
    /// back" on Settings (the 2026-09-12 toggle), so it says so everywhere.
    var onBack: (() -> Void)? = nil
    /// Taps bounce the door (Telegram grammar, same as the tab icons).
    @State private var avatarBounce = 0
    /// Last time the door actually opened — see `open()` below.
    @State private var lastOpen: TimeInterval = 0

    var body: some View {
        Button {
            // A real action again (2026-07-26), not a no-op: whichever
            // recognizer wins the press, the door opens. Same shape the
            // catalogue door beside it had, until §798 deleted it.
            open()
        } label: {
            ZStack {
                // The flat gray well is GONE (2026-08-06): this door now wears
                // the floating material the strip's own comment has claimed for
                // "the doors" since 2026-07-20 and only the catalogue door ever
                // had. An opaque 46pt disc over the glass would also leave the
                // union merging two shapes nobody can see through.
                if onBack != nil {
                    BackDoorGlyph()
                        .modifier(DoorBounce(trigger: avatarBounce))
                        .transition(.opacity)
                } else {
                    AvatarDoor()
                        .modifier(DoorBounce(trigger: avatarBounce))
                        .modifier(DoorSpin(trigger: refreshSpin, tension: pullTension))
                }
            }
            .frame(width: size, height: size)
            // Glass at the same radius the catalogue door beside it uses — one
            // shared definition, so the union merges two identical circles
            // rather than smearing one shape into a differently-rounded
            // neighbour.
            .dsGlassDoor(doorUnion)
            // The door is the circle. This one was never as bad as the
            // catalogue's — its `Circle().fill` renders across the whole
            // 46pt, so the region was already whole — but stating it means
            // the two doors beside each other can't drift on what a press
            // has to hit. Load-bearing NOW rather than merely tidy: with the
            // gray well gone in the union case there is no opaque fill left to
            // catch a press away from the glyph (the catalogue door's own
            // 2026-07-26 lesson, three reports deep).
            .contentShape(Circle())
            .dsHover()
        }
        .buttonStyle(.plain)
        // The ring and the spoken name, read where they are drawn (prd §670).
        // The name says what the ring says, because the ring is a visual cue
        // and half the people using this app will never see it.
        .modifier(DoorAlarm(isBack: onBack != nil))
        // See `SourceChips`' deleted catalogue door: a plain Button here
        // competes with the paged feed TabView's pan recognizer for the
        // first touch (Apple forums thread 725366) and can need several
        // taps to win. `highPriorityGesture` wins immediately — kept as the
        // belt beside the Button's own braces above.
        .highPriorityGesture(TapGesture().onEnded { open() })
    }

    /// One entry point for the door's two possible tap deliveries, coalesced
    /// so the fallback can never double-bounce or double-push.
    private func open() {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastOpen > 0.4 else { return }
        lastOpen = now
        avatarBounce += 1
        if let onBack { onBack() } else { onAccounts() }
    }
}

/// One full turn per refresh — additive, so back-to-back pulls keep
/// spinning forward instead of unwinding. The pull itself WINDS the door
/// first (2026-08-04): `tension` is live overscroll, mapped to up to 60° of
/// forward rotation, value-driven with no animation so it tracks the finger
/// — then the release spin launches from wherever the wind-up left it, in
/// the same direction. Tension arrives pre-zeroed under Reduce Motion.
private struct DoorSpin: ViewModifier {
    let trigger: Int
    var tension: CGFloat = 0
    @State private var angle: Double = 0

    /// 140pt of pull (the writer's clamp) → a 60° wind.
    private var windUp: Double { Double(min(tension, 140)) / 140 * 60 }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle + windUp))
            .onChange(of: trigger) {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                    angle += 360
                }
            }
    }
}

/// The tap bounce for a door that may be a PHOTO (the set avatar) — a symbol
/// effect can't move a UIImage, so the spring scale carries the same beat.
private struct DoorBounce: ViewModifier {
    let trigger: Int
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(up ? 1.2 : 1)
            .onChange(of: trigger) {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { up = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(140))
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { up = false }
                }
            }
    }
}

/// The avatar (or a person glyph before one's set) — the Accounts entry
/// (§796; it was Settings' until then). Sized up alongside the Apps door
/// (2026-07-09): the doors earned presence in the bar, not a whisper, and
/// this one keeps that size now that it stands alone (§798).
struct AvatarDoor: View {
    var body: some View {
        if let avatar = ProfileStore.shared.avatar {
            Image(uiImage: avatar)
                .resizable().scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle")
                .dsGlyph(.feature, weight: .regular)
                .foregroundStyle(DS.textSecondary)
        }
    }
}

/// The seat's glyph on a pushed screen (prd §767): the way back, in the circle
/// the face stands in, at the face's own presence.
struct BackDoorGlyph: View {
    var body: some View {
        Image(systemName: "chevron.backward")
            .dsGlyph(.title, weight: .semibold)
            .foregroundStyle(DS.textPrimary)
            .accessibilityHidden(true)
    }
}

/// THE APPS DOOR IS DELETED (prd §798, 2026-09-17). It was a grid glyph that
/// filled, turned `DS.attention` and pulsed when a connection broke — drawn
/// in the rail's glass circle and, since §793, in the dock's tail tile called
/// "Accounts". The face beside it opens that same screen (§796), so the door
/// was the same door twice and the user ruled the tile out.
///
/// **The alarm it carried is not deleted with it** (§83: no fake status, and
/// no silent loss of a real one). `DoorAlarm` below moves it onto the face,
/// in the dashed-ring vocabulary the chips already use for exactly this fact
/// (`SourceChips.ChipAttentionRing`, 2026-07-21: dashed means broken, solid
/// means selected). The pulse does not come with it — a chip's ring does not
/// pulse, and the dock is no place for standing motion — but the resolution
/// beat §412a argued for does: the ring leaves on a scale, so a repair reads
/// as something happening rather than as a person no longer noticing.
///
/// A LEAF, for the reason prd §670 gives: `bridges` is written ~90 times by a
/// landing sweep, and read from `AvatarChip`'s own body every one of those
/// writes would rebuild the dock's fixed seat.
private struct DoorAlarm: ViewModifier {
    /// The seat is the BACK door (prd §767) — it is not about your accounts
    /// then, so it carries neither the ring nor the accounts label.
    let isBack: Bool
    @Environment(BridgeStore.self) private var bridges
    /// The ring still DRAWS under Reduce Motion — it is the fact, not the
    /// flourish; only its arrival and exit stop moving. `AppsDoor` gated its
    /// healed beat the same way, and nothing mechanical catches this one
    /// (`design-motion-audit.py` reads `onAppear` entrances).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let broken = !isBack && bridges.attentionCount > 0
        let spoken = isBack
            ? String(localized: "Back")
            : (broken ? String(localized: "Accounts, needs attention")
                      : String(localized: "Accounts"))
        content
            .overlay {
                if broken {
                    Circle()
                        .strokeBorder(DS.attention,
                                      style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
                        .transition(.scale(scale: 1.25).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : DS.Motion.press, value: broken)
            .accessibilityLabel(Text(spoken))
            .dsTooltip(spoken)
    }
}
