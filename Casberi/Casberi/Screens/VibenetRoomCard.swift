import SwiftUI

/// THE VIBENET ROOM'S HEAD — the anatomy `StripeRoomCard`/
/// `AppStoreConnectRoomCard` established: a heavy headline stating the whole
/// finding as a sentence, a quiet provenance line under it, ranked rows, no
/// coloured rail and no green/red — this room can raise exactly one alarm
/// (a locked account) and it says so in words, the same way a Stripe dispute
/// does.
///
/// There is no external destination to route to (a devnet test account has
/// no thing sheet, no permalink, nothing else in the app that knows about
/// it) — so unlike its Work-group neighbours this card is its OWN detail
/// screen: a row expands in place to show its actor roster rather than
/// pushing anywhere.
///
/// Stores no `Thing` — only value types out of `VibenetRoom`. Corollary 5
/// has nothing to guard here.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount.
struct VibenetRoomCard: View {
    let room: VibenetRoom
    var onRemove: (String) -> Void

    /// Which addresses are expanded to show their actor roster. Local to the
    /// card, not persisted — this is a read, not a setting.
    @State private var expanded: Set<String> = []

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")
    /// The most rows drawn before the footnote takes over — the `StripeRoom`/
    /// `ASCRoom` cap shape, so a long watch list doesn't turn this into an
    /// unbounded list on a card meant to be a summary.
    private static let rowCap = 8

    private var drawn: [VibenetAccountItem] { Array(room.items.prefix(Self.rowCap)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

    /// One watched account. The whole row is the tap target for expanding
    /// its actor roster — a row is a read with ONE gesture; unwatching lives
    /// on the trailing menu, never a second tap target inside the row.
    private func row(_ item: VibenetAccountItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                DSHaptic.selection()
                if expanded.contains(item.address) { expanded.remove(item.address) }
                else { expanded.insert(item.address) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(VibenetRoom.shortAddress(item.address))
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                            .monospaced()
                            .lineLimit(1)
                        Text(VibenetRoom.rowLine(item))
                            .dsText(.label12)
                            .foregroundStyle(item.alarmed ? DS.textPrimary : DS.textSecondary)
                    }
                    Spacer(minLength: DS.Space.s2)
                    if item.alarmed {
                        Text(String(localized: "Locked"))
                            .dsText(.label11).fontWeight(.bold)
                            .foregroundStyle(Color.fixed("#ffffff"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Self.mark, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    } else if !item.actors.isEmpty {
                        Image(systemName: expanded.contains(item.address) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, DS.Space.s2)
            .contextMenu {
                Button(role: .destructive) {
                    onRemove(item.address)
                } label: {
                    Label(String(localized: "Stop watching"), systemImage: "trash")
                }
            }

            if expanded.contains(item.address), !item.actors.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    ForEach(item.actors) { actor in
                        actorLine(actor)
                    }
                }
                .padding(.bottom, DS.Space.s2)
                .padding(.leading, DS.Space.s1)
            }
        }
    }

    /// One actor inside an expanded account — its kind and its scope, the
    /// two facts that answer "what can this key actually do".
    private func actorLine(_ actor: VibenetActor) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            Circle()
                .fill(Self.mark.opacity(0.18))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(actor.kind.label)
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                Text(actor.scope.summary)
                    .dsText(.label11)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }
}
