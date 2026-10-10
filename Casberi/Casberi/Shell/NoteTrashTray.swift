import SwiftUI

/// RECENTLY DELETED (prd §985) — the notes you deleted on this device in the
/// last thirty days. A row's tap asks Recover or Delete now, the choice Apple
/// Notes offers on the same list.
///
/// Values and closures only: a Catalyst sheet does not inherit its
/// presenter's environment (the Accounts crash, verify-mac step 2d), so the
/// room hands in what to do and this reads nothing but the archive.
struct NoteTrashTray: View {
    let onRecover: (NoteTrashEntry) -> Void
    let onErase: (NoteTrashEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: NoteTrashEntry?

    private var trash: NoteTrash { .shared }

    var body: some View {
        DSTray(title: String(localized: "Recently deleted"), height: 560,
               detents: [.height(560), .large]) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(trash.entries) { entry in
                            row(entry)
                        }
                    }
                }
                // The honesty line (§748's kept kind): where the notes are,
                // for how long, and that another device does not have them.
                DSFootnote(Text("Kept \(NoteTrashRules.keepDays) days, then gone."))
            }
        }
        .onAppear { trash.purgeExpired() }
    }

    private func row(_ entry: NoteTrashEntry) -> some View {
        let kind = ThingKind(rawValue: entry.kind) ?? .note
        let left = NoteTrashRules.daysLeft(entry.deletedAt, now: .now)
        return Button {
            DSHaptic.tap()
            picked = entry
        } label: {
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: entry.source, size: DS.Mark.row, symbol: kind.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if let line = NotePreview.line(title: entry.title, content: entry.content,
                                                   isVoice: kind == .voice,
                                                   isLocked: entry.sourceRef == NoteLock.refMark) {
                        Text(verbatim: line)
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(left == 1 ? String(localized: "1 day") : String(localized: "\(left) days"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityHint(Text("Recover or delete now"))
        // Anchored on the row, so on a wide screen the popover points at
        // the note it is about rather than at the tray.
        .confirmationDialog(entry.title,
                            isPresented: Binding(get: { picked?.id == entry.id },
                                                 set: { if !$0 { picked = nil } }),
                            titleVisibility: .visible) {
            Button(String(localized: "Recover")) {
                onRecover(entry)
                picked = nil
                if trash.entries.isEmpty { dismiss() }
            }
            Button(String(localized: "Delete now"), role: .destructive) {
                onErase(entry)
                picked = nil
                if trash.entries.isEmpty { dismiss() }
            }
            Button(String(localized: "Cancel"), role: .cancel) { picked = nil }
        } message: {
            Text(String(localized: "Delete now can't be undone."))
        }
    }
}
