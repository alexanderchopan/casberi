import SwiftUI

/// THE VIBENET ROOM'S HEAD — the anatomy `StripeRoomCard`/
/// `AppStoreConnectRoomCard` established: a heavy headline stating the whole
/// finding as a sentence, a quiet provenance line under it, ranked rows, no
/// coloured rail and no green/red — this room can raise exactly one alarm
/// (a locked account) and it says so in words, the same way a Stripe dispute
/// does.
///
/// R3.2 (2026-08-23): a row's tap no longer expands in place — it OPENS
/// `VibenetAccountSheet`. The card went back to being a summary; every
/// reading that used to cram into the card's own width (the matrix, the
/// history strip, the sync chips, the Explorer door) now lives on a real
/// surface with room to breathe. That squeeze is what made the Explorer
/// link wrap mid-word in the first place — the fix wasn't a layout tweak,
/// it was giving the content a bigger home.
///
/// Stores no `Thing` — only value types out of `VibenetRoom`. Corollary 5
/// has nothing to guard here.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount.
struct VibenetRoomCard: View {
    let room: VibenetRoom
    var onRemove: (String) -> Void
    /// Raised by the context menu's "Name this account…" — the alert itself
    /// lives on the SCREEN (a text-entry alert needs `@State` a card
    /// re-composed from a value type shouldn't own), so this just reports
    /// which address was asked for.
    var onRename: (String) -> Void = { _ in }
    /// A row's whole gesture now — the sheet's item is the address itself
    /// (the `L2beatScreen`/`WalletbeatScreen` shape: `String` is
    /// `Identifiable`, so no wrapper type is needed).
    var onOpen: (String) -> Void = { _ in }

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")
    /// The most rows drawn before the footnote takes over — the `StripeRoom`/
    /// `ASCRoom` cap shape, so a long watch list doesn't turn this into an
    /// unbounded list on a card meant to be a summary.
    private static let rowCap = 8

    private var drawn: [VibenetAccountItem] { Array(room.items.prefix(Self.rowCap)) }

    /// Watched faces only — a discovery stranger never earns a slot in the
    /// card's own hero, only in the setup screen's own list. Carries
    /// `alarmed` (R2.4) so the stack itself can flag who's in trouble —
    /// a direct read of `item.alarmed`, no new pure logic to harness.
    private var heroFaces: [(address: String, alarmed: Bool)] {
        room.items.prefix(5).map { ($0.address, $0.alarmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if heroFaces.count > 1 {
                // A stack, not a row: one glance says "several accounts",
                // which the headline sentence beneath it then makes exact.
                // Overlap follows the house face-stack idiom (StartFigureMark
                // / AddressFlight) — identity is on the FACE, so overlap
                // costs nothing legible.
                HStack(spacing: -10) {
                    ForEach(heroFaces, id: \.address) { face in
                        WalletFace(address: face.address, size: 28, circular: true)
                            .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 2))
                            .overlay(alignment: .bottomTrailing) {
                                // One badge for both locked and unlocking —
                                // the alarm is the alarm; the row's own pill
                                // already carries which of the two words.
                                if face.alarmed {
                                    Circle()
                                        .fill(Self.mark)
                                        .frame(width: 12, height: 12)
                                        .overlay {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundStyle(Color.fixed("#ffffff"))
                                        }
                                        .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 2))
                                }
                            }
                    }
                }
                .padding(.bottom, DS.Space.s2)
            }

            Text(VibenetRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(VibenetRoom.note(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)

            if !room.items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(drawn) { item in
                        row(item)
                    }
                }
                .padding(.top, DS.Space.s3)
            }

            if room.items.count > drawn.count {
                Text(String(localized: "\(room.items.count - drawn.count) more watched"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s1)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
    }

    // MARK: - Rows

    /// One watched account, summary only — a row is a read with ONE
    /// gesture; unwatching lives on the trailing menu, never a second tap
    /// target inside the row. The subtitle keeps R2.2's precedence (unlock
    /// countdown + runway, else the urgency line, else the plain key
    /// count) because that ranking is the whole point of surfacing it here
    /// — before anyone opens anything.
    private func row(_ item: VibenetAccountItem) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(item.address)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                WalletFace(address: item.address, size: 28, circular: true)
                VStack(alignment: .leading, spacing: 3) {
                    // A nickname takes the title slot (not monospaced —
                    // it's a name, not hex) and the short address drops
                    // to a small line beneath. Unnamed rows are
                    // unchanged: the address alone, exactly as before.
                    if let name = VibenetWatch.shared.name(for: item.address) {
                        Text(name)
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(VibenetRoom.shortAddress(item.address))
                            .dsText(.label11).monospaced()
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    } else {
                        Text(VibenetRoom.shortAddress(item.address))
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                            .monospaced()
                            .lineLimit(1)
                    }
                    // An account mid-unlock leads with its OWN countdown
                    // rather than its key count — "1 key" sits right
                    // beside a badge already saying "Unlocking"; the
                    // number worth a glance here is WHEN.
                    if item.hasInitiatedUnlock, let countdown = item.unlockLabel(now: .now) {
                        Text(countdown)
                            .dsText(.label12)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        // Only when BOTH endpoints are known — a bar with
                        // a guessed start is the fake status §83 forbids,
                        // so this is silent rather than wrong on a build
                        // where the delay never read. No animation on
                        // the fill: a static capsule needs no Reduce
                        // Motion check.
                        if let progress = item.unlockProgress(now: .now) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Self.mark.opacity(0.15))
                                    Capsule().fill(Self.mark)
                                        .frame(width: geo.size.width * progress)
                                }
                            }
                            .frame(height: 4)
                            .frame(maxWidth: 160)
                        }
                    } else if let urgent = item.urgentLine(now: .now) {
                        // R2.2: a key's own clock outranks the plain key
                        // count on the row that's about to be affected
                        // by it. The room's one color carries urgency
                        // here (never bold-white-on-blue — that grammar
                        // stays the lock pill's alone).
                        Text(urgent)
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(Self.mark)
                            .lineLimit(1)
                    } else {
                        Text(VibenetRoom.rowLine(item))
                            .dsText(.label12)
                            .foregroundStyle(item.alarmed ? DS.textPrimary : DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                HStack(spacing: DS.Space.s2) {
                    // The pill states the ALARM; the chevron states
                    // there's more to see.
                    if item.alarmed {
                        Text(item.hasInitiatedUnlock ? String(localized: "Unlocking") : String(localized: "Locked"))
                            .dsText(.label11).fontWeight(.bold)
                            .foregroundStyle(Color.fixed("#ffffff"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Self.mark, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    Image(systemName: "chevron.right")
                        .dsGlyph(12)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Space.s2)
        .contextMenu {
            Button {
                onRename(item.address)
            } label: {
                Label(String(localized: "Name this account…"), systemImage: "pencil")
            }
            Button {
                DSHaptic.tap()
                UIPasteboard.general.string = item.address
            } label: {
                Label(String(localized: "Copy address"), systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                onRemove(item.address)
            } label: {
                Label(String(localized: "Stop watching"), systemImage: "trash")
            }
        }
    }
}

/// One landed vibenet event, led by WHO it happened to (R4.2).
///
/// Reported 2026-08-23: *"i can't see which accounts they are from."* The
/// room fell to `.plain`, so every row wore one identical brand glyph and
/// the only identifying mark was a truncated `…f21f` at the END of an
/// 80-char title, in the same weight as the rest of the sentence — two
/// accounts' events were indistinguishable at a glance, in a room whose
/// entire subject is which account something happened to. Every other
/// identity room in this app leads with a face; this one now does too.
///
/// Reads `authorHandle` (the account) and `summary` (the event without
/// the address) — both stamped at landing, so nothing here parses a
/// display title back into data. A row that predates those falls back to
/// its whole title, which still says everything, just less prettily.
struct VibenetEventRow: View {
    let thing: Thing

    var body: some View {
        if thing.isLive {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                if let address = thing.authorHandle {
                    WalletFace(address: address, size: 34, circular: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(thing.summary ?? thing.title)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: DS.Space.s2)
                Text(thing.capturedAt.formatted(.relative(presentation: .named)))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1).fixedSize()
            }
            .padding(.vertical, DS.Space.s2)
        }
    }

    /// The account's nickname when it has one, else its short address —
    /// the same identity the room card and the sheet show, so one account
    /// never reads as two different things across three surfaces.
    private var title: String {
        guard let address = thing.authorHandle else { return thing.title }
        return VibenetWatch.shared.name(for: address) ?? VibenetRoom.shortAddress(address)
    }
}
