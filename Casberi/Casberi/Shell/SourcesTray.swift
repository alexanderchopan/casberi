import SwiftUI

/// Every source at once (2026-07-31, user) — the long-press half of the agent
/// bar's two gestures: tap raises the agent, hold opens your places.
///
/// It exists because the strip can only ever show FOUR. Measured on a 402pt
/// phone: the two fixed doors plus the leading fade eat 135pt before the first
/// chip, and each chip is a 68pt pitch — four and a peek, out of a corpus that
/// routinely runs past twenty. Everything past the fourth cost a horizontal
/// scroll through icons with no names on them.
///
/// The two shapes considered and rejected first, so they aren't re-proposed:
/// a VERTICAL rail on the phone shows ~8 instead of 4 but costs 88pt of
/// permanent width (22% of the screen, against 8% of an iPad's — which is why
/// `SourceChips.verticalRail` is right THERE and wrong here), and it points the
/// wrong way besides: the feed is a `TabView(.page)` over these very labels, so
/// the strip is the map of a HORIZONTAL swipe. Stacked full-width rows are the
/// retired Home board wearing new clothes — a screen between you and the
/// content. This costs zero permanent chrome and shows all of them, not eight.
///
/// It carries the one thing the strip gave up: NAMES. Labels were dropped from
/// the chips on 2026-07-09 because they made the row scroll — true of a row,
/// free in a grid, so the icon-only strip finally has somewhere to send anyone
/// who doesn't recognise a mark.
///
/// The order is the strip's own frozen order (`ShellChrome.chipOrder`, mirrored
/// from `MainSurface.chipLabels`), NOT alphabetical: position is half a
/// chip's identity when it has no label, and a grid that re-sorted itself
/// would teach the opposite of what the freeze exists to protect.
struct SourcesTray: View {
    /// The strip's own ordered labels — "All" first, then sources.
    let labels: [String]
    let active: String
    let onPick: (String) -> Void

    @Environment(BridgeStore.self) private var bridges
    @Environment(\.dismiss) private var dismiss

    private static let columns = 5
    /// The chip's icon; the slot around it leaves room for the ring, exactly
    /// as `SourceChips` does at its own scale.
    private static let iconSize: CGFloat = 44
    private static let chipSize: CGFloat = 52
    /// Two lines of `label12` plus its own leading — the same fixed name box
    /// `AppsScreen.appTile` uses, so a one-word and a two-word name sit on the
    /// same baseline instead of the row jittering per cell.
    private static let nameHeight: CGFloat = 28

    private var rowCount: Int {
        max(1, Int(ceil(Double(labels.count) / Double(Self.columns))))
    }

    /// Natural height, capped. Past the cap the grid scrolls and `.large` is
    /// draggable — a 40-source corpus must not clip silently (the "Worth a
    /// look" tray's own 2026-07-24 lesson).
    private var trayHeight: CGFloat {
        let cell = Self.chipSize + DS.Space.s1 + Self.nameHeight
        let grid = CGFloat(rowCount) * cell + CGFloat(rowCount - 1) * DS.Space.s3
        // DSTray's own chrome: top clearance, the title, its gap, bottom pad.
        let chrome = DS.Space.s6 + 30 + DS.Space.s4 + DS.Space.s6
        return min(grid + chrome, 620)
    }

    var body: some View {
        DSTray(title: String(localized: "Your sources"),
               height: trayHeight,
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2),
                                         count: Self.columns),
                          alignment: .leading, spacing: DS.Space.s3) {
                    ForEach(labels, id: \.self) { label in
                        cell(label)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private func cell(_ label: String) -> some View {
        let isActive = label == active
        // Same read as the strip's: one ring, two exclusive states. Solid tint
        // is selection; DASHED orange is "this connection needs you" (the
        // 2026-07-21 ruling — the two must not be the same ring in two hues).
        let broken = bridges.bridges.contains {
            $0.name == label && $0.status == .attention
        }
        Button {
            DSHaptic.selection()
            onPick(label)
            dismiss()
        } label: {
            VStack(spacing: DS.Space.s1) {
                ZStack {
                    if label == "All" {
                        // The one WORD among icons, inside the circle at every
                        // text size — `SourceChips`' own accessibility-size fix.
                        Text("All").dsText(.label12)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .frame(width: Self.iconSize, height: Self.iconSize)
                            .clipShape(Circle())
                            .dsGlass(cornerRadius: Self.iconSize / 2)
                    } else {
                        BridgeIcon(name: label, size: Self.iconSize, circular: true)
                    }
                }
                .frame(width: Self.iconSize, height: Self.iconSize)
                .padding(2.5)
                .overlay {
                    if isActive {
                        Circle().strokeBorder(DS.tint, lineWidth: 2.5)
                    } else if broken {
                        Circle().strokeBorder(DS.attention,
                                              style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
                    }
                }
                .frame(width: Self.chipSize, height: Self.chipSize)

                Text(label)
                    .dsText(.label12)
                    .fontWeight(isActive ? .semibold : .medium)
                    .foregroundStyle(isActive ? DS.textPrimary : DS.textSecondary)
                    .multilineTextAlignment(.center)
                    // Names never truncate (prd §201) — the app-tile rule,
                    // which is the whole reason this grid can carry names the
                    // strip couldn't.
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(height: Self.nameHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .dsHover()
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(label + (broken ? String(localized: ", needs reconnecting") : ""))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
