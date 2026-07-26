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
enum WidgetLede {
    /// The widget kind both `WidgetCenter.reloadTimelines(ofKind:)` and the
    /// `StaticConfiguration` must agree on.
    static let kind = "casberi.hero"

    static let textKey = "widget.lede"
    static let stampKey = "widget.ledeAt"

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
}
