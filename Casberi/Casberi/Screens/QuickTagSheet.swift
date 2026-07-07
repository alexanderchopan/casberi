import SwiftUI
import SwiftData

/// The quick-tag tray — Feed's leading swipe opens it so a thing can be
/// tagged without opening the full sheet. Same grammar as the thing sheet's
/// Tags field: active chips lit (tap removes), candidates dim (tap adds),
/// one field to type a new one.
struct QuickTagSheet: View {
    @Bindable var thing: Thing
    @Environment(\.modelContext) private var modelContext
    @State private var draft = ""

    private var candidates: [String] {
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        return Set(all.flatMap(\.tags)).subtracting(typeTags)
            .subtracting(thing.tags).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                KindGlyph(kind: thing.kind, size: 28)
                Text(thing.title)
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
            }

            Text("TAGS")
                .dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)

            FlowLayout(spacing: DS.Space.s2) {
                ForEach(thing.tags.filter { $0 != thing.kind.typeTag }, id: \.self) { tag in
                    chip(tag, active: true) { remove(tag) }
                }
                ForEach(candidates, id: \.self) { tag in
                    chip(tag, active: false) { add(tag) }
                }
            }

            HStack(spacing: DS.Space.s2) {
                TextField("New tag", text: $draft)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .tint(DS.tint)
                    .onSubmit { add(draft); draft = "" }
                Button("Add") { add(draft); draft = "" }
                    .dsText(.label12)
                    .foregroundStyle(draft.isEmpty ? DS.textTertiary : .white)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 28)
                    .background(draft.isEmpty ? DS.gray200 : DS.tint,
                                in: Capsule(style: .continuous))
                    .disabled(draft.isEmpty)
                    .buttonStyle(.plain)
            }
            .padding(.leading, DS.Space.s4)
            .padding(.trailing, DS.Space.s2)
            .frame(height: 40)
            .background(DS.gray100, in: Capsule(style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(DS.Space.s4)
        .presentationDetents([.height(320), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thickMaterial)
        .dsColorScheme()
    }

    private func chip(_ tag: String, active: Bool, onTap: @escaping () -> Void) -> some View {
        HStack(spacing: DS.Space.s1) {
            Text(tag).dsText(.label12)
            if active {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
        }
        .foregroundStyle(active ? DS.tint : DS.textSecondary)
        .padding(.horizontal, DS.Space.s3)
        .frame(height: 28)
        .background(active ? DS.tintDim : DS.gray100, in: Capsule(style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private func add(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty,
              !thing.tags.contains(where: { $0.lowercased() == t.lowercased() })
        else { return }
        thing.tags.append(t)
        try? modelContext.save()
        DSHaptic.tap()
    }

    private func remove(_ tag: String) {
        guard tag != thing.kind.typeTag else { return }
        thing.tags.removeAll { $0 == tag }
        try? modelContext.save()
        DSHaptic.tap()
    }
}
