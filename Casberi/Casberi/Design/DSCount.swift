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
/// Privacy figures' copy is left in place for the session mid-work on those
/// files; fold it here when that lands.
enum DSCount {
    static func grouped(_ value: UInt64) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
