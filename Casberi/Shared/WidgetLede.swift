import Foundation

/// The contract between the brief and the widget (2026-07-25).
///
/// The widget used to compose its own line — a tag histogram, "Recipes fills
/// your week · 12 things across 3 apps". That is a VOLUME claim, and §213
/// ruled volume is not news ("people do not care how many things landed,
/// because we have dozens a day"). The brief already composes the one sentence
/// that IS news, ranked by what matters — risk, then money, then a person,
/// then a deadline — so the widget mirrors that sentence instead of inventing
/// a weaker one of its own.
///
/// It has to travel through the app group rather than a shared function: the
/// widget extension runs in a ~30MB budget and the lede's inputs include live
/// wallet reads it can neither afford nor make. `TodayBrief.compose` writes;
/// `HeroProvider` reads. Both sides name the keys here so a rename can't
/// silently strand the widget on a key nobody writes anymore.
/// One theme cell for the medium widget's treemap (2026-08-03) — the SAME
/// month-wide clustering `TodayBrief`'s own in-app themes card shows
/// (`HomeComposition.projectClusters`), mirrored rather than recomputed with
/// different rules. `weight` sizes the cell's AREA only; nothing ever prints
/// it as a number — the §213 ruling that killed the widget's old tag
/// histogram ("12 things across 3 apps") was about volume claims specifically,
/// and an unlabeled area is a magnitude, not a tally.
struct WidgetThemeCell: Codable, Equatable {
    let name: String
    let weight: Int
}

enum WidgetLede {
    /// The widget kind both `WidgetCenter.reloadTimelines(ofKind:)` and the
    /// `StaticConfiguration` must agree on.
    static let kind = "casberi.hero"

    static let textKey = "widget.lede"
    static let stampKey = "widget.ledeAt"
    static let themesKey = "widget.themes"
    static let themesStampKey = "widget.themesAt"

    /// How long a published lede stays truthful. The brief republishes on
    /// every foreground, so this only matters for an app that hasn't been
    /// opened in a while — at which point the sentence describes a day that
    /// has passed, and the widget's own fallback (the most recent THING) is
    /// the more honest thing to show. Deliberately longer than a day: a
    /// sentence composed last night is still the right one this morning.
    static let freshness: TimeInterval = 36 * 3600

    /// The published sentence, or nil when there isn't a fresh one. Reading
    /// through here keeps the staleness rule in one place instead of leaving
    /// each caller to remember it.
    static func current(now: Date = .now,
                        defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> String? {
        guard let defaults,
              let text = defaults.string(forKey: textKey), !text.isEmpty
        else { return nil }
        let stamp = defaults.double(forKey: stampKey)
        guard stamp > 0, now.timeIntervalSince1970 - stamp < freshness else { return nil }
        return text
    }

    /// The published theme cells, largest first, or nil when there's nothing
    /// fresh or too few to tile (below `themesMap`'s own two-cluster floor —
    /// one cell isn't a map, it's a title). Shares the lede's freshness
    /// window under its own stamp, since the two publish together but a
    /// future change publishing them apart shouldn't have to remember to
    /// split the window too.
    static func themes(now: Date = .now,
                       defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup))
    -> [WidgetThemeCell]? {
        guard let defaults,
              let data = defaults.data(forKey: themesKey),
              let cells = try? JSONDecoder().decode([WidgetThemeCell].self, from: data),
              cells.count >= 2
        else { return nil }
        let stamp = defaults.double(forKey: themesStampKey)
        guard stamp > 0, now.timeIntervalSince1970 - stamp < freshness else { return nil }
        return cells
    }
}
