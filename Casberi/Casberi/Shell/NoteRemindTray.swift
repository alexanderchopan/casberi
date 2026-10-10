import SwiftUI
import SwiftData

/// REMIND ME (prd §1022): the solid sheet a held checklist item raises. The
/// Move to shape (§980): the item under the title, the two fixed times,
/// Pick a time, and — when the item already rings — Remove reminder. One
/// footnote says where it lands, which is the one thing the rows cannot
/// (§748).
struct NoteRemindTray: View {
    let note: Thing
    let item: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @State private var picking = false
    @State private var picked = Date.now.addingTimeInterval(3600)
    @State private var busy = false

    private var existing: NoteReminders.Entry? { NoteReminders.entry(for: item, on: note) }
    private var quick: [NoteReminders.Quick] { NoteReminders.quickTimes() }

    private var height: CGFloat {
        let rows = CGFloat(quick.count + 1 + (existing == nil ? 0 : 1))
        return DS.Space.s6 + 40 + 24 + DS.Space.s4 + rows * DS.Hit.min
             + (picking ? 420 : 0) + 44 + DS.Space.s6
    }

    var body: some View {
        DSTray(title: String(localized: "Remind me"), height: height,
               detents: [.height(height), .large]) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(verbatim: NoteChecklist.plain(item))
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                VStack(spacing: 0) {
                    ForEach(quick) { q in
                        row(glyph: q.glyph, name: q.name,
                            fact: q.date.formatted(date: .omitted, time: .shortened)) {
                            set(q.date)
                        }
                    }
                    row(glyph: "calendar", name: String(localized: "Pick a time"),
                        fact: nil, tinted: true) {
                        withAnimation(DS.Motion.standard) { picking.toggle() }
                    }
                    if picking {
                        DatePicker(String(localized: "When"), selection: $picked, in: Date.now...,
                                   displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                            .tint(DS.tint)
                        DSDoorRow(icon: "bell", title: Text(String(localized: "Set for \(NoteReminders.label(picked))"))) {
                            set(picked)
                        }
                    }
                    if existing != nil {
                        DSDoorRow(icon: "bell.slash", label: "Remove reminder", role: .destructive) {
                            busy = true
                            Task { @MainActor in
                                await NoteReminders.remove(item: item, on: note, context: modelContext)
                                chrome.flash(String(localized: "Reminder removed"))
                                dismiss()
                            }
                        }
                    }
                }
                .disabled(busy)
                DSFootnote(Text("Saved to Reminders, in a list named Casberi."))
            }
        }
    }

    private func row(glyph: String, name: String, fact: String?, tinted: Bool = false,
                     act: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.tap()
            act()
        } label: {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: glyph)
                    .dsGlyph(.caption, weight: .regular)
                    .frame(width: DS.Mark.row, height: DS.Mark.row)
                    .background(DS.fillFaint, in: Circle())
                Text(verbatim: name)
                    .dsText(.body17)
                Spacer(minLength: 0)
                if let fact {
                    Text(verbatim: fact)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                } else {
                    Image(systemName: picking ? "chevron.up" : "chevron.right")
                        .dsGlyph(.tick, weight: .semibold)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .foregroundStyle(tinted ? DS.tint : DS.textPrimary)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
    }

    private func set(_ date: Date) {
        busy = true
        Task { @MainActor in
            switch await NoteReminders.set(item: item, on: note, at: date, context: modelContext) {
            case .success(let entry):
                chrome.flash(String(localized: "Reminder set for \(NoteReminders.label(entry.date))"),
                             tone: .success)
                dismiss()
            case .failure(.refused):
                chrome.flash(String(localized: "Reminders access is off in Settings"), tone: .failure)
                busy = false
            case .failure:
                chrome.flash(String(localized: "Couldn’t save the reminder"), tone: .failure)
                busy = false
            }
        }
    }
}
