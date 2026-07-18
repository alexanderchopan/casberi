import Foundation

/// Which sources lead their feed with a calendar heatmap — the GitHub
/// contribution graph, generalized. A heatmap answers "how consistently do you
/// do this over time", so it fits the sources that read as a habit: journaling,
/// training, capturing, note-keeping. Each entry carries the card's title and
/// the noun its count is measured in (singular / plural), so the subtitle stays
/// honest per source ("142 entries", "38 workouts", "210 screenshots").
///
/// GitHub itself is NOT here — it owns a richer hero fed by its own API
/// (real quartiles from the contributions calendar); this registry is for
/// sources whose grid is derived from the corpus's own dates.
enum FeedHeatmap {
    struct Label {
        let title: String
        /// Count noun, singular (1 entry) and plural (N entries).
        let unit: String
        let units: String
    }

    static let labels: [String: Label] = [
        "Day One":       Label(title: "Your journaling year", unit: "entry",      units: "entries"),
        "Apple Journal": Label(title: "Your journaling year", unit: "entry",      units: "entries"),
        "Obsidian":      Label(title: "Your writing year",    unit: "note",       units: "notes"),
        "Notion":        Label(title: "Your writing year",    unit: "page",       units: "pages"),
        "Photos":        Label(title: "Your capture year",    unit: "screenshot", units: "screenshots"),
        "Apple Health":  Label(title: "Your training year",   unit: "workout",    units: "workouts"),
        "Strava":        Label(title: "Your training year",   unit: "activity",   units: "activities"),
        "ChatGPT":       Label(title: "Your chat year",       unit: "chat",       units: "chats"),
        "Claude":        Label(title: "Your chat year",       unit: "chat",       units: "chats"),
        "Gemini":        Label(title: "Your chat year",       unit: "chat",       units: "chats"),
    ]

    static func label(for source: String) -> Label? { labels[source] }

    /// The honest count subtitle for a heatmap card.
    static func subtitle(_ label: Label, total: Int) -> String {
        "\(total.formatted()) \(total == 1 ? label.unit : label.units)"
    }
}
