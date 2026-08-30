import SwiftUI

/// Rearrange the category chips (prd §533, 2026-08-29).
///
/// The strip's category chips have always sat in a hand-authored order (user
/// ruling 2026-08-11). This is that order handed to the person it was decided
/// for: drag a row, the strip re-freezes into the new order when you go back.
/// `CategoryOrder` holds the arithmetic and the reasoning; this is only the
/// screen.
///
/// # Why a List and not a drag on the strip
///
/// The strip is a horizontal `ScrollView` and a chip's long press is already
/// the §384 room peek, so a drag there fights two gestures — one of them the
/// arbitration `BoardDragDriver` lost before it was retired. A vertical `List`
/// gets the whole interaction from UIKit for free, with a real accessibility
/// story (VoiceOver's own move actions) that no hand-rolled drag would have.
///
/// # Edit mode is ALWAYS on, deliberately
///
/// There is no `EditButton`. This screen has exactly one verb, so a mode
/// switch would be a control whose only job is to reveal the controls — and
/// the grabbers ARE the affordance: without them a row that can be dragged
/// looks exactly like a row that cannot.
///
/// # ALL ELEVEN are listed, including the ones with nothing behind them
///
/// The strip only draws a category once something in it has landed, so a list
/// of what is *currently* on screen would be short, would reshuffle as sources
/// arrive, and would give no way to say where a category should go BEFORE you
/// connect it. Every position is listed instead, and a category with nothing
/// behind it says so — which is honest rather than a dead control (§83): the
/// row is not a door, it is a slot, and the slot is real whether or not
/// anything occupies it yet.
struct CategoryOrderSheet: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.dismiss) private var dismiss

    /// The working order. Held locally so a drag is instant and the store is
    /// written once per move rather than read back mid-gesture.
    @State private var order: [String] = CategoryOrder.current

    /// Which categories the strip is actually drawing — read from
    /// `ShellChrome.chipOrder`, the strip's own published order, so this
    /// screen and the strip can never disagree about what is present. NOT
    /// re-derived from the corpus: that walk is the strip's single largest
    /// launch cost and there is no reason to pay it twice.
    private var present: Set<String> { Set(chrome.chipOrder) }

    var body: some View {
        List {
            Section {
                ForEach(order, id: \.self) { name in
                    row(name)
                        .dsListCardRow()
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: move)
            } header: {
                Text("Drag to put the chips in the order you want. All and Pinned always lead.")
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .textCase(nil)
            } footer: {
                if CategoryOrder.isCustom {
                    Button("Reset to the default order") { reset() }
                        .dsText(.callout15)
                        .foregroundStyle(DS.tint)
                        .frame(minHeight: 44)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // One verb, so the grabbers are always out — see the type's own doc.
        .environment(\.editMode, .constant(.active))
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Chip order")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func row(_ name: String) -> some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).dsText(.heading17).foregroundStyle(DS.textPrimary)
                // States the slot's own fact, and only when it is worth
                // saying: "In your strip" on every occupied row would be
                // eleven lines of noise on a full corpus, so the quiet case
                // is the unremarkable one.
                if !present.contains(name) {
                    Text("Nothing here yet")
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.s1)
        // The whole row reads as one item to VoiceOver, which is also what
        // makes the system's own "Move up / Move down" actions land on
        // something with a name.
        .accessibilityElement(children: .combine)
    }

    private func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        commit()
    }

    private func reset() {
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) {
            CategoryOrder.reset()
            order = CategoryOrder.current
        }
        chrome.chipOrderPulse += 1
    }

    /// Store the order and tell the strip. Written on every move rather than
    /// on Done, so backing out with the swipe-down gesture — which never
    /// reaches a Done handler — cannot silently discard the rearrangement.
    private func commit() {
        DSHaptic.tap()
        CategoryOrder.set(order)
        chrome.chipOrderPulse += 1
    }
}
