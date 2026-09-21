import Foundation

/// One spelling of a count somebody reads — grouped for their locale.
///
/// **Seen on a device (prd §602): the Privacy step budgets printed `320000`
/// while the Gas row two blocks down printed `21,000`** — two spellings of the
/// same kind of number on one sheet, which is the drift a shared helper exists
/// to prevent and which arrived the moment a second one was written. That fix
/// then existed TWICE inside one seat (`PrivacyDevnetFigures.grouped` and the
/// move sheet's own copy), while Frames and Hegotá printed every gas figure raw
/// through `String(gas)` — the same defect, two rooms over (prd §605).
///
/// These are quantities, never the hex the chain speaks, so they group. The
/// Privacy figures' copy has now been folded in and deleted (PERF, prd §628) —
/// it had lost its last caller and was still building a formatter per call.
///
/// A file compiled Foundation-only by a harness (`PrivacyPoolsRoom`,
/// `FramesReading`, `WalletApprovalExposure`) keeps its OWN static formatter
/// and says so: reaching `Design/` from there breaks the harness, which is a
/// different constraint from the drift this helper exists to prevent.
enum DSCount {
    /// ONE formatter (prd §628): constructing a `NumberFormatter` is one of
    /// the most expensive things Foundation does per call, and the devnet
    /// sheets call this four times in a line, per render. Formatters are
    /// thread-safe for formatting since iOS 7; the shared one is never mutated
    /// after this.
    private static let decimal: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()
    static func grouped(_ value: UInt64) -> String {
        decimal.string(from: NSNumber(value: value)) ?? String(value)
    }
}
