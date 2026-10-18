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
/// # Only the Feed's sections (prd §1345)
///
/// It used to list every slot, a category with nothing behind it saying so.
/// Opened from the Feed's own Reorder tile, it lists what the Feed draws:
/// everything there was added by the person, so nothing is hidden or empty.
struct CategoryOrderSheet: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.dismiss) private var dismiss

    /// The working order. Held locally so a drag is instant and the store is
    /// written once per move rather than read back mid-gesture.
    /// Markets is a place in Home and not in the walk (prd §1127), so it
    /// has no slot to move here.
    ///
    /// **ONLY THE FEED'S SECTIONS (prd §1345, user: "there should be no option
    /// to hide a section b/c user has already added them").** Opened from the
    /// Feed's own Reorder tile, it lists what the Feed draws, in its order —
    /// never an empty slot.
    @State private var order: [String] = []


    var body: some View {
        List {
            Section {
                ForEach(order, id: \.self) { name in
                    row(name)
                        .dsListRow()
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: move)
            } footer: {
                if CategoryOrder.isCustom {
                    Button("Reset order") { reset() }
                        .dsText(.body17)
                        .foregroundStyle(DS.pickInk)
                        .frame(minHeight: 44)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        // One verb, so the grabbers are always out — see the type's own doc.
        .environment(\.editMode, .constant(.active))
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        // `.inline`, not `dsScreenTitle` (prd §560, 2026-09-01): that modifier
        // is the FULL-SCREEN title — large on iPhone — and this is a sheet.
        // Two of the twelve nav sheets wore it, so the family had two title
        // sizes as well as two close placements.
        .navigationTitle(Text("Feed order"))
        .onAppear { if order.isEmpty { order = Self.feedOrder(chrome) } }
        .navigationBarTitleDisplayMode(.inline)
        .dsSheetDismiss { dismiss() }
    }

    private func row(_ name: String) -> some View {
        HStack(spacing: DS.Space.s3) {
            // The category's glyph, as its Feed section wears it (user:
            // "here we should have the icons").
            Image(systemName: CategoryFold.glyph(for: name))
                .dsGlyph(.body)
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Mark.row)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).dsText(.heading17).foregroundStyle(DS.textPrimary)
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
            order = Self.feedOrder(chrome)
        }
        chrome.chipOrderPulse += 1
    }

    /// Store the order and tell the strip. Written on every move rather than
    /// on Done, so backing out with the swipe-down gesture — which never
    /// reaches a Done handler — cannot silently discard the rearrangement.
    /// The Feed's sections, in the order in force.
    @MainActor static func feedOrder(_ chrome: ShellChrome) -> [String] {
        HomeScope.feedCategories(chips: chrome.chipOrder)
    }

    private func commit() {
        DSHaptic.tap()
        CategoryOrder.set(order)
        chrome.chipOrderPulse += 1
    }
}
