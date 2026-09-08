import Foundation

/// The bound on a scraped readable body, in the one place both processes can
/// see it.
///
/// In `Shared/` rather than beside either scraper because that is the whole
/// point: the app and the share extension are separate binaries that clamp the
/// same column, and a constant only one of them can read is two constants.
/// Foundation-only, so `scripts/readable-body-selftest.sh` compiles it beside
/// `ReadableParse.swift` unmodified.
enum ReadableBody {
    /// How long a SCRAPED readable body may be on `enrichedText` (prd §645
    /// pass 5, 2026-09-08 — was 1,200 in two places that could not see each
    /// other).
    ///
    /// **ONE bound, because two processes write the column.** The app scrapes
    /// a body in two processes: `LinkTitle.parseReadable` in the app, and the
    /// share extension, whose Safari preprocessing script hands over the
    /// page's own reader text. Both clamped at 1,200 independently, and after
    /// §645 pass 1 both are DRAWN — so a divergence would mean the same
    /// article read at two lengths depending on whether you pasted it or
    /// shared it. `LinkTitle.enrich` cannot paper over that: it bails on a row
    /// already wearing a real title, which is exactly what a Safari share
    /// arrives with, so the extension's clamp is final for that row.
    ///
    /// 8,000 is `ObsidianNote.retrievalLimit`, and deliberately the same
    /// number for the same reason on the same column: *"roughly 1,300 words:
    /// long enough that a real note arrives whole, bounded enough that a
    /// pathological file can't put a megabyte into every `@Query` that faults
    /// this column."* Not referenced across the target boundary because
    /// `ObsidianNote` is app-only — the reason is what is shared, and it is
    /// written here.
    static let limit = 8_000
}
