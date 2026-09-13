import SwiftUI

/// **The app's one "working" mark (prd §715, 2026-09-13).** Twenty-seven
/// `ProgressView()`s carried three sizes and two tints between them, and the
/// white-on-fill case was spelled by hand where `DSSlabDisc(onFill:)` already
/// named it. Sizes are the system's; `onFill` is for a spinner over a filled
/// control, where the default gray disappears.
struct DSSpinner: View {
    enum Size {
        case mini, small, regular

        var control: ControlSize {
            switch self {
            case .mini: .mini
            case .small: .small
            case .regular: .regular
            }
        }
    }

    var size: Size = .small
    var onFill = false

    var body: some View {
        ProgressView()
            .controlSize(size.control)
            .tint(onFill ? Color.white : nil)
    }
}
