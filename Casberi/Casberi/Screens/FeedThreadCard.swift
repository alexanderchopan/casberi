import SwiftUI

/// The All feed's head: a cross-source thread as a titled cluster (2026-08-07).
///
/// Content, not the floating layer — so it wears `dsWidgetSurface` (the one
/// content-card fill at the widget radius), never Liquid Glass, and it
/// separates from the rows below by containment and space, never a hairline
/// (design law). It holds no `Thing`: each row hands its member `id` back to
/// the feed, which resolves it against the live corpus (the head-card contract
/// every hero here follows).
struct FeedThreadCard: View {
    let thread: FeedThread.Thread
    /// Fires with a member's `Thing.id.uuidString`.
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.subject)
                    .dsText(.body17).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                Text(thread.line)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
            }
            VStack(spacing: DS.Space.s2) {
                ForEach(thread.members, id: \.id) { member in
                    Button {
                        DSHaptic.tap()
                        onOpen(member.id)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                            Text(member.title)
                                .dsText(.callout15)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(member.source)
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                            Text(member.meta)
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                                .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                }
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }
}
